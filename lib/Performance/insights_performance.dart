import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../Misc/user_cache_service.dart';
import 'insights_detail_viewer.dart';

const Color _primaryBlue = Color(0xFF005BAC);
const Color _primaryGreen = Color(0xFF8CC63F);

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
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF181A20) : Colors.white,
      appBar: AppBar(
        title: const Text('Performance Insights'),
        backgroundColor: _primaryBlue,
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
                    decoration: InputDecoration(
                      labelText: 'Select Branch',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: _primaryBlue.withOpacity(0.3)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: _primaryBlue, width: 2),
                      ),
                    ),
                    value: selectedBranch,
                    hint: const Text('Select Branch'),
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
            if (selectedBranch == null)
              Expanded(
                child: Center(
                  child: Text(
                    'Select a branch to view insights',
                    style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600]),
                  ),
                ),
              )
            else if (isLoadingUsers)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else
              Expanded(
                child: userPerformances.isEmpty
                    ? Center(child: Text('No data for this branch', style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600])))
                    : ListView.builder(
                        itemCount: userPerformances.length,
                        itemBuilder: (context, idx) {
                          final user = userPerformances[idx];
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
                                  ),
                                ),
                              );
                            },
                            child: Card(
                              color: isDark ? Colors.grey[900] : Colors.white,
                              elevation: 2,
                              margin: const EdgeInsets.symmetric(vertical: 6),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: _primaryBlue,
                                  child: Text(
                                    '${idx + 1}',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                title: Text(user.username, style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text(
                                  'Weekly: ${user.avgWeeklyMark}/70 | Perf: ${user.perfMark}/30 | BDA: ${user.bdaMark}/20',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                trailing: Text(
                                  '${user.percentage.round()}%',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                    color: user.percentage >= 80
                                        ? _primaryGreen
                                        : user.percentage >= 60
                                            ? Colors.orange
                                            : Colors.red,
                                  ),
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

  _UserPerf({
    required this.userId,
    required this.username,
    required this.avgWeeklyMark,
    required this.perfMark,
    required this.bdaMark,
    required this.percentage,
  });
}
