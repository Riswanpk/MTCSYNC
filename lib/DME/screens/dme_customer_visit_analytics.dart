import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/dme_supabase_service.dart';

class DmeCustomerVisitAnalyticsPage extends StatefulWidget {
  const DmeCustomerVisitAnalyticsPage({super.key});

  @override
  State<DmeCustomerVisitAnalyticsPage> createState() =>
      _DmeCustomerVisitAnalyticsPageState();
}

class _DmeCustomerVisitAnalyticsPageState
    extends State<DmeCustomerVisitAnalyticsPage> {
  final _svc = DmeSupabaseService.instance;

  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  DateTime _to = DateTime.now();
  List<Map<String, dynamic>> _branches = [];
  List<int> _selectedBranchIds = [];
  Map<String, dynamic> _analyticsData = {};
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadBranches();
    _loadAnalytics();
  }

  Future<void> _loadBranches() async {
    try {
      final branches = await _svc.getBranches();
      if (mounted) {
        setState(() {
          _branches = branches;
          // Pre-select all branches
          _selectedBranchIds =
              branches.map((b) => b['id'] as int).toList();
        });
      }
    } catch (e) {
      debugPrint('Error loading branches: $e');
    }
  }

  Future<void> _loadAnalytics() async {
    setState(() => _loading = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final user = uid != null ? await _svc.getCurrentUser(uid) : null;
      
      // Use selected branches, or user's branches if not admin
      List<int>? branchIds = _selectedBranchIds.isNotEmpty
          ? _selectedBranchIds
          : (user != null && !user.isAdmin)
              ? await _svc.getUserBranchIds(user.id)
              : null;

      final data = await _svc.getCustomerVisitAnalytics(
        from: _from,
        to: _to,
        branchIds: branchIds?.isNotEmpty == true ? branchIds : null,
      );

      if (mounted) {
        setState(() {
          _analyticsData = data;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading analytics: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _from, end: _to),
    );
    if (picked != null) {
      setState(() {
        _from = picked.start;
        _to = picked.end;
      });
      _loadAnalytics();
    }
  }

  Future<void> _showBranchSelector() async {
    final result = await showDialog<List<int>>(
      context: context,
      builder: (context) => _BranchSelectorDialog(
        branches: _branches,
        selectedBranchIds: _selectedBranchIds,
      ),
    );
    
    if (result != null) {
      setState(() => _selectedBranchIds = result);
      _loadAnalytics();
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd MMM yy');
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer Visit Analytics'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.date_range),
            tooltip: 'Date Range',
            onPressed: _pickDateRange,
          ),
          IconButton(
            icon: const Icon(Icons.location_on),
            tooltip: 'Select Branches',
            onPressed: _showBranchSelector,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAnalytics,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAnalytics,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Date range display
                  Card(
                    color: isDark ? const Color(0xFF1A2332) : Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Period',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white54 : Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${dateFmt.format(_from)} — ${dateFmt.format(_to)}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Branch display
                  Card(
                    color: isDark ? const Color(0xFF1A2332) : Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Branches Selected',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white54 : Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _selectedBranchIds.isEmpty
                                ? [
                                    Text(
                                      'All Branches',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: isDark
                                            ? Colors.white70
                                            : Colors.black87,
                                      ),
                                    ),
                                  ]
                                : _selectedBranchIds.map((branchId) {
                                    final branch = _branches.firstWhere(
                                      (b) => b['id'] == branchId,
                                      orElse: () => {'name': 'Unknown'},
                                    );
                                    return Chip(
                                      label: Text(branch['name'] ?? 'Unknown'),
                                      backgroundColor:
                                          const Color(0xFF005BAC).withValues(
                                        alpha: 0.2,
                                      ),
                                      labelStyle: const TextStyle(
                                        color: Color(0xFF005BAC),
                                      ),
                                    );
                                  }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Analytics Cards
                  Row(
                    children: [
                      Expanded(
                        child: Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          color: isDark ? const Color(0xFF1A2332) : Colors.white,
                          elevation: isDark ? 0 : 2,
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Total Customers Visited',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color:
                                        isDark ? Colors.white54 : Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  '${_analyticsData['total_visits'] ?? 0}',
                                  style: const TextStyle(
                                    fontSize: 36,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF005BAC),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.people,
                                      size: 16,
                                      color: isDark
                                          ? Colors.white54
                                          : Colors.grey,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Unique customers',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isDark
                                            ? Colors.white54
                                            : Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          color: isDark ? const Color(0xFF1A2332) : Colors.white,
                          elevation: isDark ? 0 : 2,
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'New Customers',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color:
                                        isDark ? Colors.white54 : Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  '${_analyticsData['new_customers'] ?? 0}',
                                  style: const TextStyle(
                                    fontSize: 36,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF8CC63F),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.person_add,
                                      size: 16,
                                      color: isDark
                                          ? Colors.white54
                                          : Colors.grey,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Created in period',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isDark
                                            ? Colors.white54
                                            : Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Summary section
                  Card(
                    color: isDark ? const Color(0xFF1A2332) : Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Summary',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color:
                                  isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _SummaryRow(
                            label: 'Total Unique Customers',
                            value:
                                '${_analyticsData['total_visits'] ?? 0}',
                            isDark: isDark,
                          ),
                          const SizedBox(height: 8),
                          _SummaryRow(
                            label: 'New Customers in Period',
                            value:
                                '${_analyticsData['new_customers'] ?? 0}',
                            isDark: isDark,
                          ),
                          const SizedBox(height: 8),
                          _SummaryRow(
                            label: 'Returning Customers',
                            value:
                                '${((_analyticsData['total_visits'] ?? 0) as int) - ((_analyticsData['new_customers'] ?? 0) as int)}',
                            isDark: isDark,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isDark;

  const _SummaryRow({
    required this.label,
    required this.value,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.white70 : Colors.black87,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: Color(0xFF005BAC),
          ),
        ),
      ],
    );
  }
}

class _BranchSelectorDialog extends StatefulWidget {
  final List<Map<String, dynamic>> branches;
  final List<int> selectedBranchIds;

  const _BranchSelectorDialog({
    required this.branches,
    required this.selectedBranchIds,
  });

  @override
  State<_BranchSelectorDialog> createState() =>
      _BranchSelectorDialogState();
}

class _BranchSelectorDialogState extends State<_BranchSelectorDialog> {
  late List<int> _selected;

  @override
  void initState() {
    super.initState();
    _selected = List.from(widget.selectedBranchIds);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select Branches'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CheckboxListTile(
              title: const Text('All Branches'),
              value: _selected.isEmpty,
              onChanged: (value) {
                setState(() {
                  _selected = value == true ? [] : [];
                });
              },
            ),
            const Divider(),
            ...widget.branches.map((branch) {
              final branchId = branch['id'] as int;
              final isSelected =
                  _selected.isEmpty || _selected.contains(branchId);
              return CheckboxListTile(
                title: Text(branch['name'] ?? 'Unknown'),
                value: isSelected && _selected.isNotEmpty,
                onChanged: (value) {
                  setState(() {
                    if (value == true) {
                      _selected.add(branchId);
                    } else {
                      _selected.remove(branchId);
                    }
                  });
                },
              );
            }).toList(),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _selected),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
