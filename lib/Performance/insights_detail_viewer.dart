import 'dart:math' as math;
import 'package:flutter/material.dart';

const Color _primaryBlue = Color(0xFF005BAC);
const Color _primaryGreen = Color(0xFF8CC63F);
const Color _darkSurface = Color(0xFF1E2028);
const Color _darkCard = Color(0xFF252830);

class InsightsDetailViewerPage extends StatefulWidget {
  final String userId;
  final String username;
  final int avgWeeklyMark;
  final int perfMark;
  final int bdaMark;
  final double percentage;
  final int avgAttendance;
  final int avgDress;
  final int avgAttitude;
  final int avgMeeting;

  const InsightsDetailViewerPage({
    required this.userId,
    required this.username,
    required this.avgWeeklyMark,
    required this.perfMark,
    required this.bdaMark,
    required this.percentage,
    required this.avgAttendance,
    required this.avgDress,
    required this.avgAttitude,
    required this.avgMeeting,
  });

  @override
  State<InsightsDetailViewerPage> createState() => _InsightsDetailViewerPageState();
}

class _InsightsDetailViewerPageState extends State<InsightsDetailViewerPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _animation = CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic);
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Color _percentColor(double pct) =>
      pct >= 80 ? _primaryGreen : pct >= 60 ? Colors.orange : Colors.red;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final total = widget.avgWeeklyMark + widget.perfMark + widget.bdaMark;

    final now = DateTime.now();
    final prevMonth = now.month == 1 ? 12 : now.month - 1;
    final prevMonthYear = now.month == 1 ? now.year - 1 : now.year;
    const monthNames = [
      'January','February','March','April','May','June',
      'July','August','September','October','November','December'
    ];
    final monthLabel = '${monthNames[prevMonth - 1]} $prevMonthYear';

    final bars = [
      _BarData('Attendance', widget.avgAttendance, 20, const Color(0xFF4A90D9), Icons.access_time_rounded),
      _BarData('Dress Code', widget.avgDress, 20, const Color(0xFF66BB6A), Icons.checkroom_rounded),
      _BarData('Attitude', widget.avgAttitude, 20, const Color(0xFFFF9800), Icons.sentiment_satisfied_alt_rounded),
      _BarData('Meeting', widget.avgMeeting, 10, const Color(0xFF9C27B0), Icons.groups_rounded),
      _BarData('Performance', widget.perfMark, 30, const Color(0xFFEF5350), Icons.trending_up_rounded),
      _BarData('BDA', widget.bdaMark, 20, const Color(0xFF26A69A), Icons.business_center_rounded),
    ];

    final pctColor = _percentColor(widget.percentage);
    final bgColor = isDark ? _darkSurface : const Color(0xFFF5F7FA);

    return Scaffold(
      backgroundColor: bgColor,
      body: CustomScrollView(
        slivers: [
          // Gradient header
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            backgroundColor: _primaryBlue,
            foregroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF003D73), _primaryBlue, Color(0xFF0078E7)],
                  ),
                ),
                child: SafeArea(
                  child: AnimatedBuilder(
                    animation: _animation,
                    builder: (context, child) {
                      return Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(height: 40),
                          // Username
                          Text(
                            widget.username,
                            style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.bold,
                              color: Colors.white, letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              monthLabel,
                              style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w500,
                                color: Colors.white.withOpacity(0.9),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          // Circular progress
                          SizedBox(
                            width: 130, height: 130,
                            child: CustomPaint(
                              painter: _CircleProgressPainter(
                                progress: (_animation.value * widget.percentage / 100).clamp(0.0, 1.0),
                                progressColor: pctColor,
                                bgColor: Colors.white.withOpacity(0.15),
                                strokeWidth: 10,
                              ),
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '${(widget.percentage * _animation.value).round()}%',
                                      style: const TextStyle(
                                        fontSize: 34, fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    Text(
                                      '$total / 120',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.white.withOpacity(0.7),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              collapseMode: CollapseMode.pin,
            ),
          ),

          // Summary chips
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Row(
                children: [
                  _SummaryChip(
                    label: 'Weekly',
                    value: '${widget.avgWeeklyMark}/70',
                    color: _primaryBlue,
                    isDark: isDark,
                  ),
                  const SizedBox(width: 10),
                  _SummaryChip(
                    label: 'Performance',
                    value: '${widget.perfMark}/30',
                    color: const Color(0xFFEF5350),
                    isDark: isDark,
                  ),
                  const SizedBox(width: 10),
                  _SummaryChip(
                    label: 'BDA',
                    value: '${widget.bdaMark}/20',
                    color: const Color(0xFF26A69A),
                    isDark: isDark,
                  ),
                ],
              ),
            ),
          ),

          // Section title
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                'Breakdown',
                style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ),
          ),

          // Bar charts
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, idx) {
                  final bar = bars[idx];
                  final fraction = bar.max > 0 ? bar.value / bar.max : 0.0;
                  return AnimatedBuilder(
                    animation: _animation,
                    builder: (context, child) {
                      final staggerDelay = (idx * 0.12).clamp(0.0, 0.6);
                      final itemProgress = ((_animation.value - staggerDelay) / (1.0 - staggerDelay)).clamp(0.0, 1.0);
                      return Transform.translate(
                        offset: Offset(0, 20 * (1 - itemProgress)),
                        child: Opacity(
                          opacity: itemProgress,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 5),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: isDark ? _darkCard : Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                if (!isDark)
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.04),
                                    blurRadius: 10,
                                    offset: const Offset(0, 2),
                                  ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 40, height: 40,
                                  decoration: BoxDecoration(
                                    color: bar.color.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(bar.icon, color: bar.color, size: 22),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
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
                                              color: isDark ? Colors.white : Colors.black87,
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: bar.color.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              '${bar.value}/${bar.max}',
                                              style: TextStyle(
                                                fontSize: 13, fontWeight: FontWeight.bold,
                                                color: bar.color,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(6),
                                        child: Stack(
                                          children: [
                                            Container(
                                              height: 8,
                                              decoration: BoxDecoration(
                                                color: isDark ? Colors.white.withOpacity(0.08) : Colors.grey[200],
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                            ),
                                            FractionallySizedBox(
                                              widthFactor: (fraction * itemProgress).clamp(0.0, 1.0),
                                              child: Container(
                                                height: 8,
                                                decoration: BoxDecoration(
                                                  gradient: LinearGradient(
                                                    colors: [bar.color, bar.color.withOpacity(0.7)],
                                                  ),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
                childCount: bars.length,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool isDark;

  const _SummaryChip({
    required this.label,
    required this.value,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: isDark ? _darkCard : Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            if (!isDark)
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w500,
                color: isDark ? Colors.grey[500] : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleProgressPainter extends CustomPainter {
  final double progress;
  final Color progressColor;
  final Color bgColor;
  final double strokeWidth;

  _CircleProgressPainter({
    required this.progress,
    required this.progressColor,
    required this.bgColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    final bgPaint = Paint()
      ..color = bgColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, bgPaint);

    final progressPaint = Paint()
      ..color = progressColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(_CircleProgressPainter old) =>
      old.progress != progress || old.progressColor != progressColor;
}

class _BarData {
  final String label;
  final int value;
  final int max;
  final Color color;
  final IconData icon;
  _BarData(this.label, this.value, this.max, this.color, this.icon);
}
