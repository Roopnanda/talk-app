import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/user_profile.dart';
import '../../services/auth_service.dart';
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

  @override
  void initState() {
    super.initState();
    _startSearch();
  }

  Future<void> _startSearch() async {
    final uid = await AuthService.instance.ensureSignedIn();
    final gender = await _storage.getGender();

    // Listen in case someone else claims us from the queue first.
    _incomingSub = _matchmaking.watchForIncomingCall(uid).listen((callId) {
      _goToCall(callId, isOfferer: false);
    });

    final callId = await _matchmaking.findOrQueue(uid: uid, gender: gender.storageValue);
    if (callId != null) {
      _goToCall(callId, isOfferer: true);
    }
    // else: we're queued and waiting — the stream listener above will fire.
  }

  void _goToCall(String callId, {required bool isOfferer}) {
    if (_navigated) return;
    _navigated = true;
    _incomingSub?.cancel();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => CallScreen(callId: callId, isOfferer: isOfferer),
      ),
    );
  }

  Future<void> _cancel() async {
    final uid = AuthService.instance.uid;
    if (uid != null) await _matchmaking.leaveQueue(uid);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _incomingSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GradientBackground(
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              const VoiceOrb(size: 150, active: true),
              const SizedBox(height: 32),
              Text('Finding someone to talk to…',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text('Usually takes a few seconds',
                  style: Theme.of(context).textTheme.bodyMedium),
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
          ),
        ),
      ),
    );
  }
}
