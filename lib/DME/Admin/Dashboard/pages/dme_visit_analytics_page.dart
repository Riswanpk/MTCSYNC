import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/dme_analytics_data.dart';
import '../services/dme_analytics_service.dart';
import '../widgets/dashboard_filter_card.dart';
import '../widgets/metric_kpi_card.dart';
import '../widgets/branch_distribution_card.dart';
import '../widgets/category_distribution_card.dart';
import '../widgets/customer_type_card.dart';
import '../../Reports/dme_new_customers_report_page.dart';
import '../../dme_admin_reminders_page.dart';

class DmeVisitAnalyticsPage extends StatefulWidget {
  final List<int>? userAssignedBranches;
  final DateTime? initialStartDate;
  final DateTime? initialEndDate;
  final int? initialBranchId;

  const DmeVisitAnalyticsPage({
    super.key,
    this.userAssignedBranches,
    this.initialStartDate,
    this.initialEndDate,
    this.initialBranchId,
  });

  @override
  State<DmeVisitAnalyticsPage> createState() => _DmeVisitAnalyticsPageState();
}

class _DmeVisitAnalyticsPageState extends State<DmeVisitAnalyticsPage> {
  bool _isLoading = true;

  late DateTime _startDate;
  late DateTime _endDate;
  int? _selectedBranchId;
  List<int> _assignedBranches = [];

  DmeAnalyticsSummary _summary = DmeAnalyticsSummary.empty();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startDate = widget.initialStartDate ?? DateTime(now.year, now.month, 1);
    _endDate = widget.initialEndDate ?? DateTime(now.year, now.month, now.day);
    _selectedBranchId = widget.initialBranchId;
    _initBranchAccess();
  }

  Future<void> _initBranchAccess() async {
    if (widget.userAssignedBranches != null) {
      _assignedBranches = widget.userAssignedBranches!;
    } else {
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final doc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();
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
        debugPrint('Error loading user assigned branches in analytics: $e');
      }
    }

    if (_assignedBranches.length == 1 && _selectedBranchId == null) {
      _selectedBranchId = _assignedBranches.first;
    }

    await _loadAnalyticsData();
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
      _loadAnalyticsData();
    }
  }

  Future<void> _loadAnalyticsData() async {
    setState(() => _isLoading = true);

    try {
      final summary = await DmeAnalyticsService.fetchAnalytics(
        startDate: _startDate,
        endDate: _endDate,
        selectedBranchId: _selectedBranchId,
        assignedBranches: _assignedBranches,
      );

      if (!mounted) return;
      setState(() {
        _summary = summary;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading visit analytics: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading analytics data: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Visit Analytics',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Reload Data',
            onPressed: _loadAnalyticsData,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Date & Branch Filter Card
            DashboardFilterCard(
              startDate: _startDate,
              endDate: _endDate,
              selectedBranchId: _selectedBranchId,
              assignedBranches: _assignedBranches,
              onPickDateRange: _pickDateRange,
              onBranchChanged: (val) {
                setState(() => _selectedBranchId = val);
                _loadAnalyticsData();
              },
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
                    child: MetricKpiCard(
                      title: 'Visited',
                      value: '${_summary.uniqueCustomersVisited}',
                      subtitle: 'Parties in period',
                      icon: Icons.people_alt_rounded,
                      color: const Color(0xFF005BAC),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: MetricKpiCard(
                      title: 'New Added',
                      value: '${_summary.newCustomersCreated}',
                      subtitle: 'Created in period',
                      icon: Icons.person_add_alt_1_rounded,
                      color: const Color(0xFF8CC63F),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => DmeNewCustomersReportPage(
                              userAssignedBranches: _assignedBranches,
                              initialStartDate: _startDate,
                              initialEndDate: _endDate,
                              initialBranchId: _selectedBranchId,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: MetricKpiCard(
                      title: 'Completed',
                      value: '${_summary.completedRemindersCount}',
                      subtitle: 'Calls verified',
                      icon: Icons.phone_callback_rounded,
                      color: Colors.orange,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => DmeAdminRemindersPage(
                              userAssignedBranches: _assignedBranches,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // 3. Branch Distribution Breakdown (When All Branches is selected)
              if (_selectedBranchId == null && _summary.salesByBranch.isNotEmpty) ...[
                BranchDistributionCard(salesByBranch: _summary.salesByBranch),
                const SizedBox(height: 20),
              ],

              // 4. Category Breakdown Distribution
              CategoryDistributionCard(
                salesByCategory: _summary.salesByCategory,
              ),
              const SizedBox(height: 20),

              // 5. Customer Types Breakdown
              CustomerTypeCard(salesByType: _summary.salesByType),
            ],
          ],
        ),
      ),
    );
  }
}
