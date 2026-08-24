import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Handles the actual audio call. Firestore is only ever used to trade
/// the SDP offer/answer and ICE candidates — once that handshake finishes,
/// audio flows directly device-to-device (peer-to-peer), not through any
/// server of ours.
///
/// STUN-only to start (Google's free public server). If you see calls
/// failing to connect for users behind strict NATs/corporate firewalls,
/// that's when you add a TURN relay — don't pay for one before you have
/// evidence you need it.
class WebrtcService {
  WebrtcService({FirebaseFirestore? firestore}) : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  final _remoteRenderer = <void Function(MediaStream)>[];

  static const Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      // TODO once you have TURN credentials:
      // {'urls': 'turn:your.turn.server:3478', 'username': '...', 'credential': '...'},
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
        for (final cb in _remoteRenderer) {
          cb(event.streams.first);
        }
      }
    };
  }

  /// Call this if you were the one who found the other person waiting
  /// (see MatchmakingService.offererUid).
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

    _callDoc(callId).snapshots().listen((snap) async {
      final data = snap.data();
      if (data == null) return;
      final answer = data['answer'];
      if (answer != null && _pc!.getRemoteDescription() == null) {
        await _pc!.setRemoteDescription(
          RTCSessionDescription(answer['sdp'], answer['type']),
        );
      }
    });

    _callDoc(callId).collection('answerCandidates').snapshots().listen((snap) {
      for (final change in snap.docChanges) {
        if (change.type == DocumentChangeType.added) {
          _pc!.addCandidate(_candidateFromMap(change.doc.data()!));
        }
      }
    });
  }

  /// Call this if MatchmakingService told you someone else claimed you
  /// (you're the answererUid on the call doc).
  Future<void> joinAsAnswerer(String callId) async {
    await _setupPeerConnection(callId);

    _pc!.onIceCandidate = (candidate) {
      _callDoc(callId).collection('answerCandidates').add(candidate.toMap());
    };

    // The offerer writes their SDP offer from a DIFFERENT device, on its
    // own timeline — their mic/peer-connection setup might still be in
    // progress right now. A single one-shot read here was a race
    // condition: it can fire before the offer exists yet. Listen instead
    // of reading once, and give it a real timeout rather than hanging
    // forever if the other person's connection genuinely never arrives.
    final snap = await _callDoc(callId)
        .snapshots()
        .firstWhere((snap) => snap.data()?['offer'] != null)
        .timeout(
          const Duration(seconds: 30),
          onTimeout: () => throw StateError(
            'Timed out waiting to connect. The other person may have left.',
          ),
        );

    final offer = snap.data()!['offer'];
    await _pc!.setRemoteDescription(RTCSessionDescription(offer['sdp'], offer['type']));

    final answer = await _pc!.createAnswer();
    await _pc!.setLocalDescription(answer);
    await _callDoc(callId).update({
      'answer': {'sdp': answer.sdp, 'type': answer.type},
    });

    _callDoc(callId).collection('offerCandidates').snapshots().listen((snap) {
      for (final change in snap.docChanges) {
        if (change.type == DocumentChangeType.added) {
          _pc!.addCandidate(_candidateFromMap(change.doc.data()!));
        }
      }
    });
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
    for (final track in _localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      await track.stop();
    }
    await _pc?.close();
    _pc = null;
    _localStream = null;
  }
}
