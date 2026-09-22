import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../Misc/dme_config.dart';
import '../../User/dme_assignment_service.dart';

const Color _primaryBlue = Color(0xFF005BAC);
const int _jblBranchId = 6; // JBL Branch ID

class DmeAdminJblReminderAssignPage extends StatefulWidget {
  const DmeAdminJblReminderAssignPage({super.key});

  @override
  State<DmeAdminJblReminderAssignPage> createState() => _DmeAdminJblReminderAssignPageState();
}

class _DmeAdminJblReminderAssignPageState extends State<DmeAdminJblReminderAssignPage> {
  bool _isLoading = true;
  bool _isExecuting = false;

  final DateTime _today = DateTime.now();
  String get _todayStr => DmeAssignmentService.formatDate(_today);

  List<Map<String, dynamic>> _jblUsers = [];
  int _jblPendingCount = 0;
  int _jblNewCount = 0;
  int _jblAttemptedCount = 0;
  int _jblOverdueCount = 0;
  Map<String, int> _jblAttemptedUserCounts = {};
  Map<String, dynamic>? _jblAssignmentStatus;

  // Global user attendance for JBL users: uid -> true (present) / false (absent)
  final Map<String, bool> _userPresence = {};

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    await Future.wait([
      _loadJblUsers(),
      _loadJblCandidateCount(),
      _loadJblAssignmentStatus(),
    ]);
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadJblUsers() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'dme_user')
          .get();

      final List<Map<String, dynamic>> users = [];

      for (var doc in snap.docs) {
        final data = doc.data();
        final uid = doc.id;
        final email = data['email']?.toString() ?? '';
        final username = data['username']?.toString() ??
            data['name']?.toString() ??
            (email.isNotEmpty ? email.split('@').first : 'User');

        List<int> branches = [];
        if (data['assigned_branches'] is List) {
          branches = (data['assigned_branches'] as List)
              .map((e) => int.tryParse(e.toString()) ?? 0)
              .where((e) => e > 0)
              .toList();
        }

        // Only include users who are assigned to JBL
        if (branches.contains(_jblBranchId)) {
          users.add({
            'uid': uid,
            'email': email,
            'username': username,
            'assigned_branches': branches,
          });

          if (!_userPresence.containsKey(uid)) {
            _userPresence[uid] = true;
          }
        }
      }

      users.sort((a, b) =>
          (a['username'] as String).toLowerCase().compareTo((b['username'] as String).toLowerCase()));

      if (mounted) {
        setState(() {
          _jblUsers = users;
        });
      }
    } catch (e) {
      debugPrint('Error loading JBL users: $e');
    }
  }

  Future<void> _loadJblCandidateCount() async {
    final client = await DmeConfig.getClient();
    if (client == null) return;

    final dateStr = _todayStr;
    final currentDay = DateTime(_today.year, _today.month, _today.day);
    int count = 0;
    int newCount = 0;
    int overdueCount = 0;
    int attemptedCount = 0;
    final Map<String, int> attemptedUserCounts = {};

    try {
      int offset = 0;
      const int pageSize = 1000;
      bool hasMore = true;

      while (hasMore) {
        final batch = await client
            .from('dme_reminders')
            .select('id, reminder_date, status, remarks, call_duration, called_by, assigned_to, call_attempts')
            .inFilter('status', ['pending', 'called'])
            .eq('last_purchase_branch', _jblBranchId)
            .lte('reminder_date', '${dateStr}T23:59:59')
            .range(offset, offset + pageSize - 1);

        final list = batch as List;
        count += list.length;

        for (var item in list) {
          final status = (item['status'] ?? '').toString().toLowerCase();
          final remarks = (item['remarks'] ?? '').toString().trim();
          final duration = int.tryParse(item['call_duration']?.toString() ?? '') ?? 0;
          final attempts = int.tryParse(item['call_attempts']?.toString() ?? '') ?? 0;
          final calledEmail = item['called_by']?.toString().toLowerCase().trim();
          final bool hasAttempt = attempts > 0 || (calledEmail != null && calledEmail.isNotEmpty) || status == 'called' || duration > 0;

          if (hasAttempt && remarks.isEmpty) {
            attemptedCount++;
            final prevAssigned = item['assigned_to']?.toString();
            if (prevAssigned != null && prevAssigned.isNotEmpty) {
              attemptedUserCounts[prevAssigned] = (attemptedUserCounts[prevAssigned] ?? 0) + 1;
            }
          } else {
            final rDateStr = item['reminder_date']?.toString();
            DateTime? rDate;
            if (rDateStr != null) {
              rDate = DateTime.tryParse(rDateStr);
            }
            if (rDate != null && DateTime(rDate.year, rDate.month, rDate.day).isBefore(currentDay)) {
              overdueCount++;
            } else {
              newCount++;
            }
          }
        }

        if (list.length < pageSize) {
          hasMore = false;
        } else {
          offset += pageSize;
        }
      }

      if (mounted) {
        setState(() {
          _jblPendingCount = count;
          _jblNewCount = newCount;
          _jblAttemptedCount = attemptedCount;
          _jblOverdueCount = overdueCount;
          _jblAttemptedUserCounts = attemptedUserCounts;
        });
      }
    } catch (e) {
      debugPrint('Error loading JBL candidate counts: $e');
    }
  }

  Future<void> _loadJblAssignmentStatus() async {
    final statusMap = await DmeAssignmentService.getBranchAssignmentStatus(dateStr: _todayStr);
    if (mounted) {
      setState(() {
        _jblAssignmentStatus = statusMap[_jblBranchId];
      });
    }
  }

  void _toggleUserAttendance(String uid, bool isPresent) {
    setState(() {
      _userPresence[uid] = isPresent;
    });
  }

  /// Calculates per-user estimated breakdown (Total, New, Overdue, Attempted) for JBL branch
  Map<String, Map<String, int>> _calculateJblUserEstimatedBreakdown() {
    final Map<String, Map<String, int>> result = {
      for (var u in _jblUsers)
        (u['uid'] as String): {
          'total': 0,
          'new': 0,
          'overdue': 0,
          'attempted': 0,
        }
    };
    final presentUsers = _jblUsers.where((u) => _userPresence[u['uid'] as String] ?? true).toList();
    if (presentUsers.isEmpty) return result;

    final presentUids = presentUsers.map((u) => u['uid'] as String).toList();

    // 1. Distribute unattempted overdue reminders equally
    if (_jblOverdueCount > 0) {
      final baseOverdue = _jblOverdueCount ~/ presentUsers.length;
      final remOverdue = _jblOverdueCount % presentUsers.length;
      for (int i = 0; i < presentUsers.length; i++) {
        final uid = presentUids[i];
        result[uid]!['overdue'] = baseOverdue + (i < remOverdue ? 1 : 0);
      }
    }

    // 2. Distribute new reminders equally
    if (_jblNewCount > 0) {
      final baseNew = _jblNewCount ~/ presentUsers.length;
      final remNew = _jblNewCount % presentUsers.length;
      for (int i = 0; i < presentUsers.length; i++) {
        final uid = presentUids[i];
        result[uid]!['new'] = baseNew + (i < remNew ? 1 : 0);
      }
    }

    // 3. Add attempted overdue reminders directly to original caller
    _jblAttemptedUserCounts.forEach((uid, attCount) {
      if (result.containsKey(uid) && (_userPresence[uid] ?? true)) {
        result[uid]!['attempted'] = (result[uid]!['attempted'] ?? 0) + attCount;
      }
    });

    // Calculate total
    for (var uid in result.keys) {
      final m = result[uid]!;
      m['total'] = (m['new'] ?? 0) + (m['overdue'] ?? 0) + (m['attempted'] ?? 0);
    }

    return result;
  }

  Future<void> _executeJblAutoDivision() async {
    final presentUsers = _jblUsers.where((u) => _userPresence[u['uid'] as String] ?? true).toList();

    if (presentUsers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All JBL users are marked absent. Toggle at least 1 user present.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_jblPendingCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No pending reminders for JBL branch to assign.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final estimatedBreakdown = _calculateJblUserEstimatedBreakdown();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.science_rounded, color: Colors.purple),
            SizedBox(width: 8),
            Expanded(
              child: Text('Assign JBL Branch Only'),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.purple.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'TEST MODE: Scoped Strictly to JBL Branch (ID: 6)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.purple),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Date: ${DateFormat('EEEE, dd MMMM yyyy').format(_today)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const Divider(height: 16),
              Text(
                '• Total JBL Reminders: $_jblPendingCount\n'
                '• Present JBL Users: ${presentUsers.length}\n'
                '• Absent Users: ${_jblUsers.length - presentUsers.length}',
                style: const TextStyle(fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '$_jblNewCount New',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue[800]),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.purple.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '$_jblAttemptedCount Attempted',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.purple.shade700),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.deepOrange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '$_jblOverdueCount Overdue',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.deepOrange),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                'Reminders Each User Will Receive:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.purple),
              ),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 180),
                decoration: BoxDecoration(
                  color: Colors.purple.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.purple.withValues(alpha: 0.2)),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    children: _jblUsers.map((u) {
                      final uid = u['uid'] as String;
                      final name = u['username'] as String;
                      final isPresent = _userPresence[uid] ?? true;
                      final uStats = estimatedBreakdown[uid] ?? {'total': 0, 'new': 0, 'overdue': 0, 'attempted': 0};
                      final total = uStats['total'] ?? 0;
                      final n = uStats['new'] ?? 0;
                      final a = uStats['attempted'] ?? 0;
                      final o = uStats['overdue'] ?? 0;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                        child: Row(
                          children: [
                            Icon(
                              isPresent ? Icons.check_circle_rounded : Icons.cancel_rounded,
                              size: 16,
                              color: isPresent ? Colors.purple : Colors.red,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                name,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  decoration: isPresent ? null : TextDecoration.lineThrough,
                                  color: isPresent ? Colors.black87 : Colors.grey[600],
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: isPresent
                                    ? Colors.purple.withValues(alpha: 0.12)
                                    : Colors.grey.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                isPresent ? '$total ($n New • $a Att. • $o OD)' : '0 (Absent)',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isPresent ? Colors.purple : Colors.grey[600],
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple,
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirm JBL Assign'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isExecuting = true);

    try {
      final client = await DmeConfig.getClient();
      if (client == null) throw Exception('Supabase client not initialized');

      final dateStr = _todayStr;
      final nowIso = DateTime.now().toIso8601String();
      final adminEmail = FirebaseAuth.instance.currentUser?.email ?? 'admin';

      // 1. Fetch JBL pending candidates strictly
      final List<dynamic> allPending = [];
      int offset = 0;
      const int pageSize = 1000;
      bool hasMore = true;

      while (hasMore) {
        final batch = await client
            .from('dme_reminders')
            .select('id, reminder_date, status, remarks, call_duration, called_by, assigned_to, call_attempts')
            .inFilter('status', ['pending', 'called'])
            .eq('last_purchase_branch', _jblBranchId)
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
        setState(() => _isExecuting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No JBL pending reminders found.')),
        );
        return;
      }

      // 2. Clean previous assignment logs strictly for JBL for today
      try {
        await client
            .from('reminder_assignment')
            .delete()
            .eq('assigned_date', dateStr)
            .eq('branch_id', _jblBranchId.toString());
      } catch (_) {}

      try {
        await client
            .from('dme_reminder_assignments')
            .delete()
            .eq('assignment_date', dateStr)
            .eq('branch_id', _jblBranchId);
      } catch (_) {}

      // 3. Partition reminders: unattempted overdue and new divided equally, attempted added to caller
      final presentUserUids = presentUsers.map((u) => u['uid'] as String).toList();
      final currentDay = DateTime(_today.year, _today.month, _today.day);
      final Map<String, List<int>> userOverdue = {for (var u in presentUserUids) u: []};
      final Map<String, List<int>> userNew = {for (var u in presentUserUids) u: []};
      final Map<String, List<int>> userAttempted = {for (var u in presentUserUids) u: []};
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
          if (prevAssigned != null && presentUserUids.contains(prevAssigned)) {
            targetCaller = prevAssigned;
          }
          if (targetCaller != null) {
            attemptedItems.add({'id': id, 'targetCaller': targetCaller});
            continue;
          }
        }

        final rDateStr = item['reminder_date']?.toString();
        DateTime? rDate;
        if (rDateStr != null) {
          rDate = DateTime.tryParse(rDateStr);
        }

        if (rDate != null && DateTime(rDate.year, rDate.month, rDate.day).isBefore(currentDay)) {
          unattemptedOverdueIds.add(id);
        } else {
          newIds.add(id);
        }
      }

      // Shuffle pools randomly for fairness
      final rnd = Random();
      unattemptedOverdueIds.shuffle(rnd);
      newIds.shuffle(rnd);

      // Distribute unattempted overdue evenly
      for (int i = 0; i < unattemptedOverdueIds.length; i++) {
        final targetUser = presentUserUids[i % presentUserUids.length];
        userOverdue[targetUser]!.add(unattemptedOverdueIds[i]);
      }

      // Distribute today's new reminders evenly
      for (int i = 0; i < newIds.length; i++) {
        final targetUser = presentUserUids[i % presentUserUids.length];
        userNew[targetUser]!.add(newIds[i]);
      }

      // Add attempted overdue reminders on top to original caller
      for (final item in attemptedItems) {
        final targetCaller = item['targetCaller'] as String;
        final id = item['id'] as int;
        userAttempted[targetCaller]!.add(id);
      }

      // Batch update reminders for JBL
      const int batchSize = 200;
      for (var user in presentUserUids) {
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

      // Record in audit table
      final userMap = {for (var u in _jblUsers) (u['uid'] as String): u};
      for (var user in presentUserUids) {
        final uEmail = (userMap[user]?['email'] as String?) ?? user;
        final count = (userOverdue[user]?.length ?? 0) + (userAttempted[user]?.length ?? 0) + (userNew[user]?.length ?? 0);
        try {
          await client.from('reminder_assignment').upsert({
            'assigned_date': dateStr,
            'branch_id': _jblBranchId.toString(),
            'user_email': uEmail,
            'reminder_count': count,
          }, onConflict: 'assigned_date,branch_id,user_email');
        } catch (_) {}
      }

      try {
        await client.from('dme_reminder_assignments').upsert({
          'assignment_date': dateStr,
          'branch_id': _jblBranchId,
          'assigned_user_ids': presentUserUids,
          'assigned_user_names': presentUserUids.map((uid) => (userMap[uid]?['username'] as String?) ?? uid).toList(),
          'total_reminders': allPending.length,
          'assigned_by': adminEmail,
          'updated_at': nowIso,
        }, onConflict: 'assignment_date,branch_id');
      } catch (_) {}

      await _loadAll();

      setState(() => _isExecuting = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Successfully assigned ${allPending.length} JBL reminders across ${presentUsers.length} user(s).',
            ),
            backgroundColor: Colors.green[700],
          ),
        );
      }
    } catch (e) {
      debugPrint('Error assigning JBL: $e');
      setState(() => _isExecuting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Strictly undoes reminder assignment ONLY for JBL branch
  Future<void> _confirmAndUndoJblAssignment() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.undo_rounded, color: Colors.deepOrange),
            SizedBox(width: 8),
            Text('Undo JBL Assignment'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.deepOrange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'TEST MODE: Scoped Strictly to JBL Branch',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.deepOrange),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Are you sure you want to undo today\'s assignment for JBL only?'),
            const SizedBox(height: 6),
            Text(
              DateFormat('EEEE, dd MMMM yyyy').format(_today),
              style: const TextStyle(fontWeight: FontWeight.bold, color: _primaryBlue),
            ),
            const Divider(height: 16),
            const Text(
              '• Only pending reminders belonging to JBL will be reset.\n'
              '• No other branch reminders will be touched or unassigned.\n'
              '• Completed calls made today will NOT be lost.',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepOrange,
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirm Undo JBL'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isExecuting = true);

    try {
      final unassignedCount = await DmeAssignmentService.undoTodayAssignments(
        dateStr: _todayStr,
        branchIds: [_jblBranchId], // Strictly JBL branch!
      );

      await _loadAll();

      setState(() => _isExecuting = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully unassigned $unassignedCount JBL reminder(s). Other branches were unaffected.'),
            backgroundColor: Colors.green[700],
          ),
        );
      }
    } catch (e) {
      debugPrint('Error undoing JBL assignment: $e');
      setState(() => _isExecuting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error undoing: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildThreeStatsCard({
    required int totalNew,
    required int totalAttempted,
    required int totalOverdue,
    required int totalPending,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.pie_chart_rounded, size: 20, color: Colors.purple),
                    SizedBox(width: 8),
                    Text(
                      'JBL Reminders Breakdown',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.purple.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$totalPending Total',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.purple),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                // 1. New Stat
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      children: [
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.fiber_new_rounded, size: 16, color: Colors.blue),
                            SizedBox(width: 4),
                            Text(
                              'New',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$totalNew',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blue),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Equally divided',
                          style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // 2. Attempted Stat
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                    decoration: BoxDecoration(
                      color: Colors.purple.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.purple.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.phone_forwarded_rounded, size: 14, color: Colors.purple.shade700),
                            const SizedBox(width: 4),
                            Text(
                              'Attempted',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.purple.shade700),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$totalAttempted',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.purple.shade700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Sticky to caller',
                          style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // 3. Overdue Stat
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                    decoration: BoxDecoration(
                      color: Colors.deepOrange.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.deepOrange.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      children: [
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.warning_amber_rounded, size: 15, color: Colors.deepOrange),
                            SizedBox(width: 4),
                            Text(
                              'Overdue',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.deepOrange),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$totalOverdue',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.deepOrange),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Equally divided',
                          style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final presentCount = _userPresence.values.where((v) => v).length;
    final absentCount = _userPresence.values.where((v) => !v).length;
    final isAlreadyAssigned = _jblAssignmentStatus != null;

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.science_rounded, size: 22),
            SizedBox(width: 8),
            Text('JBL Test Branch Assign', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        backgroundColor: Colors.purple.shade700,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _loadAll,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Prominent Test Isolation Banner
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.purple.shade700, Colors.purple.shade900],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.purple.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.shield_rounded, color: Colors.white, size: 32),
                        SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'JBL Branch Testing Mode',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'This page exclusively assigns and undoes reminders for JBL (Branch ID: 6). All other branches are 100% isolated and untouched.',
                                style: TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 2. Status & Pending Reminders Card
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'JBL Branch Pending Reminders',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    DateFormat('EEEE, dd MMMM yyyy').format(_today),
                                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.purple.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '$_jblPendingCount Pending',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: Colors.purple,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isAlreadyAssigned
                                  ? Colors.green.withValues(alpha: 0.12)
                                  : Colors.orange.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              isAlreadyAssigned
                                  ? '✓ JBL assigned for today (${_jblAssignmentStatus?['reminder_count'] ?? ''} reminders)'
                                  : 'Not assigned yet for today',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: isAlreadyAssigned ? Colors.green[800] : Colors.orange[800],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 2b. Three Stats Overview Card (New, Attempted, Overdue)
                  _buildThreeStatsCard(
                    totalNew: _jblNewCount,
                    totalAttempted: _jblAttemptedCount,
                    totalOverdue: _jblOverdueCount,
                    totalPending: _jblPendingCount,
                  ),
                  const SizedBox(height: 16),

                  // 3. User Attendance for JBL
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.people_alt_rounded, color: Colors.purple, size: 20),
                                  SizedBox(width: 8),
                                  Text(
                                    'JBL DME Users',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.grey.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '$presentCount Present  •  $absentCount Absent',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey[700]),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Toggle users present or absent for today\'s test assignment.',
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          ),
                          const Divider(height: 20),
                          if (_jblUsers.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(12.0),
                              child: Text(
                                'No DME users currently assigned to JBL branch.',
                                style: TextStyle(fontStyle: FontStyle.italic),
                              ),
                            )
                          else ...[
                            Builder(
                              builder: (_) {
                                final estimatedBreakdown = _calculateJblUserEstimatedBreakdown();
                                return ListView.separated(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: _jblUsers.length,
                                  separatorBuilder: (_, __) => const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    final user = _jblUsers[index];
                                    final uid = user['uid'] as String;
                                    final name = user['username'] as String;
                                    final email = user['email'] as String;
                                    final isPresent = _userPresence[uid] ?? true;
                                    final estStats = estimatedBreakdown[uid] ?? {'total': 0, 'new': 0, 'overdue': 0, 'attempted': 0};
                                    final estTotal = estStats['total'] ?? 0;

                                    return Container(
                                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          // User Avatar
                                          CircleAvatar(
                                            backgroundColor: isPresent ? Colors.purple : Colors.grey[400],
                                            foregroundColor: Colors.white,
                                            radius: 18,
                                            child: Text(
                                              name.isNotEmpty ? name[0].toUpperCase() : 'U',
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                            ),
                                          ),
                                          const SizedBox(width: 12),

                                          // User Details & Chips
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                // Name & Present/Absent Tag
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: Text(
                                                        name,
                                                        style: TextStyle(
                                                          fontWeight: FontWeight.bold,
                                                          fontSize: 14,
                                                          decoration: isPresent ? null : TextDecoration.lineThrough,
                                                          color: isPresent ? Colors.black87 : Colors.grey[600],
                                                        ),
                                                      ),
                                                    ),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: isPresent
                                                            ? Colors.green.withValues(alpha: 0.15)
                                                            : Colors.red.withValues(alpha: 0.15),
                                                        borderRadius: BorderRadius.circular(4),
                                                      ),
                                                      child: Text(
                                                        isPresent ? 'PRESENT' : 'ABSENT',
                                                        style: TextStyle(
                                                          fontSize: 10,
                                                          fontWeight: FontWeight.bold,
                                                          color: isPresent ? Colors.green[800] : Colors.red[800],
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 6),

                                                if (isPresent) ...[
                                                  Wrap(
                                                    spacing: 6,
                                                    runSpacing: 5,
                                                    crossAxisAlignment: WrapCrossAlignment.center,
                                                    children: [
                                                      // Projected Total
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                                        decoration: BoxDecoration(
                                                          color: Colors.purple.shade50,
                                                          borderRadius: BorderRadius.circular(6),
                                                          border: Border.all(color: Colors.purple.shade300, width: 1),
                                                        ),
                                                        child: Text(
                                                          '~ $estTotal reminders',
                                                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.purple.shade900),
                                                        ),
                                                      ),
                                                      // New
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                                        decoration: BoxDecoration(
                                                          color: Colors.blue.shade50,
                                                          borderRadius: BorderRadius.circular(6),
                                                          border: Border.all(color: Colors.blue.shade300, width: 1),
                                                        ),
                                                        child: Text(
                                                          '${estStats['new'] ?? 0} New',
                                                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue.shade900),
                                                        ),
                                                      ),
                                                      // Attempted
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                                        decoration: BoxDecoration(
                                                          color: Colors.purple.shade50,
                                                          borderRadius: BorderRadius.circular(6),
                                                          border: Border.all(color: Colors.purple.shade300, width: 1),
                                                        ),
                                                        child: Text(
                                                          '${estStats['attempted'] ?? 0} Att.',
                                                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.purple.shade900),
                                                        ),
                                                      ),
                                                      // Overdue
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                                        decoration: BoxDecoration(
                                                          color: Colors.deepOrange.shade50,
                                                          borderRadius: BorderRadius.circular(6),
                                                          border: Border.all(color: Colors.deepOrange.shade300, width: 1),
                                                        ),
                                                        child: Text(
                                                          '${estStats['overdue'] ?? 0} OD',
                                                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.deepOrange.shade900),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ] else ...[
                                                  const Text(
                                                    '0 reminders (Marked absent)',
                                                    style: TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic),
                                                  ),
                                                ],
                                                const SizedBox(height: 5),
                                                Text(
                                                  email,
                                                  style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 8),

                                          // Attendance Switch
                                          Switch(
                                            value: isPresent,
                                            onChanged: (val) => _toggleUserAttendance(uid, val),
                                            activeColor: Colors.green,
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 4. Action Buttons (Undo & Assign)
                  if (isAlreadyAssigned) ...[
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: _isExecuting ? null : _confirmAndUndoJblAssignment,
                        icon: const Icon(Icons.undo_rounded, color: Colors.deepOrange),
                        label: const Text(
                          'Undo JBL Assignment Only',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.deepOrange),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.deepOrange, width: 1.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _isExecuting ? null : _executeJblAutoDivision,
                      icon: _isExecuting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Icon(Icons.science_rounded, size: 20),
                      label: Text(
                        _isExecuting
                            ? 'Assigning JBL Reminders...'
                            : (isAlreadyAssigned
                                ? 'Re-assign JBL Reminders ($_jblPendingCount Total)'
                                : 'Assign JBL Reminders ($_jblPendingCount Total)'),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple.shade700,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
