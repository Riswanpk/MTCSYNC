import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'todoform.dart';
import '../Misc/user_cache_service.dart';
import 'todo_widgets.dart';

/// Full-screen task detail page.
class TaskDetailPage extends StatelessWidget {
  final Map<String, dynamic> data;
  final String dateStr;

  const TaskDetailPage({
    Key? key,
    required this.data,
    required this.dateStr,
  }) : super(key: key);

  bool get isAssignedByManager => data['assigned_by_name'] != null;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final priority = data['priority'] ?? 'High';

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF181A20) : const Color(0xFFF6F7FB),
      appBar: AppBar(
        title: const Text('Task Details'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          FutureBuilder<void>(
            future: UserCacheService.instance.ensureLoaded(),
            builder: (context, userSnapshot) {
              if (userSnapshot.connectionState == ConnectionState.waiting) return const SizedBox.shrink();

              final currentUserRole = UserCacheService.instance.role;
              final currentUserId = FirebaseAuth.instance.currentUser!.uid;

              // Conditions to show the edit button:
              // 1. User is a manager AND they are the one who assigned the task.
              // 2. The task was NOT assigned by a manager (i.e., it's a self-created task).
              final bool canEdit = (currentUserRole == 'manager' &&
                      data['assigned_by'] == currentUserId) ||
                  !isAssignedByManager;

              return Row(
                children: [
                  if (canEdit)
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.white),
                      tooltip: 'Edit Task',
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) =>
                                  TodoFormPage(docId: data['docId'])),
                        );
                      },
                    ),
                  if (data['status'] != 'done')
                    Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: TextButton(
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Mark as Done?'),
                              content: const Text(
                                  'Are you sure you want to mark this task as done?'),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(false),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(true),
                                  child: const Text('Yes',
                                      style: TextStyle(color: Colors.green)),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true && data['docId'] != null) {
                            await FirebaseFirestore.instance
                                .collection('todo')
                                .doc(data['docId'])
                                .update({
                              'status': 'done',
                              'timestamp': Timestamp.now(),
                            });
                            // Optionally pop back to the list page
                            if (Navigator.canPop(context)) {
                              Navigator.pop(context);
                            }
                          }
                        },
                        child: const Text('DONE',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                ],
              );
            },
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            Text(
              data['title'] ?? '',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 12),
            // Date
            Row(
              children: [
                Icon(Icons.calendar_today,
                    size: 18, color: isDark ? Colors.white70 : Colors.black54),
                const SizedBox(width: 8),
                Text(
                  dateStr,
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black54,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            // Priority
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: getPriorityBgColor(priority, isDark),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.flag, color: getPriorityColor(priority), size: 18),
                  const SizedBox(width: 8),
                  Text(
                    priority,
                    style: TextStyle(
                      color: getPriorityColor(priority),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Description
            Text(
              'Description',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              data['description'] ?? '',
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black87,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 24),
            // Status
            Row(
              children: [
                Icon(
                  data['status'] == 'done'
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  color:
                      data['status'] == 'done' ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 8),
                Text(
                  data['status'] == 'done' ? 'Completed' : 'Pending',
                  style: TextStyle(
                    color:
                        data['status'] == 'done' ? Colors.green : Colors.orange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Loads a task detail page by document ID.
class TaskDetailPageFromId extends StatelessWidget {
  final String docId;
  const TaskDetailPageFromId({Key? key, required this.docId}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('todo').doc(docId).get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        final data = snapshot.data!.data() as Map<String, dynamic>?;
        if (data == null) {
          return const Scaffold(body: Center(child: Text('Task not found')));
        }
        // Add docId to data map for TaskDetailPage
        data['docId'] = docId;

        final reminderData = data['reminder'];
        DateTime? reminderDateTime;
        if (reminderData is Timestamp) {
          reminderDateTime = reminderData.toDate();
        } else if (reminderData is String) {
          reminderDateTime = DateTime.tryParse(reminderData);
        }
        String dateStr = '';
        if (reminderDateTime != null) {
          dateStr = reminderDateTime.toLocal().toString().split(' ')[0];
        }
        return TaskDetailPage(data: data, dateStr: dateStr);
      },
    );
  }
}
