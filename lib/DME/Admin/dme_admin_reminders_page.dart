import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../dme_constants.dart';
import '../dme_config.dart';
import 'dme_admin_reminder_detail_page.dart';

const Color _primaryBlue = Color(0xFF005BAC);
const Color _whatsappGreen = Color(0xFF25D366);
const Color _pendingOrange = Color(0xFFFF9800);

enum AdminReminderViewMode { byBranch, byUser }

class DmeAdminRemindersPage extends StatefulWidget {
  final List<int>? userAssignedBranches;

  const DmeAdminRemindersPage({
    super.key,
    this.userAssignedBranches,
  });

  @override
  State<DmeAdminRemindersPage> createState() => _DmeAdminRemindersPageState();
}

class _DmeAdminRemindersPageState extends State<DmeAdminRemindersPage> {
  bool _isLoading = true;

  AdminReminderViewMode _viewMode = AdminReminderViewMode.byBranch;

  // Branch Mode filters
  int? _selectedBranchId; // null = all branches
  List<int> _assignedBranches = [];
  String _dateFilterOption = 'today'; // 'today', 'all', 'custom'
  DateTimeRange? _customDateRange;
  String _selectedStatusFilter = 'all'; // 'all', 'pending', 'completed'

  // User Mode filters
  List<Map<String, dynamic>> _dmeUsers = [];
  String? _selectedUserUid; // Firestore UID of chosen DME user

  // Quick filter tab in list
  String _activeQuickFilter = 'all'; // 'all', 'called', 'pending', 'whatsapped'
  String _searchQuery = '';

