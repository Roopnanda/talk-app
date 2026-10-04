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
  final _stateListeners = <void Function(String)>[];
  final List<StreamSubscription> _subs = [];

  bool _remoteDescriptionApplied = false;
  bool _answerApplyStarted = false;
  final List<RTCIceCandidate> _pendingCandidates = [];

  bool _speakerOn = false;
  bool get speakerOn => _speakerOn;

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

  /// Live WebRTC connection-state text ("ICE: checking", "Connection:
  /// connected", etc.) — purely diagnostic, so the NEXT time a call
  /// stalls, we see exactly which stage it's stuck in instead of
  /// guessing again.
  void onConnectionStateChange(void Function(String) callback) {
    _stateListeners.add(callback);
  }

  void _notifyState(String text) {
    for (final cb in _stateListeners) {
      cb(text);
    }
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

    _pc!.onIceConnectionState = (state) => _notifyState('ICE: ${state.toString().split('.').last}');
    _pc!.onConnectionState = (state) => _notifyState('Connection: ${state.toString().split('.').last}');
    _pc!.onIceGatheringState = (state) => _notifyState('Gathering: ${state.toString().split('.').last}');

    _pc!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        Helper.setSpeakerphoneOn(_speakerOn);
        for (final cb in _remoteRenderer) {
          cb(event.streams.first);
        }
      }
    };
  }

  Future<void> toggleSpeaker() async {
    _speakerOn = !_speakerOn;
    try {
      await Helper.setSpeakerphoneOn(_speakerOn);
    } catch (_) {}
  }

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

  Future<void> joinAsAnswerer(String callId) async {
    await _setupPeerConnection(callId);

    _pc!.onIceCandidate = (candidate) {
      _callDoc(callId).collection('answerCandidates').add(candidate.toMap());
    };

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
