import 'package:cloud_firestore/cloud_firestore.dart';

/// Helper service for managing the "yupulse_bda_marks" Firestore collection structure:
/// yupulse_bda_marks (collection)
///   -> {EMPID}_{YYYY-MM} (doc e.g., 'EMP001_2026-08')
///     -> employeeId: "EMP001"
///     -> period: "2026-08"
///     -> employeeName: "Username"
///     -> createdBy: "SyncHeadUsername"
///     -> createdAt: Timestamp
///     -> updatedAt: Timestamp
///     -> updatedBy: "SyncHeadUsername"
///     -> answers: {
///          callTargetCount: int,
///          callDoneCount: int,
///          callReason: String,
///          todoDoneCount: int
///        }
///
/// Submissions tracking collection (separate from yupulse_bda_marks):
/// yupulse_bda_submissions (collection)
///   -> {EMPID}_{YYYY-MM}
///     -> employeeId: "EMP001"
///     -> period: "2026-08"
///     -> branch: "BranchName"
///     -> employeeName: "Username"
///     -> submittedAt: Timestamp
///     -> submittedBy: "SyncHeadUsername"
class MarksFirestoreService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Sets or updates mark details for a specific employee and period.
  static Future<void> setMarkData({
    required String period,
    required String yupulseId,
    required String employeeName,
    required String currentSyncHeadUser,
    required int callTargetCount,
    required int callDoneCount,
    required String callReason,
    required int todoDoneCount,
  }) async {
    final docId = '${yupulseId}_$period';
    final docRef = _firestore.collection('yupulse_bda_marks').doc(docId);
    final snap = await docRef.get();

    final Map<String, dynamic> data = {
      'employeeId': yupulseId,
      'period': period,
      'employeeName': employeeName,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': currentSyncHeadUser,
      'answers': {
        'callTargetCount': callTargetCount,
        'callDoneCount': callDoneCount,
        'callReason': callReason,
        'todoDoneCount': todoDoneCount,
      },
    };

    if (!snap.exists || snap.data()?['createdBy'] == null) {
      data['createdBy'] = currentSyncHeadUser;
      data['createdAt'] = FieldValue.serverTimestamp();
    }

    await docRef.set(data, SetOptions(merge: true));
  }

  /// Records submission lock in yupulse_bda_submissions collection.
  static Future<void> recordSubmissionLock({
    required String period,
    required String yupulseId,
    required String branch,
    required String employeeName,
    required String currentSyncHeadUser,
  }) async {
    final docId = '${yupulseId}_$period';
    await _firestore.collection('yupulse_bda_submissions').doc(docId).set({
      'employeeId': yupulseId,
      'period': period,
      'branch': branch,
      'employeeName': employeeName,
      'submittedAt': FieldValue.serverTimestamp(),
      'submittedBy': currentSyncHeadUser,
    }, SetOptions(merge: true));
  }

  /// Checks if a user has already submitted marks for a period.
  static Future<bool> isUserSubmitted({
    required String period,
    required String yupulseId,
  }) async {
    if (yupulseId.isEmpty) return false;
    final docId = '${yupulseId}_$period';
    final doc = await _firestore.collection('yupulse_bda_submissions').doc(docId).get();
    return doc.exists;
  }

  /// Fetches mark details for a given period and yupulseId.
  static Future<DocumentSnapshot<Map<String, dynamic>>> getMarkData({
    required String period,
    required String yupulseId,
  }) async {
    final docId = '${yupulseId}_$period';
    return await _firestore.collection('yupulse_bda_marks').doc(docId).get();
  }

  /// Streams all mark documents for a period.
  static Stream<QuerySnapshot<Map<String, dynamic>>> streamPeriodMarks({
    required String period,
  }) {
    return _firestore
        .collection('yupulse_bda_marks')
        .where('period', isEqualTo: period)
        .snapshots();
  }
}
