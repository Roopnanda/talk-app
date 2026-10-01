import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_container.dart';
import '../../widgets/gradient_background.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/voice_orb.dart';
import '../home/home_screen.dart';
import 'call_screen.dart';
import 'matching_screen.dart';

/// Shown right after a call ends normally (never after a report — that
/// path skips this screen entirely on both ends). Offers one bounded,
/// mutual-consent reconnect with the same person, or a fresh match.
class ReconnectOfferScreen extends StatefulWidget {
  const ReconnectOfferScreen({
    super.key,
    required this.originalCallId,
    required this.otherUid,
    required this.wasOfferer,
  });

  final String originalCallId;
  final String otherUid;
  final bool wasOfferer;

  @override
  State<ReconnectOfferScreen> createState() => _ReconnectOfferScreenState();
}

enum _Stage { choosing, waiting }

class _ReconnectOfferScreenState extends State<ReconnectOfferScreen> {
  static const _waitLimit = Duration(seconds: 15);

  final _db = FirebaseFirestore.instance;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  Timer? _timeoutTimer;
  _Stage _stage = _Stage.choosing;

  DocumentReference<Map<String, dynamic>> get _originalRef =>
      _db.collection('calls').doc(widget.originalCallId);

  String get _myUid => AuthService.instance.uid!;

  Future<void> _tapReconnect() async {
    setState(() => _stage = _Stage.waiting);

    await _originalRef.update({
      'reconnectRequestedBy': FieldValue.arrayUnion([_myUid]),
    });

    _sub = _originalRef.snapshots().listen((snap) async {
      final data = snap.data();
      if (data == null) return;

      final newCallId = data['reconnectNewCallId'] as String?;
      if (newCallId != null) {
        _goToNewCall(newCallId);
        return;
      }

      final requested = List<String>.from(data['reconnectRequestedBy'] ?? []);
      if (requested.contains(_myUid) && requested.contains(widget.otherUid)) {
        await _tryClaimReconnect();
      }
    });

    _timeoutTimer = Timer(_waitLimit, _giveUpAndFindSomeoneNew);
  }

  Future<void> _tryClaimReconnect() async {
    try {
      await _db.runTransaction((tx) async {
        final snap = await tx.get(_originalRef);
        final data = snap.data();
        if (data == null || data['reconnectUsed'] == true) return;

        final requested = List<String>.from(data['reconnectRequestedBy'] ?? []);
        if (!requested.contains(_myUid) || !requested.contains(widget.otherUid)) return;

        final newCallRef = _db.collection('calls').doc();
        tx.set(newCallRef, {
          'participants': [_myUid, widget.otherUid],
          'offererUid': widget.wasOfferer ? _myUid : widget.otherUid,
          'answererUid': widget.wasOfferer ? widget.otherUid : _myUid,
          'status': 'pending',
          'reconnectRequestedBy': <String>[],
          'reconnectUsed': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
        tx.update(_originalRef, {
          'reconnectUsed': true,
          'reconnectNewCallId': newCallRef.id,
        });
      });
    } catch (_) {
      // Lost the race to the other device — its write is what we're
      // already listening for above.
    }
  }

  void _goToNewCall(String newCallId) {
    _cleanup();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => CallScreen(callId: newCallId, isOfferer: widget.wasOfferer),
      ),
      (route) => false,
    );
  }

  Future<void> _giveUpAndFindSomeoneNew() async {
    await _withdrawMyRequest();
    _findSomeoneNew();
  }

  Future<void> _withdrawMyRequest() async {
    await _originalRef.update({
      'reconnectRequestedBy': FieldValue.arrayRemove([_myUid]),
    }).catchError((_) {});
  }

  void _findSomeoneNew() {
    _cleanup();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MatchingScreen()),
      (route) => false,
    );
  }

  /// Back/swipe while waiting withdraws the pending request first (so a
  /// late reply from the other side can't pair you into a call you've
  /// already left), then always lands on Home — never exits the app.
  Future<void> _goHome() async {
    if (_stage == _Stage.waiting) {
      await _withdrawMyRequest();
    }
    _cleanup();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (route) => false,
    );
  }

  void _cleanup() {
    _timeoutTimer?.cancel();
    _sub?.cancel();
  }

  @override
  void dispose() {
    _cleanup();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) _goHome();
      },
      child: Scaffold(
        body: GradientBackground(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(),
                  VoiceOrb(size: 140, active: _stage == _Stage.waiting),
                  const SizedBox(height: 32),
                  if (_stage == _Stage.choosing)
                    ..._buildChoosing(context)
                  else
                    ..._buildWaiting(context),
                  const Spacer(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildChoosing(BuildContext context) {
    return [
      Text('Call ended', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      Text(
        'Want to talk to them again, or find someone new?',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: 28),
      PrimaryButton(
        label: 'Reconnect with them',
        icon: Icons.replay_rounded,
        onPressed: _tapReconnect,
      ),
      const SizedBox(height: 12),
      PrimaryButton(
        label: 'Find someone new',
        filled: false,
        onPressed: _findSomeoneNew,
      ),
    ];
  }

  List<Widget> _buildWaiting(BuildContext context) {
    return [
      Text('Waiting for them too…', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      Text(
        "If they don't respond in a few seconds, we'll find you someone new.",
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    ];
  }
}
