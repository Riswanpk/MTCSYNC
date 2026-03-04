import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'todo_widgets.dart';
import 'todoform.dart' show getCurrentISTWindow;

/// The "Others" tab – shows todos created by other branch users
/// within the current 12 PM–12 PM IST window.
class SalesTodosForManagerTab extends StatefulWidget {
  final String? userEmail;
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final Future<String> Function(String email) getUsernameByEmail;

  const SalesTodosForManagerTab({
    Key? key,
    required this.userEmail,
    required this.firestore,
    required this.auth,
    required this.getUsernameByEmail,
  }) : super(key: key);

  @override
  State<SalesTodosForManagerTab> createState() =>
      _SalesTodosForManagerTabState();
}

class _SalesTodosForManagerTabState extends State<SalesTodosForManagerTab> {
  String? _selectedUserId; // null = 'All'
  List<Map<String, dynamic>> _branchUsers = []; // {uid, username}
  bool _initialLoading = true;
  bool _fetchingTodos = false;
  List<DocumentSnapshot> _todos = [];

  @override
  void initState() {
    super.initState();
    _loadBranchUsers();
  }

  Future<void> _loadBranchUsers() async {
    final currentUid = widget.auth.currentUser?.uid;
    if (currentUid == null) return;

    final userDoc =
        await widget.firestore.collection('users').doc(currentUid).get();
    final branch = userDoc.data()?['branch'];
    if (branch == null) {
      setState(() => _initialLoading = false);
      return;
    }

    final usersSnap = await widget.firestore
        .collection('users')
        .where('branch', isEqualTo: branch)
        .get();

    final branchUsers = usersSnap.docs
        .where((doc) => doc.id != currentUid)
        .map((doc) => {
              'uid': doc.id as String,
              'username': (doc.data()['username'] ??
                      doc.data()['email'] ??
                      'Unknown') as String,
            })
        .toList();

    setState(() {
      _branchUsers = branchUsers;
      _initialLoading = false;
    });

    await _fetchTodos();
  }

  Future<void> _fetchTodos() async {
    if (_branchUsers.isEmpty) {
      setState(() => _todos = []);
      return;
    }

    setState(() => _fetchingTodos = true);

    final window = getCurrentISTWindow();
    final windowStart = window[0];
    final windowEnd = window[1];

    final List<String> uids = _selectedUserId == null
        ? _branchUsers.map((u) => u['uid'] as String).toList()
        : [_selectedUserId!];

    // Firestore whereIn max = 10
    final queryUids = uids.take(10).toList();

    final snap = await widget.firestore
        .collection('todo')
        .where('created_by', whereIn: queryUids)
        .where('timestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(windowStart))
        .where('timestamp', isLessThan: Timestamp.fromDate(windowEnd))
        .orderBy('timestamp', descending: true)
        .get();

    setState(() {
      _todos = snap.docs;
      _fetchingTodos = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_initialLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_branchUsers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_search_rounded,
                size: 64, color: primaryBlue.withOpacity(0.5)),
            const SizedBox(height: 16),
            Text(
              'No team members found',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: primaryBlue),
            ),
          ],
        ),
      );
    }

    final usernames = [
      {'uid': null, 'username': 'All'},
      ..._branchUsers,
    ];

    return Column(
      children: [
        // Filter dropdown
        Padding(
          padding: const EdgeInsets.all(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: primaryBlue.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: primaryBlue.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                Icon(Icons.filter_list_rounded,
                    color: primaryBlue, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Filter:',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: primaryBlue,
                      fontSize: 14),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButton<String?>(
                    value: _selectedUserId,
                    isExpanded: true,
                    underline: const SizedBox(),
                    items: usernames
                        .map((u) => DropdownMenuItem<String?>(
                              value: u['uid'] as String?,
                              child: Text(u['username'] as String),
                            ))
                        .toList(),
                    onChanged: (val) {
                      setState(() => _selectedUserId = val);
                      _fetchTodos();
                    },
                  ),
                ),
              ],
            ),
          ),
        ),

        // List
        Expanded(
          child: _fetchingTodos
              ? const Center(child: CircularProgressIndicator())
              : _todos.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.people_outline_rounded,
                              size: 64,
                              color: primaryGreen.withOpacity(0.5)),
                          const SizedBox(height: 16),
                          Text(
                            'No tasks from others this period',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: primaryGreen),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _fetchTodos,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        itemCount: _todos.length,
                        itemBuilder: (context, index) {
                          final doc = _todos[index];
                          final data = doc.data() as Map<String, dynamic>;
                          return TodoListItemReadOnly(
                            doc: doc,
                            data: data,
                            getUsernameByEmail: widget.getUsernameByEmail,
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }
}
