import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'todo_widgets.dart';

/// The "Others" tab for managers – shows todos from same-branch users.
class SalesTodosForManagerTab extends StatelessWidget {
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
  Widget build(BuildContext context) {
    if (userEmail == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return FutureBuilder<DocumentSnapshot>(
      future: firestore.collection('users').doc(auth.currentUser!.uid).get(),
      builder: (context, userSnapshot) {
        if (!userSnapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        final managerBranch = userSnapshot.data!.get('branch');
        final managerEmail = userSnapshot.data!.get('email');

        return FutureBuilder<QuerySnapshot>(
          future: firestore
              .collection('users')
              .where('branch',
                  isEqualTo: managerBranch) // <-- Only users from same branch
              .get(),
          builder: (context, usersSnapshot) {
            if (!usersSnapshot.hasData)
              return const Center(child: CircularProgressIndicator());
            final salesUsers = usersSnapshot.data!.docs
                .map((doc) => {
                      'email': doc['email'] as String?,
                      'username':
                          doc['username'] as String? ?? doc['email'] as String?,
                    })
                .where((user) => user['email'] != managerEmail)
                .toList();

            if (salesUsers.isEmpty) {
              return Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.person_search_rounded,
                        size: 64,
                        color: primaryBlue.withOpacity(0.5),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No team members found',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                          color: primaryBlue,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            // Pagination variables
            const int pageSize = 10;
            int _currentPage = 0;
            String? _selectedUsername;

            return StatefulBuilder(
              builder: (context, setState) {
                // Filtering logic
                List<Map<String, String?>> filteredUsers = salesUsers;
                if (_selectedUsername != null && _selectedUsername != 'All') {
                  filteredUsers = salesUsers
                      .where((user) => user['username'] == _selectedUsername)
                      .toList();
                }

                // Get the emails for the current page
                final int start = _currentPage * pageSize;
                final int end = ((start + pageSize) > filteredUsers.length)
                    ? filteredUsers.length
                    : (start + pageSize);
                final List<String> pageEmails = filteredUsers
                    .sublist(start, end)
                    .map((u) => u['email']!)
                    .toList();

                // Username dropdown options
                final usernames = [
                  'All',
                  ...{for (var u in salesUsers) u['username'] ?? u['email']}
                ];

                return Column(
                  children: [
                    // Username filter dropdown
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: primaryBlue.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: primaryBlue.withOpacity(0.2),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.filter_list_rounded, color: primaryBlue, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Filter:',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: primaryBlue,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: DropdownButton<String>(
                                value: _selectedUsername ?? 'All',
                                isExpanded: true,
                                underline: const SizedBox(),
                                items: usernames
                                    .map((username) => DropdownMenuItem(
                                          value: username,
                                          child: Text(username ?? ''),
                                        ))
                                    .toList(),
                                onChanged: (value) {
                                  setState(() {
                                    _selectedUsername = value;
                                    _currentPage =
                                        0; // Reset to first page on filter change
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: StreamBuilder<QuerySnapshot>(
                        stream: firestore
                            .collection('todo')
                            .where('email',
                                whereIn:
                                    pageEmails.isEmpty ? ['dummy'] : pageEmails)
                            .orderBy('timestamp', descending: true)
                            .snapshots(),
                        builder: (context, todosSnapshot) {
                          if (todosSnapshot.hasError)
                            return const Center(
                                child: Text('Error loading todos'));
                          if (todosSnapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                                child: CircularProgressIndicator());
                          }
                          final todos = todosSnapshot.data?.docs ?? [];
                          if (todos.isEmpty) {
                            return Expanded(
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.people_outline_rounded,
                                      size: 64,
                                      color: primaryGreen.withOpacity(0.5),
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'No tasks from others',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w500,
                                        color: primaryGreen,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Tasks from team members will appear here',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.7),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }
                          return ListView.builder(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            itemCount: todos.length,
                            itemBuilder: (context, index) {
                              final doc = todos[index];
                              final data = doc.data() as Map<String, dynamic>;

                              return TodoListItemReadOnly(
                                doc: doc,
                                data: data,
                                getUsernameByEmail: getUsernameByEmail,
                              );
                            },
                          );
                        },
                      ),
                    ),
                    // Pagination controls
                    if (filteredUsers.length > pageSize)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: primaryBlue.withOpacity(0.05),
                          border: Border(
                            top: BorderSide(
                              color: primaryBlue.withOpacity(0.1),
                              width: 1,
                            ),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: _currentPage > 0 
                                    ? primaryBlue.withOpacity(0.1) 
                                    : Colors.grey.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: IconButton(
                                icon: const Icon(Icons.arrow_back_rounded),
                                color: _currentPage > 0 ? primaryBlue : Colors.grey,
                                onPressed: _currentPage > 0
                                    ? () => setState(() => _currentPage--)
                                    : null,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Text(
                                'Page ${_currentPage + 1} of ${((filteredUsers.length - 1) ~/ pageSize) + 1}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: primaryBlue,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            Container(
                              decoration: BoxDecoration(
                                color: end < filteredUsers.length
                                    ? primaryBlue.withOpacity(0.1) 
                                    : Colors.grey.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: IconButton(
                                icon: const Icon(Icons.arrow_forward_rounded),
                                color: end < filteredUsers.length ? primaryBlue : Colors.grey,
                                onPressed: end < filteredUsers.length
                                    ? () => setState(() => _currentPage++)
                                    : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}
