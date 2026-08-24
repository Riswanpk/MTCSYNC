import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

import '../dme_constants.dart';
import '../dme_config.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class DmeAdminDashboardPage extends StatefulWidget {
  final List<int>? userAssignedBranches;

  const DmeAdminDashboardPage({
    super.key,
    this.userAssignedBranches,
  });

  @override
  State<DmeAdminDashboardPage> createState() => _DmeAdminDashboardPageState();
}

class _DmeAdminDashboardPageState extends State<DmeAdminDashboardPage> {
  bool _isLoading = true;

  // Date Filter Range
  late DateTime _startDate;
  late DateTime _endDate;
  int? _selectedBranchId; // null = all allowed branches
  List<int> _assignedBranches = [];

  // Summary Metrics
  int _uniqueCustomersVisited = 0;
  int _newCustomersCreated = 0;
  int _completedRemindersCount = 0;

  // Distribution Data
  Map<int, int> _salesByBranch = {};
  Map<int, int> _salesByCategory = {};
  Map<int, int> _salesByType = {};

  SupabaseClient? get _supabaseClient {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, 1);
    _endDate = DateTime(now.year, now.month, now.day);
    _initBranchAccess();
  }

  Future<void> _initBranchAccess() async {
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
        debugPrint('Error loading user assigned branches in dashboard: $e');
      }
    }

    if (_assignedBranches.length == 1) {
      _selectedBranchId = _assignedBranches.first;
    }

    await _loadDashboardData();
  }

  String _formatDate(DateTime date) {
    return DateFormat('dd-MM-yyyy').format(date);
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF005BAC),
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
      _loadDashboardData();
    }
  }

  Future<void> _loadDashboardData() async {
    final client = _supabaseClient;
    if (client == null || !DmeConfig.isConfigured) {
      setState(() => _isLoading = false);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final startStr = DateFormat('yyyy-MM-dd').format(_startDate);
      final endStr = DateFormat('yyyy-MM-dd').format(_endDate);

      // 1. Fetch ALL Sales in Date Range (Paginated to bypass 1000-row limit)
      List<dynamic> allSales = [];
      int salesOffset = 0;
      const int pageSize = 1000;
      bool hasMoreSales = true;

      while (hasMoreSales) {
        var query = client
            .from('dme_sales')
            .select('id, date, customer_id, purchased_branch, category_id, customer_type_id')
            .gte('date', startStr)
            .lte('date', endStr);

        if (_selectedBranchId != null) {
          query = query.eq('purchased_branch', _selectedBranchId!);
        } else if (_assignedBranches.isNotEmpty) {
          query = query.inFilter('purchased_branch', _assignedBranches);
        }

        final batch = await query.range(salesOffset, salesOffset + pageSize - 1);
        final list = batch as List;
        allSales.addAll(list);
        if (list.length < pageSize) {
          hasMoreSales = false;
        } else {
          salesOffset += pageSize;
        }
      }

      // 2. Fetch ALL Customers created in date range (Paginated)
      final startIso = DateTime(_startDate.year, _startDate.month, _startDate.day, 0, 0, 0).toIso8601String();
      final endIso = DateTime(_endDate.year, _endDate.month, _endDate.day, 23, 59, 59, 999).toIso8601String();

      List<dynamic> allCreatedCusts = [];
      int custOffset = 0;
      bool hasMoreCusts = true;

      while (hasMoreCusts) {
        var custQuery = client
            .from('dme_customers')
            .select('id, created_at, dme_customer_branches(branch_id)')
            .gte('created_at', startIso)
            .lte('created_at', endIso);

        final batch = await custQuery.range(custOffset, custOffset + pageSize - 1);
        final list = batch as List;
        allCreatedCusts.addAll(list);
        if (list.length < pageSize) {
          hasMoreCusts = false;
        } else {
          custOffset += pageSize;
        }
      }

      int newCustomersCount = 0;
      if (_selectedBranchId != null) {
        for (var c in allCreatedCusts) {
          final bList = c['dme_customer_branches'] as List?;
          if (bList != null && bList.any((b) => b['branch_id'] == _selectedBranchId)) {
            newCustomersCount++;
          }
        }
      } else {
        newCustomersCount = allCreatedCusts.length;
      }

      // 3. Fetch ALL Completed Call Reminders in Date Range (Paginated)
      List<dynamic> allReminders = [];
      int remOffset = 0;
      bool hasMoreRem = true;

      while (hasMoreRem) {
        var remindersQuery = client
            .from('dme_reminders')
            .select('id, status, updated_at')
            .eq('status', 'completed')
            .gte('updated_at', '${startStr}T00:00:00')
            .lte('updated_at', '${endStr}T23:59:59');

        if (_selectedBranchId != null) {
          remindersQuery = remindersQuery.eq('last_purchase_branch', _selectedBranchId!);
        } else if (_assignedBranches.isNotEmpty) {
          remindersQuery = remindersQuery.inFilter('last_purchase_branch', _assignedBranches);
        }

        final batch = await remindersQuery.range(remOffset, remOffset + pageSize - 1);
        final list = batch as List;
        allReminders.addAll(list);
        if (list.length < pageSize) {
          hasMoreRem = false;
        } else {
          remOffset += pageSize;
        }
      }

      // Process Aggregations: Customers Visited (Unique customer_ids with purchases in date range)
      final Set<int> uniqueCustIds = {};
      final Map<int, int> branchSales = {};
      final Map<int, int> catSales = {};
      final Map<int, int> typeSales = {};

      for (var s in allSales) {
        final custId = s['customer_id'] as int?;
        if (custId != null) {
          uniqueCustIds.add(custId);
        }

        final bId = s['purchased_branch'] as int?;
        if (bId != null) branchSales[bId] = (branchSales[bId] ?? 0) + 1;

        final catId = s['category_id'] as int?;
        if (catId != null) catSales[catId] = (catSales[catId] ?? 0) + 1;

        final tId = s['customer_type_id'] as int?;
        if (tId != null) typeSales[tId] = (typeSales[tId] ?? 0) + 1;
      }

      // If category or type are not recorded directly on sales, aggregate from customer branches in chunks
      if (catSales.isEmpty || typeSales.isEmpty) {
        if (uniqueCustIds.isNotEmpty) {
          final custIdList = uniqueCustIds.toList();
          // Chunk requests by 500
          for (int i = 0; i < custIdList.length; i += 500) {
            final chunk = custIdList.sublist(i, (i + 500 > custIdList.length) ? custIdList.length : i + 500);
            final custBranchRes = await client
                .from('dme_customer_branches')
                .select('category_id, customer_type_id, branch_id')
                .inFilter('customer_id', chunk);

            for (var cb in (custBranchRes as List)) {
              if (_selectedBranchId != null && cb['branch_id'] != _selectedBranchId) continue;
              final catId = cb['category_id'] as int?;
              final tId = cb['customer_type_id'] as int?;
              if (catId != null) catSales[catId] = (catSales[catId] ?? 0) + 1;
              if (tId != null) typeSales[tId] = (typeSales[tId] ?? 0) + 1;
            }
          }
        }
      }

      setState(() {
        _uniqueCustomersVisited = uniqueCustIds.length;
        _newCustomersCreated = newCustomersCount;
        _completedRemindersCount = allReminders.length;

        _salesByBranch = branchSales;
        _salesByCategory = catSales;
        _salesByType = typeSales;

        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading dashboard analytics: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading dashboard data: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('DME Analytics Dashboard', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Reload Data',
            onPressed: _loadDashboardData,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Date & Branch Filter Card
            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.tune_rounded, color: Color(0xFF005BAC), size: 20),
                            SizedBox(width: 6),
                            Text('Dashboard Filters', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          ],
                        ),
                        InkWell(
                          onTap: _pickDateRange,
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF005BAC).withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFF005BAC).withValues(alpha: 0.2)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.calendar_month_rounded, size: 16, color: Color(0xFF005BAC)),
                                const SizedBox(width: 6),
                                Text(
                                  '${_formatDate(_startDate)} - ${_formatDate(_endDate)}',
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF005BAC)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Branch Selector (Displays only Branch Name)
                    Row(
                      children: [
                        const Icon(Icons.storefront_rounded, size: 20, color: Colors.grey),
                        const SizedBox(width: 8),
                        const Text('Branch:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.grey[850] : Colors.grey[100],
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<int?>(
                                value: _selectedBranchId,
                                isExpanded: true,
                                items: [
                                  DropdownMenuItem<int?>(
                                    value: null,
                                    child: Text(_assignedBranches.isNotEmpty ? 'All Assigned Branches' : 'All Branches (National)'),
                                  ),
                                  ...(_assignedBranches.isNotEmpty
                                          ? DmeConstants.branches.where((b) => _assignedBranches.contains(b.id))
                                          : DmeConstants.branches)
                                      .map((b) {
                                    return DropdownMenuItem<int?>(value: b.id, child: Text(b.name));
                                  }),
                                ],
                                onChanged: (val) {
                                  setState(() => _selectedBranchId = val);
                                  _loadDashboardData();
                                },
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(40.0),
                  child: CircularProgressIndicator(),
                ),
              )
            else ...[
              // 2. Metric KPI Cards (Row of 3)
              Row(
                children: [
                  Expanded(
                    child: _buildMetricTile(
                      title: 'Visited',
                      value: '$_uniqueCustomersVisited',
                      subtitle: 'Parties in period',
                      icon: Icons.people_alt_rounded,
                      color: const Color(0xFF005BAC),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildMetricTile(
                      title: 'New Added',
                      value: '$_newCustomersCreated',
                      subtitle: 'Created in period',
                      icon: Icons.person_add_alt_1_rounded,
                      color: const Color(0xFF8CC63F),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildMetricTile(
                      title: 'Completed',
                      value: '$_completedRemindersCount',
                      subtitle: 'Calls verified',
                      icon: Icons.phone_callback_rounded,
                      color: Colors.orange,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // 3. Branch Distribution Breakdown (When National/All Branches is selected)
              if (_selectedBranchId == null && _salesByBranch.isNotEmpty) ...[
                Card(
                  elevation: 3,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(18.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Branch Distribution', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 16),
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _salesByBranch.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, idx) {
                            final entry = _salesByBranch.entries.toList()[idx];
                            final branchName = DmeConstants.getBranchName(entry.key);
                            final count = entry.value;
                            final total = _salesByBranch.values.fold<int>(0, (acc, v) => acc + v);
                            final percent = total > 0 ? (count / total) : 0.0;

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(branchName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                    Text('$count (${(percent * 100).toStringAsFixed(0)}%)', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: percent,
                                    minHeight: 8,
                                    backgroundColor: Colors.grey[200],
                                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF005BAC)),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // 4. Category Breakdown Distribution
              Card(
                elevation: 3,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(18.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Category Distribution', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      if (_salesByCategory.isEmpty)
                        const Center(child: Text('No category data in this period', style: TextStyle(color: Colors.grey)))
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _salesByCategory.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, idx) {
                            final entry = _salesByCategory.entries.toList()[idx];
                            final catName = DmeConstants.getCategoryName(entry.key);
                            final count = entry.value;
                            final total = _salesByCategory.values.fold<int>(0, (acc, v) => acc + v);
                            final percent = total > 0 ? (count / total) : 0.0;

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(catName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                    Text('$count (${(percent * 100).toStringAsFixed(0)}%)', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: percent,
                                    minHeight: 8,
                                    backgroundColor: Colors.grey[200],
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      idx % 2 == 0 ? const Color(0xFF005BAC) : const Color(0xFF8CC63F),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // 5. Customer Types Breakdown
              Card(
                elevation: 3,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(18.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Customer Type Distribution', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      if (_salesByType.isEmpty)
                        const Center(child: Text('No customer type data in this period', style: TextStyle(color: Colors.grey)))
                      else
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: _salesByType.entries.map((entry) {
                            final typeName = DmeConstants.getCustomerTypeName(entry.key);
                            final count = entry.value;
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.grey[850] : Colors.grey[100],
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircleAvatar(
                                    radius: 6,
                                    backgroundColor: const Color(0xFF8CC63F),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '$typeName: ',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                  Text(
                                    '$count',
                                    style: TextStyle(color: Colors.grey[700], fontSize: 13),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMetricTile({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    title,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                CircleAvatar(
                  radius: 11,
                  backgroundColor: color.withValues(alpha: 0.15),
                  child: Icon(icon, color: color, size: 13),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(fontSize: 9, color: Colors.grey[600]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
