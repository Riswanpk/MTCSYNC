import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../Todo & Leads/todo_leads_full_month.dart';

class DailyDashboardPage extends StatefulWidget {
  const DailyDashboardPage({super.key});

  @override
  State<DailyDashboardPage> createState() => _DailyDashboardPageState();
}

class _DailyDashboardPageState extends State<DailyDashboardPage> {
    DateTime _selectedDate = _getDefaultDashboardDate();

  static DateTime _getDefaultDashboardDate() {
    final now = DateTime.now();
    if (now.hour >= 12) {
      // After 12 PM, show next day's interval
      return now.add(const Duration(days: 1));
    } else {
      // Before 12 PM, show today's interval
      return now;
    }
  }
  String? _selectedBranch;
  List<String> _branches = [];
  String? _role;
  String? _userBranch;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final user = FirebaseAuth.instance.currentUser;
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(user!.uid).get();
    _role = userDoc['role'];
    _userBranch = userDoc['branch'];
    if (_role == 'admin') {
      final usersSnapshot = await FirebaseFirestore.instance.collection('users').get();
        _branches = usersSnapshot.docs
            .map((doc) => doc['branch'] ?? '')
            .where((b) => b != null && b.toString().isNotEmpty)
            .toSet()
            .cast<String>()
            .toList()
            ..sort();
        _selectedBranch = _branches.isNotEmpty ? _branches.first : null;
    } else {
      _selectedBranch = _userBranch;
    }
    setState(() {
      _loading = false;
    });
  }

  Future<void> _pickDate(BuildContext context) async {
    final today = DateTime.now();
    final defaultDate = _getDefaultDashboardDate();
    final maxDate = defaultDate.isAfter(today) ? defaultDate : today;
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2023, 1, 1),
      lastDate: maxDate,
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        // Force rebuild to update dashboard data
      });
    }
  }

  Future<List<Map<String, dynamic>>> _fetchUsersAndLeads({String role = 'sales'}) async {
    if (_selectedBranch == null) return [];
    final usersSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('branch', isEqualTo: _selectedBranch)
        .where('role', isEqualTo: role)
        .get();
    final users = usersSnapshot.docs
        .map((doc) => {
              'uid': doc.id,
              'username': doc['username'] ?? '',
              'email': doc['email'] ?? '',
            })
        .toList();

    // Use _selectedDate for the dashboard window
    final today = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    DateTime windowStart;
    if (today.weekday == DateTime.monday) {
      // If selected date is Monday, interval is Saturday 12 PM to Monday 12 PM
      final saturday = today.subtract(const Duration(days: 2));
      windowStart = DateTime(saturday.year, saturday.month, saturday.day, 12);
    } else {
      // Otherwise, interval is previous day 12 PM to selected date 12 PM
      final yesterday = today.subtract(const Duration(days: 1));
      windowStart = DateTime(yesterday.year, yesterday.month, yesterday.day, 12);
    }
    final windowEnd = DateTime(today.year, today.month, today.day, 12);

    // --- OPTIMIZATION: Use Future.wait to run queries for all users in parallel ---
    await Future.wait(users.map((user) async {
      final userId = user['uid'];
      final results = await Future.wait([
        FirebaseFirestore.instance
            .collection('daily_report')
            .where('userId', isEqualTo: userId)
            .where('type', isEqualTo: 'leads')
            .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(windowStart))
            .where('timestamp', isLessThan: Timestamp.fromDate(windowEnd))
            .limit(1)
            .get(),
        FirebaseFirestore.instance
            .collection('daily_report')
            .where('userId', isEqualTo: userId)
            .where('type', isEqualTo: 'todo')
            .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(windowStart))
            .where('timestamp', isLessThan: Timestamp.fromDate(windowEnd))
            .limit(1)
            .get(),
      ]);
      user['lead'] = (results[0] as QuerySnapshot).docs.isNotEmpty;
      user['todo'] = (results[1] as QuerySnapshot).docs.isNotEmpty;
    }));
    // --- END OPTIMIZATION ---

    return users;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Leads Today'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
        actions: [
          if (_role == 'admin')
            IconButton(
              icon: const Icon(Icons.download),
              tooltip: 'Download Report',
              onPressed: () async {
                // Navigate to the report page
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const TodoLeadsFullMonthPage(),
                  ),
                );
              },
            ),
        ],
      ),
      body: Column(
        children: [
          // Date dropdown
          Padding(
            padding: const EdgeInsets.only(top: 12, left: 12, right: 12, bottom: 0),
            child: Row(
              children: [
                const Text('Date:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: () => _pickDate(context),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      ),
                      child: Text(
                        "${_selectedDate.day.toString().padLeft(2, '0')}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.year}",
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_role == 'admin' && _branches.isNotEmpty)
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
                  });
                },
                isExpanded: true,
                hint: const Text("Select Branch"),
              ),
            ),
          // Legend moved to top
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 20),
                const SizedBox(width: 4),
                const Text('Lead', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 16),
                Icon(Icons.check_circle, color: Colors.blue, size: 20),
                const SizedBox(width: 4),
                const Text('Todo', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 16),
              ],
            ),
          ),
          Expanded(
            child: _role == 'admin'
                ? FutureBuilder<List<Map<String, dynamic>>>(
                    future: _fetchUsersAndLeads(role: 'sales'),
                    builder: (context, salesSnapshot) {
                      if (!salesSnapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final salesUsers = salesSnapshot.data!;
                      return FutureBuilder<List<Map<String, dynamic>>>(
                        future: _fetchUsersAndLeads(role: 'manager'),
                        builder: (context, managerSnapshot) {
                          if (!managerSnapshot.hasData) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          final managerUsers = managerSnapshot.data!;
                          if (salesUsers.isEmpty && managerUsers.isEmpty) {
                            return const Center(child: Text('No users found.'));
                          }
                          return ListView(
                            children: [
                              if (salesUsers.isNotEmpty) ...[
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  child: Text('Sales', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                ),
                                ...salesUsers.map((user) => ListTile(
                                      leading: CircleAvatar(child: Text(user['username'].toString().substring(0, 1).toUpperCase())),
                                      title: Text(user['username']),
                                      subtitle: Text(user['email']),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            user['lead'] ? Icons.check_circle : Icons.cancel,
                                            color: user['lead'] ? Colors.green : Colors.red,
                                          ),
                                          const SizedBox(width: 8),
                                          Icon(
                                            user['todo'] ? Icons.check_circle : Icons.cancel,
                                            color: user['todo'] ? Colors.blue : Colors.red,
                                          ),
                                        ],
                                      ),
                                    )),
                              ],
                              if (managerUsers.isNotEmpty) ...[
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  child: Text('Manager', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                ),
                                ...managerUsers.map((user) => ListTile(
                                      leading: CircleAvatar(child: Text(user['username'].toString().substring(0, 1).toUpperCase())),
                                      title: Text(user['username']),
                                      subtitle: Text(user['email']),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            user['lead'] ? Icons.check_circle : Icons.cancel,
                                            color: user['lead'] ? Colors.green : Colors.red,
                                          ),
                                          const SizedBox(width: 8),
                                          Icon(
                                            user['todo'] ? Icons.check_circle : Icons.cancel,
                                            color: user['todo'] ? Colors.blue : Colors.red,
                                          ),
                                        ],
                                      ),
                                    )),
                              ],
                            ],
                          );
                        },
                      );
                    },
                  )
                : FutureBuilder<List<Map<String, dynamic>>>(
                    future: _fetchUsersAndLeads(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final users = snapshot.data!;
                      if (users.isEmpty) {
                        return const Center(child: Text('No users found.'));
                      }
                      return ListView.builder(
                        itemCount: users.length,
                        itemBuilder: (context, idx) {
                          final user = users[idx];
                          return ListTile(
                            leading: CircleAvatar(child: Text(user['username'].toString().substring(0, 1).toUpperCase())),
                            title: Text(user['username']),
                            subtitle: Text(user['email']),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  user['lead'] ? Icons.check_circle : Icons.cancel,
                                  color: user['lead'] ? Colors.green : Colors.red,
                                ),
                                const SizedBox(width: 8),
                                Icon(
                                  user['todo'] ? Icons.check_circle : Icons.cancel,
                                  color: user['todo'] ? Colors.blue : Colors.red,
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}