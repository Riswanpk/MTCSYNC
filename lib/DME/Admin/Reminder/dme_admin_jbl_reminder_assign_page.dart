import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../dme_config.dart';
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
    int count = 0;

    try {
      int offset = 0;
      const int pageSize = 1000;
      bool hasMore = true;

      while (hasMore) {
        final batch = await client
            .from('dme_reminders')
            .select('id')
            .inFilter('status', ['pending', 'called'])
            .eq('last_purchase_branch', _jblBranchId)
            .lte('reminder_date', '${dateStr}T23:59:59')
            .range(offset, offset + pageSize - 1);

        final list = batch as List;
        count += list.length;

        if (list.length < pageSize) {
          hasMore = false;
        } else {
          offset += pageSize;
        }
      }

      if (mounted) {
        setState(() {
          _jblPendingCount = count;
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

  /// Strictly executes Auto Division ONLY for JBL branch
  Future<void> _executeJblAutoDivision() async {
    final presentUsers = _jblUsers
        .where((u) => _userPresence[u['uid']] ?? true)
        .map((u) => u['uid'] as String)
        .toList();

    if (presentUsers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All JBL users are marked absent. Please toggle at least one user present.'),
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
        content: Column(
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
              '• JBL Reminders to Divide: $_jblPendingCount\n'
              '• Present JBL Users: ${presentUsers.length}\n'
              '• Absent Users: ${_jblUsers.length - presentUsers.length}\n\n'
              'Only JBL branch reminders will be partitioned and assigned. ALL other branches remain untouched.',
              style: const TextStyle(fontSize: 13, height: 1.4),
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
            .select('id, reminder_date, status, remarks, call_duration, called_by, assigned_to')
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

      // 3. Partition reminders fairly among present JBL users
      final currentDay = DateTime(_today.year, _today.month, _today.day);
      final Map<String, List<int>> userLeftovers = {for (var u in presentUsers) u: []};
      final Map<String, List<int>> userTodays = {for (var u in presentUsers) u: []};
      final List<int> leftoverIds = [];
      final List<int> todayIds = [];

      for (var item in allPending) {
        final id = int.tryParse(item['id']?.toString() ?? '');
        if (id == null) continue;

        final rDateStr = item['reminder_date']?.toString();
        DateTime? rDate;
        if (rDateStr != null) {
          rDate = DateTime.tryParse(rDateStr);
        }

        if (rDate != null && DateTime(rDate.year, rDate.month, rDate.day).isBefore(currentDay)) {
          leftoverIds.add(id);
        } else {
          todayIds.add(id);
        }
      }

      // Distribute leftovers evenly
      for (int i = 0; i < leftoverIds.length; i++) {
        final targetUser = presentUsers[i % presentUsers.length];
        userLeftovers[targetUser]!.add(leftoverIds[i]);
      }

      // Distribute today's reminders evenly
      for (int i = 0; i < todayIds.length; i++) {
        final targetUser = presentUsers[i % presentUsers.length];
        userTodays[targetUser]!.add(todayIds[i]);
      }

      // Batch update reminders for JBL
      const int batchSize = 200;
      for (var user in presentUsers) {
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

      // Record in audit table
      final userMap = {for (var u in _jblUsers) (u['uid'] as String): u};
      for (var user in presentUsers) {
        final uEmail = (userMap[user]?['email'] as String?) ?? user;
        final count = (userLeftovers[user]?.length ?? 0) + (userTodays[user]?.length ?? 0);
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
          'assigned_user_ids': presentUsers,
          'assigned_user_names': presentUsers.map((u) => (userMap[u]?['username'] as String?) ?? u).toList(),
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
                          else
                            ListView.separated(
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

                                return SwitchListTile(
                                  value: isPresent,
                                  onChanged: (val) => _toggleUserAttendance(uid, val),
                                  activeColor: Colors.green,
                                  secondary: CircleAvatar(
                                    backgroundColor: isPresent ? Colors.purple : Colors.grey[400],
                                    foregroundColor: Colors.white,
                                    radius: 18,
                                    child: Text(
                                      name.isNotEmpty ? name[0].toUpperCase() : 'U',
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  title: Text(
                                    name,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      decoration: isPresent ? null : TextDecoration.lineThrough,
                                      color: isPresent ? null : Colors.grey[600],
                                    ),
                                  ),
                                  subtitle: Text(email, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                                );
                              },
                            ),
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
