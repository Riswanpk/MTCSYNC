import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../dme_constants.dart';
import '../dme_config.dart';
import '../User/dme_assignment_service.dart';

const Color _primaryBlue = Color(0xFF005BAC);
const Color _primaryGreen = Color(0xFF8CC63F);
const Color _pendingOrange = Color(0xFFFF9800);

class DmeAdminReminderAssignPage extends StatefulWidget {
  const DmeAdminReminderAssignPage({super.key});

  @override
  State<DmeAdminReminderAssignPage> createState() => _DmeAdminReminderAssignPageState();
}

class _DmeAdminReminderAssignPageState extends State<DmeAdminReminderAssignPage> {
  bool _isLoading = true;
  bool _isExecuting = false;

  DateTime _selectedDate = DateTime.now();
  String get _selectedDateStr => DmeAssignmentService.formatDate(_selectedDate);

  List<Map<String, dynamic>> _dmeUsers = [];
  List<int> _activeBranches = [];

  // BranchId -> count of candidate reminders (status = pending, reminder_date <= selectedDate)
  Map<int, int> _candidateCounts = {};
  Map<int, int> _leftoverCounts = {};
  Map<int, int> _todayCounts = {};

  // BranchId -> existing assignment info from reminder_assignment table
  Map<int, Map<String, dynamic>> _assignmentStatus = {};

  // Global user presence: uid -> true (present) / false (on leave)
  final Map<String, bool> _userPresence = {};

  // BranchId -> Set of UIDs selected for this specific branch
  final Map<int, Set<String>> _branchSelectedUsers = {};

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
    _syncUserSelections();
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadUsersAndBranches() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('role', whereIn: ['dme_user', 'dme_admin'])
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

        // Default presence to true (present) if not already explicitly toggled
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

    final dateStr = _selectedDateStr;
    final Map<int, int> totalMap = {};
    final Map<int, int> leftoverMap = {};
    final Map<int, int> todayMap = {};

