import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../services/ads_service.dart';
import '../../services/auth_service.dart';
import '../../services/matchmaking_service.dart';
import '../../services/report_service.dart';
import '../../services/webrtc_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_container.dart';
import '../../widgets/gradient_background.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/voice_orb.dart';
import '../home/home_screen.dart';

class CallScreen extends StatefulWidget {
  const CallScreen({super.key, required this.callId, required this.isOfferer});

  final String callId;
  final bool isOfferer;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final _webrtc = WebrtcService();
  final _matchmaking = MatchmakingService();
  final _reports = ReportService();

  Timer? _ticker;
  Duration _elapsed = Duration.zero;
  bool _muted = false;
  bool _connecting = true;
  String? _otherUid;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadOtherParticipant();
    _connect();
  }

  Future<void> _loadOtherParticipant() async {
    final doc = await FirebaseFirestore.instance.collection('calls').doc(widget.callId).get();
    final data = doc.data();
    if (data == null) return;
    final me = AuthService.instance.uid;
    final participants = List<String>.from(data['participants'] as List);
    setState(() => _otherUid = participants.firstWhere((id) => id != me, orElse: () => ''));
  }

  Future<void> _connect() async {
    try {
      _webrtc.onRemoteStream((_) {
        // Remote audio starts playing automatically once the track attaches;
        // flip the "connecting" flag off so the UI reflects a live call.
        if (mounted) setState(() => _connecting = false);
      });

      if (widget.isOfferer) {
        await _webrtc.startAsOfferer(widget.callId);
      } else {
        await _webrtc.joinAsAnswerer(widget.callId);
      }

      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() => _elapsed += const Duration(seconds: 1));
      });
    } catch (e) {
      // Was previously unhandled — a mic-permission denial, a Firestore
      // rules rejection, or a WebRTC setup failure would all just leave
      // this screen stuck on "Connecting…" forever with zero indication
      // why. Now it tells you.
      if (mounted) setState(() => _error = e.toString());
    }
  }

  String get _formattedTime {
    final m = _elapsed.inMinutes.toString().padLeft(2, '0');
    final s = (_elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _endCall({bool showAd = true}) async {
    _ticker?.cancel();
    await _webrtc.hangUp();
    await _matchmaking.endCall(widget.callId);
    if (showAd) {
      await AdsService.instance.showInterstitialBetweenCalls();
    }
    if (mounted) {
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
    await _endCall(showAd: false);
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return _buildError(context);

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) _endCall();
      },
      child: Scaffold(
        body: GradientBackground(
          child: SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 12),
                Text(_connecting ? 'Connecting…' : _formattedTime,
                    style: Theme.of(context).textTheme.titleMedium),
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
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: filled ? (color ?? AppColors.accent) : Colors.white.withOpacity(0.06),
              border: filled ? null : Border.all(color: AppColors.glassBorder),
            ),
            child: Icon(icon, color: filled ? AppColors.bgTop : (color ?? AppColors.textPrimary)),
          ),
          const SizedBox(height: 6),
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
