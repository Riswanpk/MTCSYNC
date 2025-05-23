import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class MonthlyReportPage extends StatefulWidget {
  final String? branch;
  final List<Map<String, dynamic>> users;
  const MonthlyReportPage({super.key, this.branch, required this.users});

  @override
  State<MonthlyReportPage> createState() => _MonthlyReportPageState();
}

class _MonthlyReportPageState extends State<MonthlyReportPage> {
  Map<String, dynamic>? _selectedUser;

  @override
  void initState() {
    super.initState();
    // Filter out admin users from the dropdown
    final nonAdminUsers = widget.users.where((u) => u['role'] != 'admin').toList();
    if (nonAdminUsers.isNotEmpty) {
      _selectedUser = nonAdminUsers.first;
    }
    _showTodoWarningIfNeeded();
  }

  void _showTodoWarningIfNeeded() async {
    final now = DateTime.now();
    if (now.hour < 11) return; // Only show after 11 AM

    final nonAdminUsers = widget.users.where((u) =>
        u['role'] == 'sales' || u['role'] == 'manager').toList();

    final todayStart = DateTime(now.year, now.month, now.day);
    final elevenAM = DateTime(now.year, now.month, now.day, 11, 0, 0);

    // Fetch todos created before 11 AM today
    final todosSnapshot = await FirebaseFirestore.instance
        .collection('todo')
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart))
        .where('timestamp', isLessThan: Timestamp.fromDate(elevenAM))
        .get();

    final Set<String> emailsWithTodo = todosSnapshot.docs
        .map((doc) => (doc.data() as Map<String, dynamic>)['email'] as String?)
        .whereType<String>()
        .toSet();

    final usersMissingTodo = nonAdminUsers
        .where((u) => !emailsWithTodo.contains(u['email']))
        .toList();

    if (usersMissingTodo.isNotEmpty && mounted) {
      final names = usersMissingTodo.map((u) => u['username']).join(', ');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Warning: The following users have not added a todo by 11 AM: $names',
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.orange[800],
            duration: const Duration(seconds: 6),
          ),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Only show users who are not admin
    final nonAdminUsers = widget.users.where((u) => u['role'] != 'admin').toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Monthly Missed Report'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      backgroundColor: isDark ? const Color(0xFF181A20) : const Color(0xFFF6F7FB),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: DropdownButton<Map<String, dynamic>>(
                  value: _selectedUser,
                  items: nonAdminUsers
                      .map((u) => DropdownMenuItem(
                            value: u,
                            child: Text(u['username']),
                          ))
                      .toList(),
                  onChanged: (val) {
                    setState(() {
                      _selectedUser = val;
                    });
                  },
                  hint: const Text("Select User"),
                ),
              ),
              if (_selectedUser != null)
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: _generateUserMonthlyReport(_selectedUser!['uid'], _selectedUser!['email']),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snap.hasError) {
                      return Center(child: Text('Error: ${snap.error}'));
                    }
                    if (!snap.hasData || snap.data!.isEmpty) {
                      return const Center(child: Text('No missed entries this month.'));
                    }
                    final missed = snap.data!;
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Date')),
                          DataColumn(label: Text('Todo')),
                          DataColumn(label: Text('Lead')),
                        ],
                        rows: missed.map((m) => DataRow(cells: [
                          DataCell(Text(m['date'])),
                          DataCell(Icon(
                            m['todo'] ? Icons.check_circle : Icons.cancel,
                            color: m['todo'] ? Colors.green : Colors.red,
                          )),
                          DataCell(Icon(
                            m['lead'] ? Icons.check_circle : Icons.cancel,
                            color: m['lead'] ? Colors.green : Colors.red,
                          )),
                        ])).toList(),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _generateUserMonthlyReport(String uid, String email) async {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final today = DateTime(now.year, now.month, now.day);

    Map<String, Map<String, bool>> missed = {};

    for (int i = 0; i < today.day; i++) {
      final date = monthStart.add(Duration(days: i));
      final dateStr = "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
      missed[dateStr] = {'todo': false, 'lead': false};
    }

    final todosSnapshot = await FirebaseFirestore.instance
        .collection('todo')
        .where('email', isEqualTo: email)
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
        .where('timestamp', isLessThan: Timestamp.fromDate(today.add(const Duration(days: 1))))
        .get();

    final leadsSnapshot = await FirebaseFirestore.instance
        .collection('follow_ups')
        .where('created_by', isEqualTo: uid)
        .where('created_at', isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
        .where('created_at', isLessThan: Timestamp.fromDate(today.add(const Duration(days: 1))))
        .get();

    for (var doc in todosSnapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final timestamp = (data['timestamp'] as Timestamp?)?.toDate();
      if (timestamp != null) {
        final dateStr = "${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')}";
        if (missed[dateStr] != null) {
          missed[dateStr]!['todo'] = true;
        }
      }
    }
    for (var doc in leadsSnapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final timestamp = (data['created_at'] as Timestamp?)?.toDate();
      if (timestamp != null) {
        final dateStr = "${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')}";
        if (missed[dateStr] != null) {
          missed[dateStr]!['lead'] = true;
        }
      }
    }

    final List<Map<String, dynamic>> missedReport = [];
    missed.forEach((dateStr, entry) {
      missedReport.add({
        'date': dateStr,
        'todo': entry['todo'] ?? false,
        'lead': entry['lead'] ?? false,
      });
    });
    return missedReport;
  }
}