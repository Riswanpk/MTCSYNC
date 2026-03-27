import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/dme_supabase_service.dart';

class DmeDashboardPage extends StatefulWidget {
  const DmeDashboardPage({super.key});

  @override
  State<DmeDashboardPage> createState() => _DmeDashboardPageState();
}

class _DmeDashboardPageState extends State<DmeDashboardPage> {
  final _svc = DmeSupabaseService.instance;

  Map<String, int> _counts = {};
  List<Map<String, dynamic>> _branchSales = [];
  List<Map<String, dynamic>> _topSalesmen = [];
  bool _loading = true;

  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  DateTime _to = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final user = uid != null ? await _svc.getCurrentUser(uid) : null;
      List<int>? branchIds;
      if (user != null && !user.isAdmin) {
        branchIds = await _svc.getUserBranchIds(user.id);
      }

      final results = await Future.wait([
        _svc.getDashboardCounts(branchIds: branchIds),
        _svc.getSalesSummaryByBranch(from: _from, to: _to),
        _svc.getTopSalesmen(from: _from, to: _to),
      ]);

      if (mounted) {
        setState(() {
          _counts = results[0] as Map<String, int>;
          _branchSales = results[1] as List<Map<String, dynamic>>;
          _topSalesmen = results[2] as List<Map<String, dynamic>>;
          _loading = false;
        });
      }
    } catch (e) {
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
      _from = picked.start;
      _to = picked.end;
      _loadAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd MMM yy');
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('DME Dashboard'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.date_range),
            tooltip: 'Date Range',
            onPressed: _pickDateRange,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAll,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAll,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Date range indicator
                  Text(
                    '${dateFmt.format(_from)} — ${dateFmt.format(_to)}',
                    style: TextStyle(
                        color: isDark ? Colors.white54 : Colors.grey[600]),
                  ),
                  const SizedBox(height: 16),

                  // ── Stat cards ──
                  Row(
                    children: [
                      _StatCard(
                        label: 'Customers',
                        value: '${_counts['customers'] ?? 0}',
                        icon: Icons.people,
                        color: const Color(0xFF005BAC),
                      ),
                      const SizedBox(width: 12),
                      _StatCard(
                        label: 'Products',
                        value: '${_counts['products'] ?? 0}',
                        icon: Icons.inventory_2,
                        color: const Color(0xFF8CC63F),
                      ),
                      const SizedBox(width: 12),
                      _StatCard(
                        label: 'Reminders',
                        value: '${_counts['pendingReminders'] ?? 0}',
                        icon: Icons.notifications_active,
                        color: Colors.orange,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // ── Sales by branch chart ──
                  Text('Sales by Branch',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white70 : Colors.black87)),
                  const SizedBox(height: 12),
                  if (_branchSales.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(
                            child: Text('No sales data for this period')),
                      ),
                    )
                  else
                    SizedBox(
                      height: 220,
                      child: BarChart(
                        BarChartData(
                          alignment: BarChartAlignment.spaceAround,
                          maxY: _branchSales.fold<double>(
                                  0,
                                  (max, b) =>
                                      (b['total_quantity'] as double) > max
                                          ? b['total_quantity'] as double
                                          : max) *
                              1.2,
                          barTouchData: BarTouchData(
                            touchTooltipData: BarTouchTooltipData(
                              getTooltipItem: (group, gi, rod, ri) {
                                final branch =
                                    _branchSales[group.x.toInt()]['branch'];
                                return BarTooltipItem(
                                  '$branch\n${rod.toY.toStringAsFixed(0)}',
                                  const TextStyle(
                                      color: Colors.white, fontSize: 12),
                                );
                              },
                            ),
                          ),
                          titlesData: FlTitlesData(
                            show: true,
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget: (value, meta) {
                                  final idx = value.toInt();
                                  if (idx >= _branchSales.length) {
                                    return const SizedBox.shrink();
                                  }
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      _branchSales[idx]['branch']
                                          .toString()
                                          .substring(
                                              0,
                                              _branchSales[idx]['branch']
                                                          .toString()
                                                          .length >
                                                      4
                                                  ? 4
                                                  : _branchSales[idx]
                                                          ['branch']
                                                      .toString()
                                                      .length),
                                      style: const TextStyle(fontSize: 10),
                                    ),
                                  );
                                },
                              ),
                            ),
                            leftTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false)),
                            topTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false)),
                          ),
                          borderData: FlBorderData(show: false),
                          barGroups: _branchSales.asMap().entries.map((e) {
                            return BarChartGroupData(
                              x: e.key,
                              barRods: [
                                BarChartRodData(
                                  toY: (e.value['total_quantity'] as double),
                                  color: const Color(0xFF005BAC),
                                  width: 22,
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(4),
                                    topRight: Radius.circular(4),
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),

                  // ── Top salesmen ──
                  Text('Top Salesmen',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white70 : Colors.black87)),
                  const SizedBox(height: 8),
                  if (_topSalesmen.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(
                            child: Text('No sales data for this period')),
                      ),
                    )
                  else
                    ..._topSalesmen.asMap().entries.map((e) {
                      final s = e.value;
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              const Color(0xFF005BAC).withOpacity(0.1),
                          child: Text('${e.key + 1}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF005BAC))),
                        ),
                        title: Text(s['salesman']?.toString() ?? 'Unknown'),
                        trailing: Text(
                          (s['total_quantity'] as double).toStringAsFixed(0),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        color: isDark ? const Color(0xFF1A2332) : Colors.white,
        elevation: isDark ? 0 : 2,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
          child: Column(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 8),
              Text(value,
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87)),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white54 : Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }
}
