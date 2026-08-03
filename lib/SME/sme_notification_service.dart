import 'dart:async';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:mtcsync/Misc/notification_permission_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../Task/task_sales.dart' show syncTaskReminders;

/// Listens for SME lead assignment FCM messages and triggers local push
/// notifications (foreground) for the assigned user.
/// Background / terminated state messages are handled automatically by the OS.
class SmeNotificationService {
  SmeNotificationService._();
  static final SmeNotificationService instance = SmeNotificationService._();

  StreamSubscription<RemoteMessage>? _subscription;
  bool _isListening = false;

  /// Start listening for foreground FCM messages of type [sme_lead_assignment].
  /// Should be called once after login/home page init.
  void startListening() {
    if (_isListening) return;
    _isListening = true;

    _subscription = FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      final data = message.data;
      const handled = {
        'sme_lead_assignment',
        'dme_lead_assignment',
        'lead_transfer',
        'core_task_assignment',
        'core_task_completion'
      };
      if (!handled.contains(data['type'])) return;

      final title = message.notification?.title ?? data['title'] ?? 'New Notification';
      final body = message.notification?.body ?? data['body'] ?? '';
      final leadDocId = data['leadDocId'] ?? '';

      final isCoreTaskAssigned = data['type'] == 'core_task_assignment';
      final isCoreTaskCompleted = data['type'] == 'core_task_completion';

      // Show local notification so AwesomeNotifications action buttons work
      await NotificationPermissionService.instance.safeCreateNotification(
        content: NotificationContent(
          id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
          channelKey: isCoreTaskAssigned ? 'task_assignment_channel' : 'basic_channel',
          title: title,
          body: body,
          notificationLayout: NotificationLayout.Default,
          payload: {
            'docId': leadDocId,
            'type': isCoreTaskAssigned
                ? 'core_task'
                : isCoreTaskCompleted
                    ? 'core_task_complete'
                    : 'sme_lead',
          },
        ),
      );

      if (isCoreTaskAssigned) {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null) {
          await syncTaskReminders(uid);
        }
      }

      // Schedule device-side reminder if the Cloud Function forwarded one
      final reminderAtStr = data['reminderAt'];
      final leadName = data['leadName'] ?? 'Lead';
      if (reminderAtStr != null) {
        final reminderMs = int.tryParse(reminderAtStr);
        if (reminderMs != null) {
          final reminderDate = DateTime.fromMillisecondsSinceEpoch(reminderMs);
          if (reminderDate.isAfter(DateTime.now())) {
            _scheduleReminder(leadDocId, leadName, reminderDate);
          }
        }
      }
    });
  }

  /// Schedule a local reminder notification on the assigned user's device.
  Future<void> _scheduleReminder(String leadDocId, String leadName, DateTime reminderDate) async {
    final tz = await AwesomeNotifications().getLocalTimeZoneIdentifier();
    await NotificationPermissionService.instance.safeCreateNotification(
      content: NotificationContent(
        id: ('sme_reminder_$leadDocId').hashCode.abs().remainder(2000000000),
        channelKey: 'reminder_channel',
        title: 'Follow-Up Reminder',
        body: 'Reminder for $leadName',
        notificationLayout: NotificationLayout.Default,
        payload: {
          'docId': leadDocId,
          'type': 'sme_lead',
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
        preciseAlarm: true,
      ),
    );
  }

  /// Stop listening (call on logout).
  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
    _isListening = false;
  }
}

