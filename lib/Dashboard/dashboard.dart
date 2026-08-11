import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'monthly.dart';
import '../Leads/leads.dart';
import 'daily.dart';
import 'insights.dart';
import '../Navigation/user_cache_service.dart';
import '../SME/sme_dashboard.dart';
import '../Sync Head/sync_head_all_leads_page.dart';
import 'components/animated_stat_card.dart';
import 'components/branch_chip.dart';
import 'components/leads_per_month_chart.dart';
import 'components/pending_todos_modal.dart';
import 'components/fetch_dashboard_counts.dart';

const Color primaryBlue = Color(0xFF005BAC);
const Color primaryGreen = Color(0xFF8CC63F);

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
    final branches = await UserCacheService.instance.getBranches();
    if (!mounted) return;
    setState(() {
      _branches = branches;
      _selectedBranch = null;
      _loadingBranches = false;
    });
  }

  Future<void> _fetchUserData() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;
    final userSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser.uid)
        .get();
    if (!mounted) return;
    setState(() {
      _userData = userSnapshot.data();
      _loadingUser = false;
    });
    if (mounted) _animController.forward();
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
    final isAdminLike = role == 'admin' || role == 'sync_head';
    final branch = userData['branch'] ?? '';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor =
        isDark ? const Color(0xFF1A1B22) : const Color(0xFFF5F7FA);

    return Scaffold(
      backgroundColor: surfaceColor,
      body: GestureDetector(
        onLongPress: (role == 'admin') ? () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const SmeDashboard(),
            ),
          );
        } : null,
        child: FadeTransition(
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
              ),

              // ── Body ──
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    const SizedBox(height: 8),

                    // ── Stat Cards ──
                    FutureBuilder<Map<String, int>>(
                      future: fetchDashboardCounts(branch: (role == 'manager' || role == 'asst_manager') ? branch : null),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const SizedBox(
                            height: 200,
                            child: Center(
                                child: CircularProgressIndicator(strokeWidth: 2.5)),
                          );
                        }
                        final counts = snapshot.data!;
                        final cards = [
                          CardData(
                            "Total Leads",
                            counts['totalLeads'].toString(),
                            Icons.leaderboard_rounded,
                            0,
                            () {
                              if (role == 'sync_head' || role == 'Sync Head') {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const SyncHeadAllLeadsPage(),
                                  ),
                                );
                              } else {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => LeadsPage(
                                        branch: (role == 'manager' || role == 'asst_manager') ? branch : ""),
                                  ),
                                );
                              }
                            },
                          ),
                          CardData(
                            "This Month",
                            counts['monthLeads'].toString(),
                            Icons.calendar_month_rounded,
                            1,
                            () async {
                              if ((role == 'manager' || role == 'asst_manager') && branch.isNotEmpty) {
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
                                if (context.mounted) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => MonthlyReportPage(
                                          branch: branch, users: users),
                                    ),
                                  );
                                }
                              } else if (isAdminLike) {
                                final usersSnapshot = await FirebaseFirestore
                                    .instance
                                    .collection('users')
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
                                if (context.mounted) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => MonthlyReportPage(
                                          branch: null, users: users),
                                    ),
                                  );
                                }
                              } else {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const MonthlyReportPage(users: []),
                                  ),
                                );
                              }
                            },
                          ),
                          CardData(
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
                          CardData(
                            "Pending Todo",
                            (counts['pendingTodos'] ?? 0).toString(),
                            Icons.pending_actions_rounded,
                            3,
                            () {
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                backgroundColor: Colors.transparent,
                                builder: (_) => PendingTodosModal(
                                  role: role,
                                  branch: branch,
                                ),
                              );
                            },
                          ),
                        ];

                        return Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: AnimatedStatCard(
                                    data: cards[0],
                                    isDark: isDark,
                                    delay: 0,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: AnimatedStatCard(
                                    data: cards[1],
                                    isDark: isDark,
                                    delay: 100,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: AnimatedStatCard(
                                    data: cards[2],
                                    isDark: isDark,
                                    delay: 200,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: AnimatedStatCard(
                                    data: cards[3],
                                    isDark: isDark,
                                    delay: 300,
                                  ),
                                ),
                              ],
                            ),
                          ],
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
                                : Colors.black.withValues(alpha: 0.06),
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
                                      primaryBlue.withValues(alpha: isDark ? 0.2 : 0.1),
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
                              if (isAdminLike && !_loadingBranches)
                                BranchChip(
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
                            child: isAdminLike
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
                                color: primaryBlue.withValues(alpha: 0.3),
                                blurRadius: 12,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.insights_rounded,
                                  color: Colors.white,
                                  size: 22,
                                ),
                                SizedBox(width: 10),
                                Text(
                                  "View Insights",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                                SizedBox(width: 6),
                                Icon(
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
      ),
    );
  }
}
