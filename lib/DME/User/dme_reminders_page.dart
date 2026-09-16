import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../dme_constants.dart';
import '../dme_config.dart';
import 'dme_reminder_detail_page.dart';
import 'dme_assignment_service.dart';
import 'dme_remarks_pending_page.dart';

class DmeRemindersPage extends StatefulWidget {
  const DmeRemindersPage({super.key});

  @override
  State<DmeRemindersPage> createState() => _DmeRemindersPageState();
}

class _DmeRemindersPageState extends State<DmeRemindersPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  bool _isAssignedByAdminToday = false;
  String _searchQuery = '';
  bool _filterOnlyMultipleAttempts = true;

  List<Map<String, dynamic>> _todayReminders = [];
  List<Map<String, dynamic>> _completedReminders = [];

  List<int> _userAssignedBranches = [];
  int? _selectedBranchId; // null means 'All Assigned Branches'

  final Map<String, String> _userIdentifierToName = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (mounted) setState(() => _isLoading = true);
    await _loadUserNames();
    await _loadUserBranches();
    await _fetchUserReminders();
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadUserNames() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('users').get();
      for (var doc in snap.docs) {
        final data = doc.data();
        final uid = doc.id;
        final email = data['email']?.toString() ?? '';
        final username = data['username']?.toString() ??
            data['name']?.toString() ??
            (email.isNotEmpty ? email.split('@').first : 'User');
        _userIdentifierToName[uid] = username;
        if (email.isNotEmpty) {
          _userIdentifierToName[email] = username;
          _userIdentifierToName[email.toLowerCase()] = username;
        }
      }
    } catch (e) {
      debugPrint('Error loading user names: $e');
    }
  }

  String _getUserDisplayName(String? userIdentifier) {
    if (userIdentifier == null) return '';
    final raw = userIdentifier.trim();
    if (raw.isEmpty) return '';
    if (_userIdentifierToName.containsKey(raw)) {
      return _userIdentifierToName[raw]!;
    }
    if (_userIdentifierToName.containsKey(raw.toLowerCase())) {
      return _userIdentifierToName[raw.toLowerCase()]!;
    }
    if (raw.contains('@')) {
      final prefix = raw.split('@').first;
      if (prefix.isNotEmpty) {
        return prefix[0].toUpperCase() + prefix.substring(1);
      }
      return prefix;
    }
    return raw;
  }

  Future<void> _loadUserBranches() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists && doc.data()?['assigned_branches'] is List) {
        final branches = (doc.data()!['assigned_branches'] as List)
            .map((e) => int.tryParse(e.toString()) ?? 0)
            .where((e) => e > 0)
            .toList();

        _userAssignedBranches = branches;
        _selectedBranchId = null; // Default to all assigned branches
      }
    } catch (e) {
      debugPrint('Error loading assigned branches: $e');
    }
  }

  Future<void> _fetchUserReminders() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _userAssignedBranches.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final isAssigned = await DmeAssignmentService.hasAdminAssignedToday(
        userBranches: _userAssignedBranches,
        todayStr: todayStr,
      );

      if (!isAssigned) {
        if (mounted) {
          setState(() {
            _isAssignedByAdminToday = false;
            _todayReminders = [];
            _completedReminders = [];
            _isLoading = false;
          });
        }
        return;
      }

      // 1. Fetch today's assigned reminders (with yesterday's leftovers sorted on top)
      final assignedToday = await DmeAssignmentService.fetchUserAssignedReminders(
        userBranches: _userAssignedBranches,
        currentUserId: user.uid,
        filterBranchId: _selectedBranchId,
      );

      // 2. Fetch completed reminders for today
      final completed = await DmeAssignmentService.fetchUserCompletedToday(
        userBranches: _userAssignedBranches,
        currentUserId: user.uid,
        filterBranchId: _selectedBranchId,
      );

      // 3. Fetch pending phone change requests to lock/grey out affected reminders
      Set<int> pendingPhoneCustomerIds = {};
      Set<int> pendingPhoneReminderIds = {};
      try {
        final client = await DmeConfig.getClient();
        if (client != null) {
          final pendingRes = await client
              .from('dme_change_requests')
              .select('customer_id, reminder_id')
              .eq('request_type', 'phone_number_change')
              .eq('status', 'pending');
          for (var row in (pendingRes as List)) {
            final cId = int.tryParse(row['customer_id']?.toString() ?? '');
            if (cId != null) pendingPhoneCustomerIds.add(cId);
            final rId = int.tryParse(row['reminder_id']?.toString() ?? '');
            if (rId != null) pendingPhoneReminderIds.add(rId);
          }
        }
      } catch (_) {}

      for (var r in assignedToday) {
        final cId = int.tryParse(r['customer_id']?.toString() ?? '');
        final rId = int.tryParse(r['id']?.toString() ?? '');
        r['is_phone_change_pending'] = (cId != null && pendingPhoneCustomerIds.contains(cId)) ||
            (rId != null && pendingPhoneReminderIds.contains(rId));
      }

      for (var r in completed) {
        final cId = int.tryParse(r['customer_id']?.toString() ?? '');
        final rId = int.tryParse(r['id']?.toString() ?? '');
        r['is_phone_change_pending'] = (cId != null && pendingPhoneCustomerIds.contains(cId)) ||
            (rId != null && pendingPhoneReminderIds.contains(rId));
      }

      if (mounted) {
        setState(() {
          _isAssignedByAdminToday = true;
          _todayReminders = assignedToday;
          _completedReminders = completed;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching user reminders: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatDate(dynamic date) {
    if (date == null) return 'N/A';
    if (date is DateTime) {
      return DateFormat('dd-MM-yyyy').format(date);
    }
    final str = date.toString().trim();
    if (str.isEmpty) return 'N/A';
    final parsed = DateTime.tryParse(str);
    if (parsed != null) {
      return DateFormat('dd-MM-yyyy').format(parsed);
    }
    return str;
  }

  void _openReminderDetail(Map<String, dynamic> reminder) async {
    if (reminder['is_phone_change_pending'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This reminder is locked because a phone number change request is pending admin approval.',
          ),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DmeReminderDetailPage(
          reminder: reminder,
          onUpdated: () {
            _fetchUserReminders();
          },
        ),
      ),
    );

    if (result == true) {
      _fetchUserReminders();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final leftoverCount = _todayReminders.where((r) => r['is_overdue_leftover'] == true).length;
    final pendingRemarksCount = _todayReminders.where((r) {
      final remarks = (r['remarks'] ?? '').toString().trim();
      final status = (r['status'] ?? '').toString().toLowerCase();
      final duration = int.tryParse(r['call_duration']?.toString() ?? '') ?? 0;
      return duration > 10 && remarks.isEmpty && status != 'completed';
    }).length;

    // Filter customers who were called today but haven't picked up yet
    final notPickedUpReminders = _todayReminders.where((r) {
      final status = (r['status'] ?? '').toString().toLowerCase();
      final attempts = int.tryParse((r['today_call_attempts'] ?? r['call_attempts'])?.toString() ?? '') ?? 0;
      final duration = int.tryParse(r['call_duration']?.toString() ?? '') ?? 0;
      return status != 'completed' && duration <= 10 && attempts >= 1;
    }).toList();

    final multipleAttemptsReminders = notPickedUpReminders.where((r) {
      final attempts = int.tryParse((r['today_call_attempts'] ?? r['call_attempts'])?.toString() ?? '') ?? 0;
      return attempts >= 2;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('DME Call Reminders'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Badge.count(
              count: pendingRemarksCount,
              isLabelVisible: pendingRemarksCount > 0,
              backgroundColor: Colors.orange.shade700,
              child: const Icon(Icons.rate_review_outlined),
            ),
            tooltip: pendingRemarksCount > 0
                ? 'Remarks Pending ($pendingRemarksCount)'
                : 'Remarks Pending List',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const DmeRemarksPendingPage(),
                ),
              ).then((_) => _fetchUserReminders());
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _loadData,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF8CC63F),
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(text: 'Today (${_todayReminders.length})'),
            Tab(text: 'Not Picked Up (${multipleAttemptsReminders.length})'),
            Tab(text: 'Completed (${_completedReminders.length})'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Branch Selection Dropdown (Optional Filter)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[850] : const Color(0xFF005BAC).withValues(alpha: 0.06),
              border: Border(bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.2))),
            ),
            child: Row(
              children: [
                const Icon(Icons.storefront_rounded, size: 22, color: Color(0xFF005BAC)),
                const SizedBox(width: 8),
                const Text('Branch:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int?>(
                      value: _selectedBranchId,
                      hint: const Text('All Assigned Branches', style: TextStyle(fontSize: 13)),
                      isExpanded: true,
                      icon: const Icon(Icons.arrow_drop_down_circle_outlined, size: 20),
                      items: [
                        DropdownMenuItem<int?>(
                          value: null,
                          child: Text(
                            'All Assigned Branches (${_userAssignedBranches.length} branches)',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF005BAC)),
                          ),
                        ),
                        ..._userAssignedBranches.map((bId) {
                          return DropdownMenuItem<int?>(
                            value: bId,
                            child: Text(
                              DmeConstants.getBranchName(bId),
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                          );
                        }),
                      ],
                      onChanged: (val) {
                        setState(() {
                          _selectedBranchId = val;
                        });
                        _fetchUserReminders();
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Daily Target Summary Ribbon
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[900] : const Color(0xFF005BAC).withValues(alpha: 0.04),
              border: Border(bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.15))),
            ),
            child: Row(
              children: [
                const Icon(Icons.assignment_turned_in_outlined, size: 18, color: Color(0xFF005BAC)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _selectedBranchId == null
                        ? 'Your Target: ${_todayReminders.length} calls today'
                        : 'Your Target for ${DmeConstants.getBranchName(_selectedBranchId)}: ${_todayReminders.length} calls',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
                if (leftoverCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.deepOrange,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$leftoverCount Yesterday Overdue',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),

          // Search Box
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search customer name, mobile, branch...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: isDark ? Colors.grey[900] : Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
            ),
          ),

          // Body Views
          Expanded(
            child: _userAssignedBranches.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.person_off_outlined, size: 56, color: Colors.grey[400]),
                        const SizedBox(height: 12),
                        Text(
                          'No branches are currently assigned to your account.',
                          style: TextStyle(fontSize: 14, color: Colors.grey[600], fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Please contact an administrator to assign branches.',
                          style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  )
                : (_isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : (!_isAssignedByAdminToday
                        ? _buildAwaitingAdminAssignmentView(isDark)
                        : TabBarView(
                            controller: _tabController,
                            children: [
                              _buildReminderList(_todayReminders, isToday: true),
                              _buildNotPickedUpView(isDark, multipleAttemptsReminders, notPickedUpReminders),
                              _buildReminderList(_completedReminders, isCompleted: true),
                            ],
                          ))),
          ),
        ],
      ),
    );
  }

  Widget _buildAwaitingAdminAssignmentView(bool isDark) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.schedule_send_rounded,
                size: 64,
                color: Colors.orange,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              "Today's Reminders Not Assigned Yet",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              "DME Admin has not performed the daily reminder division for today yet. Only after the admin assigns everyday will your reminders be displayed here.",
              style: TextStyle(fontSize: 13, color: Colors.grey[600], height: 1.4),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh_rounded, size: 20),
              label: const Text('Check Again / Refresh', style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF005BAC),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }



  Widget _buildNotPickedUpView(
    bool isDark,
    List<Map<String, dynamic>> multiAttempts,
    List<Map<String, dynamic>> allUnpicked,
  ) {
    final list = _filterOnlyMultipleAttempts ? multiAttempts : allUnpicked;

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: isDark ? Colors.grey[850] : Colors.orange.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.orange.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ChoiceChip(
                        label: Text('Called Multiple Times (${multiAttempts.length})'),
                        selected: _filterOnlyMultipleAttempts,
                        selectedColor: Colors.orange.withValues(alpha: 0.3),
                        labelStyle: TextStyle(
                          fontSize: 12,
                          fontWeight: _filterOnlyMultipleAttempts ? FontWeight.bold : FontWeight.normal,
                          color: _filterOnlyMultipleAttempts ? Colors.orange[900] : (isDark ? Colors.white70 : Colors.black87),
                        ),
                        onSelected: (val) {
                          if (val) setState(() => _filterOnlyMultipleAttempts = true);
                        },
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: Text('All Unanswered (${allUnpicked.length})'),
                        selected: !_filterOnlyMultipleAttempts,
                        selectedColor: const Color(0xFF005BAC).withValues(alpha: 0.2),
                        labelStyle: TextStyle(
                          fontSize: 12,
                          fontWeight: !_filterOnlyMultipleAttempts ? FontWeight.bold : FontWeight.normal,
                          color: !_filterOnlyMultipleAttempts ? const Color(0xFF005BAC) : (isDark ? Colors.white70 : Colors.black87),
                        ),
                        onSelected: (val) {
                          if (val) setState(() => _filterOnlyMultipleAttempts = false);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _buildReminderList(list, isToday: true, isNotPickedUpTab: true),
        ),
      ],
    );
  }

  Widget _buildReminderList(
    List<Map<String, dynamic>> list, {
    bool isToday = false,
    bool isOverdue = false,
    bool isCompleted = false,
    bool isNotPickedUpTab = false,
  }) {
    final filtered = list.where((item) {
      if (_searchQuery.isEmpty) return true;
      final name = (item['customer_name'] ?? '').toString().toLowerCase();
      final phone = (item['customer_phone'] ?? '').toString().toLowerCase();
      final branch = (item['branch_name'] ?? '').toString().toLowerCase();
      return name.contains(_searchQuery) || phone.contains(_searchQuery) || branch.contains(_searchQuery);
    }).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isCompleted
                  ? Icons.check_circle_outline_rounded
                  : isOverdue
                      ? Icons.event_busy_rounded
                      : isNotPickedUpTab
                          ? Icons.phone_missed_rounded
                          : Icons.alarm_on_rounded,
              size: 48,
              color: isNotPickedUpTab ? Colors.orange[400] : Colors.grey[400],
            ),
            const SizedBox(height: 12),
            Text(
              isCompleted
                  ? 'No calls completed today.'
                  : isOverdue
                      ? 'Great job! No overdue reminders.'
                      : isNotPickedUpTab
                          ? (_filterOnlyMultipleAttempts
                              ? 'No customers with multiple unanswered calls.'
                              : 'No customers with unanswered calls today.')
                          : 'No calls scheduled for today.',
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
          ],
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return RefreshIndicator(
      onRefresh: () async {
        await _fetchUserReminders();
      },
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: filtered.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final item = filtered[index];
          final phone = item['customer_phone'] ?? '';
          final dateStr = item['reminder_date']?.toString() ?? '';
          final remarks = item['remarks']?.toString();
          final status = (item['status'] ?? '').toString().toLowerCase();
          final isLeftover = item['is_overdue_leftover'] == true;
          final callDuration = item['call_duration'] as int?;
          final calledBy = item['called_by']?.toString();
          final attempts = int.tryParse(item['call_attempts']?.toString() ?? '') ?? 0;
          final todayAtt = int.tryParse((item['today_call_attempts'] ?? item['call_attempts'])?.toString() ?? '') ?? 0;
          final isPhonePending = item['is_phone_change_pending'] == true;
          final bool isCalledWithoutRemarks =
              !isPhonePending &&
              (status == 'called' || (callDuration != null && callDuration > 10)) &&
              (remarks == null || remarks.trim().isEmpty);

          return Card(
            elevation: isPhonePending ? 1 : (isLeftover || isCalledWithoutRemarks ? 3 : 2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: isPhonePending
                  ? BorderSide(color: Colors.grey.shade400, width: 1.2)
                  : (isCalledWithoutRemarks
                      ? const BorderSide(color: Color(0xFFF59E0B), width: 1.8)
                      : (isLeftover
                          ? const BorderSide(color: Colors.deepOrange, width: 1.5)
                          : BorderSide.none)),
            ),
            color: isPhonePending
                ? (isDark ? const Color(0xFF262626) : const Color(0xFFF3F4F6))
                : (isCalledWithoutRemarks
                    ? (isDark ? const Color(0xFF332B12) : const Color(0xFFFFFBEB))
                    : (isLeftover
                        ? (isDark ? const Color(0xFF38201B) : const Color(0xFFFFF6ED))
                        : null)),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _openReminderDetail(item),
              child: Padding(
                padding: const EdgeInsets.all(14.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: isPhonePending
                          ? Colors.grey.withValues(alpha: 0.2)
                          : (isCompleted
                              ? Colors.green.withValues(alpha: 0.15)
                              : isCalledWithoutRemarks
                                  ? Colors.amber.withValues(alpha: 0.2)
                                  : isLeftover
                                      ? Colors.deepOrange.withValues(alpha: 0.2)
                                      : isOverdue
                                          ? Colors.red.withValues(alpha: 0.15)
                                          : (attempts >= 2 && (callDuration == null || callDuration == 0)
                                              ? Colors.orange.withValues(alpha: 0.2)
                                              : const Color(0xFF005BAC).withValues(alpha: 0.15))),
                      foregroundColor: isPhonePending
                          ? Colors.grey[600]
                          : (isCompleted
                              ? Colors.green
                              : isCalledWithoutRemarks
                                  ? Colors.amber[900]
                                  : isLeftover
                                      ? Colors.deepOrange
                                      : isOverdue
                                          ? Colors.red
                                          : (attempts >= 2 && (callDuration == null || callDuration == 0)
                                              ? Colors.orange[800]
                                              : const Color(0xFF005BAC))),
                      child: Icon(
                        isPhonePending
                            ? Icons.phonelink_lock_rounded
                            : (isCompleted
                                ? Icons.check_rounded
                                : isCalledWithoutRemarks
                                    ? Icons.rate_review_rounded
                                    : isLeftover
                                        ? Icons.history_toggle_off_rounded
                                        : isOverdue
                                            ? Icons.warning_amber_rounded
                                            : (attempts >= 2 && (callDuration == null || callDuration == 0)
                                                ? Icons.phone_missed_rounded
                                                : Icons.phone_forwarded_rounded)),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // First Row: ONLY Customer Name (uninterrupted full width)
                          Text(
                            item['customer_name'] ?? 'Customer',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: isPhonePending
                                  ? (isDark ? Colors.white60 : Colors.grey[700])
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 6),

                          // Badges row if any
                          if (isPhonePending ||
                              isCalledWithoutRemarks ||
                              isLeftover ||
                              ((callDuration == null || callDuration == 0) && (todayAtt > 0 || (attempts > todayAtt && attempts > 0)))) ...[
                            Wrap(
                              spacing: 4,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                if (isPhonePending) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade600,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.lock_clock_rounded, size: 11, color: Colors.white),
                                        SizedBox(width: 2),
                                        Text(
                                          "PHONE CHANGE PENDING",
                                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                                        ),
                                      ],
                                    ),
                                  ),
                                ] else if (isCalledWithoutRemarks) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.shade800,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.edit_note_rounded, size: 11, color: Colors.white),
                                        SizedBox(width: 2),
                                        Text(
                                          "REMARKS NEEDED",
                                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                                        ),
                                      ],
                                    ),
                                  ),
                                ] else if (isLeftover) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.deepOrange,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.priority_high_rounded, size: 11, color: Colors.white),
                                        Text(
                                          "OVERDUE",
                                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                if (callDuration == null || callDuration == 0) ...[
                                  if (todayAtt >= 2) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.red.shade800,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.block_rounded, size: 10, color: Colors.white),
                                          SizedBox(width: 2),
                                          Text(
                                            "2/2 CALLS TODAY",
                                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ] else if (todayAtt == 1) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.amber.shade800,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        "1/2 CALL TODAY",
                                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                                      ),
                                    ),
                                  ],
                                  if (attempts > todayAtt && attempts > 0) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade700,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        "$attempts TOTAL",
                                        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                                      ),
                                    ),
                                  ],
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                          ],

                          // Mobile Number
                          Text(
                            'Mobile: $phone',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isLeftover
                                        ? Icons.history_rounded
                                        : (isOverdue ? Icons.warning_amber_rounded : Icons.calendar_today),
                                    size: 12,
                                    color: isLeftover
                                        ? Colors.deepOrange
                                        : (isOverdue ? Colors.red : Colors.grey),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    isLeftover
                                        ? 'Due: ${_formatDate(dateStr)} (Yesterday\'s Overdue)'
                                        : 'Due: ${_formatDate(dateStr)}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: isLeftover
                                          ? Colors.deepOrange[800]
                                          : (isOverdue ? Colors.red : Colors.grey[700]),
                                    ),
                                  ),
                                ],
                              ),
                              if (callDuration != null && callDuration > 10) ...[
                                Text(
                                  attempts > 0
                                      ? '• Call: ${callDuration}s (Attempt #$attempts)'
                                      : '• Call: ${callDuration}s',
                                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                ),
                              ] else if (attempts > 0) ...[
                                Text(
                                  '• $attempts call${attempts > 1 ? 's' : ''} attempted (Unanswered)',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.orange[800]),
                                ),
                              ],
                            ],
                          ),
                          if (calledBy != null && calledBy.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.person_pin_rounded, size: 12, color: Colors.green),
                                const SizedBox(width: 4),
                                Text(
                                  'Called by: ${_getUserDisplayName(calledBy)}',
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.green),
                                ),
                              ],
                            ),
                          ],
                          if (remarks != null && remarks.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.grey.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Note: $remarks',
                                style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey[800]),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
