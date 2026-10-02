import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../models/user_profile.dart';
import '../../services/auth_service.dart';
import '../../services/call_foreground_service.dart';
import '../../services/local_storage_service.dart';
import '../../services/matchmaking_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_container.dart';
import '../../widgets/gradient_background.dart';
import '../../widgets/voice_orb.dart';
import 'call_screen.dart';

class MatchingScreen extends StatefulWidget {
  const MatchingScreen({super.key});

  @override
  State<MatchingScreen> createState() => _MatchingScreenState();
}

class _MatchingScreenState extends State<MatchingScreen> {
  final _matchmaking = MatchmakingService();
  final _storage = LocalStorageService();
  StreamSubscription<String>? _incomingSub;
  bool _navigated = false;
  bool _serviceStarted = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startSearch();
  }

  Future<void> _startSearch() async {
    try {
      // Asked here, before joining the queue, instead of waiting until a
      // call actually starts — a clearer moment for the prompt, and it
      // means mic access is already granted by the time the foreground
      // service below starts (it requires that, even with no audio sent
      // yet).
      await _ensureMicPermission();

      // Keeps the match listener alive if the screen turns off while
      // waiting — without this, Android can suspend it in the
      // background, so a match can land but go unnoticed until the
      // screen turns back on.
      await CallForegroundService.instance.start();
      _serviceStarted = true;

      final uid = await AuthService.instance.ensureSignedIn();
      final gender = await _storage.getGender();

      await _clearStaleState(uid);

      _incomingSub = _matchmaking.watchForIncomingCall(uid).listen(
        (callId) => _goToCall(callId),
        onError: (e) {
          if (mounted) setState(() => _error = e.toString());
        },
      );

      final callId = await _matchmaking.findOrQueue(uid: uid, gender: gender.storageValue);
      if (callId != null) _goToCall(callId);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _ensureMicPermission() async {
    final stream = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': false});
    for (final track in stream.getTracks()) {
      await track.stop();
    }
  }

  Future<void> _clearStaleState(String uid) async {
    try {
      final db = FirebaseFirestore.instance;
      await db.collection('matchQueue').doc(uid).delete();
      final stale = await db
          .collection('calls')
          .where('participants', arrayContains: uid)
          .where('status', isEqualTo: 'pending')
          .orderBy('createdAt', descending: true)
          .get();
      for (final doc in stale.docs) {
        await doc.reference.update({'status': 'ended'});
      }
    } catch (_) {}
  }

  Future<void> _goToCall(String callId) async {
    if (_navigated) return;
    _navigated = true;
    _incomingSub?.cancel();
    try {
      final myUid = AuthService.instance.uid;
      final snap = await FirebaseFirestore.instance.collection('calls').doc(callId).get();
      final isOfferer = snap.data()?['offererUid'] == myUid;
      if (!mounted) return;
      // The foreground service keeps running — CallScreen takes over
      // managing it from here and stops it once the call ends.
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => CallScreen(callId: callId, isOfferer: isOfferer),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _cancel() async {
    final uid = AuthService.instance.uid;
    if (uid != null) await _matchmaking.leaveQueue(uid);
    await _stopServiceIfStarted();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _stopServiceIfStarted() async {
    if (_serviceStarted) {
      await CallForegroundService.instance.stop();
      _serviceStarted = false;
    }
  }

  @override
  void dispose() {
    _incomingSub?.cancel();
    // Only stops it here on a path that never reached a call (e.g. the
    // error screen). The success path hands ownership to CallScreen via
    // pushReplacement, which never triggers this.
    if (!_navigated) {
      _stopServiceIfStarted();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        // Same cleanup as tapping Cancel — without this, back/swipe
        // during matching would leave your queue entry behind.
        if (!didPop) _cancel();
      },
      child: Scaffold(
        body: GradientBackground(
          child: SafeArea(
            child: _error != null ? _buildError(context) : _buildSearching(context),
          ),
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Matching failed — screenshot this',
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
              onTap: () async {
                await _stopServiceIfStarted();
                if (mounted) Navigator.of(context).pop();
              },
              child: GlassContainer(
                borderRadius: 999,
                padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
                child: const Text('Back', style: TextStyle(color: AppColors.textMuted)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearching(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Spacer(),
        const VoiceOrb(size: 150, active: true),
        const SizedBox(height: 32),
        Text('Finding someone to talk to…', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text('Usually takes a few seconds', style: Theme.of(context).textTheme.bodyMedium),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.only(bottom: 40),
          child: GestureDetector(
            onTap: _cancel,
            child: GlassContainer(
              borderRadius: 999,
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.close_rounded, size: 18, color: AppColors.textMuted),
                  SizedBox(width: 8),
                  Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
