import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../../Misc/dme_config.dart';

class ReminderInitialBundle {
  final Map<String, String> userNames;
  final Map<String, dynamic>? customerDetails;
  final List<Map<String, dynamic>> branches;
  final List<Map<String, dynamic>> salesHistory;
  final List<Map<String, dynamic>> callHistory;
  final List<Map<String, dynamic>> reminderLogs;
  final bool hasShortAttendedCall;
  final Map<String, dynamic>? pendingRequest;

  const ReminderInitialBundle({
    required this.userNames,
    this.customerDetails,
    required this.branches,
    required this.salesHistory,
    required this.callHistory,
    required this.reminderLogs,
    required this.hasShortAttendedCall,
    this.pendingRequest,
  });
}

class DmeReminderDataService {
  static Future<ReminderInitialBundle> loadInitialBundle({
    required dynamic customerId,
    required dynamic reminderId,
  }) async {
    final futures = await Future.wait([
      loadUserNames(),
      fetchCustomerDetails(customerId),
      fetchCustomerBranches(customerId),
      fetchCustomerSalesHistory(customerId),
      fetchCustomerCallHistory(customerId: customerId, currentRemId: reminderId),
      fetchReminderCallLogs(reminderId),
      checkIfShortAttendedCallExists(reminderId),
      checkPendingRequests(remId: reminderId, custId: customerId),
    ]);

    return ReminderInitialBundle(
      userNames: futures[0] as Map<String, String>,
      customerDetails: futures[1] as Map<String, dynamic>?,
      branches: futures[2] as List<Map<String, dynamic>>,
      salesHistory: futures[3] as List<Map<String, dynamic>>,
      callHistory: futures[4] as List<Map<String, dynamic>>,
      reminderLogs: futures[5] as List<Map<String, dynamic>>,
      hasShortAttendedCall: futures[6] as bool,
      pendingRequest: futures[7] as Map<String, dynamic>?,
    );
  }

  static Future<Map<String, String>> loadUserNames() async {
    final Map<String, String> userNames = {};
    try {
      final snap = await FirebaseFirestore.instance.collection('users').get();
      for (var doc in snap.docs) {
        final data = doc.data();
        final uid = doc.id;
        final email = data['email']?.toString() ?? '';
        final username = data['username']?.toString() ??
            data['name']?.toString() ??
            (email.isNotEmpty ? email.split('@').first : 'User');
        userNames[uid] = username;
        if (email.isNotEmpty) {
          userNames[email] = username;
          userNames[email.toLowerCase()] = username;
        }
      }
    } catch (_) {}
    return userNames;
  }


