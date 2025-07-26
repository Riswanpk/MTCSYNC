import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PerformanceScorePage extends StatefulWidget {
  @override
  State<PerformanceScorePage> createState() => _PerformanceScorePageState();
}

class _PerformanceScorePageState extends State<PerformanceScorePage> {
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

  @override
  void initState() {
    super.initState();
    fetchScores();
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

    // Reset reasons
    lateReduced = false;
    notApprovedReduced = false;
    dressReduced = false;
    attitudeReduced = false;
    meetingReduced = false;

    int attendance = calculateAttendanceMarks(forms);
    int dress = calculateDressCodeMarks(forms);
    int attitude = calculateAttitudeMarks(forms);
    int meeting = calculateMeetingMarks(forms);

    // 3. In fetchScores(), after getting forms:
    performanceScore = calculatePerformanceMarks(forms);

    setState(() {
      totalScore = attendance + dress + attitude + meeting;
      isLoading = false;
      // 4. In setState:
      performanceScore = calculatePerformanceMarks(forms);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blueGrey[50],
      appBar: AppBar(
        title: Text('My Performance Score'),
        backgroundColor: Colors.blue[800],
        elevation: 0,
      ),
      body: Center(
        child: isLoading
            ? CircularProgressIndicator()
            : Card(
                elevation: 8,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                color: Colors.white,
                margin: EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(height: 16),
                      Text(
                        'Total Score ',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.blue[900]),
                      ),
                      SizedBox(height: 18),
                      Text(
                        '$totalScore / 70',
                        style: TextStyle(
                          fontSize: 54,
                          fontWeight: FontWeight.bold,
                          color: totalScore >= 60
                              ? Colors.green
                              : totalScore >= 40
                                  ? Colors.orange
                                  : Colors.red,
                          letterSpacing: 2,
                        ),
                      ),
                      SizedBox(height: 18),
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
                      SizedBox(height: 18),
                      Card(
                        color: Colors.teal[50],
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        margin: EdgeInsets.only(bottom: 16),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            children: [
                              Text(
                                'Performance Score ',
                                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal[900]),
                              ),
                              SizedBox(height: 8),
                              Text(
                                '$performanceScore / 30',
                                style: TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.teal[700],
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
    );
  }
}