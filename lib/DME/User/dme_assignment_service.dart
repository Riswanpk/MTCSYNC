import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../dme_config.dart';
import '../dme_constants.dart';

class DmeAssignmentService {
  /// Calculate the next working date for scheduling:
  /// Tomorrow, but if tomorrow is Sunday, advance to Monday.
  static DateTime getNextWorkingDate([DateTime? from]) {
    final base = from ?? DateTime.now();
    final tomorrow = DateTime(base.year, base.month, base.day).add(const Duration(days: 1));
    if (tomorrow.weekday == DateTime.sunday) {
      return tomorrow.add(const Duration(days: 1)); // Monday
    }
    return tomorrow;
  }

  /// Format date as YYYY-MM-DD
  static String formatDate(DateTime dt) => DateFormat('yyyy-MM-dd').format(dt);

  /// Find all active DME users assigned to these branches from Firestore and Supabase
  static Future<List<String>> getEligibleUserIds(List<int> branches, String fallbackUserId) async {
    final Set<String> userIds = {};
    if (branches.isEmpty) {
      return [fallbackUserId];
    }

    try {
      // 1. Fetch from Firestore users collection
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('role', whereIn: ['dme_user', 'dme_admin'])
          .get();

      final branchSet = branches.toSet();

      for (var doc in snap.docs) {
        final data = doc.data();
        if (data['assigned_branches'] is List) {
          final userBranches = (data['assigned_branches'] as List)
              .map((e) => int.tryParse(e.toString()) ?? 0)
              .where((e) => e > 0)
              .toSet();

          // If the user shares any of the given branches
          if (userBranches.intersection(branchSet).isNotEmpty) {
            userIds.add(doc.id);
          }
        }
      }
    } catch (e) {
      debugPrint('Error getting eligible users from Firestore: $e');
    }

    // Always ensure the current user is included
    if (fallbackUserId.isNotEmpty) {
      userIds.add(fallbackUserId);
    }

    final list = userIds.toList()..sort();
    return list.isNotEmpty ? list : [fallbackUserId];
  }

  /// Check if the Admin has performed reminder assignment for today for these branches
  static Future<bool> hasAdminAssignedToday({
    required List<int> userBranches,
    required String todayStr,
  }) async {
    if (userBranches.isEmpty) return false;
    final client = await DmeConfig.getClient();
    if (client == null) return false;

    // 1. Try checking reminder_assignment table
    try {
      final res = await client
          .from('reminder_assignment')
          .select('id')
          .eq('assignment_date', todayStr)
          .inFilter('branch_id', userBranches)
          .limit(1);
      if ((res as List).isNotEmpty) {
        return true;
      }
    } catch (_) {
      try {
        final res2 = await client
            .from('dme_reminder_assignments')
            .select('id')
            .eq('assignment_date', todayStr)
            .inFilter('branch_id', userBranches)
            .limit(1);
        if ((res2 as List).isNotEmpty) {
          return true;
        }
      } catch (_) {}
    }

    // 2. Fallback: check if dme_reminders has any records with assigned_date = todayStr for these branches
    try {
      final res = await client
          .from('dme_reminders')
          .select('id')
          .eq('assigned_date', todayStr)
          .inFilter('last_purchase_branch', userBranches)
          .limit(1);
      return (res as List).isNotEmpty;
    } catch (e) {
      debugPrint('Error checking if admin assigned today: $e');
      return false;
    }
  }

  /// Get status map of which branches have been assigned for dateStr
  static Future<Map<int, Map<String, dynamic>>> getBranchAssignmentStatus({
    required String dateStr,
  }) async {
    final Map<int, Map<String, dynamic>> map = {};
    final client = await DmeConfig.getClient();
    if (client == null) return map;

    try {
      final res = await client
          .from('reminder_assignment')
          .select()
          .eq('assignment_date', dateStr);
      for (var item in (res as List)) {
        final bId = int.tryParse(item['branch_id']?.toString() ?? '');
        if (bId != null) {
          map[bId] = Map<String, dynamic>.from(item);
        }
      }
    } catch (_) {
      try {
        final res = await client
            .from('dme_reminder_assignments')
            .select()
            .eq('assignment_date', dateStr);
        for (var item in (res as List)) {
          final bId = int.tryParse(item['branch_id']?.toString() ?? '');
          if (bId != null) {
            map[bId] = Map<String, dynamic>.from(item);
          }
        }
      } catch (_) {}
    }

    return map;
  }