    try {
      final List<dynamic> allPending = [];
      int offset = 0;
      const int pageSize = 1000;
      bool hasMore = true;

      while (hasMore) {
        final batch = await client
            .from('dme_reminders')
            .select('id, reminder_date, last_purchase_branch')
            .eq('status', 'pending')
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

      final selDay = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);

      for (var r in allPending) {
        final bId = int.tryParse(r['last_purchase_branch']?.toString() ?? '');
        if (bId == null) continue;

        totalMap[bId] = (totalMap[bId] ?? 0) + 1;

        final rDateStr = r['reminder_date']?.toString();
        final rDate = rDateStr != null ? DateTime.tryParse(rDateStr) : null;
        if (rDate != null && DateTime(rDate.year, rDate.month, rDate.day).isBefore(selDay)) {
          leftoverMap[bId] = (leftoverMap[bId] ?? 0) + 1;
        } else {
          todayMap[bId] = (todayMap[bId] ?? 0) + 1;
        }
      }

      if (mounted) {
        setState(() {
          _candidateCounts = totalMap;
          _leftoverCounts = leftoverMap;
          _todayCounts = todayMap;
        });
      }
    } catch (e) {
      debugPrint('Error loading candidate counts: $e');
    }
  }

  Future<void> _loadAssignmentStatus() async {
    final status = await DmeAssignmentService.getBranchAssignmentStatus(dateStr: _selectedDateStr);
    if (mounted) {
      setState(() => _assignmentStatus = status);
    }
  }

  void _syncUserSelections() {
    for (var branchId in _activeBranches) {
      final eligibleUsers = _dmeUsers.where((u) {
        final branches = List<int>.from(u['assigned_branches'] ?? []);
        return branches.contains(branchId);
      }).toList();

      final Set<String> selected = {};
      for (var u in eligibleUsers) {
        final uid = u['uid'] as String;
        // If user is marked present globally, include them
        if (_userPresence[uid] == true) {
          selected.add(uid);
        }
      }
      _branchSelectedUsers[branchId] = selected;
    }
  }

  void _toggleUserPresence(String uid, bool isPresent) {
    setState(() {
      _userPresence[uid] = isPresent;
      // Propagate to all branches
      for (var branchId in _activeBranches) {
        final eligible = _dmeUsers
            .where((u) => u['uid'] == uid && List<int>.from(u['assigned_branches'] ?? []).contains(branchId))
            .isNotEmpty;
        if (eligible) {
          final set = _branchSelectedUsers[branchId] ?? {};
          if (isPresent) {
            set.add(uid);
          } else {
            set.remove(uid);
          }
          _branchSelectedUsers[branchId] = set;
        }
      }
    });
  }

  void _toggleBranchUser(int branchId, String uid, bool selected) {
    setState(() {
      final set = _branchSelectedUsers[branchId] ?? {};
      if (selected) {
        set.add(uid);
      } else {
        set.remove(uid);
      }
      _branchSelectedUsers[branchId] = set;
    });
  }

  Future<void> _executeAssignment() async {
    // 1. Validate that at least one branch has selected users and reminders
    int totalRemindersToAssign = 0;
    final Map<int, List<String>> branchPayload = {};

    for (var bId in _activeBranches) {
      final count = _candidateCounts[bId] ?? 0;
      final selectedUids = _branchSelectedUsers[bId]?.toList() ?? [];

      if (count > 0 && selectedUids.isNotEmpty) {
        totalRemindersToAssign += count;
        branchPayload[bId] = selectedUids;
      }
    }

    if (totalRemindersToAssign == 0 && branchPayload.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No pending reminders or active users selected to assign.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // 2. Confirm modal
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.assignment_turned_in_rounded, color: _primaryBlue),
            const SizedBox(width: 8),
            const Text('Confirm Assignment'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Execute reminder assignment for:'),
            const SizedBox(height: 6),
            Text(
              DateFormat('EEEE, dd MMMM yyyy').format(_selectedDate),
              style: const TextStyle(fontWeight: FontWeight.bold, color: _primaryBlue),
            ),
            const Divider(height: 20),
            Text(
              '• Total Candidate Reminders: $totalRemindersToAssign\n'
              '• Active Branches Involved: ${branchPayload.length}\n'
              '• Users on Leave will receive 0 reminders.',
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
      final adminEmail = FirebaseAuth.instance.currentUser?.email ?? 'admin';

      final result = await DmeAssignmentService.assignRemindersByAdmin(
        dateStr: _selectedDateStr,
        branchToActiveUserUids: branchPayload,
        userUidToName: userUidToName,
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
            padding: const EdgeInsets.all(20.0),
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
                  'Reminders Successfully Assigned!',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                const SizedBox(height: 8),
                Text(
                  'Total ${result['total_assigned']} reminders assigned across ${branchPayload.length} branches for $_selectedDateStr.',
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
      debugPrint('Error assigning reminders: $e');
      setState(() => _isExecuting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error assigning reminders: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final isToday = DateFormat('yyyy-MM-dd').format(DateTime.now()) == _selectedDateStr;

    int totalPendingAcrossBranches = _candidateCounts.values.fold(0, (a, b) => a + b);
    int assignedBranchesCount = _assignmentStatus.keys.where((b) => _activeBranches.contains(b)).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reminder Assignment', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: _primaryBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Reload Details',
            onPressed: _isLoading ? null : _loadAll,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 90),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. Date Header & Assignment Status Card
                      _buildDateAndStatusCard(isDark, isToday, totalPendingAcrossBranches, assignedBranchesCount),
                      const SizedBox(height: 14),

                      // 2. Global Attendance / On-Leave Quick Toggle Card
                      _buildUserPresenceCard(isDark),
                      const SizedBox(height: 16),

                      // 3. Section Title
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Branch Breakdown & Division',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            '${_activeBranches.length} Branches',
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // 4. Branch Cards List
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _activeBranches.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final branchId = _activeBranches[index];
                          return _buildBranchCard(branchId, isDark);
                        },
                      ),
                    ],
                  ),
                ),

                // Sticky Bottom Action Bar
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[900] : Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 10,
                          offset: const Offset(0, -3),
                        ),
                      ],
                    ),
                    child: SafeArea(
                      child: SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: _isExecuting ? null : _executeAssignment,
                          icon: _isExecuting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : const Icon(Icons.send_rounded, size: 20),
                          label: Text(
                            _isExecuting
                                ? 'Assigning Reminders...'
                                : 'Assign Reminders ($totalPendingAcrossBranches Total)',
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
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildDateAndStatusCard(
      bool isDark, bool isToday, int totalPending, int assignedBranches) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _primaryBlue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.event_note_rounded, color: _primaryBlue, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            DateFormat('dd MMMM yyyy').format(_selectedDate),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          if (isToday) ...[
                            const SizedBox(width: 6),
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
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Assignment Date for Daily Partitioning',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _selectedDate,
                      firstDate: DateTime(2022),
                      lastDate: DateTime.now().add(const Duration(days: 30)),
                    );
                    if (picked != null) {
                      setState(() => _selectedDate = picked);
                      _loadAll();
                    }
                  },
                  icon: const Icon(Icons.edit_calendar_rounded, size: 16),
                  label: const Text('Change', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: _primaryBlue,
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem('Total Pending', '$totalPending', Icons.alarm_on_rounded, Colors.blue[700]!),
                _buildStatItem('Assigned Branches', '$assignedBranches/${_activeBranches.length}',
                    Icons.check_circle_outline_rounded, Colors.green[700]!),
                _buildStatItem('Active Users', '${_userPresence.values.where((v) => v).length}/${_dmeUsers.length}',
                    Icons.people_alt_rounded, Colors.purple[700]!),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(
              value,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
        ),
      ],
    );
  }

  Widget _buildUserPresenceCard(bool isDark) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.how_to_reg_rounded, color: _primaryGreen, size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      'Daily User Attendance / Leave',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
                Text(
                  'Uncheck if on leave',
                  style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey[600]),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _dmeUsers.map((user) {
                final uid = user['uid'] as String;
                final name = user['username'] as String;
                final isPresent = _userPresence[uid] ?? true;

                return FilterChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(name),
                      const SizedBox(width: 4),
                      Text(
                        isPresent ? '(Present)' : '(On Leave)',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isPresent ? Colors.green[800] : Colors.red[800],
                        ),
                      ),
                    ],
                  ),
                  selected: isPresent,
                  selectedColor: Colors.green.withValues(alpha: 0.15),
                  checkmarkColor: Colors.green[800],
                  backgroundColor: Colors.red.withValues(alpha: 0.1),
                  avatar: CircleAvatar(
                    backgroundColor: isPresent ? _primaryBlue : Colors.grey,
                    radius: 12,
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : 'U',
                      style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  onSelected: (val) => _toggleUserPresence(uid, val),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBranchCard(int branchId, bool isDark) {
    final branchName = DmeConstants.getBranchName(branchId);
    final totalCandidate = _candidateCounts[branchId] ?? 0;
    final leftoverCount = _leftoverCounts[branchId] ?? 0;
    final todayCount = _todayCounts[branchId] ?? 0;
    final statusInfo = _assignmentStatus[branchId];
    final isAlreadyAssigned = statusInfo != null;

    final eligibleUsers = _dmeUsers.where((u) {
      final branches = List<int>.from(u['assigned_branches'] ?? []);
      return branches.contains(branchId);
    }).toList();

    final selectedUids = _branchSelectedUsers[branchId] ?? {};
    final selectedCount = selectedUids.length;

    String divisionPreview = '';
    if (totalCandidate > 0 && selectedCount > 0) {
      final approx = (totalCandidate / selectedCount).toStringAsFixed(1);
      divisionPreview = '≈ $approx per user ($selectedCount users)';
    } else if (totalCandidate == 0) {
      divisionPreview = 'No pending calls';
    } else {
      divisionPreview = '⚠️ No users selected!';
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Branch Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: _primaryBlue.withValues(alpha: 0.12),
                      child: Text(
                        '$branchId',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _primaryBlue),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          branchName,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        Text(
                          '$totalCandidate pending ($leftoverCount leftovers, $todayCount today)',
                          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isAlreadyAssigned
                        ? Colors.green.withValues(alpha: 0.15)
                        : _pendingOrange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isAlreadyAssigned ? Colors.green.withValues(alpha: 0.5) : _pendingOrange.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    isAlreadyAssigned ? '✓ Assigned' : 'Unassigned',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isAlreadyAssigned ? Colors.green[800] : Colors.orange[900],
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 18),

            // Live Division Preview Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[850] : Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    selectedCount > 0 ? Icons.calculate_outlined : Icons.warning_amber_rounded,
                    size: 16,
                    color: selectedCount > 0 ? _primaryBlue : Colors.orange[800],
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Division: $divisionPreview',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: selectedCount > 0 ? null : Colors.orange[800],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Eligible Users for this Branch
            if (eligibleUsers.isEmpty)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  'No users currently assigned to this branch in User Management.',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600], fontStyle: FontStyle.italic),
                ),
              )
            else ...[
              const Text(
                'Select Active Users for This Branch:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Column(
                children: eligibleUsers.map((u) {
                  final uid = u['uid'] as String;
                  final name = u['username'] as String;
                  final email = u['email'] as String;
                  final isSelected = selectedUids.contains(uid);
                  final isGloballyPresent = _userPresence[uid] ?? true;

                  return CheckboxListTile(
                    value: isSelected,
                    onChanged: (val) => _toggleBranchUser(branchId, uid, val ?? false),
                    title: Row(
                      children: [
                        Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        if (!isGloballyPresent) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('Leave', style: TextStyle(fontSize: 9, color: Colors.red, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ],
                    ),
                    subtitle: Text(email, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    activeColor: _primaryBlue,
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
