import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

const Color primaryBlue = Color(0xFF005BAC);

class LeadsPerMonthChart extends StatelessWidget {
  final String? branch;
  const LeadsPerMonthChart({super.key, this.branch});

  Future<List<int>> _fetchLeadsPerMonth(String? branch) async {
    final now = DateTime.now();
    List<int> leadsPerMonth = List.filled(12, 0);

    Query query = FirebaseFirestore.instance.collection('follow_ups');
    if (branch != null && branch.isNotEmpty) {
      query = query.where('branch', isEqualTo: branch);
    }
    final snapshot = await query.get();

    for (var doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>? ?? {};
      final ts = data['created_at'];
      if (ts is Timestamp) {
        final dt = ts.toDate();
        if (dt.year == now.year) {
          leadsPerMonth[dt.month - 1]++;
        }
      }
    }
    return leadsPerMonth;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lineColor = isDark ? const Color(0xFF64B5F6) : primaryBlue;
    final areaColor = lineColor.withValues(alpha: isDark ? 0.15 : 0.12);
    final labelColor = isDark ? Colors.white54 : Colors.black45;

    return FutureBuilder<List<int>>(
      future: _fetchLeadsPerMonth(branch),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
              child: CircularProgressIndicator(strokeWidth: 2.5));
        }
        final leadsPerMonth = snapshot.data!;
        final months = [
          'J',
          'F',
          'M',
          'A',
          'M',
          'J',
          'J',
          'A',
          'S',
          'O',
          'N',
          'D'
        ];
        final maxVal = leadsPerMonth.reduce((a, b) => a > b ? a : b).toDouble();

        return LineChart(
          LineChartData(
            minY: 0,
            maxY: maxVal + math.max(maxVal * 0.2, 2),
            lineTouchData: LineTouchData(
              enabled: true,
              touchTooltipData: LineTouchTooltipData(
                tooltipBorderRadius: BorderRadius.circular(12),
                getTooltipItems: (spots) {
                  return spots.map((spot) {
                    final fullMonths = [
                      'Jan',
                      'Feb',
                      'Mar',
                      'Apr',
                      'May',
                      'Jun',
                      'Jul',
                      'Aug',
                      'Sep',
                      'Oct',
                      'Nov',
                      'Dec'
                    ];
                    return LineTooltipItem(
                      '${fullMonths[spot.x.toInt()]}\n${spot.y.toInt()} leads',
                      const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    );
                  }).toList();
                },
              ),
            ),
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (value, meta) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      value.toInt().toString(),
                      style: TextStyle(fontSize: 10, color: labelColor),
                    ),
                  ),
                  reservedSize: 32,
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (value, meta) {
                    int idx = value.toInt();
                    if (idx >= 0 && idx < months.length) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          months[idx],
                          style: TextStyle(
                            fontSize: 11,
                            color: labelColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                  interval: 1,
                  reservedSize: 28,
                ),
              ),
              rightTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            borderData: FlBorderData(show: false),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: math.max((maxVal / 4).roundToDouble(), 1),
              getDrawingHorizontalLine: (value) => FlLine(
                color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.05),
                strokeWidth: 1,
              ),
            ),
            lineBarsData: [
              LineChartBarData(
                isCurved: true,
                curveSmoothness: 0.3,
                barWidth: 3,
                color: lineColor,
                dotData: FlDotData(
                  show: true,
                  getDotPainter: (spot, percent, barData, index) =>
                      FlDotCirclePainter(
                    radius: 4,
                    color: lineColor,
                    strokeWidth: 2,
                    strokeColor: Colors.white,
                  ),
                ),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [areaColor, areaColor.withValues(alpha: 0)],
                  ),
                ),
                spots: List.generate(
                  12,
                  (i) => FlSpot(i.toDouble(), leadsPerMonth[i].toDouble()),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
