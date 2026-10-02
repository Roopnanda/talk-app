import 'package:cloud_firestore/cloud_firestore.dart';
import 'local_storage_service.dart';

enum ReportReason { harassment, sexualContent, hateSpeech, spam, minorSafety, other }

class ReportService {
  ReportService({FirebaseFirestore? firestore, LocalStorageService? storage})
      : _db = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? LocalStorageService();

  final FirebaseFirestore _db;
  final LocalStorageService _storage;

  Future<void> blockUser(String myUid, String otherUid) async {
    await _storage.addBlockedId(otherUid);
    await _db.collection('blocks').add({
      'blockedBy': myUid,
      'blockedUid': otherUid,
      'participants': [myUid, otherUid],
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> reportUser({
    required String reporterUid,
    required String reportedUid,
    required String callId,
    required ReportReason reason,
  }) async {
    await blockUser(reporterUid, reportedUid);

    await _db.collection('reports').add({
      'reporterUid': reporterUid,
      'reportedUid': reportedUid,
      'callId': callId,
      'reason': reason.name,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<bool> isSuspended(String uid) async {
    final doc = await _db.collection('suspensions').doc(uid).get();
    return doc.exists;
  }

  Future<List<String>> blockedIds() => _storage.getBlockedIds();

  /// Everyone involved in a block WITH me, in either direction — people
  /// I've blocked, and people who've blocked me. This is what closes the
  /// one-directional gap: the block relationship is symmetric now,
  /// regardless of which side a given device checks from.
  Future<Set<String>> blockedPairUids(String myUid) async {
    final snap = await _db.collection('blocks').where('participants', arrayContains: myUid).get();
    final result = <String>{};
    for (final doc in snap.docs) {
      final blockedBy = doc.data()['blockedBy'] as String?;
      final blockedUid = doc.data()['blockedUid'] as String?;
      if (blockedBy != null && blockedBy != myUid) result.add(blockedBy);
      if (blockedUid != null && blockedUid != myUid) result.add(blockedUid);
    }
    return result;
  }
}
