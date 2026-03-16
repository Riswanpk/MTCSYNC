import 'dart:async';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Listens for SME lead assignment notifications in Firestore and
/// triggers local push notifications for the assigned user.
class SmeNotificationService {
  SmeNotificationService._();
  static final SmeNotificationService instance = SmeNotificationService._();

  StreamSubscription<QuerySnapshot>? _subscription;
  bool _isListening = false;

  /// Start listening for new unread notifications addressed to the current user.
  /// Should be called once after login/home page init.
  void startListening() {
    if (_isListening) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    _isListening = true;
    _subscription = FirebaseFirestore.instance
        .collection('notifications')
        .where('recipient_uid', isEqualTo: uid)
        .where('read', isEqualTo: false)
        .where('type', isEqualTo: 'sme_lead_assignment')
        .orderBy('created_at', descending: true)
        .limit(10)
        .snapshots()
        .listen((snapshot) {
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data();
          if (data == null) continue;

          final title = data['title'] as String? ?? 'New Lead Assigned';
          final body = data['body'] as String? ?? 'A new lead has been assigned to you.';
          final leadDocId = data['lead_doc_id'] as String? ?? '';

          // Show local assignment notification
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

          // Schedule reminder on assigned user's device if the SME set one
          final reminderTs = data['reminder_at'];
          final leadName = data['lead_name'] as String? ?? 'Lead';
          if (reminderTs is Timestamp) {
            final reminderDate = reminderTs.toDate();
            if (reminderDate.isAfter(DateTime.now())) {
              _scheduleReminder(leadDocId, leadName, reminderDate);
            }
          }

          // Mark as read so it doesn't trigger again
          change.doc.reference.update({'read': true});
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