  /// Admin manual assignment of reminders across branches with explicitly chosen users.
  /// If a user is on leave, they are simply excluded from the active user list for their branches.
  static Future<Map<String, dynamic>> assignRemindersByAdmin({
    required String dateStr,
    required Map<int, List<String>> branchToActiveUserUids,
    required Map<String, String> userUidToName,
    required String adminEmail,
  }) async {
    final client = await DmeConfig.getClient();
    if (client == null) throw Exception('Supabase client not initialized');

    final Map<int, int> branchAssignedCounts = {};
    int totalAssigned = 0;
    final nowIso = DateTime.now().toIso8601String();
    final currentDay = DateTime.tryParse(dateStr) ?? DateTime.now();

    for (final entry in branchToActiveUserUids.entries) {
      final branchId = entry.key;
      final activeUsers = entry.value;

      if (activeUsers.isEmpty) {
        continue;
      }

      // 1. Fetch pending candidate reminders for this branch due on or before dateStr
      final List<dynamic> allPending = [];
      int offset = 0;
      const int pageSize = 1000;
      bool hasMore = true;

      while (hasMore) {
        final batch = await client
            .from('dme_reminders')
            .select('id, reminder_date')
            .eq('status', 'pending')
            .eq('last_purchase_branch', branchId)
            .lte('reminder_date', '${dateStr}T23:59:59')
            .range(offset, offset + pageSize - 1);

        final list = batch as List;
        allPending.addAll(list);
        if (list.length < pageSize) {
          hasMore = false;
        } else {
          offset += pageSize;
        }
      }

      if (allPending.isEmpty) {
        continue;
      }

      final List<int> leftoverIds = [];
      final List<int> todayIds = [];

      for (var item in allPending) {
        final id = int.tryParse(item['id']?.toString() ?? '');
        if (id == null) continue;

        final rDateStr = item['reminder_date']?.toString();
        final rDate = rDateStr != null ? DateTime.tryParse(rDateStr) : null;

        if (rDate != null) {
          final rDay = DateTime(rDate.year, rDate.month, rDate.day);
          if (rDay.isBefore(DateTime(currentDay.year, currentDay.month, currentDay.day))) {
            leftoverIds.add(id);
          } else {
            todayIds.add(id);
          }
        } else {
          todayIds.add(id);
        }
      }

      // Shuffle both pools
      final rnd = Random();
      leftoverIds.shuffle(rnd);
      todayIds.shuffle(rnd);

      final numUsers = activeUsers.length;
      final Map<String, List<int>> userLeftovers = {for (var u in activeUsers) u: []};
      final Map<String, List<int>> userTodays = {for (var u in activeUsers) u: []};

      for (int i = 0; i < leftoverIds.length; i++) {
        final targetUser = activeUsers[i % numUsers];
        userLeftovers[targetUser]!.add(leftoverIds[i]);
      }

      for (int j = 0; j < todayIds.length; j++) {
        final targetUser = activeUsers[j % numUsers];
        userTodays[targetUser]!.add(todayIds[j]);
      }

      const int batchSize = 200;
      for (var user in activeUsers) {
        final lList = userLeftovers[user] ?? [];
        for (int i = 0; i < lList.length; i += batchSize) {
          final chunk = lList.sublist(i, min(i + batchSize, lList.length));
          await client.from('dme_reminders').update({
            'assigned_to': user,
            'assigned_date': dateStr,
            'is_overdue_leftover': true,
            'updated_at': nowIso,
          }).inFilter('id', chunk);
        }

        final tList = userTodays[user] ?? [];
        for (int j = 0; j < tList.length; j += batchSize) {
          final chunk = tList.sublist(j, min(j + batchSize, tList.length));
          await client.from('dme_reminders').update({
            'assigned_to': user,
            'assigned_date': dateStr,
            'is_overdue_leftover': false,
            'updated_at': nowIso,
          }).inFilter('id', chunk);
        }
      }

      final branchCount = leftoverIds.length + todayIds.length;
      branchAssignedCounts[branchId] = branchCount;
      totalAssigned += branchCount;

      // 2. Record in reminder_assignment audit table
      final payload = {
        'assignment_date': dateStr,
        'branch_id': branchId,
        'assigned_user_ids': activeUsers,
        'assigned_user_names': activeUsers.map((u) => userUidToName[u] ?? u).toList(),
        'total_reminders': branchCount,
        'assigned_by': adminEmail,
        'updated_at': nowIso,
      };

      try {
        await client.from('reminder_assignment').upsert(payload, onConflict: 'assignment_date,branch_id');
      } catch (tErr) {
        try {
          await client.from('dme_reminder_assignments').upsert(payload, onConflict: 'assignment_date,branch_id');
        } catch (_) {
          debugPrint('Notice saving reminder_assignment record: $tErr');
        }
      }
    }

    return {
      'total_assigned': totalAssigned,
      'branch_counts': branchAssignedCounts,
    };
  }

