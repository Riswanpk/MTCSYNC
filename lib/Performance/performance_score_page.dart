import 'package:flutter/material.dart';
import 'monthly_performance_table_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../Misc/loading_page.dart';
import '../Misc/theme_notifier.dart';
import 'performance_graphics.dart';
import 'performance_total.dart';
// --- Score Page Widget (your original code, renamed) ---
class PerformanceScoreInnerPage extends StatefulWidget {
  @override
  State<PerformanceScoreInnerPage> createState() => _PerformanceScoreInnerPageState();
}

class _PerformanceScoreInnerPageState extends State<PerformanceScoreInnerPage> with SingleTickerProviderStateMixin {
  int totalScore = 70; // 20 + 20 + 20 + 10
  bool isLoading = true;

  // Reason flags
  bool lateReduced = false;
  bool notApprovedReduced = false;
  bool dressReduced = false;
  bool attitudeReduced = false;
  bool meetingReduced = false;

  // Add this to your state variables at the top:
  List<String> attitudeReasons = [];
  List<String> dressReasons = [];

  // 2. Add a variable:
  int performanceScore = 0;

  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    fetchScores();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    );
    // Start the animation after a short delay for effect
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _pageController.dispose();
    super.dispose();
  }

  int calculateAttendanceMarks(List<Map<String, dynamic>> dailyForms) {
    int marks = 20;
    for (var form in dailyForms) {
      final att = form['attendance'];
      if (att == 'late') {
        marks -= 5;
      } else if (att == 'notApproved') {
        marks -= 10;
      }
      // No deduction for 'punching' or 'approved'
    }
    if (marks < 0) marks = 0;
    return marks;
  }

  int calculateDressCodeMarks(List<Map<String, dynamic>> dailyForms) {
    int marks = 20;
    for (var form in dailyForms) {
      final att = form['attendance'];
      if (att == 'approved' || att == 'notApproved') continue;
      if (form['dressCode']?['cleanUniform'] == false) marks -= 5;
      if (form['dressCode']?['keepInside'] == false) marks -= 5;
      if (form['dressCode']?['neatHair'] == false) marks -= 5;
    }
    if (marks < 0) marks = 0;
    return marks;
  }

  int calculateAttitudeMarks(List<Map<String, dynamic>> dailyForms) {
    int marks = 20;
    for (var form in dailyForms) {
      final att = form['attendance'];
      if (att == 'approved' || att == 'notApproved') continue;
      if (form['attitude']?['greetSmile'] == false) marks -= 2;
      if (form['attitude']?['askNeeds'] == false) marks -= 2;
      if (form['attitude']?['helpFindProduct'] == false) marks -= 2;
      if (form['attitude']?['confirmPurchase'] == false) marks -= 2;
      if (form['attitude']?['offerHelp'] == false) marks -= 2;
    }
    if (marks < 0) marks = 0;
    return marks;
  }

  int calculateMeetingMarks(List<Map<String, dynamic>> dailyForms) {
    int marks = 10;
    for (var form in dailyForms) {
      final att = form['attendance'];
      if (att == 'approved' || att == 'notApproved') continue; // skip deduction for any leave
      if (form['meeting']?['attended'] == false) marks -= 1;
    }
    if (marks < 0) marks = 0;
    return marks;
  }

  // Replace this function:
  // int calculatePerformanceMarks(List<Map<String, dynamic>> dailyForms) { ... }

  Future<int> fetchPerformanceMarkFromDb(String uid) async {
    final doc = await FirebaseFirestore.instance.collection('performance_mark').doc(uid).get();
    if (doc.exists && doc.data()?['score'] != null) {
      return doc.data()!['score'] as int;
    }
    return 0;
  }

  Future<void> fetchScores() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final monthEnd = DateTime(now.year, now.month + 1, 1);

    final formsSnapshot = await FirebaseFirestore.instance
        .collection('dailyform')
        .where('userId', isEqualTo: user.uid)
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
        .where('timestamp', isLessThan: Timestamp.fromDate(monthEnd))
        .get();

    final forms = formsSnapshot.docs.map((doc) => doc.data() as Map<String, dynamic>).toList();

    // Get only current week forms
    final weekForms = getCurrentWeekForms(forms, now);

    // Reset reasons
    lateReduced = false;
    notApprovedReduced = false;
    dressReduced = false;
    attitudeReduced = false;
    meetingReduced = false;
    dressReasons.clear();
    attitudeReasons.clear();

    int attendance = 20;
    int dress = 20;
    int attitude = 20;
    int meeting = 10;

    for (var form in weekForms) {
      final att = form['attendance'];
      // Attendance deductions
      if (att == 'late') {
        attendance -= 5;
        lateReduced = true;
      } else if (att == 'notApproved') {
        attendance -= 10;
        notApprovedReduced = true;
      }
      // Dress deductions
      if (att != 'approved' && att != 'notApproved') {
        if (form['dressCode']?['cleanUniform'] == false) {
          dress -= 5;
          dressReduced = true;
          dressReasons.add("Wear clean uniform");
        }
        if (form['dressCode']?['keepInside'] == false) {
          dress -= 5;
          dressReduced = true;
          dressReasons.add("Keep inside");
        }
        if (form['dressCode']?['neatHair'] == false) {
          dress -= 5;
          dressReduced = true;
          dressReasons.add("Keep your hair neat");
        }
      }
      // Attitude deductions
      if (att != 'approved' && att != 'notApproved') {
        if (form['attitude']?['greetSmile'] == false) {
          attitude -= 2;
          attitudeReduced = true;
          attitudeReasons.add("Greet with a warm smile");
        }
        if (form['attitude']?['askNeeds'] == false) {
          attitude -= 2;
          attitudeReduced = true;
          attitudeReasons.add("Ask about their needs");
        }
        if (form['attitude']?['helpFindProduct'] == false) {
          attitude -= 2;
          attitudeReduced = true;
          attitudeReasons.add("Help find the right product");
        }
        if (form['attitude']?['confirmPurchase'] == false) {
          attitude -= 2;
          attitudeReduced = true;
          attitudeReasons.add("Confirm the purchase");
        }
        if (form['attitude']?['offerHelp'] == false) {
          attitude -= 2;
          attitudeReduced = true;
          attitudeReasons.add("Offer carry or delivery help");
        }
      }
      // Meeting deduction
      if (att != 'approved' && att != 'notApproved') {
        if (form['meeting']?['attended'] == false) {
          meeting -= 1;
          meetingReduced = true;
        }
      }
    }

    // Clamp to zero
    if (attendance < 0) attendance = 0;
    if (dress < 0) dress = 0;
    if (attitude < 0) attitude = 0;
    if (meeting < 0) meeting = 0;

    // Fetch performance mark from DB
    int perfMark = await fetchPerformanceMarkFromDb(user.uid);

    setState(() {
      totalScore = attendance + dress + attitude + meeting;
      isLoading = false;
      performanceScore = perfMark;
    });
  }

  Widget _buildReason(String text, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  // Example Dart function for weekly scoring
  Future<List<Map<String, dynamic>>> calculateWeeklyScores(List<Map<String, dynamic>> forms, DateTime now) async {
    // Group forms by ISO week number
    Map<int, List<Map<String, dynamic>>> weekMap = {};
    Map<int, DateTime> weekStartDates = {};

    for (var form in forms) {
      final ts = form['timestamp'];
      final date = ts is Timestamp ? ts.toDate() : DateTime.parse(ts.toString());
      int weekNum = isoWeekNumber(date);

      // Find the Monday of this ISO week
      final monday = date.subtract(Duration(days: date.weekday - 1));
      weekMap.putIfAbsent(weekNum, () => []);
      weekMap[weekNum]!.add(form);
      weekStartDates[weekNum] = monday;
    }

    final sortedWeekNums = weekMap.keys.toList()..sort();
    List<Map<String, dynamic>> weeklyScores = [];

    for (int i = 0; i < sortedWeekNums.length; i++) {
      final weekNum = sortedWeekNums[i];
      final weekForms = weekMap[weekNum]!;
      int attendance = 20, dress = 20, attitude = 20, meeting = 10;

      for (var form in weekForms) {
        final att = form['attendance'];
        if (att == 'late') attendance -= 5;
        else if (att == 'notApproved') attendance -= 10;
        // No deduction for 'punching' or 'approved'

        // Dress
        if (att == 'approved' || att == 'notApproved') {
          // skip deduction for any leave
        } else {
          if (form['dressCode']?['cleanUniform'] == false) dress -= 5;
          if (form['dressCode']?['keepInside'] == false) dress -= 5;
          if (form['dressCode']?['neatHair'] == false) dress -= 5;
        }

        // Attitude
        if (att == 'approved' || att == 'notApproved') {
          // skip deduction for any leave
        } else {
          if (form['attitude']?['greetSmile'] == false) attitude -= 2;
          if (form['attitude']?['askNeeds'] == false) attitude -= 2;
          if (form['attitude']?['helpFindProduct'] == false) attitude -= 2;
          if (form['attitude']?['confirmPurchase'] == false) attitude -= 2;
          if (form['attitude']?['offerHelp'] == false) attitude -= 2;
        }

        // Meeting
        if (att == 'approved' || att == 'notApproved') {
          // skip deduction for any leave
        } else {
          if (form['meeting']?['attended'] == false) meeting -= 1;
        }

        // Clamp to zero
        if (attendance < 0) attendance = 0;
        if (dress < 0) dress = 0;
        if (attitude < 0) attitude = 0;
        if (meeting < 0) meeting = 0;
      }
      int total = attendance + dress + attitude + meeting;
      weeklyScores.add({
        'weekLabel': 'W$weekNum',
        'attendance': attendance,
        'dress': dress,
        'attitude': attitude,
        'meeting': meeting,
        'total': total,
        'weekStart': weekStartDates[weekNum],
      });
    }
    return weeklyScores;
  }

  List<Map<String, dynamic>> getCurrentWeekForms(List<Map<String, dynamic>> forms, DateTime now) {
    // Find ISO week number for today
    final today = DateTime(now.year, now.month, now.day);
    final currentWeekNum = isoWeekNumber(today);

    // Return forms in this ISO week
    return forms.where((form) {
      final ts = form['timestamp'];
      final date = ts is Timestamp ? ts.toDate() : DateTime.parse(ts.toString());
      return isoWeekNumber(date) == currentWeekNum && date.year == today.year;
    }).toList();
  }

  int isoWeekNumber(DateTime date) {
    // ISO week starts on Monday, week 1 is the week with the first Thursday of the year
    final thursday = date.subtract(Duration(days: (date.weekday + 6) % 7 - 3));
    final firstThursday = DateTime(date.year, 1, 4);
    final diff = thursday.difference(firstThursday).inDays ~/ 7;
    return 1 + diff;
  }

  Widget _buildScoreCard({Key? key, required Widget child}) {
    return Padding(
      key: key,
      padding: const EdgeInsets.all(32.0),
      child: child,
    );
  }

  Widget _buildTotalScorePage(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 16),
        Text(
          'Total Score ',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: colorScheme.primary,
            fontFamily: 'PTSans',
          ),
        ),
        const SizedBox(height: 18),
        Text(
          '$totalScore / 70',
          style: theme.textTheme.displayMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: totalScore >= 60
                ? Colors.green
                : totalScore >= 40
                    ? Colors.orange
                    : Colors.red,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 18),
        if (lateReduced)
          _buildReason("Please reach on time everyday", Icons.access_time, Colors.redAccent),
        if (notApprovedReduced)
          _buildReason("Avoid unapproved leaves", Icons.block, Colors.redAccent),
        for (final reason in dressReasons)
          _buildReason(reason, Icons.checkroom, Colors.deepOrange),
        for (final reason in attitudeReasons)
          _buildReason(reason, Icons.sentiment_satisfied, Colors.deepPurple),
        if (meetingReduced)
          _buildReason("Attend all meetings", Icons.groups, Colors.blueGrey),
      ],
    );
  }

  Widget _buildLastMonthScorePage(ThemeData theme, ColorScheme colorScheme) {
    final isDark = theme.brightness == Brightness.dark;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Card(
          color: isDark ? colorScheme.background : Colors.teal[50],
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          margin: const EdgeInsets.only(bottom: 16),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Text(
                  "Last Month's Performance Score ",
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$performanceScore / 30',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.red[700],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSuperpositionTransition(Widget child, Animation<double> animation) {
    // Cross-fade + scale
    return FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.92, end: 1.0).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
        ),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DefaultTextStyle(
      style: theme.textTheme.bodyMedium!.copyWith(fontFamily: 'PTSans'),
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          title: Text('My Performance Score', style: theme.textTheme.titleLarge?.copyWith(fontFamily: 'PTSans')),
          backgroundColor: colorScheme.primary,
          elevation: 0,
        ),
        body: isLoading
            ? Center(child: LoadingPage())
            : Column(
                children: [
                  // Page indicator
                  Padding(
                    padding: const EdgeInsets.only(top: 12.0, bottom: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        2,
                        (index) => AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: _currentPage == index ? 24 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _currentPage == index ? colorScheme.primary : Colors.grey[400],
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: PageView(
                      controller: _pageController,
                      onPageChanged: (index) {
                        setState(() {
                          _currentPage = index;
                        });
                      },
                      children: [
                        // --- First Tab: Score Summary ---
                        SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // --- Total Score Card with Progress Bar ---
                                Card(
                                  elevation: 4,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                  color: colorScheme.surface,
                                  child: Padding(
                                    padding: const EdgeInsets.all(24.0),
                                    child: Column(
                                      children: [
                                        Text(
                                          'Your Total Score',
                                          style: theme.textTheme.titleMedium?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            color: colorScheme.primary,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          '$totalScore / 70',
                                          style: theme.textTheme.displayMedium?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            color: totalScore >= 60
                                                ? Colors.green
                                                : totalScore >= 40
                                                    ? Colors.orange
                                                    : Colors.red,
                                            letterSpacing: 2,
                                          ),
                                        ),
                                        const SizedBox(height: 18),
                                        // Progress Bar
                                        LinearProgressIndicator(
                                          value: totalScore / 70,
                                          minHeight: 12,
                                          backgroundColor: Colors.grey[300],
                                          valueColor: AlwaysStoppedAnimation<Color>(
                                            totalScore >= 60
                                                ? Colors.green
                                                : totalScore >= 40
                                                    ? Colors.orange
                                                    : Colors.red,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 28),
                                // --- Breakdown Cards ---
                                Wrap(
                                  spacing: 16,
                                  runSpacing: 16,
                                  children: [
                                    _buildBreakdownCard(
                                      icon: Icons.access_time,
                                      label: "Attendance",
                                      value: 20 - (lateReduced ? 5 : 0) - (notApprovedReduced ? 10 : 0),
                                      max: 20,
                                      color: Colors.blue,
                                    ),
                                    _buildBreakdownCard(
                                      icon: Icons.checkroom,
                                      label: "Dress Code",
                                      value: 20 - dressReasons.length * 5,
                                      max: 20,
                                      color: Colors.orange,
                                    ),
                                    _buildBreakdownCard(
                                      icon: Icons.sentiment_satisfied,
                                      label: "Attitude",
                                      value: 20 - attitudeReasons.length * 2,
                                      max: 20,
                                      color: Colors.deepPurple,
                                    ),
                                    _buildBreakdownCard(
                                      icon: Icons.groups,
                                      label: "Meeting",
                                      value: meetingReduced ? 9 : 10,
                                      max: 10,
                                      color: Colors.teal,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 32),
                                // --- Reasons Section ---
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    "How to Improve",
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.primary,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                if (lateReduced)
                                  _buildReason("Please reach on time everyday", Icons.access_time, Colors.redAccent),
                                if (notApprovedReduced)
                                  _buildReason("Avoid unapproved leaves", Icons.block, Colors.redAccent),
                                for (final reason in dressReasons)
                                  _buildReason(reason, Icons.checkroom, Colors.deepOrange),
                                for (final reason in attitudeReasons)
                                  _buildReason(reason, Icons.sentiment_satisfied, Colors.deepPurple),
                                if (meetingReduced)
                                  _buildReason("Attend all meetings", Icons.groups, Colors.blueGrey),
                                const SizedBox(height: 32),
                                // --- Last Month Score Card ---
                                _buildLastMonthScorePage(theme, colorScheme),
                              ],
                            ),
                          ),
                        ),
                        // --- Second Tab: Radar Chart ---
                        SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
                            child: Card(
                              elevation: 2,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              color: colorScheme.surfaceVariant,
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  children: [
                                    Text(
                                      "Performance Breakdown",
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.primary,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    PerformanceRadarChart(
                                      attendance: 20 - (lateReduced ? 5 : 0) - (notApprovedReduced ? 10 : 0),
                                      dress: 20 - dressReasons.length * 5,
                                      attitude: 20 - attitudeReasons.length * 2,
                                      meeting: meetingReduced ? 9 : 10,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildBreakdownCard({
    required IconData icon,
    required String label,
    required int value,
    required int max,
    required Color color,
  }) {
    return SizedBox(
      width: 150,
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 32),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(fontWeight: FontWeight.bold, color: color),
              ),
              const SizedBox(height: 6),
              Text(
                "$value / $max",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}