import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:intl/intl.dart';
import 'presentfollowup.dart';

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

Color getPriorityBackgroundColor(String priority, bool isDark) {
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

class LeadCard extends StatelessWidget {
  final String name;
  final String status;
  final dynamic date;
  final String docId;
  final String createdBy;
  final String priority;
  final String reminder;
  final VoidCallback? onStatusChanged;

  const LeadCard({
    super.key,
    required this.name,
    required this.status,
    required this.date,
    required this.docId,
    required this.createdBy,
    required this.priority,
    required this.reminder,
    this.onStatusChanged,
  });

  Future<void> _playClickSound() async {
    final player = AudioPlayer();
    await player.play(AssetSource('sounds/click.mp3'), volume: 0.5);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    String formattedDate = '';
    DateTime? parsedDate;
    if (date is Timestamp) { // Handle Firestore Timestamp
      parsedDate = date.toDate();
    } else if (date is DateTime) { // Handle DateTime object
      parsedDate = date;
    } else if (date is String && date.isNotEmpty) { // Handle String
      try {
        // Try parsing as ISO first, fallback to dd-MM-yyyy
        try {
          parsedDate = DateTime.parse(date);
        } catch (_) {
          parsedDate = DateFormat('dd-MM-yyyy').parse(date);
        }
      } catch (e) {
        parsedDate = null;
      }
    }

    if (parsedDate != null) {
      formattedDate = DateFormat('dd-MM-yyyy').format(parsedDate);
    } else {
      formattedDate = 'No Date';
    }

    String formattedReminder = reminder;
    try {
      if (reminder.isNotEmpty && reminder != 'No Reminder') {
        // Try parsing reminder as date
        DateTime? reminderDate;
        try {
          reminderDate = DateTime.parse(reminder.split(' ')[0]);
        } catch (_) {
          final parts = reminder.split(' ');
          if (parts.isNotEmpty) {
            reminderDate = DateFormat('dd-MM-yyyy').parse(parts[0]);
          }
        }
        if (reminderDate != null) {
          formattedReminder = DateFormat('dd-MM-yyyy').format(reminderDate);
        }
      }
    } catch (e) {
      // Keep original reminder string if parsing fails
    }

    return Slidable(
      key: ValueKey(docId),
      startActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.28,
        children: [
          SlidableAction(
            onPressed: (context) async {
              await FirebaseFirestore.instance
                  .collection('follow_ups')
                  .doc(docId)
                  .update({
                'status': 'Sale',
                'completed_at': FieldValue.serverTimestamp(),
              });
              onStatusChanged?.call();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Marked as Sale')),
                );
              }
            },
            backgroundColor: Colors.green.shade500,
            foregroundColor: Colors.white,
            icon: Icons.handshake_rounded,
            label: 'Sale',
            borderRadius: BorderRadius.circular(20),
          ),
        ],
      ),
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.28,
        children: [
          SlidableAction(
            onPressed: (context) async {
              await FirebaseFirestore.instance
                  .collection('follow_ups')
                  .doc(docId)
                  .update({
                'status': 'Cancelled',
                'completed_at': FieldValue.serverTimestamp(),
              });
              onStatusChanged?.call();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Marked as Cancelled')),
                );
              }
            },
            backgroundColor: Colors.red.shade400,
            foregroundColor: Colors.white,
            icon: Icons.cancel_rounded,
            label: 'Cancelled',
            borderRadius: BorderRadius.circular(20),
          ),
        ],
      ),
      child: GestureDetector(
        onTap: () async {
          await _playClickSound();
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PresentFollowUp(docId: docId),
            ),
          );
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: getPriorityBackgroundColor(priority, isDark),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: theme.shadowColor.withOpacity(isDark ? 0.2 : 0.05),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              // Priority dot
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: getPriorityColor(priority),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      text: TextSpan(
                        style: theme.textTheme.bodyLarge?.copyWith(fontSize: 16),
                        children: [
                          TextSpan(
                            text: name,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const TextSpan(text: ' '),
                          TextSpan(
                            text: '($status)',
                            style: TextStyle(color: theme.hintColor),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Date: $formattedDate',
                      style: theme.textTheme.bodySmall?.copyWith(fontSize: 13, color: theme.hintColor),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Created by: $createdBy',
                      style: theme.textTheme.bodySmall?.copyWith(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Reminder: $formattedReminder',
                      style: theme.textTheme.bodySmall?.copyWith(fontSize: 12, color: Colors.blueGrey),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