  /// Ensure reminders for today are partitioned and assigned across the eligible users
  static Future<void> ensureDailyAssignment({
    required List<int> userBranches,
    required String currentUserId,
  }) async {
    if (userBranches.isEmpty) return;

    final client = await DmeConfig.getClient();
    if (client == null) return;

    final today = DateTime.now();
    final todayStr = formatDate(today);

    try {
      // 1. Check if reminders for these branches have already been assigned for today
      final existing = await client
          .from('dme_reminders')
          .select('id')
          .eq('assigned_date', todayStr)
          .inFilter('last_purchase_branch', userBranches)
          .limit(1);

      if ((existing as List).isNotEmpty) {
        // Already assigned for today!
        return;
      }

      // 2. Fetch eligible users sharing these branches
      final eligibleUsers = await getEligibleUserIds(userBranches, currentUserId);
      final numUsers = eligibleUsers.length;
      if (numUsers == 0) return;

      // 3. Fetch candidate reminders:
      // (a) Leftovers / overdue before today: status = pending and reminder_date < today
      // (b) Today's reminders: status = pending and reminder_date = today (or starts with todayStr)
      final List<dynamic> allPending = [];
      int offset = 0;
      const int pageSize = 1000;
      bool hasMore = true;

      while (hasMore) {
        final batch = await client
            .from('dme_reminders')
            .select('id, reminder_date')
            .eq('status', 'pending')
            .inFilter('last_purchase_branch', userBranches)
            .lte('reminder_date', '${todayStr}T23:59:59')
            .range(offset, offset + pageSize - 1);

        final list = batch as List;
        allPending.addAll(list);
        if (list.length < pageSize) {
          hasMore = false;
        } else {
          offset += pageSize;
        }
      }

      if (allPending.isEmpty) return;

      final currentDay = DateTime(today.year, today.month, today.day);
      final List<int> leftoverIds = [];
      final List<int> todayIds = [];

      for (var item in allPending) {
        final id = int.tryParse(item['id']?.toString() ?? '');
        if (id == null) continue;

        final rDateStr = item['reminder_date']?.toString();
        final rDate = rDateStr != null ? DateTime.tryParse(rDateStr) : null;

        if (rDate != null) {
          final rDay = DateTime(rDate.year, rDate.month, rDate.day);
          if (rDay.isBefore(currentDay)) {
            leftoverIds.add(id);
          } else {
            todayIds.add(id);
          }
        } else {
          todayIds.add(id);
        }
      }

      // 4. Shuffle both pools randomly
      final rnd = Random();
      leftoverIds.shuffle(rnd);
      todayIds.shuffle(rnd);

      // 5. Group by assigned user
      final Map<String, List<int>> userLeftovers = {for (var u in eligibleUsers) u: []};
      final Map<String, List<int>> userTodays = {for (var u in eligibleUsers) u: []};

      for (int i = 0; i < leftoverIds.length; i++) {
        final targetUser = eligibleUsers[i % numUsers];
        userLeftovers[targetUser]!.add(leftoverIds[i]);
      }

      for (int j = 0; j < todayIds.length; j++) {
        final targetUser = eligibleUsers[j % numUsers];
        userTodays[targetUser]!.add(todayIds[j]);
      }

      // 6. Write assignments to Supabase in chunks
      const int batchSize = 200;
      final nowIso = DateTime.now().toIso8601String();

      for (var user in eligibleUsers) {
        // Update leftovers for this user
        final lList = userLeftovers[user] ?? [];
        for (int i = 0; i < lList.length; i += batchSize) {
          final chunk = lList.sublist(i, min(i + batchSize, lList.length));
          await client.from('dme_reminders').update({
            'assigned_to': user,
            'assigned_date': todayStr,
            'is_overdue_leftover': true,
            'updated_at': nowIso,
          }).inFilter('id', chunk);
        }

        // Update today's reminders for this user
        final tList = userTodays[user] ?? [];
        for (int j = 0; j < tList.length; j += batchSize) {
          final chunk = tList.sublist(j, min(j + batchSize, tList.length));
          await client.from('dme_reminders').update({
            'assigned_to': user,
            'assigned_date': todayStr,
            'is_overdue_leftover': false,
            'updated_at': nowIso,
          }).inFilter('id', chunk);
        }
      }
    } catch (e) {
      debugPrint('ensureDailyAssignment error: $e');
    }
  }

