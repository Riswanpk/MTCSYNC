import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class DailyDashboardPage extends StatefulWidget {
  const DailyDashboardPage({super.key});

  @override
  State<DailyDashboardPage> createState() => _DailyDashboardPageState();
}

class _DailyDashboardPageState extends State<DailyDashboardPage> {
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
          .toList();
      _selectedBranch = _branches.isNotEmpty ? _branches.first : null;
    } else {
      _selectedBranch = _userBranch;
    }
    setState(() {
      _loading = false;
    });
  }

  Future<List<Map<String, dynamic>>> _fetchUsersAndLeads() async {
    if (_selectedBranch == null) return [];
    final usersSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('branch', isEqualTo: _selectedBranch)
        .where('role', isEqualTo: 'sales')
        .get();
    final users = usersSnapshot.docs
        .map((doc) => {
              'uid': doc.id,
              'username': doc['username'] ?? '',
              'email': doc['email'] ?? '',
            })
        .toList();

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final windowStart = today.subtract(const Duration(days: 1)).add(const Duration(hours: 19)); // previous day 7pm
    final windowEnd = today.add(const Duration(hours: 12)); // current day 12pm

    // Fetch daily_report for each user
    for (var user in users) {
      final email = user['email'];
      final dateStr = "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";
      final doc = await FirebaseFirestore.instance.collection('daily_report').doc('$email-$dateStr').get();
      user['lead'] = doc.data()?['lead'] ?? false;
      user['todo'] = doc.data()?['todo'] ?? false;
    }

    if (now.isAfter(windowStart) && now.isBefore(windowEnd)) {
      final dateStr = "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";
      final currentUser = FirebaseAuth.instance.currentUser;
      final userEmail = currentUser?.email ?? '';
      await FirebaseFirestore.instance.collection('daily_report').doc('$userEmail-$dateStr').set({
        'email': userEmail,
        'date': dateStr,
        'todo': true,
      }, SetOptions(merge: true));
    }

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
      ),
      body: Column(
        children: [
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
                Icon(Icons.check_circle, color: Colors.blue, size: 20),
                const SizedBox(width: 4),
                const Text('Todo', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 16),
                Icon(Icons.check_circle, color: Colors.green, size: 20),
                const SizedBox(width: 4),
                const Text('Lead', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 16),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
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
                            user['todo'] ? Icons.check_circle : Icons.cancel,
                            color: user['todo'] ? Colors.blue : Colors.red,
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            user['lead'] ? Icons.check_circle : Icons.cancel,
                            color: user['lead'] ? Colors.green : Colors.red,
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