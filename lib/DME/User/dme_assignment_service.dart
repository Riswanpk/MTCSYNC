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

  /// Fetch today's assigned reminders for current user, prioritizing leftovers on top
  static Future<List<Map<String, dynamic>>> fetchUserAssignedReminders({
    required List<int> userBranches,
    required String currentUserId,
    int? filterBranchId,
  }) async {
    final client = await DmeConfig.getClient();
    if (client == null) return [];

    final today = DateTime.now();
    final todayStr = formatDate(today);

    // Make sure assignment is initialized for today
    await ensureDailyAssignment(userBranches: userBranches, currentUserId: currentUserId);

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

      // If results returned from assigned_to query, parse and sort leftovers to top
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
      debugPrint('fetchUserAssignedReminders error (falling back): $e');
    }

    // Fallback: If assigned_to/assigned_date columns are not yet added in Supabase,
    // gracefully fetch pending reminders for user branches and partition locally.
    return _fallbackFetchReminders(
      client: client,
      userBranches: userBranches,
      currentUserId: currentUserId,
      filterBranchId: filterBranchId,
    );
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

  /// Graceful in-memory fallback when database columns are pending migration
  static Future<List<Map<String, dynamic>>> _fallbackFetchReminders({
    required dynamic client,
    required List<int> userBranches,
    required String currentUserId,
    int? filterBranchId,
  }) async {
    final today = DateTime.now();
    final todayStr = formatDate(today);
    final branches = filterBranchId != null ? [filterBranchId] : userBranches;
    if (branches.isEmpty) return [];

    try {
      final List<dynamic> data = [];
      int offset = 0;
      const int pageSize = 1000;
      bool hasMore = true;

      while (hasMore) {
        final query = client
            .from('dme_reminders')
            .select(
                'id, customer_id, reminder_date, last_purchase_date, last_purchase_branch, status, remarks, updated_at, dme_customers(id, name, phone, address, salesman)')
            .eq('status', 'pending')
            .inFilter('last_purchase_branch', branches)
            .lte('reminder_date', '${todayStr}T23:59:59')
            .range(offset, offset + pageSize - 1);

        final batch = await query;
        final list = batch as List;
        data.addAll(list);
        if (list.length < pageSize) {
          hasMore = false;
        } else {
          offset += pageSize;
        }
      }

      final parsed = _parseReminderList(data);
      final currentDay = DateTime(today.year, today.month, today.day);

      // Separate leftovers and today
      final List<Map<String, dynamic>> leftovers = [];
      final List<Map<String, dynamic>> todays = [];

      for (var r in parsed) {
        final dStr = r['reminder_date']?.toString();
        final dt = dStr != null ? DateTime.tryParse(dStr) : null;
        if (dt != null && DateTime(dt.year, dt.month, dt.day).isBefore(currentDay)) {
          r['is_overdue_leftover'] = true;
          leftovers.add(r);
        } else {
          r['is_overdue_leftover'] = false;
          todays.add(r);
        }
      }

      // Deterministic pseudo-random shuffle seeded by today's date
      final dateSeed = today.year * 10000 + today.month * 100 + today.day;
      leftovers.shuffle(Random(dateSeed));
      todays.shuffle(Random(dateSeed + 1));

      final eligibleUsers = await getEligibleUserIds(userBranches, currentUserId);
      final userIndex = eligibleUsers.indexOf(currentUserId);
      final activeIndex = userIndex >= 0 ? userIndex : 0;
      final numUsers = eligibleUsers.length;

      // Slice out current user's portion
      final myLeftovers = [
        for (int i = 0; i < leftovers.length; i++)
          if (i % numUsers == activeIndex) leftovers[i]
      ];
      final myTodays = [
        for (int j = 0; j < todays.length; j++)
          if (j % numUsers == activeIndex) todays[j]
      ];

      return [...myLeftovers, ...myTodays];
    } catch (e) {
      debugPrint('Fallback fetch error: $e');
      return [];
    }
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
