import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'monthly.dart' as monthly; // Add this import with a prefix

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late Future<List<Map<String, dynamic>>> _reportFuture = Future.value([]); // <-- Initialize here
  String? _selectedBranch;
  List<String> _branches = [];
  String? _currentUserRole;
  String? _currentUserBranch;

  @override
  void initState() {
    super.initState();
    _fetchCurrentUserRoleAndBranch().then((_) {
      _fetchBranches();
      setState(() {
        _reportFuture = _generateDailyReport();
      });
    });
  }

  Future<void> _fetchCurrentUserRoleAndBranch() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      _currentUserRole = userDoc['role'];
      _currentUserBranch = userDoc['branch'];
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
      if (_branches.isNotEmpty && _selectedBranch == null) {
        _selectedBranch = _branches.first;
      }
    });
  }

  Future<List<Map<String, dynamic>>> _generateDailyReport({String? branch}) async {
    final usersSnapshot = await FirebaseFirestore.instance.collection('users').get();
    List<Map<String, dynamic>> users = usersSnapshot.docs
        .map((doc) => {
              'uid': doc.id,
              'username': doc['username'] ?? '',
              'role': doc['role'] ?? '',
              'email': doc['email'] ?? '',
              'branch': doc['branch'] ?? '',
            })
        .toList();

    // If current user is manager, filter users to only sales in their branch
    if (_currentUserRole == 'manager') {
      users = users.where((u) =>
        u['role'] == 'sales' && u['branch'] == _currentUserBranch
      ).toList();
      branch = _currentUserBranch;
    } else if (branch != null) {
      users = users.where((u) => branch == null || u['branch'] == branch).toList();
    }

    final now = DateTime.now();
    final todayNoon = DateTime(now.year, now.month, now.day, 12, 0, 0);
    final yesterday7pm = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1)).add(const Duration(hours: 19));

    // For today, if before noon, use todayNoon, else use next day's noon
    final windowEnd = now.isBefore(todayNoon)
        ? todayNoon
        : todayNoon.add(const Duration(days: 1));

    final todosSnapshot = await FirebaseFirestore.instance
        .collection('todo')
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(yesterday7pm))
        .where('timestamp', isLessThan: Timestamp.fromDate(windowEnd))
        .get();

    final deletedTodosSnapshot = await FirebaseFirestore.instance
        .collection('deleted_todos')
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(yesterday7pm))
        .where('timestamp', isLessThan: Timestamp.fromDate(windowEnd))
        .get();

    final leadsSnapshot = await FirebaseFirestore.instance
        .collection('follow_ups')
        .where('created_at', isGreaterThanOrEqualTo: Timestamp.fromDate(yesterday7pm))
        .where('created_at', isLessThan: Timestamp.fromDate(windowEnd))
        .get();

    final deletedLeadsSnapshot = await FirebaseFirestore.instance
        .collection('deleted_leads')
        .where('created_at', isGreaterThanOrEqualTo: Timestamp.fromDate(yesterday7pm))
        .where('created_at', isLessThan: Timestamp.fromDate(windowEnd))
        .get();

    final Map<String, int> userTodoCount = {};
    final Map<String, int> userDeletedTodoCount = {};
    final Map<String, int> userLeadCount = {};
    final Map<String, int> userDeletedLeadCount = {};

    for (var doc in todosSnapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final email = data['email'];
      if (email != null) {
        userTodoCount[email] = (userTodoCount[email] ?? 0) + 1;
      }
    }
    for (var doc in deletedTodosSnapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final email = data['email'];
      if (email != null) {
        userDeletedTodoCount[email] = (userDeletedTodoCount[email] ?? 0) + 1;
      }
    }
    for (var doc in leadsSnapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final uid = data['created_by'];
      if (uid != null) {
        userLeadCount[uid] = (userLeadCount[uid] ?? 0) + 1;
      }
    }
    for (var doc in deletedLeadsSnapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final uid = data['created_by'];
      if (uid != null) {
        userDeletedLeadCount[uid] = (userDeletedLeadCount[uid] ?? 0) + 1;
      }
    }

    // Build report
    final List<Map<String, dynamic>> report = [];
    for (var user in users) {
      final uid = user['uid'];
      final email = user['email'] ?? '';
      final todoCreated = userTodoCount[email] ?? 0;
      final todoDeleted = userDeletedTodoCount[email] ?? 0;
      final leadCreated = userLeadCount[uid] ?? 0;
      final leadDeleted = userDeletedLeadCount[uid] ?? 0;

      report.add({
        'username': user['username'],
        'role': user['role'],
        'branch': user['branch'],
        'hasTodo': (todoCreated - todoDeleted) > 0,
        'hasLead': (leadCreated - leadDeleted) > 0,
      });
    }
    return report;
  }

  void _goToMonthlyReport(BuildContext context) async {
    final usersSnapshot = await FirebaseFirestore.instance.collection('users').get();
    List<Map<String, dynamic>> users = usersSnapshot.docs
        .map((doc) => {
              'uid': doc.id,
              'username': doc['username'] ?? '',
              'role': doc['role'] ?? '',
              'email': doc['email'] ?? '',
              'branch': doc['branch'] ?? '',
            })
        .toList();

    // If current user is manager, filter users to only sales in their branch
    if (_currentUserRole == 'manager') {
      users = users.where((u) =>
        u['role'] == 'sales' && u['branch'] == _currentUserBranch
      ).toList();
    } else if (_selectedBranch != null) {
      users = users.where((u) => u['branch'] == _selectedBranch).toList();
    }

    if (users.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => monthly.MonthlyReportPage(
          branch: _currentUserRole == 'manager' ? _currentUserBranch : _selectedBranch,
          users: users,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.calendar_month, color: Colors.white),
            label: const Text('Monthly Report', style: TextStyle(color: Colors.white)),
            onPressed: () => _goToMonthlyReport(context),
          ),
        ],
      ),
      backgroundColor: isDark ? const Color(0xFF181A20) : const Color(0xFFF6F7FB),
      body: Column(
        children: [
          if (_branches.isNotEmpty && _currentUserRole != 'manager')
            Padding(
              padding: const EdgeInsets.all(12),
              child: DropdownButton<String>(
                value: _selectedBranch,
                items: _branches
                    .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                    .toList(),
                onChanged: (val) {
                  setState(() {
                    _selectedBranch = val;
                    _reportFuture = _generateDailyReport(branch: val);
                  });
                },
                hint: const Text("Select Branch"),
              ),
            ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _reportFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: Text('No data found.'));
                }
                final report = snapshot.data!;
                if (report.isEmpty) {
                  return const Center(child: Text('No users or no data for today.'));
                }
                // Only show sales and manager sections if not manager, else only sales
                final sales = report.where((u) => u['role'] == 'sales').toList();
                final managers = report.where((u) => u['role'] == 'manager').toList();

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Sales Report', style: Theme.of(context).textTheme.titleLarge),
                      DataTable(
                        columns: const [
                          DataColumn(label: Text('Username')),
                          DataColumn(label: Text('Todo')),
                          DataColumn(label: Text('Lead')),
                        ],
                        rows: sales.map((u) => DataRow(cells: [
                          DataCell(Text(u['username'])),
                          DataCell(Icon(
                            u['hasTodo'] ? Icons.check_circle : Icons.cancel,
                            color: u['hasTodo'] ? Colors.green : Colors.red,
                          )),
                          DataCell(Icon(
                            u['hasLead'] ? Icons.check_circle : Icons.cancel,
                            color: u['hasLead'] ? Colors.green : Colors.red,
                          )),
                        ])).toList(),
                      ),
                      if (_currentUserRole != 'manager') ...[
                        const SizedBox(height: 32),
                        Text('Manager Report', style: Theme.of(context).textTheme.titleLarge),
                        DataTable(
                          columns: const [
                            DataColumn(label: Text('Username')),
                            DataColumn(label: Text('Todo')),
                            DataColumn(label: Text('Lead')),
                          ],
                          rows: managers.map((u) => DataRow(cells: [
                            DataCell(Text(u['username'])),
                            DataCell(Icon(
                              u['hasTodo'] ? Icons.check_circle : Icons.cancel,
                              color: u['hasTodo'] ? Colors.green : Colors.red,
                            )),
                            DataCell(Icon(
                              u['hasLead'] ? Icons.check_circle : Icons.cancel,
                              color: u['hasLead'] ? Colors.green : Colors.red,
                            )),
                          ])).toList(),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// Example usage before deleting the todo:
// await FirebaseFirestore.instance.collection('deleted_todos').add({
//   ...doc.data() as Map<String, dynamic>,
//   'deleted_at': FieldValue.serverTimestamp(),
// });
// await FirebaseFirestore.instance.collection('todo').doc(doc.id).delete();

// Example usage before deleting the lead:
// await FirebaseFirestore.instance.collection('deleted_leads').add({
//   ...doc.data() as Map<String, dynamic>,
//   'deleted_at': FieldValue.serverTimestamp(),
// });
// await FirebaseFirestore.instance.collection('follow_ups').doc(doc.id).delete();