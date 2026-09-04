import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../Misc/notification_permission_service.dart';

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
        try {
          // Schedule recurring daily reminder at 9:00 AM
          await NotificationPermissionService.instance.safeCreateNotification(
            content: NotificationContent(
              id: notifId,
              channelKey: 'todo_reminder_channel',
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
        } catch (e) {
          debugPrint('Warning: Failed to schedule task reminder: $e');
        }
      } else {
        try {
          // If task is completed, ensure any scheduled reminder is cancelled
          await AwesomeNotifications().cancel(notifId);
        } catch (e) {
          debugPrint('Warning: Failed to cancel task reminder: $e');
        }
      }
    }
  } catch (e) {
    debugPrint('Error syncing task reminders: $e');
  }
}
