import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Add your theme colors
const Color primaryBlue = Color(0xFF005BAC);
const Color primaryGreen = Color(0xFF8CC63F);

class InsightsPage extends StatefulWidget {
  const InsightsPage({super.key});

  @override
  State<InsightsPage> createState() => _InsightsPageState();
}

class _InsightsPageState extends State<InsightsPage> {
  String? _selectedBranch;
  List<String> _branches = [];
  String? _role;
  String? _userBranch;

  @override
  void initState() {
    super.initState();
    _fetchBranchesAndUser();
  }

  Future<void> _fetchBranchesAndUser() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(currentUser!.uid).get();
    final userData = userDoc.data() ?? {};
    final role = userData['role'] ?? 'sales';
    final userBranch = userData['branch'] ?? '';

    final usersSnapshot = await FirebaseFirestore.instance.collection('users').get();
    final branches = usersSnapshot.docs
        .map((doc) => doc['branch'] ?? '')
        .where((b) => b != null && b.toString().isNotEmpty)
        .toSet()
        .cast<String>()
        .toList();

    setState(() {
      _role = role;
      _userBranch = userBranch;
      _branches = branches;
      _selectedBranch = role == 'admin'
          ? (branches.contains(userBranch) ? userBranch : (branches.isNotEmpty ? branches.first : null))
          : userBranch;
    });
  }

  Future<Map<String, dynamic>> _getTopPerformers() async {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);

    // Fetch all users and exclude admin/manager roles, filter by branch if manager or admin selected branch
    final usersSnapshot = await FirebaseFirestore.instance.collection('users').get();
    final users = {
      for (var doc in usersSnapshot.docs)
        if ((doc['role'] ?? 'sales') != 'admin' &&
            (doc['role'] ?? 'sales') != 'manager' &&
            (
              (_role == 'manager' && (doc['branch'] ?? '') == _userBranch) ||
              (_role == 'admin' && _selectedBranch != null && (doc['branch'] ?? '') == _selectedBranch) ||
              (_role != 'admin' && _role != 'manager')
            )
        )
          doc.id: {
            'username': doc['username'] ?? '',
            'email': doc['email'] ?? '',
            'branch': doc['branch'] ?? '',
          }
    };

    // Count leads per user for current month, filter by branch if manager or admin selected branch
    Query leadsQuery = FirebaseFirestore.instance
        .collection('follow_ups')
        .where('created_at', isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart));
    if (_role == 'manager') {
      leadsQuery = leadsQuery.where('branch', isEqualTo: _userBranch);
    } else if (_role == 'admin' && _selectedBranch != null) {
      leadsQuery = leadsQuery.where('branch', isEqualTo: _selectedBranch);
    }
    final leadsSnapshot = await leadsQuery.get();

    final Map<String, int> leadsCount = {for (var uid in users.keys) uid: 0};
    for (var doc in leadsSnapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final createdBy = data['created_by'] ?? '';
      if (createdBy != '' && leadsCount.containsKey(createdBy)) {
        leadsCount[createdBy] = (leadsCount[createdBy] ?? 0) + 1;
      }
    }

    // Find user with most and least leads
    String topLeadUserId = '';
    int topLeadCount = -1;
    String worstLeadUserId = '';
    int worstLeadCount = 1 << 30; // Large number

    leadsCount.forEach((uid, count) {
      if (count > topLeadCount) {
        topLeadUserId = uid;
        topLeadCount = count;
      }
      if (count < worstLeadCount) {
        worstLeadUserId = uid;
        worstLeadCount = count;
      }
    });

    // Count todos per user for current month, filter by branch if manager or admin selected branch
    Query todosQuery = FirebaseFirestore.instance
        .collection('todo')
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart));
    if (_role == 'manager') {
      // Only include todos created by users in the manager's branch
      final branchUserIds = users.entries
          .where((e) => e.value['branch'] == _userBranch)
          .map((e) => e.key)
          .toList();
      if (branchUserIds.isNotEmpty) {
        todosQuery = todosQuery.where('created_by', whereIn: branchUserIds.length > 10
            ? branchUserIds.sublist(0, 10) // Firestore whereIn max 10
            : branchUserIds);
      } else {
        // No users in branch, so no todos
        return {
          'topLead': {'username': 'N/A', 'count': 0},
          'worstLead': {'username': 'N/A', 'count': 0},
          'topTodo': {'username': 'N/A', 'count': 0},
          'worstTodo': {'username': 'N/A', 'count': 0},
        };
      }
    } else if (_role == 'admin' && _selectedBranch != null) {
      final branchUserIds = users.entries
          .where((e) => e.value['branch'] == _selectedBranch)
          .map((e) => e.key)
          .toList();
      if (branchUserIds.isNotEmpty) {
        todosQuery = todosQuery.where('created_by', whereIn: branchUserIds.length > 10
            ? branchUserIds.sublist(0, 10)
            : branchUserIds);
      } else {
        return {
          'topLead': {'username': 'N/A', 'count': 0},
          'worstLead': {'username': 'N/A', 'count': 0},
          'topTodo': {'username': 'N/A', 'count': 0},
          'worstTodo': {'username': 'N/A', 'count': 0},
        };
      }
    }
    final todosSnapshot = await todosQuery.get();

    final Map<String, int> todosCount = {for (var uid in users.keys) uid: 0};
    for (var doc in todosSnapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final createdBy = data['created_by'] ?? '';
      if (createdBy != '' && todosCount.containsKey(createdBy)) {
        todosCount[createdBy] = (todosCount[createdBy] ?? 0) + 1;
      }
    }

    // Find user with most and least todos
    String topTodoUserId = '';
    int topTodoCount = -1;
    String worstTodoUserId = '';
    int worstTodoCount = 1 << 30;

    todosCount.forEach((uid, count) {
      if (count > topTodoCount) {
        topTodoUserId = uid;
        topTodoCount = count;
      }
      if (count < worstTodoCount) {
        worstTodoUserId = uid;
        worstTodoCount = count;
      }
    });

    return {
      'topLead': {
        'username': users[topLeadUserId]?['username'] ?? 'N/A',
        'count': topLeadCount,
      },
      'worstLead': {
        'username': users[worstLeadUserId]?['username'] ?? 'N/A',
        'count': worstLeadCount,
      },
      'topTodo': {
        'username': users[topTodoUserId]?['username'] ?? 'N/A',
        'count': topTodoCount,
      },
      'worstTodo': {
        'username': users[worstTodoUserId]?['username'] ?? 'N/A',
        'count': worstTodoCount,
      }
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Insights'),
      ),
      body: _role == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_role == 'admin')
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    child: DropdownButtonFormField<String>(
                      value: _selectedBranch,
                      items: _branches
                          .map((b) => DropdownMenuItem(
                                value: b,
                                child: Text(b),
                              ))
                          .toList(),
                      onChanged: (val) {
                        setState(() {
                          _selectedBranch = val;
                        });
                      },
                      decoration: const InputDecoration(
                        labelText: "Select Branch",
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    ),
                  ),
                Expanded(
                  child: FutureBuilder<Map<String, dynamic>>(
                    future: _getTopPerformers(),
                    builder: (context, snapshot) {
                      final isLoading = snapshot.connectionState == ConnectionState.waiting;
                      final topLead = snapshot.data?['topLead'];
                      final worstLead = snapshot.data?['worstLead'];
                      final topTodo = snapshot.data?['topTodo'];
                      final worstTodo = snapshot.data?['worstTodo'];

                      return Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Top Performers (Current Month)",
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 24),
                            Card(
                              child: ListTile(
                                leading: const Icon(Icons.emoji_events, color: Colors.amber),
                                title: const Text("Most Leads Created"),
                                subtitle: isLoading
                                    ? const Text("Loading...")
                                    : Text(
                                        "Username: ${topLead?['username'] ?? 'N/A'}\nLeads: ${topLead?['count'] ?? 0}",
                                      ),
                              ),
                            ),
                            Card(
                              child: ListTile(
                                leading: const Icon(Icons.emoji_events_outlined, color: Colors.redAccent),
                                title: const Text("Least Leads Created"),
                                subtitle: isLoading
                                    ? const Text("Loading...")
                                    : Text(
                                        "Username: ${worstLead?['username'] ?? 'N/A'}\nLeads: ${worstLead?['count'] ?? 0}",
                                      ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Card(
                              child: ListTile(
                                leading: const Icon(Icons.check_circle, color: Colors.blue),
                                title: const Text("Most Todos Created"),
                                subtitle: isLoading
                                    ? const Text("Loading...")
                                    : Text(
                                        "Username: ${topTodo?['username'] ?? 'N/A'}\nTodos: ${topTodo?['count'] ?? 0}",
                                      ),
                              ),
                            ),
                            Card(
                              child: ListTile(
                                leading: const Icon(Icons.remove_circle_outline, color: Colors.redAccent),
                                title: const Text("Least Todos Created"),
                                subtitle: isLoading
                                    ? const Text("Loading...")
                                    : Text(
                                        "Username: ${worstTodo?['username'] ?? 'N/A'}\nTodos: ${worstTodo?['count'] ?? 0}",
                                      ),
                              ),
                            ),
                            const SizedBox(height: 32),
                            const Text(
                              "More insights coming soon...",
                              style: TextStyle(color: Colors.grey),
                            ),
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