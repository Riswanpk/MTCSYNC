import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../dme_constants.dart';
import '../dme_config.dart';
import '../User/dme_assignment_service.dart';

const Color _primaryBlue = Color(0xFF005BAC);
const Color _primaryGreen = Color(0xFF8CC63F);

class DmeAdminReminderAssignPage extends StatefulWidget {
  const DmeAdminReminderAssignPage({super.key});

  @override
  State<DmeAdminReminderAssignPage> createState() => _DmeAdminReminderAssignPageState();
}

class _DmeAdminReminderAssignPageState extends State<DmeAdminReminderAssignPage> {
  bool _isLoading = true;
  bool _isExecuting = false;

  final DateTime _today = DateTime.now();
  String get _todayStr => DmeAssignmentService.formatDate(_today);

  List<Map<String, dynamic>> _dmeUsers = [];
  List<int> _activeBranches = [];

  // BranchId -> count of candidate reminders (status = pending, reminder_date <= today)
  Map<int, int> _candidateCounts = {};

  // BranchId -> existing assignment info from reminder_assignment table
  Map<int, Map<String, dynamic>> _assignmentStatus = {};

  // Global user attendance: uid -> true (present) / false (absent / on leave)
  final Map<String, bool> _userPresence = {};

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    await Future.wait([
      _loadUsersAndBranches(),
      _loadCandidateCounts(),
      _loadAssignmentStatus(),
    ]);
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadUsersAndBranches() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'dme_user')
          .get();

      final List<Map<String, dynamic>> users = [];
      final Set<int> branchSet = {};

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

        branchSet.addAll(branches);

        users.add({
          'uid': uid,
          'email': email,
          'username': username,
          'assigned_branches': branches,
        });

        // Default presence to true (Present) if not set
        if (!_userPresence.containsKey(uid)) {
          _userPresence[uid] = true;
        }
      }

      users.sort((a, b) =>
          (a['username'] as String).toLowerCase().compareTo((b['username'] as String).toLowerCase()));

      final sortedBranches = branchSet.toList()..sort();

      if (mounted) {
        setState(() {
          _dmeUsers = users;
          _activeBranches = sortedBranches.isNotEmpty
              ? sortedBranches
              : (DmeConstants.branches.map((b) => b.id).toList()..sort());
        });
      }
    } catch (e) {
      debugPrint('Error loading users/branches: $e');
    }
  }

  Future<void> _loadCandidateCounts() async {
    final client = await DmeConfig.getClient();
    if (client == null) return;

    final dateStr = _todayStr;
    final Map<int, int> totalMap = {};

    try {
      int offset = 0;
      const int pageSize = 1000;
      bool hasMore = true;

      while (hasMore) {
        final batch = await client
            .from('dme_reminders')
            .select('id, last_purchase_branch')
            .eq('status', 'pending')
            .lte('reminder_date', '${dateStr}T23:59:59')
            .range(offset, offset + pageSize - 1);

        final list = batch as List;
        for (var r in list) {
          final bId = int.tryParse(r['last_purchase_branch']?.toString() ?? '');
          if (bId != null) {
            totalMap[bId] = (totalMap[bId] ?? 0) + 1;
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
          _candidateCounts = totalMap;
        });
      }
    } catch (e) {
      debugPrint('Error loading candidate counts: $e');
    }
  }

  Future<void> _loadAssignmentStatus() async {
    final status = await DmeAssignmentService.getBranchAssignmentStatus(dateStr: _todayStr);
    if (mounted) {
      setState(() => _assignmentStatus = status);
    }
  }

  void _toggleUserAttendance(String uid, bool isPresent) {
    setState(() {
      _userPresence[uid] = isPresent;
    });
  }

  Future<void> _executeAutoDivision() async {
    // Collect active (present) users per branch
    int totalRemindersToAssign = 0;
    final Map<int, List<String>> branchPayload = {};

    for (var bId in _activeBranches) {
      final count = _candidateCounts[bId] ?? 0;
      // Get users assigned to this branch who are marked PRESENT
      final presentUsersForBranch = _dmeUsers.where((u) {
        final uid = u['uid'] as String;
        final branches = List<int>.from(u['assigned_branches'] ?? []);
        final isPresent = _userPresence[uid] ?? true;
        return branches.contains(bId) && isPresent;
      }).map((u) => u['uid'] as String).toList();

      if (count > 0 && presentUsersForBranch.isNotEmpty) {
        totalRemindersToAssign += count;
        branchPayload[bId] = presentUsersForBranch;
      }
    }

    if (totalRemindersToAssign == 0 && branchPayload.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No pending reminders to assign or all assigned users are marked absent.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final absentCount = _userPresence.values.where((v) => !v).length;
    final presentCount = _userPresence.values.where((v) => v).length;

    // Confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.auto_mode_rounded, color: _primaryBlue),
            SizedBox(width: 8),
            Text('Auto Divide Reminders'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Assign reminders for today:'),
            const SizedBox(height: 6),
            Text(
              DateFormat('EEEE, dd MMMM yyyy').format(_today),
              style: const TextStyle(fontWeight: FontWeight.bold, color: _primaryBlue),
            ),
            const Divider(height: 20),
            Text(
              '• Total Reminders to Divide: $totalRemindersToAssign\n'
              '• Present Users: $presentCount\n'
              '• Absent Users (Excluded): $absentCount\n\n'
              'Reminders will be equally auto-divided among the present users for each branch.',
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
              backgroundColor: _primaryBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Confirm & Assign'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isExecuting = true);

    try {
      final userUidToName = <String, String>{
        for (var u in _dmeUsers) (u['uid'] as String): (u['username'] as String),
      };
      final userUidToEmail = <String, String>{
        for (var u in _dmeUsers) (u['uid'] as String): (u['email'] as String? ?? (u['uid'] as String)),
      };
      final adminEmail = FirebaseAuth.instance.currentUser?.email ?? 'admin';

      final result = await DmeAssignmentService.assignRemindersByAdmin(
        dateStr: _todayStr,
        branchToActiveUserUids: branchPayload,
        userUidToName: userUidToName,
        userUidToEmail: userUidToEmail,
        adminEmail: adminEmail,
      );

      await _loadAll();

      setState(() => _isExecuting = false);

      if (mounted) {
        showModalBottomSheet(
          context: context,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (ctx) => Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_circle_rounded, color: Colors.green, size: 48),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Auto Division Completed!',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                const SizedBox(height: 8),
                Text(
                  'Total ${result['total_assigned']} reminders auto-divided among present users for today ($_todayStr).',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[700], fontSize: 13),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryBlue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error auto dividing reminders: $e');
      setState(() => _isExecuting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _confirmAndUndoAssignment() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.undo_rounded, color: Colors.deepOrange),
            SizedBox(width: 8),
            Text('Undo Assignment'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Are you sure you want to undo today\'s reminder assignment?'),
            const SizedBox(height: 8),
            Text(
              DateFormat('EEEE, dd MMMM yyyy').format(_today),
              style: const TextStyle(fontWeight: FontWeight.bold, color: _primaryBlue),
            ),
            const Divider(height: 20),
            const Text(
              '• All pending reminders assigned for today and overdue will be unassigned.\n'
              '• Any calls already completed or called today will NOT be affected.\n'
              '• You can then adjust attendance and re-assign.',
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Confirm Undo'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isExecuting = true);

    try {
      final unassignedCount = await DmeAssignmentService.undoTodayAssignments(
        dateStr: _todayStr,
        branchIds: _activeBranches,
      );

      await _loadAll();

      setState(() => _isExecuting = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Successfully unassigned $unassignedCount pending reminder(s). You can now adjust attendance and re-assign.',
            ),
            backgroundColor: Colors.green[700],
          ),
        );
      }
    } catch (e) {
      debugPrint('Error undoing assignment: $e');
      setState(() => _isExecuting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error undoing assignment: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final presentCount = _userPresence.values.where((v) => v).length;
    final absentCount = _userPresence.values.where((v) => !v).length;
    final totalPending = _candidateCounts.values.fold(0, (a, b) => a + b);
    final isAlreadyAssignedToday = _assignmentStatus.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reminder Assign', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: _primaryBlue,
        foregroundColor: Colors.white,
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
                  // 1. Today's Date Banner Card (Without Date Change button, overflow proof)
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: _primaryBlue.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.calendar_today_rounded, color: _primaryBlue, size: 22),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 8,
                                  runSpacing: 4,
                                  children: [
                                    Text(
                                      DateFormat('dd MMMM yyyy').format(_today),
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.green.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'TODAY',
                                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  isAlreadyAssignedToday
                                      ? '✓ Reminders already assigned for today'
                                      : 'Not assigned yet for today',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: isAlreadyAssignedToday ? Colors.green[700] : Colors.orange[800],
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 2. Daily User Attendance Card
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.how_to_reg_rounded, color: _primaryGreen, size: 22),
                                  SizedBox(width: 8),
                                  Text(
                                    'Daily User Attendance',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
                            'If a user is absent / on leave, simply toggle them off. Reminders will automatically auto-divide equally among the remaining present users.',
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          ),
                          const Divider(height: 24),

                          // User Attendance List
                          if (_dmeUsers.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(12.0),
                              child: Text('No DME users found.', style: TextStyle(fontStyle: FontStyle.italic)),
                            )
                          else
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _dmeUsers.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final user = _dmeUsers[index];
                                final uid = user['uid'] as String;
                                final name = user['username'] as String;
                                final email = user['email'] as String;
                                final isPresent = _userPresence[uid] ?? true;

                                final branches = List<int>.from(user['assigned_branches'] ?? []);
                                final branchNames = branches.map((b) => DmeConstants.getBranchName(b)).join(', ');

                                return SwitchListTile(
                                  value: isPresent,
                                  onChanged: (val) => _toggleUserAttendance(uid, val),
                                  activeColor: Colors.green,
                                  secondary: CircleAvatar(
                                    backgroundColor: isPresent ? _primaryBlue : Colors.grey[400],
                                    foregroundColor: Colors.white,
                                    radius: 18,
                                    child: Text(
                                      name.isNotEmpty ? name[0].toUpperCase() : 'U',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                  ),
                                  title: Wrap(
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    spacing: 6,
                                    runSpacing: 2,
                                    children: [
                                      Text(
                                        name,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          decoration: isPresent ? null : TextDecoration.lineThrough,
                                          color: isPresent ? null : Colors.grey[600],
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
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
                                  subtitle: Text(
                                    branchNames.isNotEmpty ? 'Branches: $branchNames' : email,
                                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 3. Undo Assignment Button (Visible when already assigned today)
                  if (isAlreadyAssignedToday) ...[
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: _isExecuting ? null : _confirmAndUndoAssignment,
                        icon: const Icon(Icons.undo_rounded, color: Colors.deepOrange),
                        label: const Text(
                          'Undo Assignment for Today',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Colors.deepOrange,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.deepOrange, width: 1.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // 4. Auto Assign Button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _isExecuting ? null : _executeAutoDivision,
                      icon: _isExecuting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded, size: 20),
                      label: Text(
                        _isExecuting
                            ? 'Auto Dividing Reminders...'
                            : (isAlreadyAssignedToday
                                ? 'Re-assign / Auto Divide Reminders ($totalPending Total)'
                                : 'Assign / Auto Divide Reminders ($totalPending Total)'),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryBlue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      'Users will only see their reminders once assigned everyday.',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600], fontStyle: FontStyle.italic),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
