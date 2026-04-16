import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/dme_supabase_service.dart';
import 'dme_customer_visit_analytics.dart';

class DmeDashboardPage extends StatefulWidget {
  const DmeDashboardPage({super.key});

  @override
  State<DmeDashboardPage> createState() => _DmeDashboardPageState();
}

class _DmeDashboardPageState extends State<DmeDashboardPage> {
  final _svc = DmeSupabaseService.instance;

  Map<String, int> _counts = {};
  List<Map<String, dynamic>> _branchSales = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final countResult = await _svc.getDashboardCounts();
      debugPrint('Dashboard count result: $countResult');

      if (mounted) {
        setState(() {
          _counts = countResult;
          _branchSales = [];
          debugPrint('State updated - customers: ${_counts['customers']}');
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error in _loadAll: $e');
      if (mounted) setState(() => _loading = false);
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
                  const SizedBox(height: 16),

                  // ── Stat cards ──
                  Center(
                    child: SizedBox(
                      width: 200,
                      child: _StatCard(
                        label: 'Total Customers',
                        value: '${_counts['customers'] ?? 0}',
                        icon: Icons.people,
                        color: const Color(0xFF005BAC),
                      ),
                    ),
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

                  // ── Customer Visit Analytics Button ──
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const DmeCustomerVisitAnalyticsPage(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.analytics),
                      label: const Text('Customer Visit Analytics'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF005BAC),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
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
    return Card(
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
    );
  }
}
