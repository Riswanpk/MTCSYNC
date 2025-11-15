import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'monthly.dart';
import '../Todo & Leads/leads.dart';
import 'daily.dart';
import 'insights.dart';
import 'leadsdailyreport.dart';

// Add your theme colors
const Color primaryBlue = Color(0xFF005BAC);
const Color primaryGreen = Color(0xFF8CC63F);

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  String? _selectedBranch;
  List<String> _branches = [];
  bool _loadingBranches = true;

  @override
  void initState() {
    super.initState();
    _fetchBranches();
    _autoSendDailyReport();
  }

  Future<void> _autoSendDailyReport() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now();
    final key = 'last_daily_report_sent';
    final lastSent = prefs.getString(key);

    // Only send if not sent today
    final todayString = '${today.year}-${today.month}-${today.day}';
    if (lastSent != todayString) {
      await sendDailyLeadsReport(context);
      await prefs.setString(key, todayString);
    }
  }

  Future<void> _fetchBranches() async {
    final usersSnapshot = await FirebaseFirestore.instance.collection('users').get();
    final branches = usersSnapshot.docs
        .map((doc) => doc['branch'] ?? '')
        .where((b) => b != null && b.toString().isNotEmpty)
        .toSet()
        .cast<String>()
        .toList();
    setState(() {
      _branches = branches;
      _selectedBranch = branches.isNotEmpty ? branches.first : null;
      _loadingBranches = false;
    });
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

      // Get all sales users in this branch
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

    // --- OPTIMIZATION: Use count() aggregation and run queries concurrently ---
    final results = await Future.wait([
      // Query 1: Total leads count
      followUps.count().get(),
      // Query 2: Leads this month count
      followUps.where('created_at', isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart)).count().get(),
      // Query 3: Leads today count
      followUps
          .where('created_at', isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart))
          .where('created_at', isLessThan: Timestamp.fromDate(todayEnd))
          .count()
          .get(),
      // Query 4: Pending todos count
      (() async {
        Query pendingTodosQuery = todos.where('status', isEqualTo: 'pending');
        if (branchEmails.isNotEmpty) {
          // Firestore 'whereIn' supports up to 30 items in a query.
          // We batch requests to stay within this limit and run them in parallel.
          int pendingCount = 0;
          List<Future<AggregateQuerySnapshot>> futures = [];
          for (var i = 0; i < branchEmails.length; i += 30) {
            final batch = branchEmails.sublist(i, i + 30 > branchEmails.length ? branchEmails.length : i + 30);
            futures.add(pendingTodosQuery.where('email', whereIn: batch).count().get());
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
 'totalLeads': (results[0] as AggregateQuerySnapshot).count ?? 0,
 'monthLeads': (results[1] as AggregateQuerySnapshot).count ?? 0,
 'todayLeads': (results[2] as AggregateQuerySnapshot).count ?? 0,
      'pendingTodos': results[3] as int,
    };
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .get(),
      builder: (context, userSnapshot) {
        if (!userSnapshot.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final userData = userSnapshot.data!.data() as Map<String, dynamic>;
        final role = userData['role'] ?? 'sales';
        final branch = userData['branch'] ?? '';

        return Scaffold(
          backgroundColor: Theme.of(context).colorScheme.background,
          appBar: AppBar(
            title: const Text('Dashboard'),
            backgroundColor: Theme.of(context).colorScheme.background,
            foregroundColor: Theme.of(context).colorScheme.onBackground,
            elevation: 0,
            actions: [
              PopupMenuButton<String>(
                icon: const Icon(Icons.menu),
                onSelected: (value) async {
                  if (value == 'send_daily_report') {
                    await sendDailyLeadsReport(context);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem<String>(
                    value: 'send_daily_report',
                    child: Text('Send Daily Leads & Todo Report'),
                  ),
                ],
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                const SizedBox(height: 24),
                FutureBuilder<Map<String, int>>(
                  future: _fetchCounts(branch: role == 'manager' ? branch : null),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final counts = snapshot.data!;
                    return GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      physics: const NeverScrollableScrollPhysics(),
                      childAspectRatio: 1.25,
                      children: [
                        GestureDetector(
                          onTap: () {
                            if (role == 'manager') {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => LeadsPage(branch: branch),
                                ),
                              );
                            } else {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => LeadsPage(branch: ""),
                                ),
                              );
                            }
                          },
                          child: _StatCard(
                            title: "Total Leads",
                            value: counts['totalLeads'].toString(),
                            color: Colors.blue,
                            icon: Icons.leaderboard,
                          ),
                        ),
                        GestureDetector(
                          onTap: () async {
                            if (role == 'manager') {
                              // Fetch users for the manager's branch
                              final usersSnapshot = await FirebaseFirestore.instance
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
                                  builder: (_) => MonthlyReportPage(branch: branch, users: users),
                                ),
                              );
                            } else {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => MonthlyReportPage(users: const []),
                                ),
                              );
                            }
                          },
                          child: _StatCard(
                            title: "Leads This Month",
                            value: counts['monthLeads'].toString(),
                            color: Colors.green,
                            icon: Icons.calendar_month,
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const DailyDashboardPage()),
                            );
                          },
                          child: _StatCard(
                            title: "Leads Today",
                            value: counts['todayLeads'].toString(),
                            color: Colors.orange,
                            icon: Icons.today,
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (_) => PendingTodosModal(role: role, branch: branch),
                            );
                          },
                          child: _StatCard(
                            title: "Pending Todos",
                            value: counts['pendingTodos'].toString(),
                            color: Colors.red,
                            icon: Icons.pending_actions,
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF23242B) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4)),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Only show branch switch for admin, not for manager
                      if (role == 'admin' && !_loadingBranches)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: DropdownButton<String>(
                            value: _selectedBranch,
                            items: _branches
                                .map((b) => DropdownMenuItem(
                                      value: b,
                                      child: Text(
                                        b,
                                        style: TextStyle(
                                          color: Theme.of(context).brightness == Brightness.dark
                                              ? Colors.white
                                              : Colors.black,
                                        ),
                                      ),
                                    ))
                                .toList(),
                            onChanged: (val) {
                              setState(() {
                                _selectedBranch = val;
                              });
                            },
                            dropdownColor: Theme.of(context).brightness == Brightness.dark
                                ? const Color(0xFF23242B)
                                : Colors.white,
                            iconEnabledColor: Theme.of(context).brightness == Brightness.dark
                                ? Colors.white
                                : Colors.black,
                            hint: Text(
                              "Select Branch",
                              style: TextStyle(
                                color: Theme.of(context).brightness == Brightness.dark
                                    ? Colors.white
                                    : Colors.black,
                              ),
                            ),
                          ),
                        ),
                      SizedBox(
                        height: 260,
                        child: LeadsPerMonthChart(
                          branch: role == 'admin'
                              ? _selectedBranch
                              : branch, // For manager, always use their branch
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // --- Insights Button ---
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.insights),
                    label: const Text("Insights"),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const InsightsPage()),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }
}

