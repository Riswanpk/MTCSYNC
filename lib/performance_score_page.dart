import 'package:flutter/material.dart';
import 'monthly_performance_table_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'loading_page.dart';
import 'theme_notifier.dart';

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
    super.dispose();
  }

  int calculateAttendanceMarks(List<Map<String, dynamic>> dailyForms) {
    int marks = 20;
    int lateCount = 0;
    int notApprovedCount = 0;

    for (var form in dailyForms) {
      final att = form['attendance'];
      if (att is String) {
        if (att == 'late') lateCount++;
        if (att == 'notApproved') notApprovedCount++;
      } else if (att is Map) {
        if (att['status'] == 'late') lateCount++;
        if (att['status'] == 'notApproved') notApprovedCount++;
        if (att['lateTime'] == true) lateCount++;
        if (att['notApproved'] == true) notApprovedCount++;
      }
    }

    int latePenalty = 0;
    if (lateCount > 2) {
      latePenalty = (lateCount - 2) * 5;
      lateReduced = true;
    }
    int notApprovedPenalty = notApprovedCount * 10;
    if (notApprovedCount > 0) notApprovedReduced = true;

    marks -= (latePenalty + notApprovedPenalty);
    if (marks < 0) marks = 0;
    return marks;
  }

  int calculateDressCodeMarks(List<Map<String, dynamic>> dailyForms) {
    int marks = 20;
    int falseCount = 0;
    dressReasons.clear();
    for (var form in dailyForms) {
      if (form['dressCode']?['cleanUniform'] == false) {
        dressReduced = true;
        if (!dressReasons.contains("Wear clean uniform")) {
          dressReasons.add("Wear clean uniform");
        }
        falseCount++;
      }
      if (form['dressCode']?['keepInside'] == false) falseCount++;
      if (form['dressCode']?['neatHair'] == false) falseCount++;
    }
    marks -= falseCount * 5;
    if (marks < 0) marks = 0;
    return marks;
  }

  int calculateAttitudeMarks(List<Map<String, dynamic>> dailyForms) {
    int marks = 20;
    // Reset attitude reasons
    attitudeReasons.clear();
    for (var form in dailyForms) {
      final attitude = form['attitude'];
      if (attitude?['greetSmile'] == false) {
        attitudeReduced = true;
        if (!attitudeReasons.contains("Greet customers with a warm smile")) {
          attitudeReasons.add("Greet customers with a warm smile");
        }
        marks -= 2;
      }
      if (attitude?['askNeeds'] == false) {
        attitudeReduced = true;
        if (!attitudeReasons.contains("Ask about their needs")) {
          attitudeReasons.add("Ask about their needs");
        }
        marks -= 2;
      }
      if (attitude?['helpFindProduct'] == false) {
        attitudeReduced = true;
        if (!attitudeReasons.contains("Help find the right product")) {
          attitudeReasons.add("Help find the right product");
        }
        marks -= 2;
      }
      if (attitude?['confirmPurchase'] == false) {
        attitudeReduced = true;
        if (!attitudeReasons.contains("Confirm the purchase")) {
          attitudeReasons.add("Confirm the purchase");
        }
        marks -= 2;
      }
      if (attitude?['offerHelp'] == false) {
        attitudeReduced = true;
        if (!attitudeReasons.contains("Offer carry or delivery help")) {
          attitudeReasons.add("Offer carry or delivery help");
        }
        marks -= 2;
      }
    }
    if (marks < 0) marks = 0;
    return marks;
  }

  int calculateMeetingMarks(List<Map<String, dynamic>> dailyForms) {
    int marks = 10;
    int notAttended = 0;
    for (var form in dailyForms) {
      if (form['meeting']?['attended'] == false) notAttended++;
    }
    if (notAttended > 0) meetingReduced = true;
    marks -= notAttended * 1;
    if (marks < 0) marks = 0;
    return marks;
  }

  // 1. Add performance score calculation:
  int calculatePerformanceMarks(List<Map<String, dynamic>> dailyForms) {
    int marks = 0;
    // Find the latest form for the month with performance field
    final now = DateTime.now();
    final monthForms = dailyForms.where((form) => form['performance'] != null).toList();
    if (monthForms.isNotEmpty) {
      final perf = monthForms.last['performance'];
      if (perf?['target'] == true) marks += 15;
      if (perf?['otherPerformance'] == true) marks += 15;
    }
    return marks;
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

    int attendance = calculateAttendanceMarks(weekForms);
    int dress = calculateDressCodeMarks(weekForms);
    int attitude = calculateAttitudeMarks(weekForms);
    int meeting = calculateMeetingMarks(weekForms);

    // 3. In fetchScores(), after getting forms:
    performanceScore = calculatePerformanceMarks(weekForms);

    setState(() {
      totalScore = attendance + dress + attitude + meeting;
      isLoading = false;
      performanceScore = calculatePerformanceMarks(weekForms);
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
    // Group forms by week (Sunday-Saturday, week belongs to month of its Saturday)
    Map<DateTime, List<Map<String, dynamic>>> weekMap = {};
    for (var form in forms) {
      final ts = form['timestamp'];
      final date = ts is Timestamp ? ts.toDate() : DateTime.parse(ts.toString());

      // Find the previous Sunday for this date
      final prevSunday = date.subtract(Duration(days: date.weekday % 7));
      // The Saturday of this week
      final thisSaturday = prevSunday.add(const Duration(days: 6));

      // Only include weeks whose Saturday is in the current month/year
      if (thisSaturday.month != now.month || thisSaturday.year != now.year) continue;

      weekMap.putIfAbsent(thisSaturday, () => []);
      weekMap[thisSaturday]!.add(form);
    }

    // Sort weeks by their Saturday date
    final sortedSaturdays = weekMap.keys.toList()..sort();
    List<Map<String, dynamic>> weeklyScores = [];

    for (int i = 0; i < sortedSaturdays.length; i++) {
      final weekForms = weekMap[sortedSaturdays[i]]!;
      int attendance = 20, dress = 20, attitude = 20, meeting = 10;

      for (var form in weekForms) {
        // Attendance deductions (do NOT deduct for approved leave)
        if (form['attendance'] == 'late') attendance -= 5;
        else if (form['attendance'] == 'notApproved') attendance -= 10;
        // Dress Code
        if (form['dressCode']?['cleanUniform'] == false) dress -= 20;
        // Attitude
        if (form['attitude']?['greetSmile'] == false) attitude -= 20;
        // Meeting
        if (form['meeting']?['attended'] == false) meeting -= 1;

        // Clamp to zero
        if (attendance < 0) attendance = 0;
        if (dress < 0) dress = 0;
        if (attitude < 0) attitude = 0;
        if (meeting < 0) meeting = 0;
      }
      int total = attendance + dress + attitude + meeting;
      weeklyScores.add({
        'weekLabel': 'W${i + 1}',
        'attendance': attendance,
        'dress': dress,
        'attitude': attitude,
        'meeting': meeting,
        'total': total,
        'weekEnd': sortedSaturdays[i],
      });
    }
    return weeklyScores;
  }

  List<Map<String, dynamic>> getCurrentWeekForms(List<Map<String, dynamic>> forms, DateTime now) {
    // Find today
    final today = DateTime(now.year, now.month, now.day);

    // Find the previous Sunday for today
    final prevSunday = today.subtract(Duration(days: today.weekday % 7));
    // The Saturday of this week
    final thisSaturday = prevSunday.add(const Duration(days: 6));

    // Only if this Saturday is in the current month/year, consider this week as current
    if (thisSaturday.month != now.month || thisSaturday.year != now.year) return [];

    // Return forms in this week (from prevSunday to thisSaturday)
    return forms.where((form) {
      final ts = form['timestamp'];
      final date = ts is Timestamp ? ts.toDate() : DateTime.parse(ts.toString());
      return !date.isBefore(prevSunday) && !date.isAfter(thisSaturday);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('My Performance Score', style: theme.textTheme.titleLarge),
        backgroundColor: colorScheme.primary,
        elevation: 0,
      ),
      body: Center(
        child: isLoading
            ? LoadingPage()
            : AnimatedBuilder(
                animation: _scaleAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _scaleAnimation.value,
                    child: child,
                  );
                },
                child: Card(
                  elevation: 8,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  color: isDark ? colorScheme.surface : const Color.fromARGB(255, 203, 207, 207),
                  margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 16),
                        Text(
                          'Total Score ',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.primary,
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
                        const SizedBox(height: 18),
                        Card(
                          color: isDark ? colorScheme.background : Colors.teal[50],
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          margin: const EdgeInsets.only(bottom: 16),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              children: [
                                Text(
                                  'Performance Score ',
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
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

// --- Main Page with Bottom Navigation ---
class PerformanceScorePage extends StatefulWidget {
  @override
  State<PerformanceScorePage> createState() => _PerformanceScorePageState();
}

class _PerformanceScorePageState extends State<PerformanceScorePage> {
  int _selectedIndex = 0;

  final List<Widget> _pages = [
    PerformanceScoreInnerPage(),
    MonthlyPerformanceTablePage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.score),
            label: 'Score',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.table_chart),
            label: 'Monthly Table',
          ),
        ],
      ),
    );
  }
}