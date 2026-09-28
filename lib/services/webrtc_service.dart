import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Handles the actual audio call. Firestore is only ever used to trade
/// the SDP offer/answer and ICE candidates — once that handshake finishes,
/// audio flows directly device-to-device when possible, or through the
/// TURN relay below when it isn't.
class WebrtcService {
  WebrtcService({FirebaseFirestore? firestore}) : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  final _remoteRenderer = <void Function(MediaStream)>[];
  final List<StreamSubscription> _subs = [];

  // The other side's ICE candidates can arrive from Firestore BEFORE we've
  // applied their SDP. Adding a candidate before that fails, so they wait
  // here until the remote description is in place.
  bool _remoteDescriptionApplied = false;
  bool _answerApplyStarted = false;
  final List<RTCIceCandidate> _pendingCandidates = [];

  // Calls start on the earpiece, like a normal phone call. The in-call
  // Speaker button flips this.
  bool _speakerOn = false;
  bool get speakerOn => _speakerOn;

  // Google's free STUN plus Metered's free-tier TURN relay for when direct
  // peer-to-peer isn't possible. These credentials live in plain text in
  // the source by design of Metered's static-credential tier — not a real
  // secret. Revisit before a public launch.
  static const Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun.relay.metered.ca:80'},
      {
        'urls': 'turn:global.relay.metered.ca:80',
        'username': '5db552fdc8cd34e9d089ffd4',
        'credential': '/uYY9nOm+6G31m/x',
      },
      {
        'urls': 'turn:global.relay.metered.ca:80?transport=tcp',
        'username': '5db552fdc8cd34e9d089ffd4',
        'credential': '/uYY9nOm+6G31m/x',
      },
      {
        'urls': 'turn:global.relay.metered.ca:443',
        'username': '5db552fdc8cd34e9d089ffd4',
        'credential': '/uYY9nOm+6G31m/x',
      },
      {
        'urls': 'turns:global.relay.metered.ca:443?transport=tcp',
        'username': '5db552fdc8cd34e9d089ffd4',
        'credential': '/uYY9nOm+6G31m/x',
      },
    ],
  };

  void onRemoteStream(void Function(MediaStream) callback) {
    _remoteRenderer.add(callback);
  }

  DocumentReference<Map<String, dynamic>> _callDoc(String callId) =>
      _db.collection('calls').doc(callId);

  Future<void> _setupPeerConnection(String callId) async {
    _pc = await createPeerConnection(_iceServers);

    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': false,
    });
    for (final track in _localStream!.getTracks()) {
      await _pc!.addTrack(track, _localStream!);
    }

    _pc!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        // Re-apply the chosen route (earpiece unless the user tapped
        // Speaker) — some phones reset it when remote audio starts.
        _applyAudioRoute();
        for (final cb in _remoteRenderer) {
          cb(event.streams.first);
        }
      }
    };

    // flutter_webrtc can default to loudspeaker, so set the route
    // explicitly instead of trusting the default.
    await _applyAudioRoute();
  }

  Future<void> _applyAudioRoute() async {
    if (_pc == null) return;
    try {
      await Helper.setSpeakerphoneOn(_speakerOn);
    } catch (_) {
      // A failed route change shouldn't kill the call.
    }
    // The route has been reported to snap back a few seconds after being
    // set on some devices; applying once more makes the choice stick.
    Future.delayed(const Duration(seconds: 3), () async {
      if (_pc == null) return;
      try {
        await Helper.setSpeakerphoneOn(_speakerOn);
      } catch (_) {}
    });
  }

  /// Flips between earpiece and loudspeaker. Returns true if the
  /// loudspeaker is now on.
  Future<bool> toggleSpeaker() async {
    _speakerOn = !_speakerOn;
    await _applyAudioRoute();
    return _speakerOn;
  }

  /// The phone that was waiting in the queue creates the offer.
  Future<void> startAsOfferer(String callId) async {
    await _setupPeerConnection(callId);

    _pc!.onIceCandidate = (candidate) {
      _callDoc(callId).collection('offerCandidates').add(candidate.toMap());
    };

    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);
    await _callDoc(callId).update({
      'offer': {'sdp': offer.sdp, 'type': offer.type},
    });

    _subs.add(_callDoc(callId).snapshots().listen((snap) async {
      final answer = snap.data()?['answer'];
      final pc = _pc;
      if (answer == null || pc == null || _answerApplyStarted) return;
      _answerApplyStarted = true;
      await pc.setRemoteDescription(RTCSessionDescription(answer['sdp'], answer['type']));
      await _markRemoteDescriptionApplied();
    }));

    _subs.add(_callDoc(callId)
        .collection('answerCandidates')
        .snapshots()
        .listen(_handleCandidateSnapshot));
  }

  /// The phone that found someone waiting answers the offer.
  Future<void> joinAsAnswerer(String callId) async {
    await _setupPeerConnection(callId);

    _pc!.onIceCandidate = (candidate) {
      _callDoc(callId).collection('answerCandidates').add(candidate.toMap());
    };

    // The offer is written from the OTHER device on its own timeline, so
    // wait for it (with a timeout) instead of reading once.
    final snap = await _callDoc(callId)
        .snapshots()
        .firstWhere((s) => s.data()?['offer'] != null)
        .timeout(
          const Duration(seconds: 30),
          onTimeout: () => throw StateError(
            'Timed out waiting to connect. The other person may have left.',
          ),
        );

    final offer = snap.data()!['offer'];
    await _pc!.setRemoteDescription(RTCSessionDescription(offer['sdp'], offer['type']));
    await _markRemoteDescriptionApplied();

    _subs.add(_callDoc(callId)
        .collection('offerCandidates')
        .snapshots()
        .listen(_handleCandidateSnapshot));

    final answer = await _pc!.createAnswer();
    await _pc!.setLocalDescription(answer);
    await _callDoc(callId).update({
      'answer': {'sdp': answer.sdp, 'type': answer.type},
    });
  }

  void _handleCandidateSnapshot(QuerySnapshot<Map<String, dynamic>> snap) {
    for (final change in snap.docChanges) {
      if (change.type == DocumentChangeType.added) {
        final data = change.doc.data();
        if (data == null) continue;
        _onRemoteCandidate(_candidateFromMap(data));
      }
    }
  }

  void _onRemoteCandidate(RTCIceCandidate candidate) {
    final pc = _pc;
    if (pc == null) return;
    if (_remoteDescriptionApplied) {
      pc.addCandidate(candidate);
    } else {
      _pendingCandidates.add(candidate);
    }
  }

  Future<void> _markRemoteDescriptionApplied() async {
    _remoteDescriptionApplied = true;
    final pc = _pc;
    if (pc == null) return;
    for (final c in List<RTCIceCandidate>.from(_pendingCandidates)) {
      await pc.addCandidate(c);
    }
    _pendingCandidates.clear();
  }

  RTCIceCandidate _candidateFromMap(Map<String, dynamic> map) {
    return RTCIceCandidate(map['candidate'], map['sdpMid'], map['sdpMLineIndex']);
  }

  bool _muted = false;
  bool toggleMute() {
    _muted = !_muted;
    _localStream?.getAudioTracks().forEach((t) => t.enabled = !_muted);
    return _muted;
  }

  Future<void> hangUp() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    _pendingCandidates.clear();
    for (final track in _localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      await track.stop();
    }
    await _pc?.close();
    _pc = null;
    _localStream = null;
  }
}