// --- Add this widget for the stat cards ---
class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final Color color;
  final IconData icon;

  const _StatCard({
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    return Container(
      margin: const EdgeInsets.all(4),
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(isDark ? 0.18 : 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: color),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            style: TextStyle(fontSize: 15, color: textColor),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

enum Trend { up, down, neutral }

class MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final Color color;
  final Trend trend;

  const MetricCard({
    super.key,
    required this.title,
    required this.value,
    required this.color,
    required this.trend,
  });

  IconData get trendIcon {
    switch (trend) {
      case Trend.up:
        return Icons.arrow_drop_up;
      case Trend.down:
        return Icons.arrow_drop_down;
      case Trend.neutral:
      default:
        return Icons.remove;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                value,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor),
              ),
              const SizedBox(width: 4),
              Icon(trendIcon, color: color, size: 20),
            ],
          ),
          const SizedBox(height: 8),
          Text(title, style: TextStyle(fontSize: 12, color: textColor.withOpacity(0.7))),
          SizedBox(height: 8),
          LineChart(
            LineChartData(
              lineBarsData: [
                LineChartBarData(
                  isCurved: true,
                  color: isDark ? Colors.white : color,
                  barWidth: 2,
                  dotData: FlDotData(show: false),
                  belowBarData: BarAreaData(show: false),
                  spots: [
                    FlSpot(0, 1),
                    FlSpot(1, 1.2),
                    FlSpot(2, 1.1),
                    FlSpot(3, 1.5),
                  ],
                ),
              ],
              titlesData: FlTitlesData(show: false),
              borderData: FlBorderData(show: false),
              gridData: FlGridData(show: false),
              minX: 0,
              maxX: 3,
              minY: 0.8,
              maxY: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

class RevenueChart extends StatelessWidget {
  const RevenueChart({super.key});

  @override
  Widget build(BuildContext context) {
    return LineChart(
      LineChartData(
        minY: 27,
        maxY: 33.5,
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) => Text('${value.toStringAsFixed(1)}k', style: const TextStyle(fontSize: 10)),
              reservedSize: 32,
            ),
          ),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(show: false),
        lineBarsData: [
          LineChartBarData(
            isCurved: true,
            barWidth: 2,
            color: Colors.blue,
            dotData: FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              color: Colors.blue.withOpacity(0.2),
            ),
            spots: const [
              FlSpot(0, 33),
              FlSpot(1, 31.5),
              FlSpot(2, 31.3),
              FlSpot(3, 31.2),
              FlSpot(4, 33.5),
              FlSpot(5, 29.0),
              FlSpot(6, 30.5),
              FlSpot(7, 28.0),
              FlSpot(8, 33.2),
            ],
          ),
        ],
      ),
    );
  }
}

