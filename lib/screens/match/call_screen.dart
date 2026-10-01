import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../data/topics_data.dart';
import '../../services/ads_service.dart';
import '../../services/auth_service.dart';
import '../../services/call_foreground_service.dart';
import '../../services/matchmaking_service.dart';
import '../../services/progress_service.dart';
import '../../services/report_service.dart';
import '../../services/webrtc_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_container.dart';
import '../../widgets/gradient_background.dart';
import '../../widgets/voice_orb.dart';
import '../home/home_screen.dart';
import 'reconnect_offer_screen.dart';

class CallScreen extends StatefulWidget {
  const CallScreen({super.key, required this.callId, required this.isOfferer});

  final String callId;
  final bool isOfferer;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  static const Duration _maxCallDuration = Duration(minutes: 15);

  final _webrtc = WebrtcService();
  final _matchmaking = MatchmakingService();
  final _reports = ReportService();
  final _progress = ProgressService();

  Timer? _ticker;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _statusSub;
  Duration _elapsed = Duration.zero;
  bool _muted = false;
  bool _speakerOn = false;
  bool _connecting = true;
  bool _endingCall = false;
  String? _otherUid;
  String? _error;
  late String _topicPrompt;

  @override
  void initState() {
    super.initState();
    _topicPrompt = TopicsRepository.randomPrompt();
    _loadOtherParticipant();
    _connect();
    _watchForRemoteEnd();
  }

  void _shuffleTopic() {
    setState(() => _topicPrompt = TopicsRepository.randomPrompt());
  }

  Future<void> _loadOtherParticipant() async {
    final doc = await FirebaseFirestore.instance.collection('calls').doc(widget.callId).get();
    final data = doc.data();
    if (data == null) return;
    final me = AuthService.instance.uid;
    final participants = List<String>.from(data['participants'] as List);
    setState(() => _otherUid = participants.firstWhere((id) => id != me, orElse: () => ''));
  }

  void _watchForRemoteEnd() {
    _statusSub = FirebaseFirestore.instance
        .collection('calls')
        .doc(widget.callId)
        .snapshots()
        .listen((snap) {
      final status = snap.data()?['status'];
      if ((status == 'ended' || status == 'ended_by_report') && !_endingCall) {
        _endCall(
          showAd: true,
          alreadyEndedRemotely: true,
          offerReconnect: status == 'ended',
        );
      }
    });
  }

  Future<void> _connect() async {
    try {
      await CallForegroundService.instance.start();

      _webrtc.onRemoteStream((_) {
        if (mounted) setState(() => _connecting = false);
      });

      if (widget.isOfferer) {
        await _webrtc.startAsOfferer(widget.callId);
      } else {
        await _webrtc.joinAsAnswerer(widget.callId);
      }

      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _elapsed += const Duration(seconds: 1));
        if (_elapsed >= _maxCallDuration) {
          _endCall();
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  String get _formattedTime {
    final m = _elapsed.inMinutes.toString().padLeft(2, '0');
    final s = (_elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  bool get _timeRunningOut => _elapsed >= _maxCallDuration - const Duration(seconds: 60);

  Future<void> _endCall({
    bool showAd = true,
    bool alreadyEndedRemotely = false,
    bool offerReconnect = true,
    String status = 'ended',
  }) async {
    if (_endingCall) return;
    _endingCall = true;
    _ticker?.cancel();
    await _statusSub?.cancel();
    await CallForegroundService.instance.stop();
    await _webrtc.hangUp();
    await _progress.recordCallCompleted(_elapsed);
    if (!alreadyEndedRemotely) {
      await _matchmaking.endCall(widget.callId, status: status);
    }
    if (showAd) {
      await AdsService.instance.showInterstitialBetweenCalls();
    }
    if (!mounted) return;

    if (offerReconnect && _otherUid != null && _otherUid!.isNotEmpty) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => ReconnectOfferScreen(
            originalCallId: widget.callId,
            otherUid: _otherUid!,
            wasOfferer: widget.isOfferer,
          ),
        ),
        (route) => false,
      );
    } else {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => false,
      );
    }
  }

