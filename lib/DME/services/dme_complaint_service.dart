import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/dme_complaint.dart';

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
  }) async {
    _ensureSupabaseInitialized();
    
    // Validate that assignedToId is not empty
    if (assignedToId.isEmpty) {
      throw Exception('assignedToId is mandatory. Every complaint must be assigned to a user.');
    }
    
    final response = await _supabase
        .from(_table)
        .insert({
          'customer_name': customerName,
          'customer_phone': customerPhone,
          'branch_id': branchId,
          'complaint_text': complaintText,
          'created_by': createdById,
          'assigned_to': assignedToId, // MANDATORY - included in initial insert
          'status': 'raised',
          'has_new_remarks': false,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .select('id')
        .single();

    return response['id'] as String;
  }

  /// Add remarks to a complaint
  Future<void> addRemarks({
    required String complaintId,
    required String remarks,
    required String userId,
  }) async {
    _ensureSupabaseInitialized();
    await _supabase.from(_table).update({
      'remarks': remarks,
      'remarked_by': userId,
      'remarked_at': DateTime.now().toIso8601String(),
      'has_new_remarks': true,
      'status': 'case_resolved',
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', complaintId);
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
  Future<List<DmeComplaint>> getAllComplaints({String? status, int? branchId}) async {
    _ensureSupabaseInitialized();
    dynamic query = _supabase.from(_table).select(_selectClause);

    if (status != null) {
      query = query.eq('status', status);
    }
    if (branchId != null) {
      query = query.eq('branch_id', branchId);
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
    return DmeComplaint.fromMap(response as Map<String, dynamic>);
  }

  /// Get username for a given user ID by looking up in dme_users table
  Future<String?> getUsernameById(String userId) async {
    _ensureSupabaseInitialized();
    try {
      final response = await _supabase
          .from('dme_users')
          .select('username')
          .eq('id', userId)
          .maybeSingle();
      
      return response != null ? response['username'] as String? : null;
    } catch (e) {
      debugPrint('Error fetching username for user $userId: $e');
      return null;
    }
  }
}
