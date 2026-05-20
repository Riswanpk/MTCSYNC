import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mtcsync/Misc/notification_permission_service.dart';
import '../models/dme_reminder.dart';

/// Service for scheduling and managing reminder notifications
class DmeNotificationService {
  DmeNotificationService._();
  static final DmeNotificationService instance = DmeNotificationService._();

  static const int _reminderChannelId = 123;
  static const String _reminderChannelKey = 'dme_reminder_channel';
  static const String _reminderChannelName = 'DME Reminders';
  static const String _complaintChannelKey = 'dme_complaints_channel';
  static const String _complaintChannelName = 'DME Complaints';

  /// Initialize notification channels for DME reminders and complaints
  static Future<void> initialize() async {
    await AwesomeNotifications().initialize(
      null, // Default icon
      [
        NotificationChannel(
          channelKey: _reminderChannelKey,
          channelName: _reminderChannelName,
          channelDescription: 'Notifications for DME customer reminders',
          defaultColor: const Color.fromARGB(255, 9, 201, 100),
          ledColor: const Color.fromARGB(255, 9, 201, 100),
          importance: NotificationImportance.Max,
          enableVibration: true,
        ),
        NotificationChannel(
          channelKey: _complaintChannelKey,
          channelName: _complaintChannelName,
          channelDescription: 'Notifications for DME complaints',
          defaultColor: const Color(0xFFFFA500),
          ledColor: const Color(0xFFFFA500),
          importance: NotificationImportance.Max,
          enableVibration: true,
        ),
      ],
      debug: false,
    );
  }

  /// Schedule a reminder notification for a specific date/time
  Future<void> scheduleReminderNotification({
    required DmeReminder reminder,
    required int customerId,
    int notificationHour = 9, // 9:00 AM by default
    int notificationMinute = 0,
  }) async {
    try {
      final reminderDate = reminder.reminderDate;
      final dateTime = DateTime(
        reminderDate.year,
        reminderDate.month,
        reminderDate.day,
        notificationHour,
        notificationMinute,
        0,
      );

      // Don't schedule if the time is in the past
      if (dateTime.isBefore(DateTime.now())) {
        return;
      }

      final message = _generateNotificationMessage(reminder);

      await NotificationPermissionService.instance.safeCreateNotification(
        content: NotificationContent(
          id: _generateNotificationId(customerId),
          channelKey: _reminderChannelKey,
          title: 'DME Reminder',
          body: message,
          payload: {
            'type': 'dme_reminder',
            'customerId': customerId.toString(),
            'reminderId': reminder.id?.toString() ?? '',
            'customerName': reminder.customerName ?? '',
          },
          notificationLayout: NotificationLayout.Default,
          actionType: ActionType.Default,
        ),
        schedule: NotificationCalendar.fromDate(date: dateTime),
      );
    } catch (e) {
      debugPrint('Error scheduling reminder notification: $e');
    }
  }

  /// Send an immediate notification (for pending carryover)
  Future<void> sendImmediateNotification({
    required String title,
    required String message,
    required Map<String, String> payload,
  }) async {
    try {
      await NotificationPermissionService.instance.safeCreateNotification(
        content: NotificationContent(
          id: DateTime.now().millisecondsSinceEpoch % 2147483647,
          channelKey: _reminderChannelKey,
          title: title,
          body: message,
          payload: payload,
          notificationLayout: NotificationLayout.Default,
          actionType: ActionType.Default,
        ),
      );
    } catch (e) {
      debugPrint('Error sending immediate notification: $e');
    }
  }

  /// Cancel a scheduled notification
  Future<void> cancelNotification(int customerId) async {
    try {
      await AwesomeNotifications()
          .cancel(_generateNotificationId(customerId));
    } catch (e) {
      debugPrint('Error canceling notification: $e');
    }
  }

  /// Cancel all scheduled reminders
  Future<void> cancelAllReminders() async {
    try {
      await AwesomeNotifications().cancelAllSchedules();
    } catch (e) {
      debugPrint('Error canceling all notifications: $e');
    }
  }

