import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:mtcsync/DME/dme_config.dart';
import 'package:mtcsync/DME/dme_constants.dart';
import 'package:mtcsync/DME/User/dme_user_stats_service.dart';

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
          .where('role', isEqualTo: 'dme_user')
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

    // 1. Try checking reminder_assignment table (checks assigned_date first, then assignment_date)
    try {
      final res = await client
          .from('reminder_assignment')
          .select('id')
          .eq('assigned_date', todayStr)
          .inFilter('branch_id', userBranches.map((b) => b.toString()).toList())
          .limit(1);
      if ((res as List).isNotEmpty) {
        return true;
      }
    } catch (_) {
      try {
        final resLegacy = await client
            .from('reminder_assignment')
            .select('id')
            .eq('assignment_date', todayStr)
            .inFilter('branch_id', userBranches)
            .limit(1);
        if ((resLegacy as List).isNotEmpty) {
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
          .eq('assigned_date', dateStr);
      for (var item in (res as List)) {
        final bId = int.tryParse(item['branch_id']?.toString() ?? '');
        if (bId != null) {
          map[bId] = Map<String, dynamic>.from(item);
        }
      }
    } catch (_) {
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
    Map<String, String>? userUidToEmail,
    required String adminEmail,
  }) async {
    final client = await DmeConfig.getClient();
    if (client == null) throw Exception('Supabase client not initialized');

    final Map<int, int> branchAssignedCounts = {};
    int totalAssigned = 0;
    final nowIso = DateTime.now().toIso8601String();
    final currentDay = DateTime.tryParse(dateStr) ?? DateTime.now();

    // Track new, unattempted overdue, and attempted reminders across all branches for each user today
    final Map<String, int> globalUserNewCount = {};
    final Map<String, int> globalUserOverdueCount = {};
    final Map<String, int> globalUserAttemptedCount = {};
    for (final users in branchToActiveUserUids.values) {
      for (final u in users) {
        globalUserNewCount.putIfAbsent(u, () => 0);
        globalUserOverdueCount.putIfAbsent(u, () => 0);
        globalUserAttemptedCount.putIfAbsent(u, () => 0);
      }
    }

    // Remove previous days' assignment logs from reminder_assignment table whenever assign is triggered
    try {
      await client
          .from('reminder_assignment')
          .delete()
          .lt('assigned_date', dateStr);
    } catch (_) {}
    try {
      await client
          .from('reminder_assignment')
          .delete()
          .lt('assignment_date', dateStr);
    } catch (_) {}
    try {
      await client
          .from('dme_reminder_assignments')
          .delete()
          .lt('assignment_date', dateStr);
    } catch (_) {}

    // Before resetting, calculate how many pending reminders each user left overdue from previous days
    // and record it in dme_user_daily_stats so it shows in the call report.
    // Scoped strictly to the target branches being assigned.
    final targetBranchIds = branchToActiveUserUids.keys.toList();
    try {
      final overdueRows = await client
          .from('dme_reminders')
          .select('assigned_to, assigned_date')
          .inFilter('status', ['pending', 'called'])
          .inFilter('last_purchase_branch', targetBranchIds)
          .not('assigned_to', 'is', null)
          .lt('assigned_date', dateStr);

      // Group by (assigned_to, assigned_date)
      final Map<String, Map<String, int>> userDateOverdue = {};
      for (final row in (overdueRows as List)) {
        final uid = row['assigned_to']?.toString();
        final aDate = row['assigned_date']?.toString();
        if (uid == null || uid.isEmpty || aDate == null) continue;
        final key = '$uid|$aDate';
        userDateOverdue.putIfAbsent(key, () => {'count': 0, 'uid_ref': 0});
        userDateOverdue[key]!['count'] = userDateOverdue[key]!['count']! + 1;
      }

      // Fetch email mapping from Firestore for UIDs found
      final uidsFound = overdueRows
          .map((r) => r['assigned_to']?.toString() ?? '')
          .where((u) => u.isNotEmpty)
          .toSet();

      final Map<String, String> uidToEmail = {};
      if (uidsFound.isNotEmpty && userUidToEmail != null) {
        for (final uid in uidsFound) {
          uidToEmail[uid] = userUidToEmail[uid] ?? uid;
        }
      } else {
        for (final uid in uidsFound) {
          uidToEmail[uid] = uid;
        }
      }

      // Write overdue counts
      for (final entry in userDateOverdue.entries) {
        final parts = entry.key.split('|');
        if (parts.length != 2) continue;
        final uid = parts[0];
        final aDate = parts[1];
        await DmeUserStatsService.setOverdueCount(
          userUid: uid,
          userEmail: uidToEmail[uid] ?? uid,
          statDate: aDate,
          overdueCount: entry.value['count']!,
        );
      }
    } catch (e) {
      debugPrint('DmeAssignmentService: overdue stats recording error: $e');
    }

    // Reset uncalled pending reminders assigned on previous days for these target branches so they are cleanly re-divided today.
    // Do NOT reset reminders where a call has already been attempted (call_attempts > 0 or called_by is set).
    try {
      await client.from('dme_reminders').update({
        'assigned_to': null,
        'assigned_date': null,
        'is_overdue_leftover': false,
        'updated_at': nowIso,
      }).eq('status', 'pending')
        .inFilter('last_purchase_branch', targetBranchIds)
        .isFilter('called_by', null)
        .or('call_attempts.is.null,call_attempts.eq.0')
        .lt('assigned_date', dateStr);
    } catch (_) {
      try {
        await client.from('dme_reminders').update({
          'assigned_to': null,
          'assigned_date': null,
          'is_overdue_leftover': false,
          'updated_at': nowIso,
        }).eq('status', 'pending')
          .inFilter('last_purchase_branch', targetBranchIds)
          .isFilter('called_by', null)
          .eq('call_attempts', 0)
          .lt('assigned_date', dateStr);
      } catch (_) {}
    }

    // Clean up previous assignment audit logs for today for these branches so absent users or old counts don't linger on re-assign
    try {
      final branchIdsStr = branchToActiveUserUids.keys.map((b) => b.toString()).toList();
      await client
          .from('reminder_assignment')
          .delete()
          .eq('assigned_date', dateStr)
          .inFilter('branch_id', branchIdsStr);
    } catch (_) {}
    try {
      await client
          .from('dme_reminder_assignments')
          .delete()
          .eq('assignment_date', dateStr)
          .inFilter('branch_id', branchToActiveUserUids.keys.toList());
    } catch (_) {}

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
            .select('id, reminder_date, status, remarks, call_duration, called_by, assigned_to, call_attempts')
            .inFilter('status', ['pending', 'called'])
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

      final Map<String, List<int>> userOverdue = {for (var u in activeUsers) u: []};
      final Map<String, List<int>> userNew = {for (var u in activeUsers) u: []};
      final Map<String, List<int>> userAttempted = {for (var u in activeUsers) u: []};

      final List<int> unattemptedOverdueIds = [];
      final List<int> newIds = [];
      final List<Map<String, dynamic>> attemptedItems = [];

      for (var item in allPending) {
        final id = int.tryParse(item['id']?.toString() ?? '');
        if (id == null) continue;

        final status = (item['status'] ?? '').toString().toLowerCase();
        final remarks = (item['remarks'] ?? '').toString().trim();
        final duration = int.tryParse(item['call_duration']?.toString() ?? '') ?? 0;
        final attempts = int.tryParse(item['call_attempts']?.toString() ?? '') ?? 0;
        final calledEmail = item['called_by']?.toString().toLowerCase().trim();
        final bool hasAttempt = attempts > 0 || (calledEmail != null && calledEmail.isNotEmpty) || status == 'called' || duration > 0;

        // Sticky assignment: When a user has already attempted a call on a reminder,
        // assign that reminder to the same user next day and henceforth until remarks are submitted.
        if (hasAttempt && remarks.isEmpty) {
          String? targetCaller;
          final prevAssigned = item['assigned_to']?.toString();
          if (prevAssigned != null && activeUsers.contains(prevAssigned)) {
            targetCaller = prevAssigned;
          } else if (calledEmail != null && calledEmail.isNotEmpty) {
            for (var u in activeUsers) {
              final uEmail = (userUidToEmail?[u] ?? '').toLowerCase().trim();
              if (uEmail == calledEmail || u.toLowerCase() == calledEmail) {
                targetCaller = u;
                break;
              }
            }
          }

          if (targetCaller != null) {
            attemptedItems.add({'id': id, 'targetCaller': targetCaller});
            continue;
          }
        }

        final rDateStr = item['reminder_date']?.toString();
        final rDate = rDateStr != null ? DateTime.tryParse(rDateStr) : null;

        if (rDate != null && DateTime(rDate.year, rDate.month, rDate.day).isBefore(DateTime(currentDay.year, currentDay.month, currentDay.day))) {
          unattemptedOverdueIds.add(id);
        } else {
          newIds.add(id);
        }
      }

      // Shuffle pools for randomness
      final rnd = Random();
      unattemptedOverdueIds.shuffle(rnd);
      newIds.shuffle(rnd);

      // 1. Fairly distribute unattempted overdue reminders among active users:
      for (final id in unattemptedOverdueIds) {
        final sortedUsers = List<String>.from(activeUsers)..sort((a, b) {
          final oDiff = (userOverdue[a]?.length ?? 0).compareTo(userOverdue[b]?.length ?? 0);
          if (oDiff != 0) return oDiff;
          return (globalUserOverdueCount[a] ?? 0).compareTo(globalUserOverdueCount[b] ?? 0);
        });
        final targetUser = sortedUsers.first;
        userOverdue[targetUser]!.add(id);
        globalUserOverdueCount[targetUser] = (globalUserOverdueCount[targetUser] ?? 0) + 1;
      }

      // 2. Fairly distribute new reminders among active users:
      for (final id in newIds) {
        final sortedUsers = List<String>.from(activeUsers)..sort((a, b) {
          final nDiff = (userNew[a]?.length ?? 0).compareTo(userNew[b]?.length ?? 0);
          if (nDiff != 0) return nDiff;
          return (globalUserNewCount[a] ?? 0).compareTo(globalUserNewCount[b] ?? 0);
        });
        final targetUser = sortedUsers.first;
        userNew[targetUser]!.add(id);
        globalUserNewCount[targetUser] = (globalUserNewCount[targetUser] ?? 0) + 1;
      }

      // 3. Add attempted overdue reminders on top directly to their caller/assignee:
      for (final item in attemptedItems) {
        final targetCaller = item['targetCaller'] as String;
        final id = item['id'] as int;
        userAttempted[targetCaller]!.add(id);
        globalUserAttemptedCount[targetCaller] = (globalUserAttemptedCount[targetCaller] ?? 0) + 1;
      }

      const int batchSize = 200;
      for (var user in activeUsers) {
        // Unattempted overdue reminders
        final oList = userOverdue[user] ?? [];
        for (int i = 0; i < oList.length; i += batchSize) {
          final chunk = oList.sublist(i, min(i + batchSize, oList.length));
          await client.from('dme_reminders').update({
            'assigned_to': user,
            'assigned_date': dateStr,
            'is_overdue_leftover': true,
            'updated_at': nowIso,
          }).inFilter('id', chunk);
        }

        // Attempted overdue reminders (sticky)
        final aList = userAttempted[user] ?? [];
        for (int i = 0; i < aList.length; i += batchSize) {
          final chunk = aList.sublist(i, min(i + batchSize, aList.length));
          await client.from('dme_reminders').update({
            'assigned_to': user,
            'assigned_date': dateStr,
            'is_overdue_leftover': true,
            'updated_at': nowIso,
          }).inFilter('id', chunk);
        }

        // Today's new reminders
        final tList = userNew[user] ?? [];
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

      final branchCount = unattemptedOverdueIds.length + newIds.length + attemptedItems.length;
      branchAssignedCounts[branchId] = branchCount;
      totalAssigned += branchCount;

      // 2. Record in reminder_assignment audit table
      for (var user in activeUsers) {
        final uEmail = userUidToEmail?[user] ?? user;
        final count = (userOverdue[user]?.length ?? 0) +
            (userNew[user]?.length ?? 0) +
            (userAttempted[user]?.length ?? 0);
        try {
          await client.from('reminder_assignment').upsert({
            'assigned_date': dateStr,
            'branch_id': branchId.toString(),
            'user_email': uEmail,
            'reminder_count': count,
          }, onConflict: 'assigned_date,branch_id,user_email');
        } catch (tErr) {
          debugPrint('Error inserting reminder_assignment for $uEmail in branch $branchId: $tErr');
        }
      }

      // Also attempt fallback or legacy structure if dme_reminder_assignments exists
      try {
        await client.from('dme_reminder_assignments').upsert({
          'assignment_date': dateStr,
          'branch_id': branchId,
          'assigned_user_ids': activeUsers,
          'assigned_user_names': activeUsers.map((u) => userUidToName[u] ?? u).toList(),
          'total_reminders': branchCount,
          'assigned_by': adminEmail,
          'updated_at': nowIso,
        }, onConflict: 'assignment_date,branch_id');
      } catch (_) {}
    }

    final Map<String, Map<String, int>> userAssignedBreakdown = {};
    final allActiveUids = <String>{};
    for (final users in branchToActiveUserUids.values) {
      allActiveUids.addAll(users);
    }
    for (final u in allActiveUids) {
      final n = globalUserNewCount[u] ?? 0;
      final o = globalUserOverdueCount[u] ?? 0;
      final a = globalUserAttemptedCount[u] ?? 0;
      final total = n + o + a;
      userAssignedBreakdown[u] = {
        'total': total,
        'new': n,
        'overdue': o,
        'attempted': a,
        'leftover': o + a, // backwards compatibility
      };
    }

    // Record today's leftover overdue count in dme_user_daily_stats so call report OD displays properly
    try {
      for (final uid in allActiveUids) {
        final leftover = (globalUserOverdueCount[uid] ?? 0) + (globalUserAttemptedCount[uid] ?? 0);
        await DmeUserStatsService.setOverdueCount(
          userUid: uid,
          userEmail: userUidToEmail?[uid] ?? uid,
          statDate: dateStr,
          overdueCount: leftover,
        );
      }
    } catch (e) {
      debugPrint('Error updating today overdue stats: $e');
    }

    return {
      'total_assigned': totalAssigned,
      'branch_counts': branchAssignedCounts,
      'user_counts': userAssignedBreakdown,
    };
  }

  /// Records a snapshot of an assignment run into Firestore collection `dme_assignment_history`.
  /// This ensures previous assignments (including the first assignment) can be audited even if re-assignment occurs.
  static Future<void> recordAssignmentHistory({
    required String dateStr,
    required int totalAssigned,
    required Map<String, dynamic> userCounts,
    required Map<int, int> branchCounts,
    required List<Map<String, dynamic>> dmeUsers,
    required Map<String, bool> userPresence,
    required String adminEmail,
  }) async {
    try {
      final historyRef = FirebaseFirestore.instance.collection('dme_assignment_history');

      // Check how many runs already exist for today
      final existingSnap = await historyRef
          .where('assigned_date', isEqualTo: dateStr)
          .get();

      final runNumber = existingSnap.docs.length + 1;

      // Build per-user breakdown list
      final List<Map<String, dynamic>> userBreakdowns = [];
      for (var u in dmeUsers) {
        final uid = u['uid'] as String;
        final name = (u['username'] ?? u['name'] ?? 'User').toString();
        final email = (u['email'] ?? '').toString();
        final isPresent = userPresence[uid] ?? true;
        final branches = (u['assigned_branches'] as List?)
                ?.map((e) => int.tryParse(e.toString()) ?? 0)
                .where((e) => e > 0)
                .toList() ??
            <int>[];

        final stats = userCounts[uid] ?? userCounts[email];
        final total = (stats?['total'] as num?)?.toInt() ?? 0;
        final newCount = (stats?['new'] as num?)?.toInt() ?? 0;
        final overdueCount = (stats?['overdue'] as num?)?.toInt() ?? 0;
        final attemptedCount = (stats?['attempted'] as num?)?.toInt() ?? 0;
        final leftover = (stats?['leftover'] as num?)?.toInt() ?? (overdueCount + attemptedCount);

        userBreakdowns.add({
          'uid': uid,
          'name': name,
          'email': email,
          'is_present': isPresent,
          'total': total,
          'new': newCount,
          'overdue': overdueCount,
          'attempted': attemptedCount,
          'leftover': leftover,
          'assigned_branches': branches,
        });
      }

      final branchCountsMap = <String, int>{
        for (var e in branchCounts.entries) e.key.toString(): e.value,
      };

      await historyRef.add({
        'assigned_date': dateStr,
        'assigned_at': FieldValue.serverTimestamp(),
        'assigned_by': adminEmail,
        'run_number': runNumber,
        'status': 'active',
        'total_assigned': totalAssigned,
        'user_breakdowns': userBreakdowns,
        'branch_counts': branchCountsMap,
      });
    } catch (e) {
      debugPrint('Error recording assignment history: $e');
    }
  }

  /// Streams assignment history snapshots for [dateStr] from Firestore
  static Stream<QuerySnapshot<Map<String, dynamic>>> streamTodayAssignmentHistory(String dateStr) {
    return FirebaseFirestore.instance
        .collection('dme_assignment_history')
        .where('assigned_date', isEqualTo: dateStr)
        .snapshots();
  }

  /// Undo reminder assignments for the given date (defaults to today):
  /// 1. Finds all pending reminders that were assigned for dateStr or overdue with pending assigned.
  /// 2. Resets their assigned_to = null, assigned_date = null, is_overdue_leftover = false.
  /// 3. Deletes audit records from reminder_assignment and dme_reminder_assignments for dateStr.
  /// 4. Marks the latest active run in dme_assignment_history as undone while keeping historical details intact.
  /// Returns the number of reminders unassigned.
  static Future<int> undoTodayAssignments({
    required String dateStr,
    List<int>? branchIds,
    String? adminEmail,
  }) async {
    final client = await DmeConfig.getClient();
    if (client == null) throw Exception('Supabase client not initialized');

    final Set<int> candidateIdSet = {};

    // 1. Fetch pending reminders where assigned_date == dateStr
    int offset = 0;
    const int pageSize = 1000;
    bool hasMore = true;

    while (hasMore) {
      var query = client
          .from('dme_reminders')
          .select('id')
          .inFilter('status', ['pending', 'called'])
          .eq('assigned_date', dateStr);

      if (branchIds != null && branchIds.isNotEmpty) {
        query = query.inFilter('last_purchase_branch', branchIds);
      }

      final batch = await query.range(offset, offset + pageSize - 1);
      final list = batch as List;
      for (var item in list) {
        final id = int.tryParse(item['id']?.toString() ?? '');
        if (id != null) candidateIdSet.add(id);
      }

      if (list.length < pageSize) {
        hasMore = false;
      } else {
        offset += pageSize;
      }
    }

    // Also check pending reminders that have assigned_to != null and reminder_date <= dateStrT23:59:59
    offset = 0;
    hasMore = true;
    while (hasMore) {
      var query = client
          .from('dme_reminders')
          .select('id')
          .inFilter('status', ['pending', 'called'])
          .not('assigned_to', 'is', null)
          .lte('reminder_date', '${dateStr}T23:59:59');

      if (branchIds != null && branchIds.isNotEmpty) {
        query = query.inFilter('last_purchase_branch', branchIds);
      }

      final batch = await query.range(offset, offset + pageSize - 1);
      final list = batch as List;
      for (var item in list) {
        final id = int.tryParse(item['id']?.toString() ?? '');
        if (id != null) candidateIdSet.add(id);
      }

      if (list.length < pageSize) {
        hasMore = false;
      } else {
        offset += pageSize;
      }
    }

    final candidateIds = candidateIdSet.toList();

    // 2. Batch update reminders to unassign them
    const int batchSize = 200;
    final nowIso = DateTime.now().toIso8601String();
    for (int i = 0; i < candidateIds.length; i += batchSize) {
      final chunk = candidateIds.sublist(i, min(i + batchSize, candidateIds.length));
      await client.from('dme_reminders').update({
        'assigned_to': null,
        'assigned_date': null,
        'is_overdue_leftover': false,
        'updated_at': nowIso,
      }).inFilter('id', chunk);
    }

    // 3. Delete records from reminder_assignment audit table
    try {
      var query = client.from('reminder_assignment').delete().eq('assigned_date', dateStr);
      if (branchIds != null && branchIds.isNotEmpty) {
        query = query.inFilter('branch_id', branchIds.map((b) => b.toString()).toList());
      }
      await query;
    } catch (_) {}
    try {
      var queryLegacy = client.from('reminder_assignment').delete().eq('assignment_date', dateStr);
      if (branchIds != null && branchIds.isNotEmpty) {
        queryLegacy = queryLegacy.inFilter('branch_id', branchIds.map((b) => b.toString()).toList());
      }
      await queryLegacy;
    } catch (_) {}

    // 4. Delete records from dme_reminder_assignments legacy table
    try {
      var queryDme = client.from('dme_reminder_assignments').delete().eq('assignment_date', dateStr);
      if (branchIds != null && branchIds.isNotEmpty) {
        queryDme = queryDme.inFilter('branch_id', branchIds);
      }
      await queryDme;
    } catch (_) {}

    // 5. Mark latest active run in Firestore assignment history as 'undone' so history is retained
    try {
      final snap = await FirebaseFirestore.instance
          .collection('dme_assignment_history')
          .where('assigned_date', isEqualTo: dateStr)
          .where('status', isEqualTo: 'active')
          .get();

      for (var doc in snap.docs) {
        await doc.reference.update({
          'status': 'undone',
          'undone_at': FieldValue.serverTimestamp(),
          if (adminEmail != null && adminEmail.isNotEmpty) 'undone_by': adminEmail,
        });
      }
    } catch (e) {
      debugPrint('Error updating history status on undo: $e');
    }

    return candidateIds.length;
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
            .select('id, reminder_date, status, remarks, call_duration, called_by, assigned_to, call_attempts')
            .inFilter('status', ['pending', 'called'])
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
      final Map<String, List<int>> userOverdue = {for (var u in eligibleUsers) u: []};
      final Map<String, List<int>> userNew = {for (var u in eligibleUsers) u: []};
      final Map<String, List<int>> userAttempted = {for (var u in eligibleUsers) u: []};
      final List<int> unattemptedOverdueIds = [];
      final List<int> newIds = [];
      final List<Map<String, dynamic>> attemptedItems = [];

      for (var item in allPending) {
        final id = int.tryParse(item['id']?.toString() ?? '');
        if (id == null) continue;

        final status = (item['status'] ?? '').toString().toLowerCase();
        final remarks = (item['remarks'] ?? '').toString().trim();
        final duration = int.tryParse(item['call_duration']?.toString() ?? '') ?? 0;
        final attempts = int.tryParse(item['call_attempts']?.toString() ?? '') ?? 0;
        final calledEmail = item['called_by']?.toString().toLowerCase().trim();
        final bool hasAttempt = attempts > 0 || (calledEmail != null && calledEmail.isNotEmpty) || status == 'called' || duration > 0;

        // Sticky assignment: When a user has already attempted a call on a reminder,
        // assign that reminder to the same user next day and henceforth until remarks are submitted.
        if (hasAttempt && remarks.isEmpty) {
          String? targetCaller;
          final prevAssigned = item['assigned_to']?.toString();
          if (prevAssigned != null && eligibleUsers.contains(prevAssigned)) {
            targetCaller = prevAssigned;
          }
          if (targetCaller != null) {
            attemptedItems.add({'id': id, 'targetCaller': targetCaller});
            continue;
          }
        }

        final rDateStr = item['reminder_date']?.toString();
        final rDate = rDateStr != null ? DateTime.tryParse(rDateStr) : null;

        if (rDate != null && DateTime(rDate.year, rDate.month, rDate.day).isBefore(currentDay)) {
          unattemptedOverdueIds.add(id);
        } else {
          newIds.add(id);
        }
      }

      // 4. Shuffle both pools randomly
      final rnd = Random();
      unattemptedOverdueIds.shuffle(rnd);
      newIds.shuffle(rnd);

      // Fairly distribute unattempted overdue reminders equally
      for (int i = 0; i < unattemptedOverdueIds.length; i++) {
        final targetUser = eligibleUsers[i % eligibleUsers.length];
        userOverdue[targetUser]!.add(unattemptedOverdueIds[i]);
      }

      // Fairly distribute today's new reminders equally
      for (int i = 0; i < newIds.length; i++) {
        final targetUser = eligibleUsers[i % eligibleUsers.length];
        userNew[targetUser]!.add(newIds[i]);
      }

      // Add attempted overdue reminders on top to the attempting user
      for (final item in attemptedItems) {
        final targetCaller = item['targetCaller'] as String;
        final id = item['id'] as int;
        userAttempted[targetCaller]!.add(id);
      }

      // 6. Write assignments to Supabase in chunks
      const int batchSize = 200;
      final nowIso = DateTime.now().toIso8601String();

      for (var user in eligibleUsers) {
        // Update unattempted overdue reminders
        final oList = userOverdue[user] ?? [];
        for (int i = 0; i < oList.length; i += batchSize) {
          final chunk = oList.sublist(i, min(i + batchSize, oList.length));
          await client.from('dme_reminders').update({
            'assigned_to': user,
            'assigned_date': todayStr,
            'is_overdue_leftover': true,
            'updated_at': nowIso,
          }).inFilter('id', chunk);
        }

        // Update attempted overdue reminders (sticky)
        final aList = userAttempted[user] ?? [];
        for (int i = 0; i < aList.length; i += batchSize) {
          final chunk = aList.sublist(i, min(i + batchSize, aList.length));
          await client.from('dme_reminders').update({
            'assigned_to': user,
            'assigned_date': todayStr,
            'is_overdue_leftover': true,
            'updated_at': nowIso,
          }).inFilter('id', chunk);
        }

        // Update today's new reminders for this user
        final tList = userNew[user] ?? [];
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
                  'id, customer_id, reminder_date, last_purchase_date, last_purchase_branch, status, remarks, updated_at, call_duration, called_timestamp, called_by, assigned_to, assigned_date, is_overdue_leftover, call_attempts, today_call_attempts, last_call_attempt_timestamp, last_call_day, dme_customers(id, name, phone, address, salesman, preference)')
              .eq('assigned_to', currentUserId)
              .eq('assigned_date', todayStr)
              .inFilter('status', ['pending', 'called']);

          if (filterBranchId != null) {
            query = query.eq('last_purchase_branch', filterBranchId);
          }
          batch = await query.range(offset, offset + pageSize - 1);
        } catch (_) {
          try {
            var fallbackQuery = client
                .from('dme_reminders')
                .select(
                    'id, customer_id, reminder_date, last_purchase_date, last_purchase_branch, status, remarks, updated_at, call_duration, called_timestamp, called_by, assigned_to, assigned_date, is_overdue_leftover, call_attempts, dme_customers(id, name, phone, address, salesman, preference)')
                .eq('assigned_to', currentUserId)
                .eq('assigned_date', todayStr)
                .inFilter('status', ['pending', 'called']);

            if (filterBranchId != null) {
              fallbackQuery = fallbackQuery.eq('last_purchase_branch', filterBranchId);
            }
            batch = await fallbackQuery.range(offset, offset + pageSize - 1);
          } catch (_) {
            try {
              var fallbackQuery2 = client
                  .from('dme_reminders')
                  .select(
                      'id, customer_id, reminder_date, last_purchase_date, last_purchase_branch, status, remarks, updated_at, call_duration, called_timestamp, called_by, assigned_to, assigned_date, is_overdue_leftover, dme_customers(id, name, phone, address, salesman)')
                  .eq('assigned_to', currentUserId)
                  .eq('assigned_date', todayStr)
                  .inFilter('status', ['pending', 'called']);

              if (filterBranchId != null) {
                fallbackQuery2 = fallbackQuery2.eq('last_purchase_branch', filterBranchId);
              }
              batch = await fallbackQuery2.range(offset, offset + pageSize - 1);
            } catch (_) {
              var fallbackQuery3 = client
                  .from('dme_reminders')
                  .select(
                      'id, customer_id, reminder_date, last_purchase_date, last_purchase_branch, status, remarks, updated_at, call_duration, called_timestamp, assigned_to, assigned_date, is_overdue_leftover, dme_customers(id, name, phone, address, salesman)')
                  .eq('assigned_to', currentUserId)
                  .eq('assigned_date', todayStr)
                  .inFilter('status', ['pending', 'called']);

              if (filterBranchId != null) {
                fallbackQuery3 = fallbackQuery3.eq('last_purchase_branch', filterBranchId);
              }
              batch = await fallbackQuery3.range(offset, offset + pageSize - 1);
            }
          }
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
      rem['customer_preference'] = cust?['preference'] ?? 'Call';
      rem['branch_id'] = bId;
      rem['branch_name'] = DmeConstants.getBranchName(bId);
      rem['is_overdue_leftover'] = rem['is_overdue_leftover'] == true ||
          rem['is_overdue_leftover'] == 'true' ||
          rem['is_overdue_leftover'] == 1;
      rem['call_attempts'] = int.tryParse(rem['call_attempts']?.toString() ?? '') ?? 0;
      
      // Calculate today_call_attempts: if last_call_day is today, use today_call_attempts, else reset to 0
      final todayStr = formatDate(DateTime.now());
      final lastCallDay = rem['last_call_day']?.toString();
      if (lastCallDay != null && lastCallDay == todayStr) {
        rem['today_call_attempts'] = int.tryParse(rem['today_call_attempts']?.toString() ?? '') ?? 0;
      } else {
        // If from previous day or null, today attempts are 0
        rem['today_call_attempts'] = 0;
      }
      rem['last_call_attempt_timestamp'] = rem['last_call_attempt_timestamp'];

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