// Chart widget for leads per month
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
    final graphBgColor = isDark ? const Color(0xFF23242B) : Colors.white;
    return FutureBuilder<List<int>>(
      future: _fetchLeadsPerMonth(branch),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final leadsPerMonth = snapshot.data!;
        final months = [
          'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
          'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
        ];
        return Container(
          decoration: BoxDecoration(
            color: graphBgColor,
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.all(8),
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: (leadsPerMonth.reduce((a, b) => a > b ? a : b) + 2).toDouble(),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) => Text(
                      value.toInt().toString(),
                      style: TextStyle(fontSize: 10, color: isDark ? Colors.white : Colors.black),
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
                        return Text(months[idx], style: TextStyle(fontSize: 10, color: isDark ? Colors.white : Colors.black));
                      }
                      return const SizedBox.shrink();
                    },
                    interval: 1,
                    reservedSize: 28,
                  ),
                ),
                rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(show: false),
              gridData: FlGridData(show: false),
              lineBarsData: [
                LineChartBarData(
                  isCurved: true,
                  barWidth: 2,
                  color: isDark ? Colors.white : Colors.blue,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                      radius: 4,
                      color: isDark ? Colors.white : Colors.blue,
                      strokeWidth: 0,
                    ),
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    color: (isDark ? Colors.white : Colors.blue).withOpacity(0.2),
                  ),
                  spots: List.generate(12, (i) => FlSpot(i.toDouble(), leadsPerMonth[i].toDouble())),
                ),
              ],
              backgroundColor: graphBgColor,
            ),
          ),
        );
      },
    );
  }
}

// Add this new page at the end of the file or in a new file as appropriate

class PendingTodosModal extends StatefulWidget {
  final String role;
  final String branch;
  const PendingTodosModal({super.key, required this.role, required this.branch});

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
    final usersSnapshot = await FirebaseFirestore.instance.collection('users').get();
    final branches = usersSnapshot.docs
        .map((doc) => doc['branch'] ?? '')
        .where((b) => b != null && b.toString().isNotEmpty)
        .toSet()
        .cast<String>()
        .toList();
    setState(() {
      _branches = branches;
      if (_branches.isNotEmpty && _selectedBranch == null) {
        _selectedBranch = widget.role == 'manager' ? widget.branch : _branches.first;
      }
    });
  }

  Future<void> _fetchUsersAndTodos() async {
    Query usersQuery = FirebaseFirestore.instance.collection('users').where('role', isEqualTo: 'sales');
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

    // Get all pending todos for these users
    final emails = users.map((u) => u['email'] as String).toList();
    Query todosQuery = FirebaseFirestore.instance.collection('todo')
        .where('status', isEqualTo: 'pending')
        .where('email', whereIn: emails.isEmpty ? [''] : emails);

    final todosSnapshot = await todosQuery.get();
    final todos = todosSnapshot.docs.map((doc) => doc.data() as Map<String, dynamic>).toList();

    // Count pending todos per user email
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = theme.colorScheme.background;
    final cardColor = isDark ? const Color(0xFF23242B) : Colors.grey[50];
    final textColor = theme.colorScheme.onBackground;

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
            boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 12)],
          ),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 5,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.grey[400],
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    Center(
                      child: Text(
                        "Pending Todos by Sales",
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                    ),
                    if (_branches.isNotEmpty && widget.role != 'manager')
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: DropdownButton<String>(
                          value: _selectedBranch,
                          items: _branches
                              .map((b) => DropdownMenuItem(value: b, child: Text(b)))
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
                          hint: const Text("Select Branch"),
                          isExpanded: true,
                          dropdownColor: bgColor,
                          style: TextStyle(color: textColor),
                        ),
                      ),
                    if (_users.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 32),
                        child: Center(
                          child: Text(
                            'No sales users found.',
                            style: TextStyle(color: textColor),
                          ),
                        ),
                      )
                    else
                      ..._users.map((user) {
                        final count = _pendingCounts[user['email']] ?? 0;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black12,
                                blurRadius: 8,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.purple.withOpacity(0.15),
                              child: Icon(Icons.person, color: Colors.purple),
                            ),
                            title: Text(
                              user['username'],
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: textColor,
                              ),
                            ),
                            subtitle: Text(
                              user['branch'],
                              style: TextStyle(color: textColor.withOpacity(0.7)),
                            ),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: count > 0
                                    ? Colors.red.withOpacity(0.1)
                                    : Colors.green.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '$count Pending',
                                style: TextStyle(
                                  color: count > 0 ? Colors.red : Colors.green,
                                  fontWeight: FontWeight.bold,
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