  /// Generate a unique notification ID based on customer ID
  static int _generateNotificationId(int customerId) {
    return 9000 + (customerId % 10000); // Range: 9000-19000
  }

  /// Generate notification message
  static String _generateNotificationMessage(DmeReminder reminder) {
    final customerName = reminder.customerName ?? 'Customer';
    final dateStr =
        DateFormat('dd MMM').format(reminder.lastPurchaseDate);
    return 'Call $customerName - Last purchase: $dateStr';
  }

  /// Send immediate notification when complaint is raised
  /// Sends to the assigned user with message "New complaint raised"
  Future<void> sendComplaintAssignmentNotification({
    required String complaintId,
    required String customerName,
    required String assignedToUsername,
  }) async {
    try {
      await NotificationPermissionService.instance.safeCreateNotification(
        content: NotificationContent(
          id: _generateComplaintNotificationId(complaintId),
          channelKey: _complaintChannelKey,
          title: 'New complaint raised',
          body: 'Complaint from $customerName is assigned to you',
          payload: {
            'type': 'complaint_assigned',
            'complaintId': complaintId,
            'customerName': customerName,
            'page': 'assigned_complaints',
          },
          notificationLayout: NotificationLayout.Default,
          actionType: ActionType.Default,
        ),
      );
    } catch (e) {
      debugPrint('Error sending complaint assignment notification: $e');
    }
  }

  /// Send immediate notification when complaint is raised to manager
  /// Sends to the branch manager with message "New complaint raised"
  Future<void> sendComplaintRaisedToManagerNotification({
    required String complaintId,
    required String customerName,
    required String branchName,
  }) async {
    try {
      await NotificationPermissionService.instance.safeCreateNotification(
        content: NotificationContent(
          id: _generateComplaintNotificationId('$complaintId-manager'),
          channelKey: _complaintChannelKey,
          title: 'New complaint raised',
          body: 'Complaint from $customerName in branch $branchName',
          payload: {
            'type': 'complaint_raised',
            'complaintId': complaintId,
            'customerName': customerName,
            'branchName': branchName,
            'page': 'complaints_management',
          },
          notificationLayout: NotificationLayout.Default,
          actionType: ActionType.Default,
        ),
      );
    } catch (e) {
      debugPrint('Error sending complaint raised to manager notification: $e');
    }
  }

  /// Send immediate notification when remarks are added to a complaint
  Future<void> sendRemarksNotification({
    required String complaintId,
    required String customerName,
    required String remarkedByUsername,
  }) async {
    try {
      await NotificationPermissionService.instance.safeCreateNotification(
        content: NotificationContent(
          id: _generateComplaintNotificationId(complaintId),
          channelKey: _complaintChannelKey,
          title: 'New Remarks on Your Complaint',
          body: '$remarkedByUsername has added remarks to the complaint for $customerName',
          payload: {
            'type': 'complaint_remarks',
            'complaintId': complaintId,
            'customerName': customerName,
            'page': 'my_complaints',
          },
          notificationLayout: NotificationLayout.Default,
          actionType: ActionType.Default,
        ),
      );
    } catch (e) {
      debugPrint('Error sending remarks notification: $e');
    }
  }

  /// Dynamically generate notification ID based on complaint ID
  static int _generateComplaintNotificationId(String complaintId) {
    return complaintId.hashCode.abs() % 2147483647;
  }

  /// Listen for notification taps and return payload
  /// Call this during app initialization to handle notification routing
  /// Note: awesome_notifications uses callbacks instead of streams.
  /// This is a placeholder for managing notifications.
  Stream<ReceivedNotification> get onNotificationTap {
    // Return empty stream - notifications should be handled through 
    // initialization callbacks and the actionStream of AwesomeNotifications
    return const Stream.empty();
  }

  /// Request notification permission (for devices that require it)
  static Future<bool> requestPermission() async {
    return AwesomeNotifications()
        .isNotificationAllowed()
        .then((isAllowed) {
      if (!isAllowed) {
        return AwesomeNotifications().requestPermissionToSendNotifications();
      }
      return true;
    });
  }
}
