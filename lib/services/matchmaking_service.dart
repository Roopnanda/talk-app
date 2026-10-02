import 'package:cloud_firestore/cloud_firestore.dart';
import 'report_service.dart';

class MatchmakingService {
  MatchmakingService({FirebaseFirestore? firestore, ReportService? reportService})
      : _db = firestore ?? FirebaseFirestore.instance,
        _reports = reportService ?? ReportService();

  final FirebaseFirestore _db;
  final ReportService _reports;

  CollectionReference<Map<String, dynamic>> get _queue => _db.collection('matchQueue');
  CollectionReference<Map<String, dynamic>> get _calls => _db.collection('calls');

  Future<String?> findOrQueue({required String uid, required String gender}) async {
    if (await _reports.isSuspended(uid)) {
      throw StateError('This account can no longer be matched.');
    }

    // Local blocks (this device, instant) combined with server-known
    // blocks in EITHER direction — so a block is enforced no matter
    // which side of the pair is doing the matching.
    final localBlocked = await _reports.blockedIds();
    final pairBlocked = await _reports.blockedPairUids(uid);
    final blocked = {...localBlocked, ...pairBlocked};

    final candidates = await _queue.orderBy('joinedAt').limit(20).get();

    QueryDocumentSnapshot<Map<String, dynamic>>? candidate;
    for (final doc in candidates.docs) {
      if (doc.id != uid && !blocked.contains(doc.id)) {
        candidate = doc;
        break;
      }
    }

    if (candidate == null) {
      await _joinQueue(uid: uid, gender: gender);
      return null;
    }

    try {
      return await _db.runTransaction<String>((tx) async {
        final freshSnap = await tx.get(candidate!.reference);
        if (!freshSnap.exists) {
          throw StateError('candidate_already_claimed');
        }
        final claimed = candidate!;

        final callRef = _calls.doc();
        tx.set(callRef, {
          'participants': [claimed.id, uid],
          'offererUid': claimed.id,
          'answererUid': uid,
          'status': 'pending',
          'reconnectRequestedBy': <String>[],
          'reconnectUsed': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
        tx.delete(claimed.reference);
        tx.delete(_queue.doc(uid));
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

  Future<void> endCall(String callId, {String status = 'ended'}) {
    return _calls.doc(callId).update({'status': status, 'endedAt': FieldValue.serverTimestamp()});
  }
}
