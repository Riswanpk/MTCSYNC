import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../Misc/user_cache_service.dart';
import 'todo_widgets.dart';

/// Builds the pending or completed todo list for a user.
class TodoListBody extends StatelessWidget {
  final String status;
  final bool onlySelf;
  final String? userEmail;
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final Future<void> Function(DocumentSnapshot doc) onToggleStatus;
  final Future<void> Function(String docId) onDelete;
  final Future<String> Function(String email) getUsernameByEmail;

  const TodoListBody({
    Key? key,
    required this.status,
    this.onlySelf = false,
    required this.userEmail,
    required this.firestore,
    required this.auth,
    required this.onToggleStatus,
    required this.onDelete,
    required this.getUsernameByEmail,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (userEmail == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final user = auth.currentUser;
    if (user == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return FutureBuilder<void>(
      future: UserCacheService.instance.ensureLoaded(),
      builder: (context, userSnapshot) {
        if (userSnapshot.connectionState == ConnectionState.waiting)
          return const Center(child: CircularProgressIndicator());
        final role = UserCacheService.instance.role;

        return StreamBuilder<QuerySnapshot>(
          stream: firestore
              .collection('todo')
              .where('email', isEqualTo: userEmail)
              .where('status', isEqualTo: status)
              .orderBy('timestamp', descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError)
              return const Center(child: Text('Error loading todos'));
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final todos = snapshot.data?.docs ?? [];

            if (todos.isEmpty) {
              return Center(
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        status == 'pending'
                            ? Icons.check_circle_outline_rounded
                            : Icons.celebration_rounded,
                        size: 64,
                        color: primaryGreen.withOpacity(0.5),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        status == 'pending'
                            ? 'No pending tasks'
                            : 'No completed tasks',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                          color: primaryGreen,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        status == 'pending'
                            ? 'All caught up!'
                            : 'Complete tasks to see them here',
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              itemCount: todos.length,
              itemBuilder: (context, index) {
                final doc = todos[index];
                final data = doc.data() as Map<String, dynamic>;

                return TodoListItem(
                  doc: doc,
                  data: data,
                  onToggleStatus: onToggleStatus,
                  onDelete: onDelete,
                  getUsernameByEmail: getUsernameByEmail,
                );
              },
            );
          },
        );
      },
    );
  }
}