  // Data
  List<Map<String, dynamic>> _reminders = [];

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    setState(() => _isLoading = true);
    await _loadAssignedBranches();
    await _loadDmeUsers();
    await _fetchReminders();
  }

  Future<void> _loadAssignedBranches() async {
    if (widget.userAssignedBranches != null) {
      _assignedBranches = widget.userAssignedBranches!;
    } else {
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
          final data = doc.data();
          final role = data?['role']?.toString();
          if (role == 'dme_user' && data?['assigned_branches'] is List) {
            _assignedBranches = (data!['assigned_branches'] as List)
                .map((e) => int.tryParse(e.toString()) ?? 0)
                .where((e) => e > 0)
                .toList();
          }
        }
      } catch (e) {
        debugPrint('Error loading assigned branches: $e');
      }
    }
  }

  Future<void> _loadDmeUsers() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('role', whereIn: ['dme_user', 'dme_admin'])
          .get();

      List<Map<String, dynamic>> users = [];
      for (var doc in snap.docs) {
        final data = doc.data();
        final uid = doc.id;
        final email = data['email']?.toString() ?? '';
        final username =
            data['username']?.toString() ?? data['name']?.toString() ?? (email.isNotEmpty ? email.split('@').first : 'User');
        final role = data['role']?.toString() ?? 'dme_user';

        List<int> branches = [];
        if (data['assigned_branches'] is List) {
          branches = (data['assigned_branches'] as List)
              .map((e) => int.tryParse(e.toString()) ?? 0)
              .where((e) => e > 0)
              .toList();
        }

        users.add({
          'uid': uid,
          'email': email,
          'username': username,
          'role': role,
          'assigned_branches': branches,
        });
      }

      users.sort((a, b) => (a['username'] as String).toLowerCase().compareTo((b['username'] as String).toLowerCase()));

      _dmeUsers = users;
      if (_selectedUserUid == null && _dmeUsers.isNotEmpty) {
        _selectedUserUid = _dmeUsers.first['uid'];
      }
    } catch (e) {
      debugPrint('Error loading DME users: $e');
    }
  }

  Future<void> _fetchReminders() async {
    final client = await DmeConfig.getClient();
    if (client == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

      // 1. Fetch WhatsApp Proofs to cross-reference WhatsApp completions
      Map<int, Map<String, dynamic>> proofsMap = {};
      try {
        final proofsRes = await client
            .from('dme_whatsapp_proofs')
            .select('id, reminder_id, customer_id, image_url, remarks, created_at, uploaded_by')
            .gte('created_at', '${todayStr}T00:00:00')
            .lte('created_at', '${todayStr}T23:59:59')
            .limit(1000);

        for (var p in (proofsRes as List)) {
          final remId = p['reminder_id'] as int?;
          if (remId != null) {
            proofsMap[remId] = Map<String, dynamic>.from(p);
          }
        }
      } catch (e) {
        debugPrint('Proof fetch note: $e');
      }

      List<Map<String, dynamic>> resultList = [];

      if (_viewMode == AdminReminderViewMode.byUser) {
        // --- BY USER MODE: User's current day's list ---
        final user = _dmeUsers.firstWhere(
          (u) => u['uid'] == _selectedUserUid,
          orElse: () => _dmeUsers.isNotEmpty ? _dmeUsers.first : {},
        );

        if (user.isNotEmpty) {
          final uid = user['uid']?.toString() ?? '';
          final email = (user['email']?.toString() ?? '').toLowerCase();

          // A. Fetch today's reminders assigned to this user
          final assignedQuery = client
              .from('dme_reminders')
              .select(
                  'id, customer_id, reminder_date, last_purchase_date, last_purchase_branch, status, remarks, updated_at, call_duration, called_timestamp, called_by, assigned_to, assigned_date, is_overdue_leftover, dme_customers(id, name, phone, address, salesman)')
              .eq('assigned_to', uid)
              .eq('assigned_date', todayStr);

          final assignedBatch = await assignedQuery.limit(1000);

          // B. Fetch reminders completed by this user today (by called_by email)
          List<dynamic> calledBatch = [];
          if (email.isNotEmpty) {
            try {
              final calledQuery = client
                  .from('dme_reminders')
                  .select(
                      'id, customer_id, reminder_date, last_purchase_date, last_purchase_branch, status, remarks, updated_at, call_duration, called_timestamp, called_by, assigned_to, assigned_date, is_overdue_leftover, dme_customers(id, name, phone, address, salesman)')
                  .ilike('called_by', email)
                  .gte('updated_at', '${todayStr}T00:00:00')
                  .lte('updated_at', '${todayStr}T23:59:59');
              calledBatch = await calledQuery.limit(1000);
            } catch (_) {}
          }

          final Map<int, Map<String, dynamic>> mapById = {};
          for (var item in (assignedBatch as List)) {
            final id = item['id'] as int;
            mapById[id] = Map<String, dynamic>.from(item);
          }
          for (var item in calledBatch) {
            final id = item['id'] as int;
            mapById[id] = Map<String, dynamic>.from(item);
          }

          for (var item in mapById.values) {
            _populateReminderMetadata(item, proofsMap);
            resultList.add(item);
          }

          // Sort: pending leftovers on top, then other pendings, then completed
          resultList.sort((a, b) {
            final statusA = (a['status'] ?? '').toString();
            final statusB = (b['status'] ?? '').toString();
            if (statusA == 'pending' && statusB != 'pending') return -1;
            if (statusA != 'pending' && statusB == 'pending') return 1;

            final leftA = a['is_overdue_leftover'] == true;
            final leftB = b['is_overdue_leftover'] == true;
            if (leftA && !leftB) return -1;
            if (!leftA && leftB) return 1;

            return (a['id'] as int).compareTo(b['id'] as int);
          });
        }
      } else {
        // --- BY BRANCH MODE ---
        var query = client
            .from('dme_reminders')
            .select(
                'id, customer_id, reminder_date, last_purchase_date, last_purchase_branch, status, remarks, updated_at, call_duration, called_timestamp, called_by, assigned_to, assigned_date, is_overdue_leftover, dme_customers(id, name, phone, address, salesman)');

        // Branch filter
        if (_selectedBranchId != null) {
          query = query.eq('last_purchase_branch', _selectedBranchId!);
        } else if (_assignedBranches.isNotEmpty) {
          query = query.inFilter('last_purchase_branch', _assignedBranches);
        }

        // Status filter
        if (_selectedStatusFilter != 'all') {
          query = query.eq('status', _selectedStatusFilter);
        }

        // Date filter
        if (_dateFilterOption == 'today') {
          query = query.or('and(reminder_date.eq.$todayStr),and(assigned_date.eq.$todayStr)');
        } else if (_dateFilterOption == 'custom' && _customDateRange != null) {
          final sStr = DateFormat('yyyy-MM-dd').format(_customDateRange!.start);
          final eStr = DateFormat('yyyy-MM-dd').format(_customDateRange!.end);
          query = query.gte('reminder_date', sStr).lte('reminder_date', eStr);
        }

        final res = await query.order('id', ascending: false).limit(1000);
        for (var item in (res as List)) {
          final rem = Map<String, dynamic>.from(item);
          _populateReminderMetadata(rem, proofsMap);
          resultList.add(rem);
        }
      }

      if (mounted) {
        setState(() {
          _reminders = resultList;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching reminders in admin page: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading reminders: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _populateReminderMetadata(Map<String, dynamic> rem, Map<int, Map<String, dynamic>> proofsMap) {
    final cust = rem['dme_customers'] as Map<String, dynamic>?;
    final bId = int.tryParse(rem['last_purchase_branch']?.toString() ?? '');
    final remId = rem['id'] as int?;

    rem['customer_name'] = cust?['name'] ?? 'Unknown Customer';
    rem['customer_phone'] = cust?['phone'] ?? '';
    rem['customer_address'] = cust?['address'] ?? '';
    rem['customer_salesman'] = cust?['salesman'] ?? '';
    rem['branch_id'] = bId;
    rem['branch_name'] = DmeConstants.getBranchName(bId);

    final remarks = (rem['remarks'] ?? '').toString();
    final hasProof = remId != null && proofsMap.containsKey(remId);
    final isWhatsApp = hasProof || remarks.startsWith('[WhatsApp]');

    rem['is_whatsapp'] = isWhatsApp;
    if (hasProof) {
      rem['proof_url'] = proofsMap[remId]?['image_url'];
    }
  }

  // Summary counts
  int get _totalCount => _reminders.length;
  int get _pendingCount => _reminders.where((r) => (r['status'] ?? '').toString().toLowerCase() == 'pending').length;
  int get _whatsappedCount => _reminders.where((r) => r['is_whatsapp'] == true).length;
  int get _calledCount => _reminders
      .where((r) => (r['status'] ?? '').toString().toLowerCase() == 'completed' && r['is_whatsapp'] != true)
      .length;

  List<Map<String, dynamic>> _getFilteredList() {
    var list = _reminders;

    // Filter tab
    if (_activeQuickFilter == 'pending') {
      list = list.where((r) => (r['status'] ?? '').toString().toLowerCase() == 'pending').toList();
    } else if (_activeQuickFilter == 'called') {
      list = list
          .where((r) => (r['status'] ?? '').toString().toLowerCase() == 'completed' && r['is_whatsapp'] != true)
          .toList();
    } else if (_activeQuickFilter == 'whatsapped') {
      list = list.where((r) => r['is_whatsapp'] == true).toList();
    }

    // Search query
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      list = list.where((r) {
        final name = (r['customer_name'] ?? '').toString().toLowerCase();
        final phone = (r['customer_phone'] ?? '').toString().toLowerCase();
        final salesman = (r['customer_salesman'] ?? '').toString().toLowerCase();
        final remarks = (r['remarks'] ?? '').toString().toLowerCase();
        final branch = (r['branch_name'] ?? '').toString().toLowerCase();
        return name.contains(q) || phone.contains(q) || salesman.contains(q) || remarks.contains(q) || branch.contains(q);
      }).toList();
    }

    return list;
  }

  Future<void> _pickCustomDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2022),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _customDateRange ??
          DateTimeRange(
            start: DateTime.now().subtract(const Duration(days: 7)),
            end: DateTime.now(),
          ),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: _primaryBlue,
              onPrimary: Colors.white,
              onSurface: Colors.black87,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _customDateRange = picked;
        _dateFilterOption = 'custom';
      });
      _fetchReminders();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final filteredList = _getFilteredList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('DME Reminders Management'),
        backgroundColor: _primaryBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _fetchReminders,
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. Controls & Filter Card
          _buildFilterHeaderCard(isDark),

          // 2. Summary Box (when By User is active or in branch view)
          _buildSummaryBox(isDark),

          // 3. Quick Filter Tabs & Search Row
          _buildQuickFilterRow(isDark),

          // 4. Reminders List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredList.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.inbox_rounded, size: 64, color: Colors.grey[400]),
                            const SizedBox(height: 12),
                            Text(
                              'No reminders found for selected criteria.',
                              style: TextStyle(fontSize: 15, color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        itemCount: filteredList.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final item = filteredList[index];
                          return _buildReminderCard(item, isDark);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  // --- FILTER CONTROLS HEADER ---
  Widget _buildFilterHeaderCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Top Selector: View Mode ("By Branch" vs "By User")
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[800] : Colors.grey[100],
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            if (_viewMode != AdminReminderViewMode.byBranch) {
                              setState(() {
                                _viewMode = AdminReminderViewMode.byBranch;
                                _activeQuickFilter = 'all';
                              });
                              _fetchReminders();
                            }
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            decoration: BoxDecoration(
                              color: _viewMode == AdminReminderViewMode.byBranch ? _primaryBlue : Colors.transparent,
                              borderRadius: BorderRadius.circular(9),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              'By Branch',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: _viewMode == AdminReminderViewMode.byBranch
                                    ? Colors.white
                                    : (isDark ? Colors.white70 : Colors.black87),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            if (_viewMode != AdminReminderViewMode.byUser) {
                              setState(() {
                                _viewMode = AdminReminderViewMode.byUser;
                                _activeQuickFilter = 'all';
                              });
                              _fetchReminders();
                            }
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            decoration: BoxDecoration(
                              color: _viewMode == AdminReminderViewMode.byUser ? _primaryBlue : Colors.transparent,
                              borderRadius: BorderRadius.circular(9),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              'By User',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: _viewMode == AdminReminderViewMode.byUser
                                    ? Colors.white
                                    : (isDark ? Colors.white70 : Colors.black87),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Secondary Dropdowns depending on mode
          if (_viewMode == AdminReminderViewMode.byUser) ...[
            // User Dropdown Selector
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade400),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  isExpanded: true,
                  value: _selectedUserUid,
                  hint: const Text('Select DME User', style: TextStyle(fontSize: 13)),
                  items: _dmeUsers.map((u) {
                    return DropdownMenuItem<String?>(
                      value: u['uid'],
                      child: Row(
                        children: [
                          const Icon(Icons.person_pin_rounded, size: 18, color: _primaryBlue),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${u['username']}  (${u['email']})',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null && val != _selectedUserUid) {
                      setState(() {
                        _selectedUserUid = val;
                        _activeQuickFilter = 'all';
                      });
                      _fetchReminders();
                    }
                  },
                ),
              ),
            ),
          ] else ...[
            // Branch Dropdown & Date Interval Selector
            Row(
              children: [
                // Branch Selector
                Expanded(
                  flex: 5,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int?>(
                        isExpanded: true,
                        value: _selectedBranchId,
                        hint: const Text('All Branches', style: TextStyle(fontSize: 12)),
                        items: [
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text('All Branches', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                          ...DmeConstants.branches
                              .where((b) => _assignedBranches.isEmpty || _assignedBranches.contains(b.id))
                              .map(
                                (b) => DropdownMenuItem<int?>(
                                  value: b.id,
                                  child: Text(b.name, style: const TextStyle(fontSize: 12)),
                                ),
                              ),
                        ],
                        onChanged: (val) {
                          setState(() => _selectedBranchId = val);
                          _fetchReminders();
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Date Filter Option
                Expanded(
                  flex: 3,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: _dateFilterOption,
                        items: const [
                          DropdownMenuItem(value: 'today', child: Text('Today', style: TextStyle(fontSize: 12))),
                          DropdownMenuItem(value: 'all', child: Text('All Dates', style: TextStyle(fontSize: 12))),
                          DropdownMenuItem(value: 'custom', child: Text('Range', style: TextStyle(fontSize: 12))),
                        ],
                        onChanged: (val) {
                          if (val == 'custom') {
                            _pickCustomDateRange();
                          } else if (val != null) {
                            setState(() => _dateFilterOption = val);
                            _fetchReminders();
                          }
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Status Filter Option
                Expanded(
                  flex: 3,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: _selectedStatusFilter,
                        items: const [
                          DropdownMenuItem(value: 'all', child: Text('All Status', style: TextStyle(fontSize: 12))),
                          DropdownMenuItem(value: 'pending', child: Text('Pending', style: TextStyle(fontSize: 12))),
                          DropdownMenuItem(value: 'completed', child: Text('Completed', style: TextStyle(fontSize: 12))),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _selectedStatusFilter = val);
                            _fetchReminders();
                          }
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // --- SUMMARY BOX ON TOP ---
  Widget _buildSummaryBox(bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _viewMode == AdminReminderViewMode.byUser
                    ? "User's Current Day Summary"
                    : "Reminders Overview",
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              Text(
                DateFormat('dd MMM yyyy').format(DateTime.now()),
                style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w500),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              // 1. Total Calls
              Expanded(
                child: _buildSummaryMetricItem(
                  label: 'Total Calls',
                  value: '$_totalCount',
                  icon: Icons.assignment_rounded,
                  color: _primaryBlue,
                  isSelected: _activeQuickFilter == 'all',
                  onTap: () => setState(() => _activeQuickFilter = 'all'),
                ),
              ),
              const SizedBox(width: 8),

              // 2. Called
              Expanded(
                child: _buildSummaryMetricItem(
                  label: 'Called',
                  value: '$_calledCount',
                  icon: Icons.phone_callback_rounded,
                  color: const Color(0xFF0E7A38),
                  isSelected: _activeQuickFilter == 'called',
                  onTap: () => setState(() => _activeQuickFilter = 'called'),
                ),
              ),
              const SizedBox(width: 8),

              // 3. Pending
              Expanded(
                child: _buildSummaryMetricItem(
                  label: 'Pending',
                  value: '$_pendingCount',
                  icon: Icons.pending_actions_rounded,
                  color: _pendingOrange,
                  isSelected: _activeQuickFilter == 'pending',
                  onTap: () => setState(() => _activeQuickFilter = 'pending'),
                ),
              ),
              const SizedBox(width: 8),

              // 4. Whatsapped
              Expanded(
                child: _buildSummaryMetricItem(
                  label: 'WhatsApp',
                  value: '$_whatsappedCount',
                  icon: Icons.chat_bubble_rounded,
                  color: _whatsappGreen,
                  isSelected: _activeQuickFilter == 'whatsapped',
                  onTap: () => setState(() => _activeQuickFilter = 'whatsapped'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryMetricItem({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.15) : color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? color : color.withValues(alpha: 0.3),
            width: isSelected ? 1.8 : 1.0,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 10, color: Colors.grey[700], fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // --- SEARCH BAR ROW ---
  Widget _buildQuickFilterRow(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
      child: TextField(
        onChanged: (val) => setState(() => _searchQuery = val),
        decoration: InputDecoration(
          hintText: 'Search customer, phone, remarks, branch...',
          prefixIcon: const Icon(Icons.search, size: 20),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          fillColor: isDark ? Colors.grey[850] : Colors.grey[50],
          filled: true,
        ),
      ),
    );
  }

  // --- SINGLE REMINDER CARD ---
  Widget _buildReminderCard(Map<String, dynamic> item, bool isDark) {
    final status = (item['status'] ?? '').toString().toLowerCase();
    final isCompleted = status == 'completed';
    final isWhatsApp = item['is_whatsapp'] == true;
    final isLeftover = item['is_overdue_leftover'] == true;

    Color statusColor;
    String statusLabel;
    IconData statusIcon;

    if (isCompleted) {
      if (isWhatsApp) {
        statusColor = _whatsappGreen;
        statusLabel = 'WhatsApp';
        statusIcon = Icons.chat_bubble_rounded;
      } else {
        statusColor = const Color(0xFF0E7A38);
        statusLabel = 'Called';
        statusIcon = Icons.phone_callback_rounded;
      }
    } else {
      statusColor = _pendingOrange;
      statusLabel = isLeftover ? 'Leftover Pending' : 'Pending';
      statusIcon = isLeftover ? Icons.warning_amber_rounded : Icons.pending_actions_rounded;
    }

    final remarks = (item['remarks'] ?? '').toString().trim();
    final calledBy = item['called_by']?.toString();
    final duration = item['call_duration'];
    final reminderDateStr = item['reminder_date']?.toString();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => DmeAdminReminderDetailPage(
                reminder: item,
                onUpdated: _fetchReminders,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Row: Name, Status Badge
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item['customer_name'] ?? 'Unknown Customer',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(Icons.phone, size: 13, color: Colors.grey[700]),
                            const SizedBox(width: 4),
                            Text(
                              item['customer_phone'] ?? '',
                              style: TextStyle(fontSize: 13, color: Colors.grey[800], fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Status Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: statusColor.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(statusIcon, size: 12, color: statusColor),
                        const SizedBox(width: 4),
                        Text(
                          statusLabel,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: statusColor),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Metadata info: Branch, Salesman, Scheduled Date
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  // Branch Pill
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _primaryBlue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      item['branch_name'] ?? '',
                      style: const TextStyle(fontSize: 11, color: _primaryBlue, fontWeight: FontWeight.w600),
                    ),
                  ),

                  // Scheduled Date Pill
                  if (reminderDateStr != null && reminderDateStr.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Due: $reminderDateStr',
                        style: TextStyle(fontSize: 11, color: Colors.grey[800]),
                      ),
                    ),
                  ],

                  // Salesman
                  if ((item['customer_salesman'] ?? '').toString().isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.purple.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'SM: ${item['customer_salesman']}',
                        style: const TextStyle(fontSize: 11, color: Colors.purple, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ],
              ),

              // Remarks / Notes Box
              if (remarks.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[800] : Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.notes_rounded, size: 14, color: Colors.grey),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          remarks,
                          style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Called by & Duration (if completed)
              if (isCompleted && (calledBy != null || duration != null)) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (calledBy != null && calledBy.isNotEmpty) ...[
                      Text('Called by: $calledBy', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                      const SizedBox(width: 8),
                    ],
                    if (duration != null) ...[
                      Text('Duration: ${duration}s', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                    ],
                  ],
                ),
              ],

              const SizedBox(height: 10),

              // Tap to view full customer details & history
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'View details & history',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _primaryBlue.withValues(alpha: 0.9),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 11,
                    color: _primaryBlue.withValues(alpha: 0.9),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
