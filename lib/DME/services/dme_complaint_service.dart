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

  /// Create a new complaint
  Future<String> createComplaint(DmeComplaint complaint) async {
    _ensureSupabaseInitialized();
    final response = await _supabase
        .from(_table)
        .insert({
          'customer_name': complaint.customerName,
          'customer_phone': complaint.customerPhone,
          'branch_name': complaint.branchName,
          'complaint_text': complaint.complaintText,
          'created_by': complaint.createdById,
          'status': 'raised',
        })
        .select('id')
        .single();

    return response['id'] as String;
  }

  /// Update complaint status with explicit FK relationship names
  /// Uses relationship: !created_by, !resolved_by, !closed_by to avoid PostgREST ambiguity
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

  /// Get all complaints with explicit relationship selects to avoid PostgREST ambiguity
  Future<List<DmeComplaint>> getAllComplaints({String? status, String? branch}) async {
    _ensureSupabaseInitialized();
    dynamic query = _supabase
        .from(_table)
        .select('*,created_by_user:dme_users!created_by(username),resolved_by_user:dme_users!resolved_by(username),closed_by_user:dme_users!closed_by(username)');

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

  /// Get complaints raised by a specific user
  Future<List<DmeComplaint>> getComplaintsByUser({required String userId, String? status}) async {
    _ensureSupabaseInitialized();
    dynamic query = _supabase
        .from(_table)
        .select('*,created_by_user:dme_users!created_by(username),resolved_by_user:dme_users!resolved_by(username),closed_by_user:dme_users!closed_by(username)')
        .eq('created_by', userId);

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
    dynamic query = _supabase
        .from(_table)
        .select('*,created_by_user:dme_users!created_by(username),resolved_by_user:dme_users!resolved_by(username),closed_by_user:dme_users!closed_by(username)')
        .eq('branch_name', branch);

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
    final response = await _supabase
        .from(_table)
        .select('*,created_by_user:dme_users!created_by(username),resolved_by_user:dme_users!resolved_by(username),closed_by_user:dme_users!closed_by(username)')
        .eq('id', complaintId)
        .single();

    if (response.isEmpty) return null;
    return DmeComplaint.fromMap(response as Map<String, dynamic>);
  }
}
