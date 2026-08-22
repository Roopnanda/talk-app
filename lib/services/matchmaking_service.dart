import 'package:cloud_firestore/cloud_firestore.dart';
import 'report_service.dart';

/// Pairs two waiting users and creates the `calls/{callId}` document that
/// [WebrtcService] then uses for signaling.
///
/// Deliberately client-side + transaction-based rather than a Cloud
/// Function: it's simpler to stand up (no Blaze-plan Functions deploy
/// needed to get a working MVP) and is plenty for the traffic this kind
/// of app sees at launch. Move pairing into a Cloud Function later if you
/// need server-side fairness/anti-abuse checks the client shouldn't see.
class MatchmakingService {
  MatchmakingService({FirebaseFirestore? firestore, ReportService? reportService})
      : _db = firestore ?? FirebaseFirestore.instance,
        _reports = reportService ?? ReportService();

  final FirebaseFirestore _db;
  final ReportService _reports;

  CollectionReference<Map<String, dynamic>> get _queue => _db.collection('matchQueue');
  CollectionReference<Map<String, dynamic>> get _calls => _db.collection('calls');

  /// Tries to claim someone already waiting. If nobody's there, adds
  /// yourself to the queue and returns null — call [watchForIncomingCall]
  /// to find out when someone else claims you.
  Future<String?> findOrQueue({required String uid, required String gender}) async {
    if (await _reports.isSuspended(uid)) {
      throw StateError('This account can no longer be matched.');
    }

    final blocked = await _reports.blockedIds();

    final candidates = await _queue
        .orderBy('joinedAt')
        .limit(20) // small buffer so we can skip blocked users client-side
        .get();

    QueryDocumentSnapshot<Map<String, dynamic>>? candidate;
    for (final doc in candidates.docs) {
      if (doc.id != uid && !blocked.contains(doc.id)) {
        candidate = doc;
        break;
      }
    }

    // Nobody eligible waiting right now — join the queue ourselves.
    if (candidate == null) {
      await _joinQueue(uid: uid, gender: gender);
      return null;
    }

    try {
      return await _db.runTransaction<String>((tx) async {
        // Bind to a non-nullable local once — `candidate` itself can't be
        // smart-cast to non-null inside this closure (Dart doesn't promote
        // captured variables across an `await`), so every later reference
        // needs a fresh, genuinely non-nullable name instead of repeated `!`.
        final claimed = candidate!;

        final freshSnap = await tx.get(claimed.reference);
        if (!freshSnap.exists) {
          // Someone else claimed this candidate between our read above
          // and this transaction — treat it like "nobody was there."
          throw StateError('candidate_already_claimed');
        }

        final callRef = _calls.doc();
        tx.set(callRef, {
          'participants': [claimed.id, uid],
          'offererUid': claimed.id, // whoever was waiting longest sends the offer
          'answererUid': uid,
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
        });
        tx.delete(claimed.reference);
        tx.delete(_queue.doc(uid)); // in case we were also queued
        return callRef.id;
      });
    } on StateError {
      await _joinQueue(uid: uid, gender: gender);
      return null;
    }
  }

  Future<void> _joinQueue({required String uid, required String gender}) {
    return _queue.doc(uid).set({
      'gender': gender,
      'joinedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> leaveQueue(String uid) => _queue.doc(uid).delete();

  /// Fires once when another user's [findOrQueue] claims this uid.
  Stream<String> watchForIncomingCall(String uid) {
    return _calls
        .where('participants', arrayContains: uid)
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .limit(1)
        .snapshots()
        .where((snap) => snap.docs.isNotEmpty)
        .map((snap) => snap.docs.first.id);
  }

  Future<void> endCall(String callId) {
    return _calls.doc(callId).update({'status': 'ended', 'endedAt': FieldValue.serverTimestamp()});
  }
}
