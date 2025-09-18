import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'performance_graphics.dart';

class InsightsDetailViewerPage extends StatefulWidget {
  final String userId;
  final String username;
  const InsightsDetailViewerPage({required this.userId, required this.username});

  @override
  State<InsightsDetailViewerPage> createState() => _InsightsDetailViewerPageState();
}

class _InsightsDetailViewerPageState extends State<InsightsDetailViewerPage> {
  int attendance = 20;
  int dress = 20;
  int attitude = 20;
  int meeting = 10;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchMonthlyScores();
  }

  Future<void> fetchMonthlyScores() async {
    final now = DateTime.now();
    // --- Use previous month ---
    final prevMonth = now.month == 1 ? 12 : now.month - 1;
    final prevMonthYear = now.month == 1 ? now.year - 1 : now.year;
    final monthStart = DateTime(prevMonthYear, prevMonth, 1);
    final monthEnd = DateTime(prevMonthYear, prevMonth + 1, 1);

    final formsSnapshot = await FirebaseFirestore.instance
        .collection('dailyform')
        .where('userId', isEqualTo: widget.userId)
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
        .where('timestamp', isLessThan: Timestamp.fromDate(monthEnd))
        .get();

    final forms = formsSnapshot.docs.map((doc) => doc.data() as Map<String, dynamic>).toList();

    int att = 20, drs = 20, atti = 20, meet = 10;
    for (var form in forms) {
      final status = form['attendance'];
      if (status == 'late') att -= 5;
      else if (status == 'notApproved') att -= 10;
      if (status != 'approved' && status != 'notApproved') {
        if (form['dressCode']?['cleanUniform'] == false) drs -= 5;
        if (form['dressCode']?['keepInside'] == false) drs -= 5;
        if (form['dressCode']?['neatHair'] == false) drs -= 5;
        if (form['attitude']?['greetSmile'] == false) atti -= 2;
        if (form['attitude']?['askNeeds'] == false) atti -= 2;
        if (form['attitude']?['helpFindProduct'] == false) atti -= 2;
        if (form['attitude']?['confirmPurchase'] == false) atti -= 2;
        if (form['attitude']?['offerHelp'] == false) atti -= 2;
        if (form['meeting']?['attended'] == false) meet -= 1;
      }
    }
    setState(() {
      attendance = att < 0 ? 0 : att;
      dress = drs < 0 ? 0 : drs;
      attitude = atti < 0 ? 0 : atti;
      meeting = meet < 0 ? 0 : meet;
      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.username} - Monthly Performance'),
        backgroundColor: colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
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
                        const SizedBox(height: 12),
                        PerformanceRadarChart(
                          attendance: attendance,
                          dress: dress,
                          attitude: attitude,
                          meeting: meeting,
                        ),
                        const SizedBox(height: 28),
                        Wrap(
                          spacing: 16,
                          runSpacing: 16,
                          children: [
                            _buildBreakdownCard(
                              icon: Icons.access_time,
                              label: "Attendance",
                              value: attendance,
                              max: 20,
                              color: Colors.blue,
                            ),
                            _buildBreakdownCard(
                              icon: Icons.checkroom,
                              label: "Dress Code",
                              value: dress,
                              max: 20,
                              color: Colors.orange,
                            ),
                            _buildBreakdownCard(
                              icon: Icons.sentiment_satisfied,
                              label: "Attitude",
                              value: attitude,
                              max: 20,
                              color: Colors.deepPurple,
                            ),
                            _buildBreakdownCard(
                              icon: Icons.groups,
                              label: "Meeting",
                              value: meeting,
                              max: 10,
                              color: Colors.teal,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
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
