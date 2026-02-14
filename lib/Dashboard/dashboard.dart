import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'monthly.dart';
import '../Todo & Leads/leads.dart';
import 'daily.dart';
import 'insights.dart';
// ...existing code...
import 'leadscount.dart';

// Theme colors
const Color primaryBlue = Color(0xFF005BAC);
const Color primaryGreen = Color(0xFF8CC63F);

// Gradient pairs for stat cards
const List<List<Color>> _cardGradients = [
  [Color(0xFF4A90D9), Color(0xFF005BAC)], // Blue
  [Color(0xFF66BB6A), Color(0xFF2E7D32)], // Green
  [Color(0xFFFFA726), Color(0xFFE65100)], // Orange
  [Color(0xFFEF5350), Color(0xFFB71C1C)], // Red
];

const List<List<Color>> _cardGradientsDark = [
  [Color(0xFF1565C0), Color(0xFF0D47A1)],
  [Color(0xFF2E7D32), Color(0xFF1B5E20)],
  [Color(0xFFE65100), Color(0xFFBF360C)],
  [Color(0xFFC62828), Color(0xFF8E0000)],
];

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with SingleTickerProviderStateMixin {
  String? _selectedBranch;
  List<String> _branches = [];
  bool _loadingBranches = true;
  Map<String, dynamic>? _userData;
  bool _loadingUser = true;
  late AnimationController _animController;
  late Animation<double> _fadeIn;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeIn = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _fetchBranches();
    _fetchUserData();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _fetchBranches() async {
    final usersSnapshot =
        await FirebaseFirestore.instance.collection('users').get();
    final branches = usersSnapshot.docs
        .map((doc) => doc['branch'] ?? '')
        .where((b) => b != null && b.toString().isNotEmpty)
        .toSet()
        .cast<String>()
        .toList()
      ..sort();
    setState(() {
      _branches = branches;
      _selectedBranch = null;
      _loadingBranches = false;
    });
  }

  Future<void> _fetchUserData() async {
    final userSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(FirebaseAuth.instance.currentUser!.uid)
        .get();
    setState(() {
      _userData = userSnapshot.data() as Map<String, dynamic>?;
      _loadingUser = false;
    });
    _animController.forward();
  }

  Future<Map<String, int>> _fetchCounts({String? branch}) async {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));

    Query followUps = FirebaseFirestore.instance.collection('follow_ups');
    Query todos = FirebaseFirestore.instance.collection('todo');

    List<String> branchEmails = [];
    if (branch != null && branch.isNotEmpty) {
      followUps = followUps.where('branch', isEqualTo: branch);

      final usersSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('branch', isEqualTo: branch)
          .where('role', isEqualTo: 'sales')
          .get();
      branchEmails = usersSnapshot.docs
          .map((doc) => doc['email'] as String)
          .where((e) => e.isNotEmpty)
          .toList();
    }

    final results = await Future.wait([
      branch == null
          ? FirebaseFirestore.instance
              .collection('leadscount')
              .doc('admin')
              .get()
              .then((snap) => (snap.data()?['totalLeads'] ?? 0) as int)
          : followUps.count().get(),
      followUps
          .where('created_at',
              isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
          .count()
          .get(),
      followUps
          .where('created_at',
              isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart))
          .where('created_at', isLessThan: Timestamp.fromDate(todayEnd))
          .count()
          .get(),
      (() async {
        Query pendingTodosQuery = todos.where('status', isEqualTo: 'pending');
        if (branchEmails.isNotEmpty) {
          int pendingCount = 0;
          List<Future<AggregateQuerySnapshot>> futures = [];
          for (var i = 0; i < branchEmails.length; i += 30) {
            final batch = branchEmails.sublist(
                i, i + 30 > branchEmails.length ? branchEmails.length : i + 30);
            futures.add(
                pendingTodosQuery.where('email', whereIn: batch).count().get());
          }
          final snapshots = await Future.wait(futures);
          for (final snap in snapshots) {
            pendingCount += snap.count ?? 0;
          }
          return pendingCount;
        } else {
          final pendingTodosSnap = await pendingTodosQuery.count().get();
          return pendingTodosSnap.count ?? 0;
        }
      })(),
    ]);

    return {
      'totalLeads': branch == null
          ? results[0] as int
          : (results[0] as AggregateQuerySnapshot).count ?? 0,
      'monthLeads': (results[1] as AggregateQuerySnapshot).count ?? 0,
      'todayLeads': (results[2] as AggregateQuerySnapshot).count ?? 0,
      'pendingTodos': results[3] as int,
    };
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingUser) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: const Center(
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }
    final userData = _userData ?? {};
    final role = userData['role'] ?? 'sales';
    final branch = userData['branch'] ?? '';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor =
        isDark ? const Color(0xFF1A1B22) : const Color(0xFFF5F7FA);

    return Scaffold(
      backgroundColor: surfaceColor,
      body: FadeTransition(
        opacity: _fadeIn,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // ── Sliver App Bar ──
            SliverAppBar(
              expandedHeight: 120,
              floating: false,
              pinned: true,
              elevation: 0,
              backgroundColor: isDark ? const Color(0xFF1A1B22) : Colors.white,
              surfaceTintColor: Colors.transparent,
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
                title: Text(
                  'Dashboard',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF1A1B22),
                    letterSpacing: -0.3,
                  ),
                ),
                background: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isDark
                          ? [const Color(0xFF1A1B22), const Color(0xFF23242B)]
                          : [Colors.white, const Color(0xFFF0F4FF)],
                    ),
                  ),
                ),
              ),
              actions: [
                // ...existing code...
              ],
            ),

            // ── Body ──
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  const SizedBox(height: 8),

                  // ── Stat Cards ──
                  FutureBuilder<Map<String, int>>(
                    future:
                        _fetchCounts(branch: role == 'manager' ? branch : null),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const SizedBox(
                          height: 200,
                          child: Center(
                              child:
                                  CircularProgressIndicator(strokeWidth: 2.5)),
                        );
                      }
                      final counts = snapshot.data!;
                      final cards = [
                        _CardData(
                          "Total Leads",
                          counts['totalLeads'].toString(),
                          Icons.leaderboard_rounded,
                          0,
                          () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => LeadsPage(
                                    branch: role == 'manager' ? branch : ""),
                              ),
                            );
                          },
                        ),
                        _CardData(
                          "This Month",
                          counts['monthLeads'].toString(),
                          Icons.calendar_month_rounded,
                          1,
                          () async {
                            if (role == 'manager') {
                              final usersSnapshot = await FirebaseFirestore
                                  .instance
                                  .collection('users')
                                  .where('branch', isEqualTo: branch)
                                  .where('role', isNotEqualTo: 'admin')
                                  .get();
                              final users = usersSnapshot.docs
                                  .map((doc) => {
                                        'uid': doc.id,
                                        'username': doc['username'] ?? '',
                                        'role': doc['role'] ?? '',
                                        'email': doc['email'] ?? '',
                                        'branch': doc['branch'] ?? '',
                                      })
                                  .toList();
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => MonthlyReportPage(
                                      branch: branch, users: users),
                                ),
                              );
                            } else {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      MonthlyReportPage(users: const []),
                                ),
                              );
                            }
                          },
                        ),
                        _CardData(
                          "Today",
                          counts['todayLeads'].toString(),
                          Icons.today_rounded,
                          2,
                          () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const DailyDashboardPage()),
                            );
                          },
                        ),
                        _CardData(
                          "Pending",
                          counts['pendingTodos'].toString(),
                          Icons.pending_actions_rounded,
                          3,
                          () {
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (_) =>
                                  PendingTodosModal(role: role, branch: branch),
                            );
                          },
                        ),
                      ];

                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
                          childAspectRatio: 1.3,
                        ),
                        itemCount: cards.length,
                        itemBuilder: (context, index) {
                          final card = cards[index];
                          return _AnimatedStatCard(
                            data: card,
                            isDark: isDark,
                            delay: index * 100,
                          );
                        },
                      );
                    },
                  ),

                  const SizedBox(height: 24),

                  // ── Chart Section ──
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF23242B) : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: isDark
                              ? Colors.black26
                              : Colors.black.withOpacity(0.06),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color:
                                    primaryBlue.withOpacity(isDark ? 0.2 : 0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.show_chart_rounded,
                                color: isDark ? Colors.white70 : primaryBlue,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Leads Overview',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: isDark
                                      ? Colors.white
                                      : const Color(0xFF1A1B22),
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                            if (role == 'admin' && !_loadingBranches)
                              _BranchChip(
                                branches: _branches,
                                selectedBranch: _selectedBranch,
                                isDark: isDark,
                                onChanged: (val) {
                                  setState(() {
                                    _selectedBranch = val;
                                  });
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          height: 240,
                          child: role == 'admin'
                              ? (_selectedBranch == null
                                  ? Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.touch_app_rounded,
                                            size: 40,
                                            color: isDark
                                                ? Colors.white24
                                                : Colors.black12,
                                          ),
                                          const SizedBox(height: 12),
                                          Text(
                                            "Select a branch",
                                            style: TextStyle(
                                              color: isDark
                                                  ? Colors.white38
                                                  : Colors.black38,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  : LeadsPerMonthChart(branch: _selectedBranch))
                              : LeadsPerMonthChart(branch: branch),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── Insights Button ──
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const InsightsPage()),
                        );
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Ink(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: isDark
                                ? [
                                    const Color(0xFF1565C0),
                                    const Color(0xFF0D47A1)
                                  ]
                                : [const Color(0xFF4A90D9), primaryBlue],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: primaryBlue.withOpacity(0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.insights_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                              const SizedBox(width: 10),
                              const Text(
                                "View Insights",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.3,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Icon(
                                Icons.arrow_forward_ios_rounded,
                                color: Colors.white70,
                                size: 16,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Data helper for stat cards ──
class _CardData {
  final String title;
  final String value;
  final IconData icon;
  final int colorIndex;
  final VoidCallback onTap;
  const _CardData(
      this.title, this.value, this.icon, this.colorIndex, this.onTap);
}

// ── Animated Gradient Stat Card ──
class _AnimatedStatCard extends StatefulWidget {
  final _CardData data;
  final bool isDark;
  final int delay;

  const _AnimatedStatCard({
    required this.data,
    required this.isDark,
    required this.delay,
  });

  @override
  State<_AnimatedStatCard> createState() => _AnimatedStatCardState();
}

class _AnimatedStatCardState extends State<_AnimatedStatCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _scale = Tween<double>(begin: 0.85, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
    _opacity = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gradients = widget.isDark ? _cardGradientsDark : _cardGradients;
    final gradient = gradients[widget.data.colorIndex % gradients.length];

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return Opacity(
          opacity: _opacity.value,
          child: Transform.scale(
            scale: _scale.value,
            child: child,
          ),
        );
      },
      child: GestureDetector(
        onTap: widget.data.onTap,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: gradient,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: gradient[1].withOpacity(0.35),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Decorative circle
              Positioned(
                top: -15,
                right: -15,
                child: Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.12),
                  ),
                ),
              ),
              Positioned(
                bottom: -20,
                left: -10,
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.08),
                  ),
                ),
              ),
              // Content
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        widget.data.icon,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.data.value,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            height: 1.1,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.data.title,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withOpacity(0.85),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Branch selector chip for chart ──
class _BranchChip extends StatelessWidget {
  final List<String> branches;
  final String? selectedBranch;
  final bool isDark;
  final ValueChanged<String?> onChanged;

  const _BranchChip({
    required this.branches,
    required this.selectedBranch,
    required this.isDark,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      offset: const Offset(0, 40),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: (isDark ? Colors.white : primaryBlue).withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: (isDark ? Colors.white : primaryBlue).withOpacity(0.15),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              selectedBranch ?? 'Branch',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : primaryBlue,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 16,
              color: isDark ? Colors.white54 : primaryBlue,
            ),
          ],
        ),
      ),
      itemBuilder: (context) => branches
          .map((b) => PopupMenuItem<String>(
                value: b,
                child: Text(b),
              ))
          .toList(),
      onSelected: onChanged,
    );
  }
}

