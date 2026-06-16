import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/dme_complaint.dart';
import 'dme_supabase_service.dart';

class DmeComplaintService {
  DmeComplaintService._();
  static final DmeComplaintService instance = DmeComplaintService._();

  // Lazy initialization to avoid accessing Supabase before it's ready
  late final _supabase = Supabase.instance.client;
  static const _table = 'dme_complaints';

  /// Ensure Supabase is initialized before use
  void _ensureSupabaseInitialized() {
    try {
      Supabase.instance.client;
    } catch (e) {
      throw Exception('Supabase not initialized. Please ensure Supabase is initialized in main.dart before accessing DME services.');
    }
  }

  /// Get select clause - fetch complaints with branch name
  /// Note: User relationships (assigned_to_user, etc) require proper FK constraints in database
  /// For now, we fetch basic complaint data and let the model handle null usernames gracefully
  String get _selectClause =>
      '*,dme_branches!branch_id(id,name)';

  /// Create a new complaint with mandatory assignment
  Future<String> createComplaint({
    required String customerName,
    required String customerPhone,
    required int branchId,
    required String complaintText,
    required String createdById,
    required String assignedToId,
    String? voiceNoteUrl,
  }) async {
    _ensureSupabaseInitialized();
    
    // Validate that assignedToId is not empty
    if (assignedToId.isEmpty) {
      throw Exception('assignedToId is mandatory. Every complaint must be assigned to a user.');
    }
    
    final row = <String, dynamic>{
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'branch_id': branchId,
      'complaint_text': complaintText,
      'created_by': createdById,
      'assigned_to': assignedToId, // MANDATORY - included in initial insert
      'status': 'raised',
      'has_new_remarks': false,
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (voiceNoteUrl != null) row['voice_file_url'] = voiceNoteUrl;

    final response = await _supabase
        .from(_table)
        .insert(row)
        .select('id')
        .single();

    return response['id'] as String;
  }

  /// Add remarks to a complaint
  Future<void> addRemarks({
    required String complaintId,
    required String remarks,
    required String userId,
    String? voiceFileUrl,
  }) async {
    _ensureSupabaseInitialized();
    final updateData = {
      'remarks': remarks,
      'remarked_by': userId,
      'remarked_at': DateTime.now().toIso8601String(),
      'has_new_remarks': true,
      'status': 'case_resolved',
      'updated_at': DateTime.now().toIso8601String(),
    };
    // Note: voiceFileUrl is stored in Firebase Storage, not in Supabase
    await _supabase.from(_table).update(updateData).eq('id', complaintId);
  }

  /// Mark remarks as read by the complaint creator
  Future<void> markRemarksAsRead({required String complaintId}) async {
    _ensureSupabaseInitialized();
    await _supabase.from(_table).update({
      'has_new_remarks': false,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', complaintId);
  }

  /// Update complaint status with explicit FK relationship names
  Future<void> updateComplaintStatus({
    required String complaintId,
    required String newStatus,
    required String userId,
  }) async {
    _ensureSupabaseInitialized();
    final updateMap = <String, dynamic>{'status': newStatus, 'updated_at': DateTime.now().toIso8601String()};

    if (newStatus == 'case_resolved') {
      updateMap['resolved_by'] = userId;
      updateMap['resolved_at'] = DateTime.now().toIso8601String();
    } else if (newStatus == 'verified_closed') {
      updateMap['closed_by'] = userId;
      updateMap['closed_at'] = DateTime.now().toIso8601String();
    }

    await _supabase.from(_table).update(updateMap).eq('id', complaintId);
  }

  /// Get all complaints with explicit relationship selects
  Future<List<DmeComplaint>> getAllComplaints({
    String? status,
    int? branchId,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    _ensureSupabaseInitialized();
    dynamic query = _supabase.from(_table).select(_selectClause);

    if (status != null) {
      query = query.eq('status', status);
    }
    if (branchId != null) {
      query = query.eq('branch_id', branchId);
    }
    if (dateFrom != null) {
      query = query.gte('created_at', dateFrom.toIso8601String());
    }
    if (dateTo != null) {
      query = query.lte('created_at', dateTo.toIso8601String());
    }

    query = query.order('created_at', ascending: false);

    final response = await query;
    final data = response as List<dynamic>? ?? [];
    return data.map((doc) => DmeComplaint.fromMap(doc as Map<String, dynamic>)).toList();
  }

  /// Get complaints raised by a specific user (created by)
  Future<List<DmeComplaint>> getMyComplaints({required String userId, String? status}) async {
    _ensureSupabaseInitialized();
    dynamic query = _supabase.from(_table).select(_selectClause).eq('created_by', userId);

    if (status != null) {
      query = query.eq('status', status);
    }

    query = query.order('created_at', ascending: false);

    final response = await query;
    final data = response as List<dynamic>? ?? [];
    return data.map((doc) => DmeComplaint.fromMap(doc as Map<String, dynamic>)).toList();
  }

  /// Get complaints assigned to a specific user
  Future<List<DmeComplaint>> getAssignedComplaints({required String userId, String? status}) async {
    _ensureSupabaseInitialized();
    dynamic query = _supabase.from(_table).select(_selectClause).eq('assigned_to', userId);

    if (status != null) {
      query = query.eq('status', status);
    }

    query = query.order('created_at', ascending: false);

    final response = await query;
    final data = response as List<dynamic>? ?? [];
    return data.map((doc) => DmeComplaint.fromMap(doc as Map<String, dynamic>)).toList();
  }

  /// Get complaints for a specific branch
  Future<List<DmeComplaint>> getComplaintsForBranch({required int branchId, String? status}) async {
    _ensureSupabaseInitialized();
    dynamic query = _supabase.from(_table).select(_selectClause).eq('branch_id', branchId);

    if (status != null) {
      query = query.eq('status', status);
    }

    query = query.order('created_at', ascending: false);

    final response = await query;
    final data = response as List<dynamic>? ?? [];
    return data.map((doc) => DmeComplaint.fromMap(doc as Map<String, dynamic>)).toList();
  }

  /// Get a specific complaint
  Future<DmeComplaint?> getComplaint(String complaintId) async {
    _ensureSupabaseInitialized();
    final response = await _supabase.from(_table).select(_selectClause).eq('id', complaintId).single();

    if (response.isEmpty) return null;
    // ignore: unnecessary_cast
    return DmeComplaint.fromMap(response as Map<String, dynamic>);
  }

  /// Get complaints for a specific customer by name
  Future<List<DmeComplaint>> getComplaintsForCustomer({required String customerName, String? status}) async {
    _ensureSupabaseInitialized();
    dynamic query = _supabase.from(_table).select(_selectClause).eq('customer_name', customerName);

    if (status != null) {
      query = query.eq('status', status);
    }

    query = query.order('created_at', ascending: false);

    final response = await query;
    final data = response as List<dynamic>? ?? [];
    // ignore: unnecessary_cast
    return data.map((doc) => DmeComplaint.fromMap(doc as Map<String, dynamic>)).toList();
  }

  /// Get branch ID by branch name — delegates to branch cache to avoid DB hits.
  Future<int?> getBranchIdByName(String branchName) =>
      DmeSupabaseService.instance.getBranchIdByNameCached(branchName);

  /// Get username for a given user ID by looking up in dme_users table
  Future<String?> getUsernameById(String userId) async {
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();
      
      if (userDoc.exists) {
        return userDoc.data()?['username'] as String?;
      }
      return null;
    } catch (e) {
      debugPrint('Error fetching username for user $userId: $e');
      return null;
    }
  }

  /// Return complaint back to the original creator (sales user) when not resolved
  Future<void> returnToCreator({
    required String complaintId,
    required String creatorId,
  }) async {
    _ensureSupabaseInitialized();
    await _supabase.from(_table).update({
      'status': 'raised',
      'assigned_to': creatorId,
      'has_new_remarks': true,
      'resolved_by': null,
      'resolved_at': null,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', complaintId);
  }

  /// Mark complaint notification as seen by a specific user
  Future<void> markComplaintNotificationAsSeen({
    required String complaintId,
    required String userId,
  }) async {
    try {
      final docId = '${complaintId}__${userId}';
      await FirebaseFirestore.instance
          .collection('user_seen_complaints')
          .doc(docId)
          .set({
            'complaint_id': complaintId,
            'user_id': userId,
            'seen_at': DateTime.now().toIso8601String(),
          }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error marking complaint as seen: $e');
    }
  }

  /// Check if a complaint has been marked as seen by a specific user
  Future<bool> isComplaintSeen({
    required String complaintId,
    required String userId,
  }) async {
    try {
      final docId = '${complaintId}__${userId}';
      final doc = await FirebaseFirestore.instance
          .collection('user_seen_complaints')
          .doc(docId)
          .get();
      return doc.exists;
    } catch (e) {
      debugPrint('Error checking if complaint is seen: $e');
      return false;
    }
  }

  /// Delete a complaint from Supabase
  Future<void> deleteComplaint({required String complaintId}) async {
    _ensureSupabaseInitialized();
    await _supabase.from(_table).delete().eq('id', complaintId);
  }
}
