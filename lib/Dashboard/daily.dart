import 'package:flutter/material.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../Todo/todo_leads_full_month.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../Navigation/user_cache_service.dart';

class DailyDashboardPage extends StatefulWidget {
  const DailyDashboardPage({super.key});

  @override
  State<DailyDashboardPage> createState() => _DailyDashboardPageState();
}

class _DailyDashboardPageState extends State<DailyDashboardPage> {
  DateTime _selectedDate = _getDefaultDashboardDateIST();
  static final _istLocation = _initIST();

  static tz.Location _initIST() {
    tz.initializeTimeZones();
    return tz.getLocation('Asia/Kolkata');
  }

  static DateTime _getDefaultDashboardDateIST() {
    final nowIST = tz.TZDateTime.now(_initIST());
    if (nowIST.hour >= 12) {
      // After 12 PM IST, show next day's interval
      return nowIST.add(const Duration(days: 1));
    } else {
      // Before 12 PM IST, show today's interval
      return nowIST;
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
    if (_role == 'admin' || _role == 'Sync Head' || _role == 'sync_head') {
      _branches = await UserCacheService.instance.getBranches();
        _selectedBranch = _branches.isNotEmpty ? _branches.first : null;
    } else {
      _selectedBranch = _userBranch;
    }
    setState(() {
      _loading = false;
    });
  }

  Future<void> _pickDate(BuildContext context) async {
    final nowIST = tz.TZDateTime.now(_istLocation);
    final defaultDate = _getDefaultDashboardDateIST();
    final maxDate = defaultDate.isAfter(nowIST) ? defaultDate : nowIST;
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2023, 1, 1),
      lastDate: DateTime(maxDate.year, maxDate.month, maxDate.day),
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

    // Use _selectedDate for the dashboard window, always in IST
    final ist = _istLocation;
    final todayIST = tz.TZDateTime(ist, _selectedDate.year, _selectedDate.month, _selectedDate.day);
    DateTime windowStart;
    if (todayIST.weekday == DateTime.monday) {
      // If selected date is Monday, interval is Saturday 12 PM to Monday 12 PM
      final saturday = todayIST.subtract(const Duration(days: 2));
      windowStart = tz.TZDateTime(ist, saturday.year, saturday.month, saturday.day, 12);
    } else {
      // Otherwise, interval is previous day 12 PM to selected date 12 PM
      final yesterday = todayIST.subtract(const Duration(days: 1));
      windowStart = tz.TZDateTime(ist, yesterday.year, yesterday.month, yesterday.day, 12);
    }
    final windowEnd = tz.TZDateTime(ist, todayIST.year, todayIST.month, todayIST.day, 12);

    // Batch fetch follow_ups and todos created in the window
    final results = await Future.wait([
      FirebaseFirestore.instance
          .collection('follow_ups')
          .where('created_at', isGreaterThanOrEqualTo: Timestamp.fromDate(windowStart))
          .where('created_at', isLessThan: Timestamp.fromDate(windowEnd))
          .get(),
      FirebaseFirestore.instance
          .collection('todo')
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(windowStart))
          .where('timestamp', isLessThan: Timestamp.fromDate(windowEnd))
          .get(),
    ]);

    final followUpsDocs = (results[0] as QuerySnapshot).docs;
    final todosDocs = (results[1] as QuerySnapshot).docs;

    final userCreatedLead = <String>{};
    for (final doc in followUpsDocs) {
      final data = doc.data() as Map<String, dynamic>;
      final createdBy = data['created_by']?.toString();
      if (createdBy != null && createdBy.isNotEmpty) {
        userCreatedLead.add(createdBy);
      }
      final email = data['email']?.toString().trim().toLowerCase();
      if (email != null && email.isNotEmpty) {
        userCreatedLead.add(email);
      }
    }

    final userCreatedTodo = <String>{};
    for (final doc in todosDocs) {
      final data = doc.data() as Map<String, dynamic>;
      final createdBy = data['created_by']?.toString();
      if (createdBy != null && createdBy.isNotEmpty) {
        userCreatedTodo.add(createdBy);
      }
      final email = data['email']?.toString().trim().toLowerCase();
      if (email != null && email.isNotEmpty) {
        userCreatedTodo.add(email);
      }
    }

    for (var user in users) {
      final uid = user['uid']?.toString() ?? '';
      final email = (user['email']?.toString() ?? '').trim().toLowerCase();
      user['lead'] = userCreatedLead.contains(uid) || (email.isNotEmpty && userCreatedLead.contains(email));
      user['todo'] = userCreatedTodo.contains(uid) || (email.isNotEmpty && userCreatedTodo.contains(email));
    }

    return users;
  }

  // Fetch both managers and assistant managers and merge them (no duplicates).
  // ignore: unused_element
  Future<List<Map<String, dynamic>>> _fetchManagersAndAsst() async {
    final managers = await _fetchUsersAndLeads(role: 'manager');
    final assts = await _fetchUsersAndLeads(role: 'asst_manager');
    final Map<String, Map<String, dynamic>> merged = {};
    for (var u in managers) {
      merged[u['uid'] as String] = u;
    }
    for (var u in assts) {
      merged[u['uid'] as String] = u;
    }
    return merged.values.toList();
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
          if (_role == 'admin' || _role == 'Sync Head' || _role == 'sync_head')
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
          if ((_role == 'admin' || _role == 'Sync Head' || _role == 'sync_head') && _branches.isNotEmpty)
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
            child: (_role == 'admin' || _role == 'Sync Head' || _role == 'sync_head')
                ? FutureBuilder<List<Map<String, dynamic>>>(
                    future: _fetchUsersAndLeads(role: 'sales'),
                    builder: (context, salesSnapshot) {
                      if (!salesSnapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final salesUsers = salesSnapshot.data!;
                      return FutureBuilder<List<dynamic>>(
                        future: Future.wait([
                          _fetchUsersAndLeads(role: 'asst_manager'),
                          _fetchUsersAndLeads(role: 'manager'),
                        ]),
                        builder: (context, managerSnapshot) {
                          if (!managerSnapshot.hasData) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          final asstUsers = managerSnapshot.data![0] as List<Map<String, dynamic>>;
                          final managerUsers = managerSnapshot.data![1] as List<Map<String, dynamic>>;
                          if (salesUsers.isEmpty && asstUsers.isEmpty && managerUsers.isEmpty) {
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
                              if (asstUsers.isNotEmpty) ...[
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  child: Text('Asst Manager', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                ),
                                ...asstUsers.map((user) => ListTile(
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
                : (_role == 'manager'
                    ? FutureBuilder<List<dynamic>>(
                        future: Future.wait([
                          _fetchUsersAndLeads(role: 'sales'),
                          _fetchUsersAndLeads(role: 'asst_manager'),
                        ]),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          final salesUsers = snapshot.data![0] as List<Map<String, dynamic>>;
                          final asstUsers = snapshot.data![1] as List<Map<String, dynamic>>;
                          if (salesUsers.isEmpty && asstUsers.isEmpty) {
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
                              if (asstUsers.isNotEmpty) ...[
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  child: Text('Asst Manager', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                ),
                                ...asstUsers.map((user) => ListTile(
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
                  )),
          ),
      ],
      ),
    );
  }
}