import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../dme_constants.dart';
import '../dme_config.dart';
import 'dme_reminder_detail_page.dart';

class DmeRemindersPage extends StatefulWidget {
  const DmeRemindersPage({super.key});

  @override
  State<DmeRemindersPage> createState() => _DmeRemindersPageState();
}

class _DmeRemindersPageState extends State<DmeRemindersPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  String _searchQuery = '';

  List<Map<String, dynamic>> _todayReminders = [];
  List<Map<String, dynamic>> _overdueReminders = [];
  List<Map<String, dynamic>> _completedReminders = [];

  List<int> _userAssignedBranches = [];
  int? _selectedBranchId; // null means 'All Assigned Branches'

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
    setState(() => _isLoading = true);
    await _loadUserBranches();
    setState(() => _isLoading = false);
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
        _selectedBranchId = null; // Do not auto-select or auto-load
      }
    } catch (e) {
      debugPrint('Error loading assigned branches: $e');
    }
  }

  Future<void> _fetchRemindersForBranch(int branchId) async {
    final client = await DmeConfig.getClient();
    if (client == null) return;

    setState(() => _isLoading = true);

    try {
      // Query reminders specifically for the selected branch
      var query = client
          .from('dme_reminders')
          .select('id, customer_id, reminder_date, last_purchase_date, last_purchase_branch, status, remarks, updated_at, dme_customers(id, name, phone, address, salesman)')
          .eq('last_purchase_branch', branchId);

      final response = await query;
      final List data = response as List;

      final now = DateTime.now();
      final currentDay = DateTime(now.year, now.month, now.day);

      List<Map<String, dynamic>> today = [];
      List<Map<String, dynamic>> overdue = [];
      List<Map<String, dynamic>> completed = [];

      for (var item in data) {
        final reminder = Map<String, dynamic>.from(item);
        final cust = reminder['dme_customers'] as Map<String, dynamic>?;

        reminder['customer_name'] = cust?['name'] ?? 'Unknown Customer';
        reminder['customer_phone'] = cust?['phone'] ?? '';
        reminder['customer_address'] = cust?['address'] ?? '';
        reminder['customer_salesman'] = cust?['salesman'] ?? '';
        reminder['branch_id'] = branchId;
        reminder['branch_name'] = DmeConstants.getBranchName(branchId);

        final reminderDateStr = reminder['reminder_date']?.toString() ?? '';
        final status = (reminder['status'] ?? 'pending').toString().toLowerCase();
        final parsedDate = DateTime.tryParse(reminderDateStr);

        if (status == 'completed' || status == 'called') {
          completed.add(reminder);
        } else if (parsedDate != null) {
          final reminderDay = DateTime(parsedDate.year, parsedDate.month, parsedDate.day);

          if (reminderDay.isBefore(currentDay)) {
            overdue.add(reminder);
          } else if (reminderDay.isAtSameMomentAs(currentDay)) {
            today.add(reminder);
          }
          // Future dates (reminderDay.isAfter(currentDay)) are excluded from Today & Overdue
        }
      }

      setState(() {
        _todayReminders = today;
        _overdueReminders = overdue;
        _completedReminders = completed;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching reminders: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading reminders: $e'), backgroundColor: Colors.red),
        );
      }
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
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DmeReminderDetailPage(
          reminder: reminder,
          onUpdated: () {
            if (_selectedBranchId != null) {
              _fetchRemindersForBranch(_selectedBranchId!);
            }
          },
        ),
      ),
    );

    if (result == true && _selectedBranchId != null) {
      _fetchRemindersForBranch(_selectedBranchId!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('DME Call Reminders'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF8CC63F),
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            Tab(text: 'Today (${_todayReminders.length})'),
            Tab(text: 'Overdue (${_overdueReminders.length})'),
            Tab(text: 'Completed (${_completedReminders.length})'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Branch Selection Dropdown (Required selection)
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
                      hint: const Text('Select an assigned branch...', style: TextStyle(fontSize: 13, color: Colors.grey)),
                      isExpanded: true,
                      icon: const Icon(Icons.arrow_drop_down_circle_outlined, size: 20),
                      items: _userAssignedBranches.map((bId) {
                        return DropdownMenuItem<int?>(
                          value: bId,
                          child: Text(
                            DmeConstants.getBranchName(bId),
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _selectedBranchId = val;
                          });
                          _fetchRemindersForBranch(val);
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Search Box
          if (_selectedBranchId != null)
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search customer name, mobile...',
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
            child: _selectedBranchId == null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.storefront_outlined, size: 56, color: Colors.grey[400]),
                        const SizedBox(height: 12),
                        Text(
                          'Please select a branch from the dropdown above',
                          style: TextStyle(fontSize: 14, color: Colors.grey[600], fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  )
                : (_isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildReminderList(_todayReminders, isToday: true),
                          _buildReminderList(_overdueReminders, isOverdue: true),
                          _buildReminderList(_completedReminders, isCompleted: true),
                        ],
                      )),
          ),
        ],
      ),
    );
  }

  Widget _buildReminderList(List<Map<String, dynamic>> list, {bool isToday = false, bool isOverdue = false, bool isCompleted = false}) {
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
                      : Icons.alarm_on_rounded,
              size: 48,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 12),
            Text(
              isCompleted
                  ? 'No completed calls yet.'
                  : isOverdue
                      ? 'Great job! No overdue reminders.'
                      : 'No calls scheduled for today.',
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        if (_selectedBranchId != null) {
          await _fetchRemindersForBranch(_selectedBranchId!);
        }
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

          return Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                      backgroundColor: isCompleted
                          ? Colors.green.withValues(alpha: 0.15)
                          : isOverdue
                              ? Colors.red.withValues(alpha: 0.15)
                              : const Color(0xFF005BAC).withValues(alpha: 0.15),
                      foregroundColor: isCompleted
                          ? Colors.green
                          : isOverdue
                              ? Colors.red
                              : const Color(0xFF005BAC),
                      child: Icon(
                        isCompleted
                            ? Icons.check_rounded
                            : isOverdue
                                ? Icons.warning_amber_rounded
                                : Icons.phone_forwarded_rounded,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item['customer_name'] ?? 'Customer',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF005BAC).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  item['branch_name'] ?? 'Branch',
                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF005BAC)),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Mobile: $phone',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                          if ((item['customer_address'] ?? '').toString().isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              item['customer_address'],
                              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.calendar_today, size: 12, color: isOverdue ? Colors.red : Colors.grey),
                              const SizedBox(width: 4),
                              Text(
                                'Due: ${_formatDate(dateStr)}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: isOverdue ? Colors.red : Colors.grey[700],
                                ),
                              ),
                            ],
                          ),
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
