import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
    final snap = await FirebaseFirestore.instance.collection('users').get();
    final branchSet = <String>{};
    for (var doc in snap.docs) {
      final branch = doc.data()['branch'];
      if (branch != null) branchSet.add(branch);
    }
    setState(() {
      branches = branchSet.toList()..sort();
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

    // Get current month for performance mark
    final perfMonth = now.month;
    final perfYear = now.year;

    List<_UserPerf> perfList = [];
    for (final user in users) {
      // Fetch dailyforms for previous month
      final formsSnap = await FirebaseFirestore.instance
          .collection('dailyform')
          .where('userId', isEqualTo: user['id'])
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
          .where('timestamp', isLessThan: Timestamp.fromDate(monthEnd))
          .get();
      final forms = formsSnap.docs.map((doc) => doc.data() as Map<String, dynamic>).toList();

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
        weekCount++;
      }
      double avgWeeklyMark = weekCount > 0 ? totalSum / weekCount : 0;

      // Fetch performance mark for current month (out of 30)
      final perfSnap = await FirebaseFirestore.instance
          .collection('performance_mark')
          .where('userId', isEqualTo: user['id'])
          .where('month', isEqualTo: perfMonth)
          .where('year', isEqualTo: perfYear)
          .get();
      int perfMark = 0;
      if (perfSnap.docs.isNotEmpty) {
        final data = perfSnap.docs.first.data();
        perfMark = data['score'] is int ? data['score'] : 0;
      }

      int total = avgWeeklyMark.round() + perfMark;
      perfList.add(_UserPerf(
        userId: user['id'],
        username: user['username'],
        avgWeeklyMark: avgWeeklyMark.round(),
        perfMark: perfMark,
        total: total,
      ));
    }
    perfList.sort((a, b) => b.total.compareTo(a.total));
    setState(() {
      userPerformances = perfList;
      isLoadingUsers = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Performance Insights'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            isLoadingBranches
                ? const Center(child: CircularProgressIndicator())
                : DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'Select Branch'),
                    value: selectedBranch,
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
            const SizedBox(height: 24),
            if (selectedBranch != null)
              isLoadingUsers
                  ? const Center(child: CircularProgressIndicator())
                  : Expanded(
                      child: userPerformances.isEmpty
                          ? Center(child: Text('No data for this branch'))
                          : ListView.builder(
                              itemCount: userPerformances.length,
                              itemBuilder: (context, idx) {
                                final user = userPerformances[idx];
                                return Card(
                                  color: isDark ? Colors.grey[900] : Colors.white,
                                  elevation: 2,
                                  margin: const EdgeInsets.symmetric(vertical: 6),
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: Colors.blue,
                                      child: Text(
                                        '${idx + 1}',
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    title: Text(user.username, style: TextStyle(fontWeight: FontWeight.bold)),
                                    subtitle: Text(
                                      'Avg Weekly: ${user.avgWeeklyMark} / 70 | Perf: ${user.perfMark} / 30',
                                      style: TextStyle(fontSize: 13),
                                    ),
                                    trailing: Text(
                                      '${user.total} / 100',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                        color: user.total >= 80
                                            ? Colors.green
                                            : user.total >= 60
                                                ? Colors.orange
                                                : Colors.red,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
          ],
        ),
      ),
      backgroundColor: isDark ? const Color(0xFF181A20) : Colors.white,
    );
  }
}

class _UserPerf {
  final String userId;
  final String username;
  final int avgWeeklyMark;
  final int perfMark;
  final int total;

  _UserPerf({
    required this.userId,
    required this.username,
    required this.avgWeeklyMark,
    required this.perfMark,
    required this.total,
  });
}
