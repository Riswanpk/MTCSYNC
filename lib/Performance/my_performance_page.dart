import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../Navigation/user_cache_service.dart';

const Color _primaryBlue = Color(0xFF005BAC);
const Color _primaryGreen = Color(0xFF8CC63F);
const Color _darkSurface = Color(0xFF1E2028);
const Color _darkCard = Color(0xFF252830);

class MyPerformancePage extends StatefulWidget {
  const MyPerformancePage({super.key});

  @override
  State<MyPerformancePage> createState() => _MyPerformancePageState();
}

class _MyPerformancePageState extends State<MyPerformancePage>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _animation;

  bool _isLoading = true;
  String? _errorMsg;

  int _avgWeeklyMark = 0;
  int _perfMark = 0;
  int _bdaMark = 0;
  double _percentage = 0;
  int _avgAttendance = 0;
  int _avgDress = 0;
  int _avgAttitude = 0;
  int _avgMeeting = 0;

  static const _monthNames = [
    'January','February','March','April','May','June',
    'July','August','September','October','November','December'
  ];

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _animation = CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic);
    _loadData();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() { _isLoading = true; _errorMsg = null; });
    try {
      await UserCacheService.instance.ensureLoaded();
      final uid = UserCacheService.instance.uid;
      final branch = UserCacheService.instance.branch;
      if (uid == null || branch == null) {
        setState(() { _isLoading = false; _errorMsg = 'User data unavailable.'; });
        return;
      }

      final now = DateTime.now();
      final prevMonth = now.month == 1 ? 12 : now.month - 1;
      final prevYear = now.month == 1 ? now.year - 1 : now.year;
      final monthStart = DateTime(prevYear, prevMonth, 1);
      final monthEnd = DateTime(prevYear, prevMonth + 1, 1);
      final monthYear = '${_monthNames[prevMonth - 1]} $prevYear';

      // Fetch daily forms for this user in the previous month
      final formsSnap = await FirebaseFirestore.instance
          .collection('dailyform')
          .where('userId', isEqualTo: uid)
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
          .where('timestamp', isLessThan: Timestamp.fromDate(monthEnd))
          .get();

      final forms = formsSnap.docs.map((d) => d.data()).toList();

      // Group by week
      final weekMap = <int, List<Map<String, dynamic>>>{};
      for (final form in forms) {
        final ts = form['timestamp'];
        final date = ts is Timestamp ? ts.toDate() : DateTime.parse(ts.toString());
        final week = ((date.day - 1) ~/ 7) + 1;
        weekMap.putIfAbsent(week, () => []);
        weekMap[week]!.add(form);
      }

      double totalSum = 0, attendanceSum = 0, dressSum = 0, attitudeSum = 0, meetingSum = 0;
      int weekCount = 0;
      for (final weekForms in weekMap.values) {
        int attendance = 20, dress = 20, attitude = 20, meeting = 10;
        for (final form in weekForms) {
          final att = form['attendance'];
          if (att == 'late') attendance -= 5;
          else if (att == 'notApproved') attendance -= 10;
          if (att != 'approved' && att != 'notApproved') {
            if (form['dressCode']?['cleanUniform'] == false) dress -= 5;
            if (form['dressCode']?['keepInside'] == false) dress -= 5;
            if (form['dressCode']?['neatHair'] == false) dress -= 5;
            if (form['attitude']?['greetSmile'] == false) attitude -= 2;
            if (form['attitude']?['askNeeds'] == false) attitude -= 2;
            if (form['attitude']?['helpFindProduct'] == false) attitude -= 2;
            if (form['attitude']?['confirmPurchase'] == false) attitude -= 2;
            if (form['attitude']?['offerHelp'] == false) attitude -= 2;
            if (form['meeting']?['attended'] == false) meeting -= 1;
          }
        }
        if (attendance < 0) attendance = 0;
        if (dress < 0) dress = 0;
        if (attitude < 0) attitude = 0;
        if (meeting < 0) meeting = 0;
        totalSum += attendance + dress + attitude + meeting;
        attendanceSum += attendance;
        dressSum += dress;
        attitudeSum += attitude;
        meetingSum += meeting;
        weekCount++;
      }

      final avgWeekly = weekCount > 0 ? totalSum / weekCount : 0.0;

      // Fetch performance & BDA marks
      int perfMark = 0, bdaMark = 0;
      final branchDoc = await FirebaseFirestore.instance
          .collection('performance_mark')
          .doc(monthYear)
          .collection('branches')
          .doc(branch)
          .get();
      if (branchDoc.exists && branchDoc.data()?['users'] != null) {
        final usersMap = Map<String, dynamic>.from(branchDoc.data()!['users']);
        if (usersMap.containsKey(uid)) {
          final userData = Map<String, dynamic>.from(usersMap[uid]);
          perfMark = userData['score'] is int ? userData['score'] : 0;
          bdaMark = userData['bdaScore'] is int ? userData['bdaScore'] : 0;
        }
      }

      final total = avgWeekly.round() + perfMark + bdaMark;
      final percentage = (total / 120) * 100;

      setState(() {
        _avgWeeklyMark = avgWeekly.round();
        _perfMark = perfMark;
        _bdaMark = bdaMark;
        _percentage = percentage;
        _avgAttendance = weekCount > 0 ? (attendanceSum / weekCount).round() : 0;
        _avgDress = weekCount > 0 ? (dressSum / weekCount).round() : 0;
        _avgAttitude = weekCount > 0 ? (attitudeSum / weekCount).round() : 0;
        _avgMeeting = weekCount > 0 ? (meetingSum / weekCount).round() : 0;
        _isLoading = false;
      });

      _animController.forward(from: 0);
    } catch (e) {
      setState(() { _isLoading = false; _errorMsg = 'Failed to load data.'; });
    }
  }

  Color _percentColor(double pct) =>
      pct >= 80 ? _primaryGreen : pct >= 60 ? Colors.orange : Colors.red;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final now = DateTime.now();
    final prevMonth = now.month == 1 ? 12 : now.month - 1;
    final prevYear = now.month == 1 ? now.year - 1 : now.year;
    final monthLabel = '${_monthNames[prevMonth - 1]} $prevYear';
    final username = UserCacheService.instance.username ?? '';
    final bgColor = isDark ? _darkSurface : const Color(0xFFF5F7FA);

    return Scaffold(
      backgroundColor: bgColor,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMsg != null
              ? Center(child: Text(_errorMsg!, style: const TextStyle(color: Colors.red)))
              : _buildContent(context, isDark, monthLabel, username),
    );
  }

  Widget _buildContent(BuildContext context, bool isDark, String monthLabel, String username) {
    final total = _avgWeeklyMark + _perfMark + _bdaMark;
    final pctColor = _percentColor(_percentage);

    final bars = [
      _BarData('Attendance', _avgAttendance, 20, const Color(0xFF4A90D9), Icons.access_time_rounded),
      _BarData('Dress Code', _avgDress, 20, const Color(0xFF66BB6A), Icons.checkroom_rounded),
      _BarData('Attitude', _avgAttitude, 20, const Color(0xFFFF9800), Icons.sentiment_satisfied_alt_rounded),
      _BarData('Meeting', _avgMeeting, 10, const Color(0xFF9C27B0), Icons.groups_rounded),
      _BarData('Performance', _perfMark, 30, const Color(0xFFEF5350), Icons.trending_up_rounded),
      _BarData('BDA', _bdaMark, 20, const Color(0xFF26A69A), Icons.business_center_rounded),
    ];

    return CustomScrollView(
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
                        Text(
                          username,
                          style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold,
                            color: Colors.white, letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            monthLabel,
                            style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        // Animated circular progress
                        SizedBox(
                          width: 130, height: 130,
                          child: CustomPaint(
                            painter: _CircleProgressPainter(
                              progress: (_animation.value * _percentage / 100).clamp(0.0, 1.0),
                              progressColor: pctColor,
                              bgColor: Colors.white.withValues(alpha: 0.15),
                              strokeWidth: 10,
                            ),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '${(_percentage * _animation.value).round()}%',
                                    style: const TextStyle(
                                      fontSize: 34, fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  Text(
                                    '$total / 120',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.white.withValues(alpha: 0.7),
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
                _SummaryChip(label: 'Weekly', value: '$_avgWeeklyMark/70', color: _primaryBlue, isDark: isDark),
                const SizedBox(width: 10),
                _SummaryChip(label: 'Performance', value: '$_perfMark/30', color: const Color(0xFFEF5350), isDark: isDark),
                const SizedBox(width: 10),
                _SummaryChip(label: 'BDA', value: '$_bdaMark/20', color: const Color(0xFF26A69A), isDark: isDark),
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

        // Animated bar cards
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
                                  color: Colors.black.withValues(alpha: 0.04),
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
                                  color: bar.color.withValues(alpha: 0.12),
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
                                            color: bar.color.withValues(alpha: 0.1),
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
                                              color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey[200],
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                          ),
                                          FractionallySizedBox(
                                            widthFactor: (fraction * itemProgress).clamp(0.0, 1.0),
                                            child: Container(
                                              height: 8,
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  colors: [bar.color, bar.color.withValues(alpha: 0.7)],
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
                color: Colors.black.withValues(alpha: 0.04),
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
