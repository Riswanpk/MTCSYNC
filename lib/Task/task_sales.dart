import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:intl/intl.dart';
import '../Navigation/user_cache_service.dart';

/// Top-level function to synchronize local reminders at 9 AM daily for active tasks.
Future<void> syncTaskReminders(String userId) async {
  try {
    final snapshot = await FirebaseFirestore.instance
        .collection('core_tasks')
        .where('assigned_to', isEqualTo: userId)
        .get();

    final tz = await AwesomeNotifications().getLocalTimeZoneIdentifier();

    for (var doc in snapshot.docs) {
      final data = doc.data();
      final String status = data['status'] ?? 'pending';
      final String title = data['title'] ?? 'Task';
      final int notifId = doc.id.hashCode & 0x7FFFFFFF;

      if (status == 'pending') {
        // Schedule recurring daily reminder at 9:00 AM
        await AwesomeNotifications().createNotification(
          content: NotificationContent(
            id: notifId,
            channelKey: 'reminder_channel',
            title: 'Daily Task Reminder',
            body: 'Pending task: "$title"',
            notificationLayout: NotificationLayout.Default,
            payload: {
              'type': 'core_task',
              'docId': doc.id,
            },
          ),
          schedule: NotificationCalendar(
            hour: 9,
            minute: 0,
            second: 0,
            millisecond: 0,
            timeZone: tz,
            repeats: true,
            preciseAlarm: true,
          ),
        );
      } else {
        // If task is completed, ensure any scheduled reminder is cancelled
        await AwesomeNotifications().cancel(notifId);
      }
    }
  } catch (e) {
    debugPrint('Error syncing task reminders: $e');
  }
}

class UserTaskPage extends StatefulWidget {
  const UserTaskPage({super.key});

  @override
  State<UserTaskPage> createState() => _UserTaskPageState();
}

class _UserTaskPageState extends State<UserTaskPage> {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final Map<String, TextEditingController> _noteControllers = {};

  @override
  void initState() {
    super.initState();
    _triggerSync();
  }

  @override
  void dispose() {
    for (final controller in _noteControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _triggerSync() async {
    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      await syncTaskReminders(uid);
    }
  }

  TextEditingController _getControllerForTask(String docId) {
    if (!_noteControllers.containsKey(docId)) {
      _noteControllers[docId] = TextEditingController();
    }
    return _noteControllers[docId]!;
  }

  Future<void> _completeTask(String docId, String title, String assignedByUid) async {
    final noteController = _getControllerForTask(docId);
    final note = noteController.text.trim();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Complete Task?'),
        content: const Text('Are you sure you want to mark this task as completed?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.green),
            child: const Text('Complete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) throw Exception('No authenticated user');

      final userCache = UserCacheService.instance;
      await userCache.ensureLoaded();
      final currentUsername = userCache.username ?? currentUser.email ?? 'User';

      // 1. Update Firestore status to completed
      await _firestore.collection('core_tasks').doc(docId).update({
        'status': 'completed',
        'note': note,
        'completed_at': FieldValue.serverTimestamp(),
      });

      // 2. Cancel the 9 AM local daily reminder notification
      final notifId = docId.hashCode & 0x7FFFFFFF;
      await AwesomeNotifications().cancel(notifId);

      // 3. Send Completion FCM Notification to Core Team member
      FirebaseFunctions.instanceFor(region: 'asia-south1')
          .httpsCallable('sendLeadAssignmentNotification')
          .call(<String, dynamic>{
        'recipientUid': assignedByUid,
        'title': 'Task Completed',
        'body': '$currentUsername completed the task: "$title"',
        'notifType': 'core_task_completion',
        'leadDocId': docId,
      }).catchError((error) {
        debugPrint('FCM Warning: failed to send task completion notification: $error');
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Task marked as completed successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        _noteControllers.remove(docId)?.dispose();
        setState(() {});
      }
    } catch (e) {
      debugPrint('Error completing task: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to complete task: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final uid = _auth.currentUser?.uid;

    if (uid == null) {
      return const Scaffold(
        body: Center(child: Text('User not authenticated')),
      );
    }

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A1628) : const Color(0xFFF6F7FB),
      appBar: AppBar(
        title: const Text('My Tasks'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF005BAC), Color(0xFF8CC63F)],
            ),
          ),
        ),
        foregroundColor: Colors.white,
        elevation: 4,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore
            .collection('core_tasks')
            .where('assigned_to', isEqualTo: uid)
            .where('status', isEqualTo: 'pending')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.assignment_turned_in_rounded,
                    size: 64,
                    color: isDark ? Colors.white24 : Colors.black26,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No pending tasks assigned to you!',
                    style: TextStyle(
                      fontSize: 16,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                  ),
                ],
              ),
            );
          }

          // Sort local side by timestamp
          final sortedDocs = docs.toList()
            ..sort((a, b) {
              final tsA = a['timestamp'] as Timestamp?;
              final tsB = b['timestamp'] as Timestamp?;
              if (tsA == null) return 1;
              if (tsB == null) return -1;
              return tsB.compareTo(tsA);
            });

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: sortedDocs.length,
            itemBuilder: (context, index) {
              final doc = sortedDocs[index];
              final data = doc.data() as Map<String, dynamic>;
              final String docId = doc.id;
              final String title = data['title'] ?? '';
              final String assignedByName = data['assigned_by_name'] ?? 'Core Team';
              final String assignedByUid = data['assigned_by'] ?? '';
              final Timestamp? createdTs = data['timestamp'] as Timestamp?;
              final String createdDateStr = createdTs != null
                  ? DateFormat('dd MMM yyyy, hh:mm a').format(createdTs.toDate())
                  : 'N/A';

              final noteController = _getControllerForTask(docId);

              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                color: isDark ? const Color(0xFF16253B) : Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        children: [
                          Icon(Icons.assignment_late_rounded, color: Colors.orange[400], size: 22),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Assigned by: $assignedByName',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: isDark ? Colors.white70 : Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      // Task Title
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Assigned: $createdDateStr',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Note Field
                      TextField(
                        controller: noteController,
                        decoration: InputDecoration(
                          hintText: 'Add a completion note (optional)...',
                          hintStyle: TextStyle(color: isDark ? Colors.white30 : Colors.black38),
                          filled: true,
                          fillColor: isDark ? const Color(0xFF0F1A2B) : const Color(0xFFF3F4F6),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        style: TextStyle(fontSize: 13, color: isDark ? Colors.white : Colors.black87),
                      ),
                      const SizedBox(height: 16),
                      // Complete Button
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: ElevatedButton.icon(
                          onPressed: () => _completeTask(docId, title, assignedByUid),
                          icon: const Icon(Icons.check_circle_outline_rounded, color: Colors.white, size: 18),
                          label: const Text(
                            'Complete Task',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF8CC63F),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            elevation: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