  Future<void> _reportAndEnd(ReportReason reason) async {
    final myUid = AuthService.instance.uid;
    if (myUid == null || _otherUid == null || _otherUid!.isEmpty) return;
    await _reports.reportUser(
      reporterUid: myUid,
      reportedUid: _otherUid!,
      callId: widget.callId,
      reason: reason,
    );
    await _endCall(showAd: false, offerReconnect: false, status: 'ended_by_report');
  }

  void _showReportSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: GlassContainer(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Report this person', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text('They will be blocked immediately and reviewed.',
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 16),
              ...ReportReason.values.map((r) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_reasonLabel(r), style: const TextStyle(color: AppColors.textPrimary)),
                    onTap: () {
                      Navigator.of(context).pop();
                      _reportAndEnd(r);
                    },
                  )),
            ],
          ),
        ),
      ),
    );
  }

  String _reasonLabel(ReportReason r) => switch (r) {
        ReportReason.harassment => 'Harassment or bullying',
        ReportReason.sexualContent => 'Sexual content',
        ReportReason.hateSpeech => 'Hate speech',
        ReportReason.spam => 'Spam or scam',
        ReportReason.minorSafety => 'I believe this user is a minor',
        ReportReason.other => 'Other',
      };

  @override
  void dispose() {
    _ticker?.cancel();
    _statusSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return _buildError(context);

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        // Deliberately does nothing — only End, a report, or the other
        // side hanging up should ever end a call.
      },
      child: Scaffold(
        body: GradientBackground(
          child: SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 12),
                Text(
                  _connecting ? 'Connecting…' : _formattedTime,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: _timeRunningOut ? AppColors.warn : null,
                      ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: GestureDetector(
                    onTap: _shuffleTopic,
                    child: GlassContainer(
                      borderRadius: 16,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Row(
                        children: [
                          const Icon(Icons.lightbulb_outline_rounded, color: AppColors.accent, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _topicPrompt,
                              style: Theme.of(context).textTheme.bodyMedium,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.refresh_rounded, color: AppColors.textMuted, size: 18),
                        ],
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                VoiceOrb(size: 150, active: !_connecting),
                const Spacer(),
                GlassContainer(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  borderRadius: 24,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _circleAction(
                        icon: _muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                        label: _muted ? 'Unmute' : 'Mute',
                        onTap: () => setState(() => _muted = _webrtc.toggleMute()),
                      ),
                      _circleAction(
                        icon: _speakerOn ? Icons.volume_up_rounded : Icons.volume_down_rounded,
                        label: 'Speaker',
                        active: _speakerOn,
                        onTap: () async {
                          final on = await _webrtc.toggleSpeaker();
                          if (mounted) setState(() => _speakerOn = on);
                        },
                      ),
                      _circleAction(
                        icon: Icons.flag_outlined,
                        label: 'Report',
                        color: AppColors.warn,
                        onTap: _showReportSheet,
                      ),
                      _circleAction(
                        icon: Icons.call_end_rounded,
                        label: 'End',
                        color: AppColors.warn,
                        filled: true,
                        onTap: () => _endCall(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    return Scaffold(
      body: GradientBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Call failed to connect — screenshot this',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                Expanded(
                  child: SingleChildScrollView(
                    child: SelectableText(
                      _error!,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                Center(
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const HomeScreen()),
                      (route) => false,
                    ),
                    child: GlassContainer(
                      borderRadius: 999,
                      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
                      child: const Text('Back to home', style: TextStyle(color: AppColors.textMuted)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _circleAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
    bool filled = false,
    bool active = false,
  }) {
    final iconColor = filled
        ? AppColors.bgTop
        : active
            ? AppColors.accent
            : (color ?? AppColors.textPrimary);
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: filled
                  ? (color ?? AppColors.accent)
                  : active
                      ? AppColors.accent.withOpacity(0.22)
                      : Colors.white.withOpacity(0.06),
              border: filled
                  ? null
                  : Border.all(color: active ? AppColors.accent : AppColors.glassBorder),
            ),
            child: Icon(icon, color: iconColor),
          ),
          const SizedBox(height: 6),
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
