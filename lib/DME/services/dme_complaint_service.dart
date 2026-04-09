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

  /// Get select clause with all relationships
  String get _selectClause =>
      '*,created_by_user:dme_users!created_by(username),resolved_by_user:dme_users!resolved_by(username),closed_by_user:dme_users!closed_by(username),assigned_to_user:dme_users!assigned_to(username),remarked_by_user:dme_users!remarked_by(username)';

  /// Create a new complaint with assignment
  Future<String> createComplaint({
    required String customerName,
    required String customerPhone,
    required String branchName,
    required String complaintText,
    required String createdById,
    required String assignedToId,
  }) async {
    _ensureSupabaseInitialized();
    final response = await _supabase
        .from(_table)
        .insert({
          'customer_name': customerName,
          'customer_phone': customerPhone,
          'branch_name': branchName,
          'complaint_text': complaintText,
          'created_by': createdById,
          'assigned_to': assignedToId,
          'status': 'raised',
          'has_new_remarks': false,
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
  Future<List<DmeComplaint>> getAllComplaints({String? status, String? branch}) async {
    _ensureSupabaseInitialized();
    dynamic query = _supabase.from(_table).select(_selectClause);

    if (status != null) {
      query = query.eq('status', status);
    }
    if (branch != null) {
      query = query.eq('branch_name', branch);
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
  Future<List<DmeComplaint>> getComplaintsForBranch({required String branch, String? status}) async {
    _ensureSupabaseInitialized();
    dynamic query = _supabase.from(_table).select(_selectClause).eq('branch_name', branch);

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
}
