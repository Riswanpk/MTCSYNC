import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

Future<void> updateTodoWidgetFromFirestore() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  // Sync local phone notifications for todos
  syncAllTodoLocalNotifications().catchError((e) {
    debugPrint('Failed to sync todo local notifications: $e');
  });

  // --- Todos ---
  final todoSnapshot = await FirebaseFirestore.instance
      .collection('todo')
      .where('email', isEqualTo: user.email)
      .where('status', isEqualTo: 'pending')
      .limit(20)
      .get();

  final todoCount = todoSnapshot.docs.isNotEmpty
      ? '${todoSnapshot.docs.length} tasks'
      : '0 tasks';

  final todoItems = todoSnapshot.docs
      .map((doc) => '${doc.id}|||${doc['title'] as String}')
      .join('\n\n\n');

  await HomeWidget.saveWidgetData<String>('todo_count', todoCount);
  await HomeWidget.saveWidgetData<String>(
    'todo_items',
    todoSnapshot.docs.isNotEmpty ? todoItems : null,
  );

  // --- Today's Leads ---
  final now = DateTime.now();
  final todayStr =
      '${now.day.toString().padLeft(2, '0')}-${now.month.toString().padLeft(2, '0')}-${now.year}';

  final leadsSnapshot = await FirebaseFirestore.instance
      .collection('follow_ups')
      .where('created_by', isEqualTo: user.uid)
      .limit(200)
      .get();

  final todayLeads = leadsSnapshot.docs.where((doc) {
    final data = doc.data();
    final reminder = data['reminder'] as String? ?? '';
    final status = data['status'] as String? ?? '';
    if (status == 'Sale' || status == 'Cancelled') return false;
    return reminder.startsWith(todayStr);
  }).toList();

  final leadsCount =
      todayLeads.isNotEmpty ? '${todayLeads.length} leads' : '0 leads';

  final leadsItems = todayLeads
      .map((doc) => '${doc.id}|||${doc.data()['name'] as String? ?? 'Unknown'}')
      .join('\n\n\n');

  await HomeWidget.saveWidgetData<String>('leads_today_count', leadsCount);
  await HomeWidget.saveWidgetData<String>(
    'leads_today_items',
    todayLeads.isNotEmpty ? leadsItems : null,
  );

  await HomeWidget.updateWidget(
    name: 'TodoWidgetProvider',
    iOSName: 'TodoWidgetProvider',
  );
}

/// Checks all pending todos for the logged-in user in Firestore and ensures 
/// local AwesomeNotifications are scheduled on the device for future reminders, 
/// or immediately triggered for past/due postponed reminders missed during cold boot or when phone was off.
Future<void> syncAllTodoLocalNotifications() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  try {
    final pendingTodosSnapshot = await FirebaseFirestore.instance
        .collection('todo')
        .where('email', isEqualTo: user.email)
        .where('status', isEqualTo: 'pending')
        .limit(50)
        .get();

    final now = DateTime.now();
    final tz = await AwesomeNotifications().getLocalTimeZoneIdentifier();

    for (var doc in pendingTodosSnapshot.docs) {
      final data = doc.data();
      final title = data['title'] as String? ?? 'Task';
      final reminderData = data['reminder'];
      final reminderSent = data['reminder_sent'] as bool? ?? false;
      final notifId = doc.id.hashCode & 0x7FFFFFFF;

      DateTime? reminderDate;
      if (reminderData is Timestamp) {
        reminderDate = reminderData.toDate();
      } else if (reminderData is String) {
        reminderDate = DateTime.tryParse(reminderData);
      }

      if (reminderDate == null) continue;

      if (reminderDate.isAfter(now)) {
        // Scheduled in the FUTURE — ensure local notification is registered in AwesomeNotifications
        await AwesomeNotifications().createNotification(
          content: NotificationContent(
            id: notifId,
            channelKey: 'reminder_channel',
            title: 'To-Do Reminder',
            body: 'Reminder: $title',
            notificationLayout: NotificationLayout.Default,
            payload: {
              'type': 'todo',
              'docId': doc.id,
            },
          ),
          schedule: NotificationCalendar(
            year: reminderDate.year,
            month: reminderDate.month,
            day: reminderDate.day,
            hour: reminderDate.hour,
            minute: reminderDate.minute,
            second: 0,
            millisecond: 0,
            timeZone: tz,
            repeats: false,
            preciseAlarm: true,
            allowWhileIdle: true,
          ),
        );
      } else if (!reminderSent) {
        // Reminder time has already passed; update Firestore flag quietly so we don't trigger duplicate notifications
        await doc.reference.update({'reminder_sent': true});
      }
    }
  } catch (e) {
    debugPrint('Error syncing todo local notifications: $e');
  }
}

