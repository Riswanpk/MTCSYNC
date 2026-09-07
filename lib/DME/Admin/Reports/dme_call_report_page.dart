import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../../dme_constants.dart';
import '../../dme_config.dart';
import 'dme_call_report_models.dart';
import 'dme_user_call_detail_page.dart';

const Color _primaryBlue = Color(0xFF005BAC);
const Color _whatsappGreen = Color(0xFF25D366);

class DmeCallReportPage extends StatefulWidget {
  final List<int>? userAssignedBranches;

  const DmeCallReportPage({super.key, this.userAssignedBranches});

  @override
  State<DmeCallReportPage> createState() => _DmeCallReportPageState();
}

class _DmeCallReportPageState extends State<DmeCallReportPage> {
  DateTime _startDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _endDate = DateTime.now();

  int? _selectedBranchId; // null = 'All Branches'
  List<int> _allowedBranches = [];

  bool _isLoading = false;
  String _searchQuery = '';

  List<DmeUserCallStat> _userStats = [];

  // Aggregated Summary
  int _grandTotalCalls = 0;
  int _grandTotalWhatsApp = 0;
  int _grandTotalActions = 0;

  @override
  void initState() {
    super.initState();
    _initBranchAccess();
  }

  Future<void> _initBranchAccess() async {
    if (widget.userAssignedBranches != null) {
      _allowedBranches = widget.userAssignedBranches!;
    } else {
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
          if (!mounted) return;
          final data = doc.data();
          final role = data?['role']?.toString();
          if (role == 'dme_user' && data?['assigned_branches'] is List) {
            _allowedBranches = (data!['assigned_branches'] as List)
                .map((e) => int.tryParse(e.toString()) ?? 0)
                .where((e) => e > 0)
                .toList();
          }
        }
      } catch (e) {
        debugPrint('Error loading user assigned branches: $e');
      }
    }
    if (!mounted) return;
    _fetchCallReportData();
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
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
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _fetchCallReportData();
    }
  }

  Future<void> _fetchCallReportData() async {
    final client = await DmeConfig.getClient();
    if (client == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Supabase is not configured.')),
        );
      }
      return;
    }

    setState(() => _isLoading = true);

    try {
      final startStr = DateFormat('yyyy-MM-dd').format(_startDate);
      final endStr = DateFormat('yyyy-MM-dd').format(_endDate);

      // 1. Fetch DME Users from Firestore
      final usersSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('role', whereIn: ['dme_user', 'dme_admin'])
          .get();

      final List<Map<String, dynamic>> rawUsers = [];
      for (var doc in usersSnap.docs) {
        final data = doc.data();
        final uid = doc.id;
        final email = (data['email'] ?? '').toString().trim().toLowerCase();
        final username = (data['username'] ?? data['name'] ?? email.split('@').first).toString().trim();
        final role = (data['role'] ?? 'dme_user').toString();

        List<int> branches = [];
        if (data['assigned_branches'] is List) {
          branches = (data['assigned_branches'] as List)
              .map((e) => int.tryParse(e.toString()) ?? 0)
              .where((e) => e > 0)
              .toList();
        }

        // If filtering by branch, only include users who have access to this branch or have no restriction
        if (_selectedBranchId != null && branches.isNotEmpty && !branches.contains(_selectedBranchId)) {
          continue;
        }

        rawUsers.add({
          'uid': uid,
          'email': email,
          'username': username.isNotEmpty ? username : (email.isNotEmpty ? email.split('@').first : 'User'),
          'role': role,
          'assigned_branches': branches,
        });
      }

      // 2. Fetch completed reminders in date range
      var remindersQuery = client
          .from('dme_reminders')
          .select('id, customer_id, reminder_date, last_purchase_branch, status, remarks, updated_at, dme_customers(id, name, phone, address, salesman)')
          .inFilter('status', ['completed', 'called'])
          .gte('updated_at', '${startStr}T00:00:00')
          .lte('updated_at', '${endStr}T23:59:59');

      if (_selectedBranchId != null) {
        remindersQuery = remindersQuery.eq('last_purchase_branch', _selectedBranchId!);
      } else if (_allowedBranches.isNotEmpty) {
        remindersQuery = remindersQuery.inFilter('last_purchase_branch', _allowedBranches);
      }

      final remRes = await remindersQuery;
      final List<dynamic> remList = remRes as List<dynamic>;

      // 3. Fetch WhatsApp Proofs in date range
      var proofsQuery = client
          .from('dme_whatsapp_proofs')
          .select('id, reminder_id, customer_id, image_url, remarks, created_at, uploaded_by')
          .gte('created_at', '${startStr}T00:00:00')
          .lte('created_at', '${endStr}T23:59:59');

      final List<dynamic> proofsList = [];
      try {
        final pRes = await proofsQuery;
        proofsList.addAll(pRes as List<dynamic>);
      } catch (e) {
        debugPrint('dme_whatsapp_proofs query note: $e');
      }

      final Map<int, Map<String, dynamic>> reminderProofMap = {};
      final Map<String, List<Map<String, dynamic>>> userProofsMap = {};

      for (var p in proofsList) {
        final remId = p['reminder_id'] as int?;
        final uEmail = (p['uploaded_by'] ?? '').toString().trim().toLowerCase();
        if (remId != null) {
          reminderProofMap[remId] = Map<String, dynamic>.from(p);
        }
        if (uEmail.isNotEmpty) {
          userProofsMap.putIfAbsent(uEmail, () => []).add(Map<String, dynamic>.from(p));
        }
      }

      // 4. Convert reminders into Customer Call Items
      final List<DmeCustomerCallItem> allCallItems = [];

      for (var r in remList) {
        final remId = r['id'] as int;
        final custId = r['customer_id'] as int? ?? 0;
        final bId = r['last_purchase_branch'] as int? ?? 0;
        final branchName = DmeConstants.getBranchName(bId);
        final status = (r['status'] ?? 'completed').toString();
        final remarks = (r['remarks'] ?? '').toString().trim();
        final updatedAtStr = (r['updated_at'] ?? r['reminder_date'])?.toString() ?? '';
        final completedAt = DateTime.tryParse(updatedAtStr) ?? DateTime.now();

        final cust = r['dme_customers'] as Map<String, dynamic>?;
        final custName = (cust?['name'] ?? 'Unknown Customer').toString();
        final custPhone = (cust?['phone'] ?? '').toString();
        final custAddr = (cust?['address'] ?? '').toString();
        final custSalesman = (cust?['salesman'] ?? '').toString();

        final hasProof = reminderProofMap.containsKey(remId);
        final bool isWhatsApp = hasProof || remarks.startsWith('[WhatsApp]');
        final proofObj = reminderProofMap[remId];
        final uploadedBy = proofObj?['uploaded_by']?.toString().toLowerCase();
        final proofUrl = proofObj?['image_url']?.toString();

        String cleanRemarks = remarks;
        if (cleanRemarks.startsWith('[WhatsApp]')) {
          cleanRemarks = cleanRemarks.replaceFirst('[WhatsApp]', '').trim();
        }
        if (cleanRemarks.isEmpty && proofObj?['remarks'] != null) {
          cleanRemarks = proofObj!['remarks'].toString();
        }

        allCallItems.add(DmeCustomerCallItem(
          reminderId: remId,
          customerId: custId,
          customerName: custName,
          customerPhone: custPhone,
          customerAddress: custAddr,
          customerSalesman: custSalesman,
          branchId: bId,
          branchName: branchName,
          status: status,
          remarks: cleanRemarks,
          isWhatsApp: isWhatsApp,
          completedAt: completedAt,
          uploadedBy: uploadedBy,
          proofImageUrl: proofUrl,
        ));
      }

      // 5. Associate Call Items with DME Users
      final List<DmeUserCallStat> userStatsList = [];
      int grandCalls = 0;
      int grandWhatsApp = 0;

      // Also create an 'Unassigned / General' category if some branch calls don't map to a specific user
      final Set<int> attributedReminderIds = {};

      for (var u in rawUsers) {
        final email = u['email'] as String;
        final branches = u['assigned_branches'] as List<int>;

        final List<DmeCustomerCallItem> matchedItems = [];

        for (var item in allCallItems) {
          bool isMatch = false;

          // Match by explicit uploaded_by email
          if (item.uploadedBy != null && item.uploadedBy == email) {
            isMatch = true;
          }
          // Match by branch assignment
          else if (branches.contains(item.branchId)) {
            isMatch = true;
          }

          if (isMatch) {
            matchedItems.add(item);
            attributedReminderIds.add(item.reminderId);
          }
        }

        userStatsList.add(DmeUserCallStat(
          uid: u['uid'] as String,
          email: email,
          username: u['username'] as String,
          role: u['role'] as String,
          assignedBranches: branches,
          callItems: matchedItems,
        ));
      }

      // If there are actions not attributed to any specific user, create a Branch Activity entry
      final unattributedItems = allCallItems.where((i) => !attributedReminderIds.contains(i.reminderId)).toList();
      if (unattributedItems.isNotEmpty) {
        userStatsList.add(DmeUserCallStat(
          uid: 'branch_system',
          email: 'system@dme.local',
          username: 'Other Branch Activities',
          role: 'dme_user',
          assignedBranches: unattributedItems.map((i) => i.branchId).toSet().toList(),
          callItems: unattributedItems,
        ));
      }

      // Sort users by highest total actions first
      userStatsList.sort((a, b) => b.totalActions.compareTo(a.totalActions));

      for (var item in allCallItems) {
        if (item.isWhatsApp) {
          grandWhatsApp++;
        } else {
          grandCalls++;
        }
      }

      if (mounted) {
        setState(() {
          _userStats = userStatsList;
          _grandTotalCalls = grandCalls;
          _grandTotalWhatsApp = grandWhatsApp;
          _grandTotalActions = allCallItems.length;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching call report data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading Call Report: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  List<DmeUserCallStat> _getFilteredUsers() {
    if (_searchQuery.trim().isEmpty) return _userStats;
    final q = _searchQuery.trim().toLowerCase();
    return _userStats.where((u) {
      return u.username.toLowerCase().contains(q) ||
          u.email.toLowerCase().contains(q) ||
          u.assignedBranches.any((b) => DmeConstants.getBranchName(b).toLowerCase().contains(q));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final filteredUsers = _getFilteredUsers();

    return Scaffold(
      appBar: AppBar(
        title: const Text('DME Call Report'),
        backgroundColor: _primaryBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Call Stats',
            onPressed: _isLoading ? null : _fetchCallReportData,
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Header: Date Range & Branch Selection
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[900] : Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    // Date Interval Selector
                    Expanded(
                      flex: 3,
                      child: InkWell(
                        onTap: _pickDateRange,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade400),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.date_range, size: 18, color: _primaryBlue),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${DateFormat('dd-MM-yy').format(_startDate)} to ${DateFormat('dd-MM-yy').format(_endDate)}',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Branch Selector Dropdown
                    Expanded(
                      flex: 2,
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
                                  .where((b) => _allowedBranches.isEmpty || _allowedBranches.contains(b.id))
                                  .map(
                                    (b) => DropdownMenuItem<int?>(
                                      value: b.id,
                                      child: Text(b.name, style: const TextStyle(fontSize: 12)),
                                    ),
                                  ),
                            ],
                            onChanged: (val) {
                              setState(() => _selectedBranchId = val);
                              _fetchCallReportData();
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Search Bar for Users
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Search DME user by name, email, branch...',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    filled: true,
                    fillColor: isDark ? Colors.grey[850] : Colors.grey[100],
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val),
                ),
              ],
            ),
          ),

          // KPI Summary Cards Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            color: _primaryBlue.withValues(alpha: 0.05),
            child: Row(
              children: [
                _buildKpiCard('Total Calls', '$_grandTotalCalls', Icons.phone_in_talk_rounded, Colors.blue[800]!),
                const SizedBox(width: 8),
                _buildKpiCard('WhatsApp', '$_grandTotalWhatsApp', Icons.chat_bubble_rounded, const Color(0xFF0E7A38)),
                const SizedBox(width: 8),
                _buildKpiCard('Total Actions', '$_grandTotalActions', Icons.task_alt_rounded, _primaryBlue),
              ],
            ),
          ),

          // User Call Stats List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredUsers.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.person_search_rounded, size: 48, color: Colors.grey[400]),
                            const SizedBox(height: 8),
                            Text(
                              'No DME user activity found for this period.',
                              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: filteredUsers.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, idx) {
                          final userStat = filteredUsers[idx];
                          return _buildUserStatCard(context, userStat);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 4),
                Text(
                  value,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              title,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserStatCard(BuildContext context, DmeUserCallStat userStat) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => DmeUserCallDetailPage(
                userStat: userStat,
                startDate: _startDate,
                endDate: _endDate,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // User info row
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: _primaryBlue.withValues(alpha: 0.12),
                    foregroundColor: _primaryBlue,
                    child: Text(
                      userStat.username.isNotEmpty ? userStat.username[0].toUpperCase() : 'U',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          userStat.username,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        Text(
                          userStat.email,
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.grey),
                ],
              ),

              // Assigned Branches Tags
              if (userStat.assignedBranches.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: userStat.assignedBranches.map((bId) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        DmeConstants.getBranchName(bId),
                        style: TextStyle(fontSize: 10, color: Colors.grey[800], fontWeight: FontWeight.w600),
                      ),
                    );
                  }).toList(),
                ),
              ],

              const Divider(height: 20),

              // Statistics Counters (Calls, WhatsApp, Total)
              Row(
                children: [
                  // Calls count
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.phone_in_talk_rounded, size: 14, color: _primaryBlue),
                          const SizedBox(width: 4),
                          Text(
                            'Calls: ${userStat.totalCalls}',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _primaryBlue),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // WhatsApp count
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                      decoration: BoxDecoration(
                        color: _whatsappGreen.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.chat_bubble_rounded, size: 14, color: Color(0xFF1EBE5D)),
                          const SizedBox(width: 4),
                          Text(
                            'WhatsApp: ${userStat.totalWhatsApp}',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0E7A38)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Total
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                    decoration: BoxDecoration(
                      color: _primaryBlue.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: _primaryBlue.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      'Total: ${userStat.totalActions}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: _primaryBlue),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Footer: Active Days list hint
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    userStat.activeDays.isEmpty
                        ? 'No activity in this period'
                        : 'Active Days: ${userStat.activeDays.join(', ')} (${userStat.activeDays.length} days)',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w500),
                  ),
                  Text(
                    'Tap to view day tabs →',
                    style: TextStyle(fontSize: 11, color: _primaryBlue, fontWeight: FontWeight.bold),
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
