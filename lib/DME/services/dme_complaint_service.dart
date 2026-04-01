import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/dme_complaint.dart';

class DmeComplaintService {
  DmeComplaintService._();
  static final DmeComplaintService instance = DmeComplaintService._();

  final _db = FirebaseFirestore.instance;
  static const _collection = 'dme_complaints';

  /// Create a new complaint
  Future<String> createComplaint(DmeComplaint complaint) async {
    final docRef = _db.collection(_collection).doc();
    await docRef.set({
      ...complaint.toMap(),
      'id': docRef.id,
    });
    return docRef.id;
  }

  /// Update complaint status (e.g., mark case resolved)
  Future<void> updateComplaintStatus({
    required String complaintId,
    required String newStatus,
    required String userId,
  }) async {
    final updateMap = <String, dynamic>{
      'status': newStatus,
      'updated_at': DateTime.now().toIso8601String(),
    };

    if (newStatus == 'case_resolved') {
      updateMap['resolved_by'] = userId;
      updateMap['resolved_at'] = DateTime.now().toIso8601String();
    } else if (newStatus == 'verified_closed') {
      updateMap['closed_by'] = userId;
      updateMap['closed_at'] = DateTime.now().toIso8601String();
    }

    await _db.collection(_collection).doc(complaintId).update(updateMap);
  }

  /// Get complaints for a specific branch (for branch users to view)
  Future<List<DmeComplaint>> getComplaintsForBranch({
    required String branch,
    String? status,
  }) async {
    var query = _db
        .collection(_collection)
        .where('branch', isEqualTo: branch)
        .orderBy('created_at', descending: true);

    if (status != null) {
      query = query.where('status', isEqualTo: status);
    }

    final docs = await query.get();
    return docs.docs.map((doc) => DmeComplaint.fromMap(doc.data())).toList();
  }

  /// Get complaints raised by a specific user
  Future<List<DmeComplaint>> getComplaintsByUser({
    required String userId,
    String? status,
  }) async {
    var query = _db
        .collection(_collection)
        .where('created_by', isEqualTo: userId)
        .orderBy('created_at', descending: true);

    if (status != null) {
      query = query.where('status', isEqualTo: status);
    }

    final docs = await query.get();
    return docs.docs.map((doc) => DmeComplaint.fromMap(doc.data())).toList();
  }

  /// Get all complaints across all branches (admin only)
  Future<List<DmeComplaint>> getAllComplaints({
    String? status,
    String? branch,
  }) async {
    var query = _db
        .collection(_collection)
        .orderBy('created_at', descending: true);

    if (status != null) {
      query = query.where('status', isEqualTo: status);
    }
    if (branch != null) {
      query = query.where('branch', isEqualTo: branch);
    }

    final docs = await query.get();
    return docs.docs.map((doc) => DmeComplaint.fromMap(doc.data())).toList();
  }

  /// Get a specific complaint
  Future<DmeComplaint?> getComplaint(String complaintId) async {
    final doc = await _db.collection(_collection).doc(complaintId).get();
    return doc.exists ? DmeComplaint.fromMap(doc.data()!) : null;
  }

  /// Stream complaints for real-time updates
  Stream<List<DmeComplaint>> streamComplaintsForBranch({
    required String branch,
  }) {
    return _db
        .collection(_collection)
        .where('branch', isEqualTo: branch)
        .orderBy('created_at', descending: true)
        .limit(50)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map((doc) => DmeComplaint.fromMap(doc.data())).toList(),
        );
  }

  /// Delete a complaint (admin only)
  Future<void> deleteComplaint(String complaintId) async {
    await _db.collection(_collection).doc(complaintId).delete();
  }
}