  static Future<Map<String, dynamic>?> fetchCustomerDetails(dynamic customerId) async {
    if (customerId == null) return null;
    final client = await DmeConfig.getClient();
    if (client == null) return null;

    try {
      Map<String, dynamic>? res;
      try {
        res = await client
            .from('dme_customers')
            .select('phone, preference, "Contact_Person"')
            .eq('id', customerId)
            .maybeSingle();
      } catch (_) {
        res = await client
            .from('dme_customers')
            .select('phone, preference')
            .eq('id', customerId)
            .maybeSingle();
      }
      return res;
    } catch (_) {
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>> fetchCustomerBranches(dynamic customerId) async {
    if (customerId == null) return [];
    final client = await DmeConfig.getClient();
    if (client == null) return [];

    try {
      final res = await client
          .from('dme_customer_branches')
          .select('branch_id, customer_type_id, category_id')
          .eq('customer_id', customerId);
      return List<Map<String, dynamic>>.from(res);
    } catch (e) {
      debugPrint('Error fetching customer branches: $e');
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> fetchCustomerSalesHistory(dynamic customerId) async {
    if (customerId == null) return [];
    final client = await DmeConfig.getClient();
    if (client == null) return [];

    try {
      List<dynamic> res;
      try {
        res = await client
            .from('dme_sales')
            .select('*, dme_sales_detail(*)')
            .eq('customer_id', customerId)
            .order('date', ascending: false);
      } catch (_) {
        res = await client
            .from('dme_sales')
            .select('*')
            .eq('customer_id', customerId)
            .order('date', ascending: false);
      }

      final salesList = List<Map<String, dynamic>>.from(res);

      for (var sale in salesList) {
        final details = sale['dme_sales_detail'];
        if (details == null || (details is List && details.isEmpty)) {
          final saleId = sale['id'];
          if (saleId != null) {
            try {
              final detRes = await client
                  .from('dme_sales_detail')
                  .select('*')
                  .eq('sale_id', saleId);
              if (detRes.isNotEmpty) {
                sale['dme_sales_detail'] = detRes;
              }
            } catch (_) {}
          }
        }
      }
      return salesList;
    } catch (e) {
      debugPrint('Error fetching sales history: $e');
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> fetchCustomerCallHistory({
    required dynamic customerId,
    required dynamic currentRemId,
  }) async {
    if (customerId == null) return [];
    final client = await DmeConfig.getClient();
    if (client == null) return [];

    try {
      List<dynamic> res;
      try {
        res = await client
            .from('dme_reminders')
            .select(
              'id, reminder_date, last_purchase_branch, status, remarks, call_duration, called_timestamp, called_by, updated_at',
            )
            .eq('customer_id', customerId)
            .neq('id', currentRemId ?? 0)
            .inFilter('status', ['completed', 'called'])
            .order('called_timestamp', ascending: false);
      } catch (err) {
        if (err.toString().contains('called_by')) {
          res = await client
              .from('dme_reminders')
              .select(
                'id, reminder_date, last_purchase_branch, status, remarks, call_duration, called_timestamp, updated_at',
              )
              .eq('customer_id', customerId)
              .neq('id', currentRemId ?? 0)
              .inFilter('status', ['completed', 'called'])
              .order('called_timestamp', ascending: false);
        } else {
          rethrow;
        }
      }
      return List<Map<String, dynamic>>.from(res);
    } catch (e) {
      debugPrint('Error fetching customer call history: $e');
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> fetchReminderCallLogs(dynamic remId) async {
    if (remId == null) return [];
    final client = await DmeConfig.getClient();
    if (client == null) return [];

    try {
      final res = await client
          .from('dme_call_logs')
          .select('*')
          .eq('reminder_id', remId)
          .order('attempt_timestamp', ascending: false);
      return List<Map<String, dynamic>>.from(res);
    } catch (e) {
      debugPrint('Error fetching reminder call logs: $e');
      return [];
    }
  }

  static Future<bool> checkIfShortAttendedCallExists(dynamic remId) async {
    if (remId == null) return false;
    final client = await DmeConfig.getClient();
    if (client == null) return false;

    try {
      final res = await client
          .from('dme_call_logs')
          .select('ring_duration')
          .eq('reminder_id', remId);
      final logs = List<Map<String, dynamic>>.from(res);
      return logs.any((l) {
        final dur = int.tryParse(l['ring_duration']?.toString() ?? '') ?? 0;
        return dur > 0 && dur <= 10;
      });
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, dynamic>?> checkPendingRequests({
    dynamic remId,
    dynamic custId,
  }) async {
    final client = await DmeConfig.getClient();
    if (client == null) return null;

    try {
      var query = client
          .from('dme_change_requests')
          .select('id, request_type, status')
          .eq('status', 'pending');

      if (remId != null) {
        query = query.eq('reminder_id', remId);
      } else if (custId != null) {
        query = query.eq('customer_id', custId);
      } else {
        return null;
      }

      final res = await query.limit(1);
      if (res.isNotEmpty) {
        return Map<String, dynamic>.from(res.first);
      }
    } catch (e) {
      debugPrint('Error checking pending requests: $e');
    }
    return null;
  }

  static Future<void> saveContactPerson({
    required dynamic customerId,
    required String text,
  }) async {
    if (customerId == null) return;
    final client = await DmeConfig.getClient();
    if (client == null) return;

    try {
      await client.from('dme_customers').update({
        'Contact_Person': text.isEmpty ? null : text,
      }).eq('id', customerId);
    } catch (_) {
      await client.from('dme_customers').update({
        'contact_person': text.isEmpty ? null : text,
      }).eq('id', customerId);
    }
  }

  static Future<void> updateCallAttemptsInDb({
    required dynamic reminderId,
    required int totalAttempts,
    required int todayAttempts,
    required DateTime lastAttemptTimestamp,
  }) async {
    try {
      final client = await DmeConfig.getClient();
      if (client == null || reminderId == null) return;

      final todayStr = DateFormat('yyyy-MM-dd').format(lastAttemptTimestamp);
      final userEmail = FirebaseAuth.instance.currentUser?.email;

      final updatePayload = <String, dynamic>{
        'call_attempts': totalAttempts,
        'today_call_attempts': todayAttempts,
        'last_call_attempt_timestamp': lastAttemptTimestamp.toUtc().toIso8601String(),
        'last_call_day': todayStr,
        if (userEmail != null && userEmail.isNotEmpty) 'called_by': userEmail,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      try {
        await client.from('dme_reminders').update(updatePayload).eq('id', reminderId);
      } catch (_) {
        try {
          updatePayload.remove('today_call_attempts');
          updatePayload.remove('last_call_attempt_timestamp');
          updatePayload.remove('last_call_day');
          await client.from('dme_reminders').update(updatePayload).eq('id', reminderId);
        } catch (_) {}
      }
    } catch (_) {}
  }

  static Future<void> markReminderCompleted({
    required dynamic reminderId,
    required String remarks,
    required int? callDuration,
    required DateTime? calledTimestamp,
  }) async {
    final client = await DmeConfig.getClient();
    if (client == null || reminderId == null) return;

    final userEmail = FirebaseAuth.instance.currentUser?.email;
    final updatePayload = <String, dynamic>{
      'status': 'completed',
      'remarks': remarks,
      'call_duration': callDuration,
      'called_timestamp': (calledTimestamp ?? DateTime.now()).toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (userEmail != null && userEmail.isNotEmpty) {
      updatePayload['called_by'] = userEmail;
    }

    try {
      await client.from('dme_reminders').update(updatePayload).eq('id', reminderId);
    } catch (err) {
      if (err.toString().contains('called_by')) {
        updatePayload.remove('called_by');
        await client.from('dme_reminders').update(updatePayload).eq('id', reminderId);
      } else {
        rethrow;
      }
    }
  }

  static Future<void> updateReminderAfterCall({
    required dynamic reminderId,
    required int callAttempts,
    required int todayCallAttempts,
    required DateTime calledTime,
    required String todayStr,
    required String? userEmail,
    required bool isAttended,
    required int duration,
    required bool isAlreadyCompleted,
  }) async {
    if (reminderId == null) return;
    final client = await DmeConfig.getClient();
    if (client == null) return;

    final now = DateTime.now();
    final payload = <String, dynamic>{
      'call_attempts': callAttempts,
      'today_call_attempts': todayCallAttempts,
      'last_call_attempt_timestamp': calledTime.toUtc().toIso8601String(),
      'last_call_day': todayStr,
      if (userEmail != null && userEmail.isNotEmpty) 'called_by': userEmail,
      'updated_at': now.toUtc().toIso8601String(),
    };
    if (!isAlreadyCompleted) {
      if (isAttended) {
        payload['call_duration'] = duration;
        payload['called_timestamp'] = calledTime.toIso8601String();
        payload['status'] = 'called';
      } else if (duration > 0) {
        payload['call_duration'] = duration;
        payload['called_timestamp'] = calledTime.toIso8601String();
      }
    }
    try {
      await client.from('dme_reminders').update(payload).eq('id', reminderId);
    } catch (_) {
      try {
        payload.remove('today_call_attempts');
        payload.remove('last_call_attempt_timestamp');
        payload.remove('last_call_day');
        await client.from('dme_reminders').update(payload).eq('id', reminderId);
      } catch (_) {}
    }
  }
}

