import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:mtcsync/DME/Misc/dme_config.dart';
import '../models/dme_complaint_model.dart';

class DmeComplaintsService {
  static final DmeComplaintsService instance = DmeComplaintsService._internal();
  DmeComplaintsService._internal();

  /// Send push notification via Firebase Functions
  Future<void> sendComplaintNotification({
    required String recipientUid,
    required String title,
    required String body,
    required int complaintId,
    bool isUnregistered = false,
    String notifType = 'dme_complaint',
  }) async {
    if (recipientUid.trim().isEmpty) return;
    try {
      await FirebaseFunctions.instanceFor(region: 'asia-south1')
          .httpsCallable('sendLeadAssignmentNotification')
          .call(<String, dynamic>{
        'recipientUid': recipientUid,
        'title': title,
        'body': body,
        'notifType': notifType,
        'leadDocId': complaintId.toString(),
        'complaintId': complaintId.toString(),
        'isUnregistered': isUnregistered.toString(),
      });
    } catch (e) {
      debugPrint('FCM Warning: Failed to send complaint notification to $recipientUid: $e');
    }
  }

  /// Register a new complaint from DME user
  Future<int> registerComplaint({
    int? reminderId,
    int? customerId,
    required String customerName,
    required String customerPhone,
    String? customerAddress,
    required String branch,
    required String description,
    required String createdByUid,
    String? createdByName,
    String? createdByEmail,
    required String assignedToUid,
    String? assignedToName,
    String? assignedToEmail,
    String? assignedToRole,
    String? initialAudioUrl,
  }) async {
    final client = await DmeConfig.getClient();
    if (client == null) throw Exception('Supabase is not configured.');

    final insertMap = <String, dynamic>{
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'branch': branch,
      'description': description,
      'created_by_uid': createdByUid,
      'assigned_to_uid': assignedToUid,
      'status': 'assigned',
      'is_escalated': false,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    };

    if (reminderId != null) insertMap['reminder_id'] = reminderId;
    if (customerId != null) insertMap['customer_id'] = customerId;
    if (customerAddress != null && customerAddress.isNotEmpty) insertMap['customer_address'] = customerAddress;
    if (createdByName != null) insertMap['created_by_name'] = createdByName;
    if (createdByEmail != null) insertMap['created_by_email'] = createdByEmail;
    if (assignedToName != null) insertMap['assigned_to_name'] = assignedToName;
    if (assignedToEmail != null) insertMap['assigned_to_email'] = assignedToEmail;
    if (assignedToRole != null) insertMap['assigned_to_role'] = assignedToRole;
    if (initialAudioUrl != null && initialAudioUrl.isNotEmpty) insertMap['initial_audio_url'] = initialAudioUrl;

    // 1. Insert into dme_complaints
    final res = await client.from('dme_complaints').insert(insertMap).select('id').single();
    final complaintId = res['id'] is int ? res['id'] as int : int.parse(res['id'].toString());

    // 2. Insert initial timeline entry into dme_complaint_updates
    try {
      await client.from('dme_complaint_updates').insert({
        'complaint_id': complaintId,
        'action_type': 'created',
        'action_by_uid': createdByUid,
        'action_by_name': createdByName ?? 'DME User',
        'action_by_role': 'dme_user',
        'remarks': description,
        'audio_url': initialAudioUrl,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Warning: Failed to insert timeline update: $e');
    }

    // 3. Send notification to assigned user
    unawaited(sendComplaintNotification(
      recipientUid: assignedToUid,
      title: 'New Complaint Assigned',
      body: 'Complaint for "$customerName" assigned to you: "$description"',
      complaintId: complaintId,
    ));

    // 4. Send notification to branch manager(s)
    unawaited(() async {
      try {
        final managersSnap = await FirebaseFirestore.instance
            .collection('users')
            .where('branch', isEqualTo: branch)
            .where('role', isEqualTo: 'manager')
            .get();

        for (var doc in managersSnap.docs) {
          final mUid = doc.id;
          if (mUid != assignedToUid) {
            await sendComplaintNotification(
              recipientUid: mUid,
              title: 'Branch Complaint Raised ($branch)',
              body: 'Complaint for "$customerName" assigned to ${assignedToName ?? 'team member'}',
              complaintId: complaintId,
            );
          }
        }
      } catch (e) {
        debugPrint('Warning: Could not notify branch managers: $e');
      }
    }());

    return complaintId;
  }

  /// Register a complaint for an unregistered customer (stored in dme_unregistered_customer_complaints)
  Future<int> registerUnregisteredComplaint({
    required String customerName,
    required String customerPhone,
    String? customerAddress,
    required String branch,
    required String description,
    required String createdByUid,
    String? createdByName,
    String? createdByEmail,
    required String assignedToUid,
    String? assignedToName,
    String? assignedToEmail,
    String? assignedToRole,
    String? initialAudioUrl,
  }) async {
    final client = await DmeConfig.getClient();
    if (client == null) throw Exception('Supabase is not configured.');

    final insertMap = <String, dynamic>{
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'branch': branch,
      'description': description,
      'created_by_uid': createdByUid,
      'assigned_to_uid': assignedToUid,
      'status': 'assigned',
      'is_escalated': false,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    };

    if (customerAddress != null && customerAddress.isNotEmpty) insertMap['customer_address'] = customerAddress;
    if (createdByName != null) insertMap['created_by_name'] = createdByName;
    if (createdByEmail != null) insertMap['created_by_email'] = createdByEmail;
    if (assignedToName != null) insertMap['assigned_to_name'] = assignedToName;
    if (assignedToEmail != null) insertMap['assigned_to_email'] = assignedToEmail;
    if (assignedToRole != null) insertMap['assigned_to_role'] = assignedToRole;
    if (initialAudioUrl != null && initialAudioUrl.isNotEmpty) insertMap['initial_audio_url'] = initialAudioUrl;

    // 1. Insert into dme_unregistered_customer_complaints
    final res = await client.from('dme_unregistered_customer_complaints').insert(insertMap).select('id').single();
    final complaintId = res['id'] is int ? res['id'] as int : int.parse(res['id'].toString());

    // 2. Insert initial timeline entry into dme_unregistered_complaint_updates
    try {
      await client.from('dme_unregistered_complaint_updates').insert({
        'complaint_id': complaintId,
        'action_type': 'created',
        'action_by_uid': createdByUid,
        'action_by_name': createdByName ?? 'DME User',
        'action_by_role': 'dme_user',
        'remarks': description,
        'audio_url': initialAudioUrl,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Warning: Failed to insert unregistered timeline update: $e');
    }

    // 3. Send notification to assigned user
    unawaited(sendComplaintNotification(
      recipientUid: assignedToUid,
      title: 'New Complaint Assigned (Unregistered Customer)',
      body: 'Complaint for "$customerName" assigned to you: "$description"',
      complaintId: complaintId,
      isUnregistered: true,
    ));

    // 4. Send notification to branch manager(s)
    unawaited(() async {
      try {
        final managersSnap = await FirebaseFirestore.instance
            .collection('users')
            .where('branch', isEqualTo: branch)
            .where('role', isEqualTo: 'manager')
            .get();

        for (var doc in managersSnap.docs) {
          final mUid = doc.id;
          if (mUid != assignedToUid) {
            await sendComplaintNotification(
              recipientUid: mUid,
              title: 'Branch Complaint Raised ($branch)',
              body: 'Complaint for "$customerName" (Unregistered) assigned to ${assignedToName ?? 'team member'}',
              complaintId: complaintId,
              isUnregistered: true,
            );
          }
        }
      } catch (e) {
        debugPrint('Warning: Could not notify branch managers: $e');
      }
    }());

    return complaintId;
  }

  /// Assigned user submits action taken (called customer, remarks, voice record)
  Future<void> submitActionTaken({
    required int complaintId,
    bool isUnregistered = false,
    required String actionByUid,
    required String actionByName,
    String? actionByRole,
    required String remarks,
    String? audioUrl,
    required String createdByUid, // DME user to notify
    required String customerName,
  }) async {
    final client = await DmeConfig.getClient();
    if (client == null) throw Exception('Supabase is not configured.');

    final now = DateTime.now();
    final tableName = isUnregistered ? 'dme_unregistered_customer_complaints' : 'dme_complaints';
    final updatesTable = isUnregistered ? 'dme_unregistered_complaint_updates' : 'dme_complaint_updates';

    // 1. Update complaints table
    await client.from(tableName).update({
      'status': 'action_taken',
      'action_remarks': remarks,
      'action_audio_url': audioUrl,
      'action_taken_at': now.toIso8601String(),
      'action_taken_by_uid': actionByUid,
      'action_taken_by_name': actionByName,
      'updated_at': now.toIso8601String(),
    }).eq('id', complaintId);

    // 2. Insert into complaint updates table
    try {
      await client.from(updatesTable).insert({
        'complaint_id': complaintId,
        'action_type': 'action_taken',
        'action_by_uid': actionByUid,
        'action_by_name': actionByName,
        'action_by_role': actionByRole ?? 'sales',
        'remarks': remarks,
        'audio_url': audioUrl,
        'created_at': now.toIso8601String(),
      });
    } catch (e) {
      debugPrint('Warning: Failed to insert timeline update: $e');
    }

    // 3. Send notification back to DME user using complaint_review_pending sound
    unawaited(sendComplaintNotification(
      recipientUid: createdByUid,
      title: 'Complaint Update Submitted',
      body: '$actionByName took action on complaint for "$customerName". Please verify resolution.',
      complaintId: complaintId,
      isUnregistered: isUnregistered,
      notifType: 'complaint_review_pending',
    ));
  }

  /// DME User marks complaint as Resolved
  Future<void> markResolved({
    required int complaintId,
    bool isUnregistered = false,
    required String verifiedByUid,
    required String verifiedByName,
    String? remarks,
    required String assignedToUid,
    String? createdByUid,
    required String customerName,
  }) async {
    final client = await DmeConfig.getClient();
    if (client == null) throw Exception('Supabase is not configured.');

    final now = DateTime.now();
    final tableName = isUnregistered ? 'dme_unregistered_customer_complaints' : 'dme_complaints';
    final updatesTable = isUnregistered ? 'dme_unregistered_complaint_updates' : 'dme_complaint_updates';

    // 1. Update complaints table
    await client.from(tableName).update({
      'status': 'resolved',
      'dme_resolution_remarks': remarks ?? 'Resolved by DME',
      'resolved_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    }).eq('id', complaintId);

    // 2. Insert timeline entry
    try {
      await client.from(updatesTable).insert({
        'complaint_id': complaintId,
        'action_type': 'resolved',
        'action_by_uid': verifiedByUid,
        'action_by_name': verifiedByName,
        'action_by_role': 'dme_user',
        'remarks': remarks ?? 'Marked as Resolved',
        'created_at': now.toIso8601String(),
      });
    } catch (e) {
      debugPrint('Warning: Failed to insert timeline update: $e');
    }

    // 3. Send notification with complaint_resolved sound to raised DME user
    if (createdByUid != null && createdByUid.isNotEmpty && createdByUid != verifiedByUid) {
      unawaited(sendComplaintNotification(
        recipientUid: createdByUid,
        title: 'Complaint Resolved ✓',
        body: 'Complaint for "$customerName" has been marked as resolved.',
        complaintId: complaintId,
        isUnregistered: isUnregistered,
        notifType: 'complaint_resolved',
      ));
    }

    // 4. Also notify assigned user with complaint_resolved sound if different
    if (assignedToUid.isNotEmpty && assignedToUid != verifiedByUid && assignedToUid != createdByUid) {
      unawaited(sendComplaintNotification(
        recipientUid: assignedToUid,
        title: 'Complaint Resolved ✓',
        body: 'Complaint for "$customerName" has been marked as resolved.',
        complaintId: complaintId,
        isUnregistered: isUnregistered,
        notifType: 'complaint_resolved',
      ));
    }
  }

  /// DME User marks complaint as Not Resolved (sends back to assigned user with remarks)
  Future<void> markNotResolved({
    required int complaintId,
    bool isUnregistered = false,
    required String verifiedByUid,
    required String verifiedByName,
    required String remarks,
    required String assignedToUid,
    required String customerName,
  }) async {
    final client = await DmeConfig.getClient();
    if (client == null) throw Exception('Supabase is not configured.');

    final now = DateTime.now();
    final tableName = isUnregistered ? 'dme_unregistered_customer_complaints' : 'dme_complaints';
    final updatesTable = isUnregistered ? 'dme_unregistered_complaint_updates' : 'dme_complaint_updates';

    // 1. Update complaints table
    await client.from(tableName).update({
      'status': 'not_resolved',
      'dme_resolution_remarks': remarks,
      'updated_at': now.toIso8601String(),
    }).eq('id', complaintId);

    // 2. Insert timeline entry
    try {
      await client.from(updatesTable).insert({
        'complaint_id': complaintId,
        'action_type': 'not_resolved',
        'action_by_uid': verifiedByUid,
        'action_by_name': verifiedByName,
        'action_by_role': 'dme_user',
        'remarks': remarks,
        'created_at': now.toIso8601String(),
      });
    } catch (e) {
      debugPrint('Warning: Failed to insert timeline update: $e');
    }

    // 3. Send notification back to assigned user showing remarks
    unawaited(sendComplaintNotification(
      recipientUid: assignedToUid,
      title: 'Complaint Not Resolved - Action Required',
      body: 'Remarks from DME: "$remarks". Please follow up with customer again.',
      complaintId: complaintId,
      isUnregistered: isUnregistered,
    ));
  }

  /// Manager escalates complaint to themselves
  Future<void> escalateComplaint({
    required int complaintId,
    bool isUnregistered = false,
    required String managerUid,
    required String managerName,
    required String managerEmail,
    required String formerAssignedToUid,
    required String formerAssignedToName,
    required String formerAssignedToEmail,
    required String customerName,
  }) async {
    final client = await DmeConfig.getClient();
    if (client == null) throw Exception('Supabase is not configured.');

    final now = DateTime.now();
    final tableName = isUnregistered ? 'dme_unregistered_customer_complaints' : 'dme_complaints';
    final updatesTable = isUnregistered ? 'dme_unregistered_complaint_updates' : 'dme_complaint_updates';

    // 1. Update complaints table: assign to manager, store former user data
    await client.from(tableName).update({
      'assigned_to_uid': managerUid,
      'assigned_to_name': managerName,
      'assigned_to_email': managerEmail,
      'assigned_to_role': 'manager',
      'is_escalated': true,
      'former_assigned_to_uid': formerAssignedToUid,
      'former_assigned_to_name': formerAssignedToName,
      'former_assigned_to_email': formerAssignedToEmail,
      'escalated_by_uid': managerUid,
      'escalated_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    }).eq('id', complaintId);

    // 2. Insert timeline entry
    try {
      await client.from(updatesTable).insert({
        'complaint_id': complaintId,
        'action_type': 'escalated',
        'action_by_uid': managerUid,
        'action_by_name': managerName,
        'action_by_role': 'manager',
        'remarks': 'Escalated by Manager $managerName from $formerAssignedToName',
        'created_at': now.toIso8601String(),
      });
    } catch (e) {
      debugPrint('Warning: Failed to insert timeline update: $e');
    }

    // 3. Notify former user
    unawaited(sendComplaintNotification(
      recipientUid: formerAssignedToUid,
      title: 'Complaint Escalated',
      body: 'Complaint for "$customerName" has been escalated to Manager $managerName.',
      complaintId: complaintId,
      isUnregistered: isUnregistered,
    ));
  }

  /// Fetch single complaint by ID with its timeline updates
  Future<Map<String, dynamic>> fetchComplaintWithHistory(int complaintId, {bool isUnregistered = false}) async {
    final client = await DmeConfig.getClient();
    if (client == null) throw Exception('Supabase is not configured.');

    final tableName = isUnregistered ? 'dme_unregistered_customer_complaints' : 'dme_complaints';

    Map<String, dynamic>? complaintData;
    bool foundInUnregistered = isUnregistered;

    try {
      complaintData = await client
          .from(tableName)
          .select('*')
          .eq('id', complaintId)
          .maybeSingle();
    } catch (_) {}

    // Fallback if not found in requested table
    if (complaintData == null) {
      final altTable = isUnregistered ? 'dme_complaints' : 'dme_unregistered_customer_complaints';
      final altRes = await client.from(altTable).select('*').eq('id', complaintId).maybeSingle();
      if (altRes != null) {
        complaintData = altRes;
        foundInUnregistered = !isUnregistered;
      }
    }

    if (complaintData == null) {
      throw Exception('Complaint #$complaintId not found.');
    }

    final effectiveUpdatesTable = foundInUnregistered ? 'dme_unregistered_complaint_updates' : 'dme_complaint_updates';

    List<DmeComplaintUpdate> updates = [];
    try {
      final updatesRes = await client
          .from(effectiveUpdatesTable)
          .select('*')
          .eq('complaint_id', complaintId)
          .order('created_at', ascending: true);

      updates = (updatesRes as List).map((m) => DmeComplaintUpdate.fromMap(m)).toList();
    } catch (e) {
      debugPrint('Error fetching complaint updates: $e');
    }

    return {
      'complaint': DmeComplaint.fromMap(complaintData, isUnregistered: foundInUnregistered),
      'updates': updates,
    };
  }

  /// Fetch active complaints assigned to a specific user (for Sales / Asst. Manager)
  /// Combines standard complaints and unregistered complaints
  Future<List<DmeComplaint>> fetchAssignedComplaints(String uid) async {
    final client = await DmeConfig.getClient();
    if (client == null) return [];

    try {
      final futures = await Future.wait([
        client.from('dme_complaints').select('*').eq('assigned_to_uid', uid).order('updated_at', ascending: false),
        client.from('dme_unregistered_customer_complaints').select('*').eq('assigned_to_uid', uid).order('updated_at', ascending: false).catchError((_) => []),
      ]);

      final regular = (futures[0] as List).map((m) => DmeComplaint.fromMap(m)).toList();
      final unregistered = (futures[1] as List).map((m) => DmeComplaint.fromMap(m, isUnregistered: true)).toList();

      final combined = [...regular, ...unregistered];
      combined.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return combined;
    } catch (e) {
      debugPrint('Error fetching assigned complaints: $e');
      return [];
    }
  }

  /// Fetch active complaints count for homepage button badge
  Future<int> fetchActiveAssignedCount(String uid) async {
    final client = await DmeConfig.getClient();
    if (client == null) return 0;

    try {
      final results = await Future.wait([
        client.from('dme_complaints').select('id').eq('assigned_to_uid', uid).neq('status', 'resolved'),
        client.from('dme_unregistered_customer_complaints').select('id').eq('assigned_to_uid', uid).neq('status', 'resolved').catchError((_) => []),
      ]);

      return (results[0] as List).length + (results[1] as List).length;
    } catch (e) {
      debugPrint('Error counting assigned complaints: $e');
      return 0;
    }
  }

  /// Fetch count of complaints with action taken (for DME user homepage badge)
  Future<int> fetchActionTakenCount({String? createdByUid}) async {
    final client = await DmeConfig.getClient();
    if (client == null) return 0;

    try {
      var query1 = client.from('dme_complaints').select('id').eq('status', 'action_taken');
      var query2 = client.from('dme_unregistered_customer_complaints').select('id').eq('status', 'action_taken');

      if (createdByUid != null && createdByUid.isNotEmpty) {
        query1 = query1.eq('created_by_uid', createdByUid);
        query2 = query2.eq('created_by_uid', createdByUid);
      }

      final results = await Future.wait([
        query1,
        query2.catchError((_) => []),
      ]);

      return (results[0] as List).length + (results[1] as List).length;
    } catch (e) {
      debugPrint('Error counting action taken complaints: $e');
      return 0;
    }
  }

  /// Fetch complaints for DME User view (combines regular & unregistered)
  Future<List<DmeComplaint>> fetchDmeComplaints({String? statusFilter, String? createdByUid}) async {
    final client = await DmeConfig.getClient();
    if (client == null) return [];

    try {
      var q1 = client.from('dme_complaints').select('*');
      var q2 = client.from('dme_unregistered_customer_complaints').select('*');

      if (createdByUid != null && createdByUid.isNotEmpty) {
        q1 = q1.eq('created_by_uid', createdByUid);
        q2 = q2.eq('created_by_uid', createdByUid);
      }
      if (statusFilter != null && statusFilter.isNotEmpty && statusFilter != 'all') {
        q1 = q1.eq('status', statusFilter);
        q2 = q2.eq('status', statusFilter);
      }

      final results = await Future.wait([
        q1.order('created_at', ascending: false).limit(100),
        q2.order('created_at', ascending: false).limit(100).catchError((_) => []),
      ]);

      final regular = (results[0] as List).map((m) => DmeComplaint.fromMap(m)).toList();
      final unregistered = (results[1] as List).map((m) => DmeComplaint.fromMap(m, isUnregistered: true)).toList();

      final combined = [...regular, ...unregistered];
      combined.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return combined;
    } catch (e) {
      debugPrint('Error fetching DME complaints: $e');
      return [];
    }
  }

  /// Fetch complaints for Manager view (combines regular & unregistered)
  Future<List<DmeComplaint>> fetchManagerComplaints({
    required String branch,
    String? userUid,
  }) async {
    final client = await DmeConfig.getClient();
    if (client == null) return [];

    try {
      var q1 = client.from('dme_complaints').select('*').eq('branch', branch);
      var q2 = client.from('dme_unregistered_customer_complaints').select('*').eq('branch', branch);

      if (userUid != null && userUid.isNotEmpty) {
        q1 = q1.eq('assigned_to_uid', userUid);
        q2 = q2.eq('assigned_to_uid', userUid);
      }

      final results = await Future.wait([
        q1.order('created_at', ascending: false).limit(100),
        q2.order('created_at', ascending: false).limit(100).catchError((_) => []),
      ]);

      final regular = (results[0] as List).map((m) => DmeComplaint.fromMap(m)).toList();
      final unregistered = (results[1] as List).map((m) => DmeComplaint.fromMap(m, isUnregistered: true)).toList();

      final combined = [...regular, ...unregistered];
      combined.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return combined;
    } catch (e) {
      debugPrint('Error fetching manager complaints: $e');
      return [];
    }
  }

  /// Fetch complaints for Admin / DME Admin (Read-Only)
  Future<List<DmeComplaint>> fetchAdminComplaints({
    required String branch,
    String? userUid,
  }) async {
    final client = await DmeConfig.getClient();
    if (client == null) return [];

    try {
      var q1 = client.from('dme_complaints').select('*');
      var q2 = client.from('dme_unregistered_customer_complaints').select('*');

      if (branch.isNotEmpty && branch != 'All') {
        q1 = q1.eq('branch', branch);
        q2 = q2.eq('branch', branch);
      }
      if (userUid != null && userUid.isNotEmpty && userUid != 'All') {
        q1 = q1.eq('assigned_to_uid', userUid);
        q2 = q2.eq('assigned_to_uid', userUid);
      }

      final results = await Future.wait([
        q1.order('created_at', ascending: false).limit(100),
        q2.order('created_at', ascending: false).limit(100).catchError((_) => []),
      ]);

      final regular = (results[0] as List).map((m) => DmeComplaint.fromMap(m)).toList();
      final unregistered = (results[1] as List).map((m) => DmeComplaint.fromMap(m, isUnregistered: true)).toList();

      final combined = [...regular, ...unregistered];
      combined.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return combined;
    } catch (e) {
      debugPrint('Error fetching admin complaints: $e');
      return [];
    }
  }

  /// Delete a complaint and its timeline updates
  Future<void> deleteComplaint(int complaintId, {bool isUnregistered = false}) async {
    final client = await DmeConfig.getClient();
    if (client == null) throw Exception('Supabase is not configured.');

    final tableName = isUnregistered ? 'dme_unregistered_customer_complaints' : 'dme_complaints';
    final updatesTable = isUnregistered ? 'dme_unregistered_complaint_updates' : 'dme_complaint_updates';

    // 1. Delete timeline updates for this complaint
    try {
      await client.from(updatesTable).delete().eq('complaint_id', complaintId);
    } catch (e) {
      debugPrint('Warning: Failed to delete complaint updates: $e');
    }

    // 2. Delete complaint record
    await client.from(tableName).delete().eq('id', complaintId);
  }

  /// Fetch customer sales history with products detail from Supabase
  static Future<List<Map<String, dynamic>>> fetchCustomerSales(int customerId) async {
    final client = await DmeConfig.getClient();
    if (client == null) return [];

    try {
      List<Map<String, dynamic>> salesList = [];
      try {
        final res = await client
            .from('dme_sales')
            .select('id, date, purchased_branch, salesman, category_id, customer_type_id, dme_sales_detail(products)')
            .eq('customer_id', customerId)
            .order('date', ascending: false)
            .limit(10);
        salesList = List<Map<String, dynamic>>.from(res);
      } catch (_) {
        final resFallback = await client
            .from('dme_sales')
            .select('id, date, purchased_branch, salesman, category_id, customer_type_id')
            .eq('customer_id', customerId)
            .order('date', ascending: false)
            .limit(10);
        salesList = List<Map<String, dynamic>>.from(resFallback);
      }

      final saleIdsNeedingDetails = salesList.where((s) {
        final dt = s['dme_sales_detail'];
        return dt == null || (dt is List && dt.isEmpty);
      }).map((s) => s['id']).where((id) => id != null).toList();

      if (saleIdsNeedingDetails.isNotEmpty) {
        try {
          final detailRows = await client
              .from('dme_sales_detail')
              .select('sale_id, products')
              .inFilter('sale_id', saleIdsNeedingDetails);

          final Map<dynamic, dynamic> detailMap = {};
          for (var r in (detailRows as List)) {
            final sId = r['sale_id'];
            if (sId != null) detailMap[sId] = r['products'];
          }

          for (var s in salesList) {
            final sId = s['id'];
            if (detailMap.containsKey(sId)) {
              s['dme_sales_detail'] = [
                {'products': detailMap[sId]}
              ];
            }
          }
        } catch (_) {}
      }

      return salesList;
    } catch (e) {
      debugPrint('Error fetching customer sales: $e');
      return [];
    }
  }
}
