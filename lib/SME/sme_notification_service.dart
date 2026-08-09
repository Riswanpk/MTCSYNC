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
      final type = data['type'] ?? data['notifType'];
      const handled = {
        'sme_lead_assignment',
        'dme_lead_assignment',
        'lead_transfer',
        'core_task_assignment',
        'core_task_completion',
        'todo',
        'supersale_notification'
      };
      if (!handled.contains(type)) return;

      final title = message.notification?.title ?? data['title'] ?? 'New Notification';
      final body = message.notification?.body ?? data['body'] ?? '';
      final leadDocId = data['leadDocId'] ?? '';

      final isCoreTaskAssigned = type == 'core_task_assignment';
      final isCoreTaskCompleted = type == 'core_task_completion';
      final isTodo = type == 'todo';
      final isSupersale = type == 'supersale_notification';
      final subType = data['subType'] ?? '';

      final isDmeComplaint = type == 'dme_complaint' || type == 'complaint_assigned' || type == 'complaint_raised';
      final isSmeLead = type == 'sme_lead_assignment' || type == 'sme_lead';

      String targetChannel = 'basic_channel_v2';
      if (isSupersale) {
        if (subType == 'booking_open') {
          targetChannel = 'supersale_open_channel';
        } else if (subType == 'booking_closed') {
          targetChannel = 'supersale_closed_channel';
        } else {
          targetChannel = 'delivery_reminder_channel';
        }
      } else if (isTodo) {
        targetChannel = 'todo_reminder_channel';
      } else if (isCoreTaskAssigned) {
        targetChannel = 'task_assignment_channel';
      } else if (isCoreTaskCompleted) {
        targetChannel = 'task_completion_channel';
      } else if (isSmeLead) {
        targetChannel = 'sme_lead_channel';
      } else if (isDmeComplaint) {
        targetChannel = 'dme_complaints_channel';
      }

      // Show local notification so AwesomeNotifications action buttons work
      await NotificationPermissionService.instance.safeCreateNotification(
        content: NotificationContent(
          id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
          channelKey: targetChannel,
          title: title,
          body: body,
          notificationLayout: NotificationLayout.Default,
          payload: {
            'docId': leadDocId,
            'type': isSupersale
                ? 'supersale'
                : (isCoreTaskAssigned
                    ? 'core_task'
                    : (isCoreTaskCompleted
                        ? 'core_task_complete'
                        : (isTodo ? 'todo' : 'sme_lead_assignment'))),
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
        channelKey: 'todo_reminder_channel',
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