// ── Chart widget for leads per month ──
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
    final areaColor = lineColor.withOpacity(isDark ? 0.15 : 0.12);
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
                      TextStyle(
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
                  AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            borderData: FlBorderData(show: false),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: math.max((maxVal / 4).roundToDouble(), 1),
              getDrawingHorizontalLine: (value) => FlLine(
                color: (isDark ? Colors.white : Colors.black).withOpacity(0.05),
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
                    colors: [areaColor, areaColor.withOpacity(0)],
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

// ── Pending Todos Modal ──
class PendingTodosModal extends StatefulWidget {
  final String role;
  final String branch;
  const PendingTodosModal(
      {super.key, required this.role, required this.branch});

  @override
  State<PendingTodosModal> createState() => _PendingTodosModalState();
}

class _PendingTodosModalState extends State<PendingTodosModal> {
  String? _selectedBranch;
  List<String> _branches = [];
  List<Map<String, dynamic>> _users = [];
  Map<String, int> _pendingCounts = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _fetchBranches();
    await _fetchUsersAndTodos();
    setState(() {
      _loading = false;
    });
  }

  Future<void> _fetchBranches() async {
    final usersSnapshot =
        await FirebaseFirestore.instance.collection('users').get();
    final branches = usersSnapshot.docs
        .map((doc) => doc['branch'] ?? '')
        .where((b) => b != null && b.toString().isNotEmpty)
        .toSet()
        .cast<String>()
        .toList()
      ..sort();
    setState(() {
      _branches = branches;
      if (_branches.isNotEmpty && _selectedBranch == null) {
        _selectedBranch =
            widget.role == 'manager' ? widget.branch : _branches.first;
      }
    });
  }

  Future<void> _fetchUsersAndTodos() async {
    Query usersQuery = FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'sales');
    if (widget.role == 'manager') {
      usersQuery = usersQuery.where('branch', isEqualTo: widget.branch);
    } else if (_selectedBranch != null) {
      usersQuery = usersQuery.where('branch', isEqualTo: _selectedBranch);
    }
    final usersSnapshot = await usersQuery.get();
    final users = usersSnapshot.docs
        .map((doc) => {
              'uid': doc.id,
              'username': doc['username'] ?? '',
              'email': doc['email'] ?? '',
              'branch': doc['branch'] ?? '',
            })
        .toList();

    final emails = users.map((u) => u['email'] as String).toList();
    Query todosQuery = FirebaseFirestore.instance
        .collection('todo')
        .where('status', isEqualTo: 'pending')
        .where('email', whereIn: emails.isEmpty ? [''] : emails);

    final todosSnapshot = await todosQuery.get();
    final todos = todosSnapshot.docs
        .map((doc) => doc.data() as Map<String, dynamic>)
        .toList();

    final Map<String, int> pendingCounts = {};
    for (var user in users) {
      final email = user['email'];
      pendingCounts[email] = todos.where((t) => t['email'] == email).length;
    }

    setState(() {
      _users = users;
      _pendingCounts = pendingCounts;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1A1B22) : Colors.white;
    final cardColor =
        isDark ? const Color(0xFF23242B) : const Color(0xFFF5F7FA);
    final textColor = isDark ? Colors.white : const Color(0xFF1A1B22);

    return SafeArea(
      child: DraggableScrollableSheet(
        initialChildSize: 0.8,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: _loading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2.5))
              : ListView(
                  controller: scrollController,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  children: [
                    // Handle bar
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white24 : Colors.black12,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),

                    // Title row
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(isDark ? 0.2 : 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.pending_actions_rounded,
                            color: isDark ? Colors.redAccent : Colors.red[700],
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Pending Todos",
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: textColor,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              Text(
                                "by sales team",
                                style: TextStyle(
                                  fontSize: 13,
                                  color: textColor.withOpacity(0.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    // Branch selector
                    if (_branches.isNotEmpty && widget.role != 'manager')
                      Padding(
                        padding: const EdgeInsets.only(top: 16, bottom: 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 4),
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isDark
                                  ? Colors.white10
                                  : Colors.black.withOpacity(0.06),
                            ),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedBranch,
                              items: _branches
                                  .map((b) => DropdownMenuItem(
                                      value: b, child: Text(b)))
                                  .toList(),
                              onChanged: (val) async {
                                setState(() {
                                  _selectedBranch = val;
                                  _loading = true;
                                });
                                await _fetchUsersAndTodos();
                                setState(() {
                                  _loading = false;
                                });
                              },
                              hint: Text(
                                "Select Branch",
                                style: TextStyle(
                                    color: textColor.withOpacity(0.5)),
                              ),
                              isExpanded: true,
                              dropdownColor: bgColor,
                              style: TextStyle(
                                color: textColor,
                                fontSize: 14,
                              ),
                              icon: Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: textColor.withOpacity(0.5),
                              ),
                            ),
                          ),
                        ),
                      ),

                    const SizedBox(height: 12),

                    if (_users.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 40),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(
                                Icons.person_off_rounded,
                                size: 48,
                                color: textColor.withOpacity(0.15),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No sales users found',
                                style: TextStyle(
                                  color: textColor.withOpacity(0.4),
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      ..._users.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final user = entry.value;
                        final count = _pendingCounts[user['email']] ?? 0;
                        final hasPending = count > 0;

                        return TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0.0, end: 1.0),
                          duration: Duration(milliseconds: 300 + (idx * 50)),
                          curve: Curves.easeOut,
                          builder: (context, value, child) {
                            return Opacity(
                              opacity: value,
                              child: Transform.translate(
                                offset: Offset(0, 20 * (1 - value)),
                                child: child,
                              ),
                            );
                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color: cardColor,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: hasPending
                                    ? Colors.red.withOpacity(0.15)
                                    : Colors.green.withOpacity(0.1),
                                width: 1,
                              ),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 6),
                              leading: Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: hasPending
                                        ? [
                                            Colors.red.withOpacity(0.15),
                                            Colors.red.withOpacity(0.05),
                                          ]
                                        : [
                                            Colors.green.withOpacity(0.15),
                                            Colors.green.withOpacity(0.05),
                                          ],
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Center(
                                  child: Text(
                                    (user['username'] as String).isNotEmpty
                                        ? (user['username'] as String)[0]
                                            .toUpperCase()
                                        : '?',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: hasPending
                                          ? Colors.red[700]
                                          : Colors.green[700],
                                    ),
                                  ),
                                ),
                              ),
                              title: Text(
                                user['username'],
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: textColor,
                                  fontSize: 14,
                                ),
                              ),
                              subtitle: Text(
                                user['branch'],
                                style: TextStyle(
                                  color: textColor.withOpacity(0.45),
                                  fontSize: 12,
                                ),
                              ),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 6),
                                decoration: BoxDecoration(
                                  color: hasPending
                                      ? Colors.red
                                          .withOpacity(isDark ? 0.2 : 0.08)
                                      : Colors.green
                                          .withOpacity(isDark ? 0.2 : 0.08),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  '$count',
                                  style: TextStyle(
                                    color: hasPending
                                        ? (isDark
                                            ? Colors.redAccent
                                            : Colors.red[700])
                                        : (isDark
                                            ? Colors.greenAccent
                                            : Colors.green[700]),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                  ],
                ),
        ),
      ),
    );
  }
}