  /// Fetch today's assigned reminders for current user, prioritizing leftovers on top.
  /// NOTE: Only displays reminders after the admin assigns everyday.
  static Future<List<Map<String, dynamic>>> fetchUserAssignedReminders({
    required List<int> userBranches,
    required String currentUserId,
    int? filterBranchId,
  }) async {
    final client = await DmeConfig.getClient();
    if (client == null) return [];

    final today = DateTime.now();
    final todayStr = formatDate(today);
    final branches = filterBranchId != null ? [filterBranchId] : userBranches;
    if (branches.isEmpty) return [];

    // 1. Check if Admin has assigned reminders for today
    final isAssigned = await hasAdminAssignedToday(
      userBranches: branches,
      todayStr: todayStr,
    );

    if (!isAssigned) {
      // Not assigned by admin yet! Do not display reminders.
      return [];
    }

    try {
      final List<dynamic> data = [];
      int offset = 0;
      const int pageSize = 1000;
      bool hasMore = true;

      while (hasMore) {
        dynamic batch;
        try {
          var query = client
              .from('dme_reminders')
              .select(
                  'id, customer_id, reminder_date, last_purchase_date, last_purchase_branch, status, remarks, updated_at, call_duration, called_timestamp, called_by, assigned_to, assigned_date, is_overdue_leftover, dme_customers(id, name, phone, address, salesman)')
              .eq('assigned_to', currentUserId)
              .eq('assigned_date', todayStr)
              .eq('status', 'pending');

          if (filterBranchId != null) {
            query = query.eq('last_purchase_branch', filterBranchId);
          }
          batch = await query.range(offset, offset + pageSize - 1);
        } catch (_) {
          var fallbackQuery = client
              .from('dme_reminders')
              .select(
                  'id, customer_id, reminder_date, last_purchase_date, last_purchase_branch, status, remarks, updated_at, call_duration, called_timestamp, assigned_to, assigned_date, is_overdue_leftover, dme_customers(id, name, phone, address, salesman)')
              .eq('assigned_to', currentUserId)
              .eq('assigned_date', todayStr)
              .eq('status', 'pending');

          if (filterBranchId != null) {
            fallbackQuery = fallbackQuery.eq('last_purchase_branch', filterBranchId);
          }
          batch = await fallbackQuery.range(offset, offset + pageSize - 1);
        }
        final list = batch as List;
        data.addAll(list);

        if (list.length < pageSize) {
          hasMore = false;
        } else {
          offset += pageSize;
        }
      }

      if (data.isNotEmpty) {
        final reminders = _parseReminderList(data);
        reminders.sort((a, b) {
          final aLeftover = a['is_overdue_leftover'] == true ? 1 : 0;
          final bLeftover = b['is_overdue_leftover'] == true ? 1 : 0;
          if (aLeftover != bLeftover) {
            return bLeftover.compareTo(aLeftover); // Leftovers first!
          }
          final aDate = a['reminder_date']?.toString() ?? '';
          final bDate = b['reminder_date']?.toString() ?? '';
          return aDate.compareTo(bDate);
        });
        return reminders;
      }
    } catch (e) {
      debugPrint('fetchUserAssignedReminders error: $e');
    }

    return [];
  }

