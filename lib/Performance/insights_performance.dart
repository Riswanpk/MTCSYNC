import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../Misc/user_cache_service.dart';
import 'insights_detail_viewer.dart';

const Color _primaryBlue = Color(0xFF005BAC);
const Color _primaryGreen = Color(0xFF8CC63F);
const Color _darkSurface = Color(0xFF1E2028);
const Color _darkCard = Color(0xFF252830);

class InsightsPerformancePage extends StatefulWidget {
  @override
  State<InsightsPerformancePage> createState() => _InsightsPerformancePageState();
}

class _InsightsPerformancePageState extends State<InsightsPerformancePage> {
  String? selectedBranch;
  List<String> branches = [];
  bool isLoadingBranches = true;
  bool isLoadingUsers = false;
  List<_UserPerf> userPerformances = [];

  @override
  void initState() {
    super.initState();
    fetchBranches();
  }

  Future<void> fetchBranches() async {
    setState(() { isLoadingBranches = true; });
    final cachedBranches = await UserCacheService.instance.getBranches();
    setState(() {
      branches = cachedBranches;
      isLoadingBranches = false;
    });
  }

  Future<void> fetchUserPerformances(String branch) async {
    setState(() { isLoadingUsers = true; userPerformances.clear(); });
    // Get all users in branch
    final usersSnap = await FirebaseFirestore.instance
        .collection('users')
        .where('branch', isEqualTo: branch)
        .get();
    final users = usersSnap.docs.map((doc) => {
      'id': doc.id,
      'username': doc.data()['username'] ?? doc.data()['email'] ?? doc.id,
    }).toList();

    // Get previous month range for weekly marks
    final now = DateTime.now();
    final prevMonth = now.month == 1 ? 12 : now.month - 1;
    final prevMonthYear = now.month == 1 ? now.year - 1 : now.year;
    final monthStart = DateTime(prevMonthYear, prevMonth, 1);
    final monthEnd = DateTime(prevMonthYear, prevMonth + 1, 1);

    List<_UserPerf> perfList = [];

    // Batch fetch: get all dailyforms for the timestamp range at once
    final allFormsSnap = await FirebaseFirestore.instance
        .collection('dailyform')
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
        .where('timestamp', isLessThan: Timestamp.fromDate(monthEnd))
        .get();

    // Group forms by userId
    final formsByUser = <String, List<Map<String, dynamic>>>{};
    for (final doc in allFormsSnap.docs) {
      final data = doc.data();
      final userId = data['userId'] as String?;
      if (userId == null) continue;
      formsByUser.putIfAbsent(userId, () => []);
      formsByUser[userId]!.add(data);
    }

    // Fetch performance marks from new structure: performance_mark/{monthYear}/branches/{branch}
    const monthNames = ['January','February','March','April','May','June','July','August','September','October','November','December'];
    final perfMonthYear = "${monthNames[prevMonth - 1]} $prevMonthYear";
    final branchDoc = await FirebaseFirestore.instance
        .collection('performance_mark')
        .doc(perfMonthYear)
        .collection('branches')
        .doc(branch)
        .get();

    final perfMarkByUser = <String, int>{};
    final bdaMarkByUser = <String, int>{};
    if (branchDoc.exists && branchDoc.data()?['users'] != null) {
      final usersMap = Map<String, dynamic>.from(branchDoc.data()!['users']);
      for (final entry in usersMap.entries) {
        final userData = Map<String, dynamic>.from(entry.value);
        perfMarkByUser[entry.key] = userData['score'] is int ? userData['score'] : 0;
        bdaMarkByUser[entry.key] = userData['bdaScore'] is int ? userData['bdaScore'] : 0;
      }
    }

    for (final user in users) {
      final forms = formsByUser[user['id']] ?? [];

      // Group forms by week
      Map<int, List<Map<String, dynamic>>> weekMap = {};
      for (var form in forms) {
        final ts = form['timestamp'];
        final date = ts is Timestamp ? ts.toDate() : DateTime.parse(ts.toString());
        int weekOfMonth = ((date.day - 1) ~/ 7) + 1;
        weekMap.putIfAbsent(weekOfMonth, () => []);
        weekMap[weekOfMonth]!.add(form);
      }

      double totalSum = 0;
      int weekCount = 0;
      double attendanceSum = 0, dressSum = 0, attitudeSum = 0, meetingSum = 0;
      for (final weekForms in weekMap.values) {
        int attendance = 20, dress = 20, attitude = 20, meeting = 10;
        for (var form in weekForms) {
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
        int weekTotal = attendance + dress + attitude + meeting;
        totalSum += weekTotal;
        attendanceSum += attendance;
        dressSum += dress;
        attitudeSum += attitude;
        meetingSum += meeting;
        weekCount++;
      }
      double avgWeeklyMark = weekCount > 0 ? totalSum / weekCount : 0;
      double avgAttendance = weekCount > 0 ? attendanceSum / weekCount : 0;
      double avgDress = weekCount > 0 ? dressSum / weekCount : 0;
      double avgAttitude = weekCount > 0 ? attitudeSum / weekCount : 0;
      double avgMeeting = weekCount > 0 ? meetingSum / weekCount : 0;

      int perfMark = perfMarkByUser[user['id']] ?? 0;
      int bdaMark = bdaMarkByUser[user['id']] ?? 0;

      int rawTotal = avgWeeklyMark.round() + perfMark + bdaMark;
      double percentage = (rawTotal / 120) * 100;
      perfList.add(_UserPerf(
        userId: user['id'],
        username: user['username'],
        avgWeeklyMark: avgWeeklyMark.round(),
        perfMark: perfMark,
        bdaMark: bdaMark,
        percentage: percentage,
        avgAttendance: avgAttendance.round(),
        avgDress: avgDress.round(),
        avgAttitude: avgAttitude.round(),
        avgMeeting: avgMeeting.round(),
      ));
    }
    perfList.sort((a, b) => b.percentage.compareTo(a.percentage));
    setState(() {
      userPerformances = perfList;
      isLoadingUsers = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? _darkSurface : const Color(0xFFF5F7FA);

    return Scaffold(
      backgroundColor: bgColor,
      body: CustomScrollView(
        slivers: [
          // Gradient header
          SliverAppBar(
            expandedHeight: 140,
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
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 30),
                      const Text(
                        'Performance Insights',
                        style: TextStyle(
                          fontSize: 22, fontWeight: FontWeight.bold,
                          color: Colors.white, letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Monthly employee performance overview',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              collapseMode: CollapseMode.pin,
            ),
          ),

          // Branch selector
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: isLoadingBranches
                  ? const Center(child: Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator(),
                    ))
                  : Container(
                      decoration: BoxDecoration(
                        color: isDark ? _darkCard : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          if (!isDark)
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                        ],
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: DropdownButtonFormField<String>(
                        decoration: InputDecoration(
                          labelText: 'Select Branch',
                          labelStyle: TextStyle(
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                          prefixIcon: Icon(
                            Icons.store_rounded,
                            color: _primaryBlue.withOpacity(0.7),
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                        ),
                        dropdownColor: isDark ? _darkCard : Colors.white,
                        value: selectedBranch,
                        hint: Text(
                          'Select Branch',
                          style: TextStyle(color: isDark ? Colors.grey[500] : Colors.grey[400]),
                        ),
                        items: branches
                            .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                            .toList(),
                        onChanged: (val) {
                          setState(() {
                            selectedBranch = val;
                            userPerformances.clear();
                          });
                          if (val != null) fetchUserPerformances(val);
                        },
                      ),
                    ),
            ),
          ),

          // Content
          if (selectedBranch == null)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.analytics_outlined, size: 64,
                      color: isDark ? Colors.grey[700] : Colors.grey[300]),
                    const SizedBox(height: 12),
                    Text(
                      'Select a branch to view insights',
                      style: TextStyle(
                        fontSize: 15,
                        color: isDark ? Colors.grey[500] : Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (isLoadingUsers)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (userPerformances.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.people_outline_rounded, size: 64,
                      color: isDark ? Colors.grey[700] : Colors.grey[300]),
                    const SizedBox(height: 12),
                    Text(
                      'No data for this branch',
                      style: TextStyle(
                        fontSize: 15,
                        color: isDark ? Colors.grey[500] : Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, idx) {
                    final user = userPerformances[idx];
                    final pctColor = user.percentage >= 80
                        ? _primaryGreen
                        : user.percentage >= 60
                            ? Colors.orange
                            : Colors.red;

                    // Rank decoration for top 3
                    Widget? rankBadge;
                    if (idx == 0) {
                      rankBadge = _RankBadge(icon: Icons.emoji_events_rounded, color: const Color(0xFFFFD700));
                    } else if (idx == 1) {
                      rankBadge = _RankBadge(icon: Icons.emoji_events_rounded, color: const Color(0xFFC0C0C0));
                    } else if (idx == 2) {
                      rankBadge = _RankBadge(icon: Icons.emoji_events_rounded, color: const Color(0xFFCD7F32));
                    }

                    return GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => InsightsDetailViewerPage(
                              userId: user.userId,
                              username: user.username,
                              avgWeeklyMark: user.avgWeeklyMark,
                              perfMark: user.perfMark,
                              bdaMark: user.bdaMark,
                              percentage: user.percentage,
                              avgAttendance: user.avgAttendance,
                              avgDress: user.avgDress,
                              avgAttitude: user.avgAttitude,
                              avgMeeting: user.avgMeeting,
                            ),
                          ),
                        );
                      },
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 5),
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
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  // Rank number or badge
                                  SizedBox(
                                    width: 44, height: 44,
                                    child: rankBadge ?? CircleAvatar(
                                      backgroundColor: _primaryBlue.withOpacity(0.1),
                                      child: Text(
                                        '${idx + 1}',
                                        style: TextStyle(
                                          color: _primaryBlue,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  // Name & breakdown
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          user.username,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                            color: isDark ? Colors.white : Colors.black87,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            _MiniTag(label: 'W: ${user.avgWeeklyMark}/70', color: _primaryBlue, isDark: isDark),
                                            const SizedBox(width: 6),
                                            _MiniTag(label: 'P: ${user.perfMark}/30', color: const Color(0xFFEF5350), isDark: isDark),
                                            const SizedBox(width: 6),
                                            _MiniTag(label: 'B: ${user.bdaMark}/20', color: const Color(0xFF26A69A), isDark: isDark),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Percentage
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: pctColor.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      '${user.percentage.round()}%',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                        color: pctColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              // Mini progress bar
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: Stack(
                                  children: [
                                    Container(
                                      height: 5,
                                      decoration: BoxDecoration(
                                        color: isDark ? Colors.white.withOpacity(0.06) : Colors.grey[200],
                                      ),
                                    ),
                                    FractionallySizedBox(
                                      widthFactor: (user.percentage / 100).clamp(0.0, 1.0),
                                      child: Container(
                                        height: 5,
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [pctColor, pctColor.withOpacity(0.6)],
                                          ),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
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
                  childCount: userPerformances.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

}

class _RankBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _RankBadge({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44, height: 44,
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color, size: 26),
    );
  }
}

class _MiniTag extends StatelessWidget {
  final String label;
  final Color color;
  final bool isDark;
  const _MiniTag({required this.label, required this.color, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(isDark ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

class _UserPerf {
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

  _UserPerf({
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
}
