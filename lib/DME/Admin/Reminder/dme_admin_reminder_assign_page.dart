import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../Misc/dme_constants.dart';
import '../../Misc/dme_config.dart';
import '../../User/dme_assignment_service.dart';

const Color _primaryBlue = Color(0xFF005BAC);
const Color _primaryGreen = Color(0xFF8CC63F);
const int _jblBranchId = 6; // JBL branch assigned separately in JBL testing page

class DmeAdminReminderAssignPage extends StatefulWidget {
  const DmeAdminReminderAssignPage({super.key});

  @override
  State<DmeAdminReminderAssignPage> createState() => _DmeAdminReminderAssignPageState();
}

class _DmeAdminReminderAssignPageState extends State<DmeAdminReminderAssignPage>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  bool _isExecuting = false;

  late TabController _tabController;

  final DateTime _today = DateTime.now();
  String get _todayStr => DmeAssignmentService.formatDate(_today);

  List<Map<String, dynamic>> _dmeUsers = [];
  List<int> _activeBranches = [];

  // BranchId -> count of candidate reminders (status = pending, reminder_date <= today)
  Map<int, int> _candidateCounts = {};
  Map<int, int> _candidateNewCounts = {};
  Map<int, int> _candidateOverdueCounts = {};
  Map<int, int> _candidateAttemptedCounts = {};
  Map<String, int> _candidateAttemptedUserCounts = {};

  // UserUid / email -> assigned breakdown for today: {'total': x, 'new': y, 'overdue': z, 'attempted': a, 'leftover': z + a}
  Map<String, Map<String, int>> _assignedUserBreakdown = {};

  // Global user attendance: uid -> true (present) / false (absent / on leave)
  final Map<String, bool> _userPresence = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    await Future.wait([
      _loadUsersAndBranches(),
      _loadCandidateCounts(),
      _loadAssignedBreakdown(),
    ]);
    await _checkAndSyncTodayHistory();
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _checkAndSyncTodayHistory() async {
    if (_assignedUserBreakdown.isEmpty) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('dme_assignment_history')
          .where('assigned_date', isEqualTo: _todayStr)
          .limit(1)
          .get();

      if (snap.docs.isEmpty && _dmeUsers.isNotEmpty) {
        final totalAssigned = _assignedUserBreakdown.values
            .fold(0, (acc, m) => acc + (m['total'] ?? 0));
        if (totalAssigned > 0) {
          final adminEmail = FirebaseAuth.instance.currentUser?.email ?? 'admin';
          await DmeAssignmentService.recordAssignmentHistory(
            dateStr: _todayStr,
            totalAssigned: totalAssigned,
            userCounts: _assignedUserBreakdown,
            branchCounts: _candidateCounts,
            dmeUsers: _dmeUsers,
            userPresence: _userPresence,
            adminEmail: adminEmail,
          );
        }
      }
    } catch (e) {
      debugPrint('Error syncing today history: $e');
    }
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
        branchSet.remove(_jblBranchId);

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
              : (DmeConstants.branches.map((b) => b.id).where((b) => b != _jblBranchId).toList()..sort());
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
    final Map<int, int> newMap = {};
    final Map<int, int> overdueMap = {};
    final Map<int, int> attemptedMap = {};
    final Map<String, int> userAttemptedMap = {};

    try {
      int offset = 0;
      const int pageSize = 1000;
      bool hasMore = true;
      final currentDay = DateTime.tryParse(dateStr) ?? DateTime.now();
      final startOfToday = DateTime(currentDay.year, currentDay.month, currentDay.day);

      while (hasMore) {
        final batch = await client
            .from('dme_reminders')
            .select('id, last_purchase_branch, reminder_date, status, remarks, call_duration, called_by, assigned_to, call_attempts')
            .inFilter('status', ['pending', 'called'])
            .lte('reminder_date', '${dateStr}T23:59:59')
            .range(offset, offset + pageSize - 1);

        final list = batch as List;
        for (var r in list) {
          final bId = int.tryParse(r['last_purchase_branch']?.toString() ?? '');
          if (bId == null || bId == _jblBranchId) continue;

          final status = (r['status'] ?? '').toString().toLowerCase();
          final remarks = (r['remarks'] ?? '').toString().trim();
          final duration = int.tryParse(r['call_duration']?.toString() ?? '') ?? 0;
          final attempts = int.tryParse(r['call_attempts']?.toString() ?? '') ?? 0;
          final calledEmail = r['called_by']?.toString().toLowerCase().trim();
          final prevAssigned = r['assigned_to']?.toString();
          final bool hasAttempt = attempts > 0 || (calledEmail != null && calledEmail.isNotEmpty) || status == 'called' || duration > 0;

          // If called with remarks, it is completed and not a candidate
          if (remarks.isNotEmpty) continue;

          totalMap[bId] = (totalMap[bId] ?? 0) + 1;

          if (hasAttempt) {
            attemptedMap[bId] = (attemptedMap[bId] ?? 0) + 1;
            String? targetUid;
            if (prevAssigned != null && prevAssigned.isNotEmpty) {
              targetUid = prevAssigned;
            } else if (calledEmail != null && calledEmail.isNotEmpty) {
              for (var u in _dmeUsers) {
                final uEmail = (u['email']?.toString() ?? '').toLowerCase().trim();
                final uUid = u['uid']?.toString() ?? '';
                if (uEmail == calledEmail || uUid.toLowerCase() == calledEmail) {
                  targetUid = uUid;
                  break;
                }
              }
            }
            if (targetUid != null) {
              userAttemptedMap[targetUid] = (userAttemptedMap[targetUid] ?? 0) + 1;
            }
          } else {
            final rDateStr = r['reminder_date']?.toString();
            final rDate = rDateStr != null ? DateTime.tryParse(rDateStr) : null;
            bool isOverdue = false;
            if (rDate != null) {
              final rDay = DateTime(rDate.year, rDate.month, rDate.day);
              if (rDay.isBefore(startOfToday)) {
                isOverdue = true;
              }
            }

            if (isOverdue) {
              overdueMap[bId] = (overdueMap[bId] ?? 0) + 1;
            } else {
              newMap[bId] = (newMap[bId] ?? 0) + 1;
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
          _candidateCounts = totalMap;
          _candidateNewCounts = newMap;
          _candidateOverdueCounts = overdueMap;
          _candidateAttemptedCounts = attemptedMap;
          _candidateAttemptedUserCounts = userAttemptedMap;
        });
      }
    } catch (e) {
      debugPrint('Error loading candidate counts: $e');
    }
  }

  Future<void> _loadAssignedBreakdown() async {
    final client = await DmeConfig.getClient();
    if (client == null) return;

    try {
      final res = await client
          .from('dme_reminders')
          .select('assigned_to, last_purchase_branch, is_overdue_leftover, call_attempts, called_by, call_duration, status')
          .eq('assigned_date', _todayStr)
          .inFilter('status', ['pending', 'called']);

      final Map<String, Map<String, int>> map = {};
      for (var r in (res as List)) {
        final bId = int.tryParse(r['last_purchase_branch']?.toString() ?? '');
        if (bId == _jblBranchId) continue;
        final uid = r['assigned_to']?.toString();
        if (uid == null || uid.isEmpty) continue;
        final isLeftover = r['is_overdue_leftover'] == true;
        final attempts = int.tryParse(r['call_attempts']?.toString() ?? '') ?? 0;
        final calledEmail = r['called_by']?.toString().toLowerCase().trim();
        final duration = int.tryParse(r['call_duration']?.toString() ?? '') ?? 0;
        final status = (r['status'] ?? '').toString().toLowerCase();
        final bool hasAttempt = attempts > 0 || (calledEmail != null && calledEmail.isNotEmpty) || status == 'called' || duration > 0;

        final entry = map.putIfAbsent(uid, () => {
          'total': 0,
          'new': 0,
          'overdue': 0,
          'attempted': 0,
          'leftover': 0,
        });
        entry['total'] = (entry['total'] ?? 0) + 1;
        if (hasAttempt) {
          entry['attempted'] = (entry['attempted'] ?? 0) + 1;
          entry['leftover'] = (entry['leftover'] ?? 0) + 1;
        } else if (isLeftover) {
          entry['overdue'] = (entry['overdue'] ?? 0) + 1;
          entry['leftover'] = (entry['leftover'] ?? 0) + 1;
        } else {
          entry['new'] = (entry['new'] ?? 0) + 1;
        }
      }

      if (mounted) {
        setState(() => _assignedUserBreakdown = map);
      }
    } catch (e) {
      debugPrint('Error loading assigned breakdown: $e');
    }
  }

  void _toggleUserAttendance(String uid, bool isPresent) {
    setState(() {
      _userPresence[uid] = isPresent;
    });
  }

  Map<String, Map<String, int>> _calculateUserEstimatedBreakdown() {
    final Map<String, int> overdueCounts = {for (var u in _dmeUsers) (u['uid'] as String): 0};
    final Map<String, int> newCounts = {for (var u in _dmeUsers) (u['uid'] as String): 0};
    final Map<String, int> attemptedCounts = {
      for (var u in _dmeUsers) (u['uid'] as String): (_candidateAttemptedUserCounts[u['uid'] as String] ?? 0)
    };

    for (var bId in _activeBranches) {
      final oCount = _candidateOverdueCounts[bId] ?? 0;
      final nCount = _candidateNewCounts[bId] ?? 0;
      if (oCount == 0 && nCount == 0) continue;

      final presentUsersForBranch = _dmeUsers.where((u) {
        final uid = u['uid'] as String;
        final branches = List<int>.from(u['assigned_branches'] ?? []);
        final isPresent = _userPresence[uid] ?? true;
        return branches.contains(bId) && isPresent;
      }).map((u) => u['uid'] as String).toList();

      if (presentUsersForBranch.isEmpty) continue;

      // 1. Distribute unattempted overdue reminders fairly among present users
      for (int i = 0; i < oCount; i++) {
        final sorted = List<String>.from(presentUsersForBranch)..sort((a, b) {
          return (overdueCounts[a] ?? 0).compareTo(overdueCounts[b] ?? 0);
        });
        final target = sorted.first;
        overdueCounts[target] = (overdueCounts[target] ?? 0) + 1;
      }

      // 2. Distribute new reminders fairly among present users
      for (int i = 0; i < nCount; i++) {
        final sorted = List<String>.from(presentUsersForBranch)..sort((a, b) {
          return (newCounts[a] ?? 0).compareTo(newCounts[b] ?? 0);
        });
        final target = sorted.first;
        newCounts[target] = (newCounts[target] ?? 0) + 1;
      }
    }

    return {
      for (var u in _dmeUsers)
        (u['uid'] as String): {
          'total': (overdueCounts[u['uid']] ?? 0) +
              (newCounts[u['uid']] ?? 0) +
              (attemptedCounts[u['uid']] ?? 0),
          'new': newCounts[u['uid']] ?? 0,
          'overdue': overdueCounts[u['uid']] ?? 0,
          'attempted': attemptedCounts[u['uid']] ?? 0,
          'leftover': (overdueCounts[u['uid']] ?? 0) + (attemptedCounts[u['uid']] ?? 0),
        }
    };
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
    final estimatedBreakdown = _calculateUserEstimatedBreakdown();

    final totalNewToAssign = _candidateNewCounts.values.fold(0, (a, b) => a + b);
    final totalAttemptedToAssign = _candidateAttemptedCounts.values.fold(0, (a, b) => a + b);
    final totalOverdueToAssign = _candidateOverdueCounts.values.fold(0, (a, b) => a + b);

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
        content: SingleChildScrollView(
          child: Column(
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
                '• Total Reminders to Assign: $totalRemindersToAssign\n'
                '• New (Equally Divided): $totalNewToAssign\n'
                '• Overdue (Equally Divided): $totalOverdueToAssign\n'
                '• Attempted (Sticky to Caller): $totalAttemptedToAssign\n'
                '• Present Users: $presentCount\n'
                '• Absent Users (Excluded): $absentCount',
                style: const TextStyle(fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 14),
              const Text(
                'Reminders Each User Will Receive:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _primaryBlue),
              ),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    children: _dmeUsers.map((u) {
                      final uid = u['uid'] as String;
                      final name = u['username'] as String;
                      final isPresent = _userPresence[uid] ?? true;
                      final stats = estimatedBreakdown[uid] ?? {'total': 0, 'new': 0, 'overdue': 0, 'attempted': 0};
                      final count = stats['total'] ?? 0;
                      final newCount = stats['new'] ?? 0;
                      final overdueCount = stats['overdue'] ?? 0;
                      final attemptedCount = stats['attempted'] ?? 0;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                        child: Row(
                          children: [
                            Icon(
                              isPresent ? Icons.check_circle_rounded : Icons.cancel_rounded,
                              size: 16,
                              color: isPresent ? Colors.green : Colors.red,
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
                                    ? _primaryBlue.withValues(alpha: 0.12)
                                    : Colors.grey.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                isPresent
                                    ? '$count ($newCount New • $attemptedCount Att. • $overdueCount OD)'
                                    : '0 (Absent)',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isPresent ? _primaryBlue : Colors.grey[600],
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

      // Record snapshot into assignment history for today
      await DmeAssignmentService.recordAssignmentHistory(
        dateStr: _todayStr,
        totalAssigned: (result['total_assigned'] as num?)?.toInt() ?? 0,
        userCounts: (result['user_counts'] as Map<String, dynamic>?) ?? {},
        branchCounts: _candidateCounts,
        dmeUsers: _dmeUsers,
        userPresence: _userPresence,
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
                const SizedBox(height: 14),
                Container(
                  constraints: const BoxConstraints(maxHeight: 220),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      children: _dmeUsers.where((u) => (_userPresence[u['uid']] ?? true)).map((u) {
                        final uid = u['uid'] as String;
                        final name = u['username'] as String;
                        final userCounts = (result['user_counts'] as Map<String, dynamic>?)?[uid] as Map<String, dynamic>?;
                        final total = userCounts?['total'] ?? _assignedUserBreakdown[uid]?['total'] ?? 0;
                        final n = userCounts?['new'] ?? _assignedUserBreakdown[uid]?['new'] ?? 0;
                        final a = userCounts?['attempted'] ?? _assignedUserBreakdown[uid]?['attempted'] ?? 0;
                        final o = userCounts?['overdue'] ?? _assignedUserBreakdown[uid]?['overdue'] ?? 0;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _primaryBlue.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '$total total',
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _primaryBlue),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '$n New',
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue[800]),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.purple.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '$a Att.',
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.purple.shade700),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.deepOrange.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '$o OD',
                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.deepOrange),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
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
      final adminEmail = FirebaseAuth.instance.currentUser?.email ?? 'admin';
      final unassignedCount = await DmeAssignmentService.undoTodayAssignments(
        dateStr: _todayStr,
        branchIds: _activeBranches,
        adminEmail: adminEmail,
      );

      setState(() {
        _assignedUserBreakdown = {};
      });

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
    final totalNew = _candidateNewCounts.values.fold(0, (a, b) => a + b);
    final totalAttempted = _candidateAttemptedCounts.values.fold(0, (a, b) => a + b);
    final totalOverdue = _candidateOverdueCounts.values.fold(0, (a, b) => a + b);

    final totalAssignedPendingToday =
        _assignedUserBreakdown.values.fold(0, (acc, m) => acc + (m['total'] ?? 0));
    final isAlreadyAssignedToday = totalAssignedPendingToday > 0;

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
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: const [
            Tab(
              icon: Icon(Icons.assignment_ind_rounded, size: 20),
              text: 'Assign & Attendance',
            ),
            Tab(
              icon: Icon(Icons.history_rounded, size: 20),
              text: "Today's History",
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildAssignTab(
                  presentCount: presentCount,
                  absentCount: absentCount,
                  totalPending: totalPending,
                  totalNew: totalNew,
                  totalAttempted: totalAttempted,
                  totalOverdue: totalOverdue,
                  isAlreadyAssignedToday: isAlreadyAssignedToday,
                ),
                _buildHistoryTab(),
              ],
            ),
    );
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
                    Icon(Icons.pie_chart_rounded, size: 20, color: _primaryBlue),
                    SizedBox(width: 8),
                    Text(
                      'Reminders Breakdown',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _primaryBlue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$totalPending Total',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _primaryBlue),
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

  Widget _buildAssignTab({
    required int presentCount,
    required int absentCount,
    required int totalPending,
    required int totalNew,
    required int totalAttempted,
    required int totalOverdue,
    required bool isAlreadyAssignedToday,
  }) {
    return SingleChildScrollView(
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
                  const SizedBox(height: 14),

                  // 2. Three Stats Overview Card (New, Attempted, Overdue)
                  _buildThreeStatsCard(
                    totalNew: totalNew,
                    totalAttempted: totalAttempted,
                    totalOverdue: totalOverdue,
                    totalPending: totalPending,
                  ),
                  const SizedBox(height: 16),

                  // 3. Daily User Attendance Card
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
                          else ...[
                            Builder(
                              builder: (_) {
                                final estimatedBreakdown = _calculateUserEstimatedBreakdown();
                                return ListView.separated(
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

                                    final assignedStats = _assignedUserBreakdown[uid] ?? _assignedUserBreakdown[email];
                                    final bool hasAssigned = isAlreadyAssignedToday &&
                                        assignedStats != null &&
                                        (assignedStats['total'] ?? 0) > 0;
                                    final estStats = estimatedBreakdown[uid] ?? {'total': 0, 'new': 0, 'overdue': 0, 'attempted': 0};

                                    final branches = List<int>.from(user['assigned_branches'] ?? []).where((b) => b != _jblBranchId).toList();
                                    final branchNames = branches.map((b) => DmeConstants.getBranchName(b)).join(', ');

                                    return Container(
                                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          // User Avatar
                                          CircleAvatar(
                                            backgroundColor: isPresent ? _primaryBlue : Colors.grey[400],
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

                                                // Breakdown Chips
                                                if (hasAssigned) ...[
                                                  Wrap(
                                                    spacing: 6,
                                                    runSpacing: 5,
                                                    crossAxisAlignment: WrapCrossAlignment.center,
                                                    children: [
                                                      // Total Assigned
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                                        decoration: BoxDecoration(
                                                          color: Colors.green.shade50,
                                                          borderRadius: BorderRadius.circular(6),
                                                          border: Border.all(color: Colors.green.shade400, width: 1),
                                                        ),
                                                        child: Row(
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: [
                                                            Icon(Icons.check_circle_rounded, size: 12, color: Colors.green.shade800),
                                                            const SizedBox(width: 4),
                                                            Text(
                                                              '${assignedStats['total']} Assigned',
                                                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green.shade900),
                                                            ),
                                                          ],
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
                                                          '${assignedStats['new'] ?? 0} New',
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
                                                          '${assignedStats['attempted'] ?? 0} Att.',
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
                                                          '${assignedStats['overdue'] ?? assignedStats['leftover'] ?? 0} OD',
                                                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.deepOrange.shade900),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ] else if (isPresent) ...[
                                                  Wrap(
                                                    spacing: 6,
                                                    runSpacing: 5,
                                                    crossAxisAlignment: WrapCrossAlignment.center,
                                                    children: [
                                                      // Projected Total
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                                        decoration: BoxDecoration(
                                                          color: Colors.blue.shade50,
                                                          borderRadius: BorderRadius.circular(6),
                                                          border: Border.all(color: _primaryBlue.withValues(alpha: 0.5), width: 1),
                                                        ),
                                                        child: Text(
                                                          '~ ${estStats['total']} reminders',
                                                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _primaryBlue),
                                                        ),
                                                      ),
                                                      // New
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                                        decoration: BoxDecoration(
                                                          color: Colors.blue.shade50,
                                                          borderRadius: BorderRadius.circular(6),
                                                          border: Border.all(color: Colors.blue.shade200, width: 1),
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
                                                          border: Border.all(color: Colors.purple.shade200, width: 1),
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
                                                          border: Border.all(color: Colors.deepOrange.shade200, width: 1),
                                                        ),
                                                        child: Text(
                                                          '${estStats['overdue'] ?? estStats['leftover'] ?? 0} OD',
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
                                                  branchNames.isNotEmpty ? 'Branches: $branchNames' : email,
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
    );
  }

  Widget _buildHistoryTab() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: DmeAssignmentService.streamTodayAssignmentHistory(_todayStr),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Text(
                'Error loading assignment history: ${snapshot.error}',
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: _primaryBlue.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.history_rounded, size: 56, color: Colors.grey[500]),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No Assignment History For Today',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'When you run the reminder assignment for today, each run (the first assignment and any redo runs) is permanently recorded here so you can review original details at any time.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Colors.grey[600], height: 1.4),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: () => _tabController.animateTo(0),
                    icon: const Icon(Icons.assignment_ind_rounded, size: 18),
                    label: const Text('Go to Assign Tab'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryBlue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // Sort runs chronologically: Run 1 first, then Run 2, etc.
        final runs = docs.map((d) => d.data()).toList();
        runs.sort((a, b) {
          final runA = (a['run_number'] as num?)?.toInt() ?? 1;
          final runB = (b['run_number'] as num?)?.toInt() ?? 1;
          return runA.compareTo(runB);
        });

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Header summary banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _primaryBlue.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _primaryBlue.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, size: 18, color: _primaryBlue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Showing ${runs.length} assignment run(s) recorded for today ($_todayStr). First assignment details are preserved even if re-assigned.',
                      style: const TextStyle(fontSize: 12, color: _primaryBlue, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // List of run cards
            ...runs.map((run) => _buildRunHistoryCard(run)),
          ],
        );
      },
    );
  }

  Widget _buildRunHistoryCard(Map<String, dynamic> run) {
    final runNumber = (run['run_number'] as num?)?.toInt() ?? 1;
    final isFirst = runNumber == 1;
    final status = (run['status'] ?? 'active').toString();
    final isActive = status == 'active';
    final totalAssigned = (run['total_assigned'] as num?)?.toInt() ?? 0;
    final assignedBy = (run['assigned_by'] ?? 'admin').toString();

    // Timestamp formatting
    String assignedTimeStr = 'Earlier Today';
    final assignedAt = run['assigned_at'];
    if (assignedAt is Timestamp) {
      final dt = assignedAt.toDate();
      assignedTimeStr = DateFormat('hh:mm a').format(dt);
    }

    String? undoneTimeStr;
    final undoneAt = run['undone_at'];
    if (undoneAt is Timestamp) {
      undoneTimeStr = DateFormat('hh:mm a').format(undoneAt.toDate());
    }
    final undoneBy = run['undone_by']?.toString();

    final userBreakdowns = (run['user_breakdowns'] as List?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList() ??
        [];

    final presentCount = userBreakdowns.where((u) => u['is_present'] == true).length;
    final absentCount = userBreakdowns.where((u) => u['is_present'] == false).length;

    final branchCounts = (run['branch_counts'] as Map?)
            ?.map((k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0)) ??
        <String, int>{};

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: isActive ? 3 : 1.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isActive
              ? Colors.green.withValues(alpha: 0.45)
              : Colors.grey.withValues(alpha: 0.3),
          width: isActive ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Run Header & Status Badge
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: isFirst
                        ? _primaryBlue.withValues(alpha: 0.12)
                        : Colors.purple.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isFirst ? Icons.looks_one_rounded : Icons.history_toggle_off_rounded,
                        size: 16,
                        color: isFirst ? _primaryBlue : Colors.purple,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isFirst ? 'Run 1 • First Assignment' : 'Run $runNumber • Re-assignment',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: isFirst ? _primaryBlue : Colors.purple,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isActive
                        ? Colors.green.withValues(alpha: 0.15)
                        : Colors.deepOrange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isActive
                          ? Colors.green.withValues(alpha: 0.4)
                          : Colors.deepOrange.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isActive ? Icons.check_circle_rounded : Icons.undo_rounded,
                        size: 13,
                        color: isActive ? Colors.green[700] : Colors.deepOrange,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isActive ? 'Active (Current)' : 'Undone / Redone',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isActive ? Colors.green[800] : Colors.deepOrange,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Time and Admin info
            Wrap(
              spacing: 12,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.schedule_rounded, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      'Assigned: $assignedTimeStr',
                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.person_outline_rounded, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      'By: $assignedBy',
                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                    ),
                  ],
                ),
              ],
            ),

            if (!isActive && undoneTimeStr != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.undo_rounded, size: 13, color: Colors.deepOrange),
                  const SizedBox(width: 4),
                  Text(
                    'Undone at $undoneTimeStr ${undoneBy != null ? "by $undoneBy" : ""}',
                    style: const TextStyle(fontSize: 11, color: Colors.deepOrange, fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 12),

            // Summary Metrics Box
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'TOTAL ASSIGNED',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$totalAssigned Reminders',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _primaryBlue),
                        ),
                      ],
                    ),
                  ),
                  Container(width: 1, height: 28, color: Colors.grey.withValues(alpha: 0.3)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'ATTENDANCE',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$presentCount Present • $absentCount Absent',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: absentCount > 0 ? Colors.orange[800] : Colors.green[800],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Branch Breakdown Chips
            if (branchCounts.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: branchCounts.entries.map((e) {
                  final bId = int.tryParse(e.key) ?? 0;
                  final bName = DmeConstants.getBranchName(bId);
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '$bName: ${e.value}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  );
                }).toList(),
              ),
            ],

            const SizedBox(height: 14),
            const Text(
              'User Breakdown in this run:',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            const SizedBox(height: 6),

            // User Breakdown List
            ...userBreakdowns.map((u) {
              final isPresent = u['is_present'] == true;
              final name = (u['name'] ?? 'User').toString();
              final total = (u['total'] as num?)?.toInt() ?? 0;
              final newCount = (u['new'] as num?)?.toInt() ?? 0;
              final leftover = (u['leftover'] as num?)?.toInt() ?? 0;
              final branches = (u['assigned_branches'] as List?)
                      ?.map((b) => int.tryParse(b.toString()) ?? 0)
                      .where((b) => b > 0)
                      .toList() ??
                  <int>[];

              return Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: isPresent
                      ? Colors.white
                      : Colors.red.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isPresent
                        ? Colors.grey.withValues(alpha: 0.2)
                        : Colors.red.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isPresent ? Icons.check_circle_rounded : Icons.cancel_rounded,
                      size: 16,
                      color: isPresent ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              decoration: isPresent ? null : TextDecoration.lineThrough,
                              color: isPresent ? Colors.black87 : Colors.grey[600],
                            ),
                          ),
                          if (branches.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              branches.map((b) => DmeConstants.getBranchName(b)).join(', '),
                              style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (isPresent)
                      Builder(
                        builder: (_) {
                          final overdueCount = (u['overdue'] as num?)?.toInt();
                          final attemptedCount = (u['attempted'] as num?)?.toInt();
                          final String statsText;
                          if (overdueCount != null && attemptedCount != null) {
                            statsText = '$total ($newCount New • $attemptedCount Att. • $overdueCount OD)';
                          } else {
                            statsText = '$total ($newCount New • $leftover Leftover)';
                          }
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _primaryBlue.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              statsText,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: _primaryBlue,
                              ),
                            ),
                          );
                        },
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Absent (0)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[600],
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