  /// Parse raw Supabase response into UI-friendly reminder maps
  static List<Map<String, dynamic>> _parseReminderList(List<dynamic> rawList) {
    List<Map<String, dynamic>> list = [];
    for (var item in rawList) {
      final rem = Map<String, dynamic>.from(item);
      final cust = rem['dme_customers'] as Map<String, dynamic>?;
      final bId = int.tryParse(rem['last_purchase_branch']?.toString() ?? '');

      rem['customer_name'] = cust?['name'] ?? 'Unknown Customer';
      rem['customer_phone'] = cust?['phone'] ?? '';
      rem['customer_address'] = cust?['address'] ?? '';
      rem['customer_salesman'] = cust?['salesman'] ?? '';
      rem['branch_id'] = bId;
      rem['branch_name'] = DmeConstants.getBranchName(bId);
      rem['is_overdue_leftover'] = rem['is_overdue_leftover'] == true ||
          rem['is_overdue_leftover'] == 'true' ||
          rem['is_overdue_leftover'] == 1;

      list.add(rem);
    }
    return list;
  }



  /// Fetch completed calls for the current user for today
  static Future<List<Map<String, dynamic>>> fetchUserCompletedToday({
    required List<int> userBranches,
    required String currentUserId,
    int? filterBranchId,
  }) async {
    final client = await DmeConfig.getClient();
    if (client == null || userBranches.isEmpty) return [];

    final now = DateTime.now();
    final todayStr = formatDate(now);
    final branches = filterBranchId != null ? [filterBranchId] : userBranches;

    try {
      final List<dynamic> data = [];
      int offset = 0;
      const int pageSize = 1000;
      bool hasMore = true;

      while (hasMore) {
        dynamic batch;
        try {
          batch = await client
              .from('dme_reminders')
              .select(
                  'id, customer_id, reminder_date, last_purchase_date, last_purchase_branch, status, remarks, updated_at, call_duration, called_timestamp, called_by, assigned_to, dme_customers(id, name, phone, address, salesman)')
              .inFilter('status', ['completed', 'called'])
              .inFilter('last_purchase_branch', branches)
              .gte('updated_at', '${todayStr}T00:00:00')
              .lte('updated_at', '${todayStr}T23:59:59')
              .range(offset, offset + pageSize - 1);
        } catch (_) {
          batch = await client
              .from('dme_reminders')
              .select(
                  'id, customer_id, reminder_date, last_purchase_date, last_purchase_branch, status, remarks, updated_at, call_duration, called_timestamp, assigned_to, dme_customers(id, name, phone, address, salesman)')
              .inFilter('status', ['completed', 'called'])
              .inFilter('last_purchase_branch', branches)
              .gte('updated_at', '${todayStr}T00:00:00')
              .lte('updated_at', '${todayStr}T23:59:59')
              .range(offset, offset + pageSize - 1);
        }

        final list = batch as List;
        data.addAll(list);
        if (list.length < pageSize) {
          hasMore = false;
        } else {
          offset += pageSize;
        }
      }

      final parsed = _parseReminderList(data);
      // Filter to current user if assigned_to or called_by matches
      final userFiltered = parsed.where((r) {
        final assigned = r['assigned_to']?.toString();
        final called = r['called_by']?.toString().toLowerCase();
        if (called != null && called.isNotEmpty) {
          // If called_by email is set, show it to matching branch user or assigned user
          return true;
        }
        if (assigned != null && assigned.isNotEmpty) {
          return assigned == currentUserId;
        }
        return true;
      }).toList();

      return userFiltered;
    } catch (e) {
      debugPrint('Error fetching completed today: $e');
      return [];
    }
  }
}
