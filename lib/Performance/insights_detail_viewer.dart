import 'package:flutter/material.dart';

const Color _primaryBlue = Color(0xFF005BAC);
const Color _primaryGreen = Color(0xFF8CC63F);

class InsightsDetailViewerPage extends StatefulWidget {
  final String userId;
  final String username;
  final int avgWeeklyMark;
  final int perfMark;
  final int bdaMark;
  final double percentage;

  const InsightsDetailViewerPage({
    required this.userId,
    required this.username,
    required this.avgWeeklyMark,
    required this.perfMark,
    required this.bdaMark,
    required this.percentage,
  });

  @override
  State<InsightsDetailViewerPage> createState() => _InsightsDetailViewerPageState();
}

class _InsightsDetailViewerPageState extends State<InsightsDetailViewerPage> {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final total = widget.avgWeeklyMark + widget.perfMark + widget.bdaMark;

    // Previous month name for display
    final now = DateTime.now();
    final prevMonth = now.month == 1 ? 12 : now.month - 1;
    final prevMonthYear = now.month == 1 ? now.year - 1 : now.year;
    const monthNames = [
      'January','February','March','April','May','June',
      'July','August','September','October','November','December'
    ];
    final monthLabel = '${monthNames[prevMonth - 1]} $prevMonthYear';

    final bars = [
      _BarData('Daily Form Avg', widget.avgWeeklyMark, 70, _primaryBlue),
      _BarData('Performance', widget.perfMark, 30, Colors.orange),
      _BarData('BDA', widget.bdaMark, 20, _primaryGreen),
    ];

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF181A20) : Colors.white,
      appBar: AppBar(
        title: Text(widget.username),
        backgroundColor: _primaryBlue,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Month label
            Center(
              child: Text(
                monthLabel,
                style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w500,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Percentage circle
            Center(
              child: Container(
                width: 120, height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark ? Colors.grey[850] : Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 12, offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    '${widget.percentage.round()}%',
                    style: TextStyle(
                      fontSize: 32, fontWeight: FontWeight.bold,
                      color: widget.percentage >= 80
                          ? Colors.green
                          : widget.percentage >= 60
                              ? Colors.orange
                              : Colors.red,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'Total: $total / 120',
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
            ),
            const SizedBox(height: 32),

            // Bar chart
            ...bars.map((bar) {
              final fraction = bar.max > 0 ? bar.value / bar.max : 0.0;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          bar.label,
                          style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                        Text(
                          '${bar.value} / ${bar.max}',
                          style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Stack(
                        children: [
                          Container(
                            height: 28,
                            decoration: BoxDecoration(
                              color: isDark ? Colors.grey[800] : Colors.grey[200],
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          FractionallySizedBox(
                            widthFactor: fraction.clamp(0.0, 1.0),
                            child: Container(
                              height: 28,
                              decoration: BoxDecoration(
                                color: bar.color,
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _BarData {
  final String label;
  final int value;
  final int max;
  final Color color;
  _BarData(this.label, this.value, this.max, this.color);
}
