import 'dart:async';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

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

    _subscription = FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final data = message.data;
      if (data['type'] != 'sme_lead_assignment') return;

      final title = message.notification?.title ?? data['title'] ?? 'New Lead Assigned';
      final body = message.notification?.body ?? data['body'] ?? 'A new lead has been assigned to you.';
      final leadDocId = data['leadDocId'] ?? '';

      // Show local notification so AwesomeNotifications action buttons work
      AwesomeNotifications().createNotification(
        content: NotificationContent(
          id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
          channelKey: 'basic_channel',
          title: title,
          body: body,
          notificationLayout: NotificationLayout.Default,
          payload: {
            'docId': leadDocId,
            'type': 'lead',
          },
        ),
      );

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
    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: ('sme_reminder_$leadDocId').hashCode.abs().remainder(2000000000),
        channelKey: 'reminder_channel',
        title: 'Follow-Up Reminder',
        body: 'Reminder for $leadName',
        notificationLayout: NotificationLayout.Default,
        payload: {
          'docId': leadDocId,
          'type': 'lead',
        },
      ),
      actionButtons: [
        NotificationActionButton(
          key: 'EDIT_FOLLOWUP',
          label: 'Edit',
          autoDismissible: true,
        ),
      ],
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

