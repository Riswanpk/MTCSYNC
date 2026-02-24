import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'task_detail_widgets.dart';
import 'todoform.dart';

const Color primaryBlue = Color(0xFF005BAC);
const Color primaryGreen = Color(0xFF8CC63F);

/// Returns the priority indicator color.
Color getPriorityColor(String priority) {
  switch (priority) {
    case 'High':
      return Colors.red;
    case 'Medium':
      return Colors.amber;
    case 'Low':
      return Colors.green;
    default:
      return Colors.grey;
  }
}

/// Returns the priority background color based on theme brightness.
Color getPriorityBgColor(String priority, bool isDark) {
  if (isDark) {
    switch (priority) {
      case 'High':
        return const Color(0xFF3B2323);
      case 'Medium':
        return const Color(0xFF39321A);
      case 'Low':
        return const Color(0xFF1B3223);
      default:
        return Colors.grey.shade800;
    }
  } else {
    switch (priority) {
      case 'High':
        return const Color(0xFFFFEBEE);
      case 'Medium':
        return const Color(0xFFFFF8E1);
      case 'Low':
        return const Color(0xFFE8F5E9);
      default:
        return Colors.grey.shade100;
    }
  }
}

/// A reusable todo list item card with slidable actions.
class TodoListItem extends StatelessWidget {
  final DocumentSnapshot doc;
  final Map<String, dynamic> data;
  final Future<void> Function(DocumentSnapshot doc) onToggleStatus;
  final Future<void> Function(String docId) onDelete;
  final Future<String> Function(String email) getUsernameByEmail;
  final bool showSlidableActions;

  const TodoListItem({
    Key? key,
    required this.doc,
    required this.data,
    required this.onToggleStatus,
    required this.onDelete,
    required this.getUsernameByEmail,
    this.showSlidableActions = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final title = data['title'] ?? 'No title';
    final description = data['description'] ?? '';
    final priority = data['priority'] ?? 'High';
    final reminderData = data['reminder'];
    DateTime? reminderDateTime;
    if (reminderData is Timestamp) {
      reminderDateTime = reminderData.toDate();
    } else if (reminderData is String) {
      reminderDateTime = DateTime.tryParse(reminderData);
    }
    final timeStr = reminderDateTime != null
        ? TimeOfDay.fromDateTime(reminderDateTime.toLocal()).format(context)
        : 'No reminder';

    final priorityColor = getPriorityColor(priority);
    final priorityBgColor = getPriorityBgColor(priority, isDark);

    final child = Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: priorityBgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: priorityColor.withOpacity(0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: priorityColor.withOpacity(0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
            spreadRadius: 0,
          ),
          BoxShadow(
            color: isDark 
                ? Colors.black.withOpacity(0.3)
                : Colors.white.withOpacity(0.8),
            blurRadius: 6,
            offset: const Offset(0, -2),
            spreadRadius: 0,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => TaskDetailPage(
                  data: {
                    ...data,
                    'docId': doc.id,
                  },
                  dateStr: reminderDateTime != null
                      ? reminderDateTime.toString()
                      : '',
                ),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 60,
                  decoration: BoxDecoration(
                    color: priorityColor,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: priorityColor.withOpacity(0.4),
                        blurRadius: 4,
                        spreadRadius: 0,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: data['status'] == 'done'
                              ? Theme.of(context).disabledColor
                              : Theme.of(context).textTheme.bodyLarge?.color,
                          decoration: data['status'] == 'done'
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.access_time_rounded,
                            size: 14,
                            color: Theme.of(context).hintColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            timeStr,
                            style: TextStyle(
                              color: Theme.of(context).hintColor,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      if (description.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          description,
                          style: TextStyle(
                            color: Theme.of(context).textTheme.bodySmall?.color,
                            fontSize: 13,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (!showSlidableActions) {
      return child;
    }

    return Slidable(
      key: ValueKey(doc.id),
      startActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.28,
        children: [
          SlidableAction(
            onPressed: (context) async {
              await onToggleStatus(doc);
            },
            backgroundColor: Colors.green.shade400,
            foregroundColor: Colors.white,
            icon: Icons.check_circle,
            label: 'Done',
            borderRadius: BorderRadius.circular(16),
          ),
        ],
      ),
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.25,
        children: [
          SlidableAction(
            onPressed: (context) async {
              // Show time picker for new reminder
              final now = DateTime.now();
              final initialTime = reminderDateTime != null
                  ? TimeOfDay.fromDateTime(reminderDateTime)
                  : TimeOfDay.fromDateTime(now);
              final pickedTime = await showTimePicker(
                context: context,
                initialTime: initialTime,
              );
              if (pickedTime != null) {
                // Use today's date or existing reminder date
                final baseDate = reminderDateTime ?? now;
                final newReminder = DateTime(
                  baseDate.year,
                  baseDate.month,
                  baseDate.day,
                  pickedTime.hour,
                  pickedTime.minute,
                );
                await FirebaseFirestore.instance
                    .collection('todo')
                    .doc(doc.id)
                    .update({'reminder': newReminder.toIso8601String()});
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Reminder time updated')),
                );
              }
            },
            backgroundColor: Colors.orange.shade400,
            foregroundColor: Colors.white,
            icon: Icons.schedule,
            label: 'Postpone',
            borderRadius: BorderRadius.circular(16),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Read-only todo item for the manager "Others" tab (no slide actions).
class TodoListItemReadOnly extends StatelessWidget {
  final DocumentSnapshot doc;
  final Map<String, dynamic> data;
  final Future<String> Function(String email) getUsernameByEmail;

  const TodoListItemReadOnly({
    Key? key,
    required this.doc,
    required this.data,
    required this.getUsernameByEmail,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return TodoListItem(
      doc: doc,
      data: data,
      onToggleStatus: (_) async {},
      onDelete: (_) async {},
      getUsernameByEmail: getUsernameByEmail,
      showSlidableActions: false,
    );
  }
}
