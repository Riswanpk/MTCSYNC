import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/foundation.dart';
import '../../Misc/notification_permission_service.dart';
import '../../Navigation/user_cache_service.dart';

/// Service for scheduling local supersale opening/closing and delivery reminder notifications.
class SupersaleNotificationService {
  SupersaleNotificationService._();
  static final SupersaleNotificationService instance = SupersaleNotificationService._();

  Set<String> _scheduledDocIds = {};

  Future<void> syncScheduledNotifications(
    List<QueryDocumentSnapshot> postings,
    String? userBranch,
  ) async {
    final role = UserCacheService.instance.role ?? '';
    final isTargetRole = ['sales', 'manager', 'asst_manager'].contains(role);
    if (!isTargetRole || userBranch == null) return;

    final now = DateTime.now();
    final activeDocIds = postings.map((d) => d.id).toSet();

    // Cancel notifications for deleted supersales
    final deletedDocIds = _scheduledDocIds.difference(activeDocIds);
    for (final deletedId in deletedDocIds) {
      final openNotifId = ('${deletedId}_open').hashCode & 0x7FFFFFFF;
      final preCloseNotifId = ('${deletedId}_preclose').hashCode & 0x7FFFFFFF;
      final closedNotifId = ('${deletedId}_closed').hashCode & 0x7FFFFFFF;
      await AwesomeNotifications().cancel(openNotifId);
      await AwesomeNotifications().cancel(preCloseNotifId);
      await AwesomeNotifications().cancel(closedNotifId);
    }
    _scheduledDocIds = activeDocIds;

    for (final doc in postings) {
      final data = doc.data() as Map<String, dynamic>;
      final List<dynamic> branches = data['branches'] ?? [];
      final isEligible = branches.contains(userBranch) || branches.contains('all');
      if (!isEligible) {
        final openNotifId = ('${doc.id}_open').hashCode & 0x7FFFFFFF;
        final preCloseNotifId = ('${doc.id}_preclose').hashCode & 0x7FFFFFFF;
        final closedNotifId = ('${doc.id}_closed').hashCode & 0x7FFFFFFF;
        await AwesomeNotifications().cancel(openNotifId);
        await AwesomeNotifications().cancel(preCloseNotifId);
        await AwesomeNotifications().cancel(closedNotifId);
        continue;
      }

      final itemName = data['item'] ?? 'Supersale';
      final Timestamp? startTs = data['bookingStart'];
      final Timestamp? endTs = data['bookingEnd'];
      if (startTs == null || endTs == null) continue;

      final startDt = startTs.toDate();
      final endDt = endTs.toDate();
      final preCloseDt = endDt.subtract(const Duration(minutes: 30));

      final openNotifId = ('${doc.id}_open').hashCode & 0x7FFFFFFF;
      final preCloseNotifId = ('${doc.id}_preclose').hashCode & 0x7FFFFFFF;
      final closedNotifId = ('${doc.id}_closed').hashCode & 0x7FFFFFFF;

      // Schedule Open notification if bookingStart is in the future
      if (startDt.isAfter(now)) {
        final tz = await AwesomeNotifications().getLocalTimeZoneIdentifier();
        await NotificationPermissionService.instance.safeCreateNotification(
          content: NotificationContent(
            id: openNotifId,
            channelKey: 'supersale_open_channel',
            title: 'Booking Opened',
            body: 'Supersale booking for "$itemName" is now open for your branch.',
            notificationLayout: NotificationLayout.Default,
            payload: {
              'type': 'supersale',
              'subType': 'booking_open',
              'docId': doc.id,
            },
          ),
          schedule: NotificationCalendar(
            year: startDt.year,
            month: startDt.month,
            day: startDt.day,
            hour: startDt.hour,
            minute: startDt.minute,
            second: startDt.second,
            timeZone: tz,
            preciseAlarm: true,
            allowWhileIdle: true,
          ),
        );
      }

      // Schedule 30-min Reminder before closing notification if preCloseDt is in the future
      if (preCloseDt.isAfter(now)) {
        final tz = await AwesomeNotifications().getLocalTimeZoneIdentifier();
        await NotificationPermissionService.instance.safeCreateNotification(
          content: NotificationContent(
            id: preCloseNotifId,
            channelKey: 'supersale_open_channel',
            title: 'Supersale Closing Soon!',
            body: 'Supersale booking for "$itemName" will close in 30 minutes!',
            notificationLayout: NotificationLayout.Default,
            payload: {
              'type': 'supersale',
              'subType': 'booking_preclose',
              'docId': doc.id,
            },
          ),
          schedule: NotificationCalendar(
            year: preCloseDt.year,
            month: preCloseDt.month,
            day: preCloseDt.day,
            hour: preCloseDt.hour,
            minute: preCloseDt.minute,
            second: preCloseDt.second,
            timeZone: tz,
            preciseAlarm: true,
            allowWhileIdle: true,
          ),
        );
      }

      // Schedule Closed notification if bookingEnd is in the future
      if (endDt.isAfter(now)) {
        final tz = await AwesomeNotifications().getLocalTimeZoneIdentifier();
        await NotificationPermissionService.instance.safeCreateNotification(
          content: NotificationContent(
            id: closedNotifId,
            channelKey: 'supersale_closed_channel',
            title: 'Booking Closed',
            body: 'Supersale booking for "$itemName" has been closed.',
            notificationLayout: NotificationLayout.Default,
            payload: {
              'type': 'supersale',
              'subType': 'booking_closed',
              'docId': doc.id,
            },
          ),
          schedule: NotificationCalendar(
            year: endDt.year,
            month: endDt.month,
            day: endDt.day,
            hour: endDt.hour,
            minute: endDt.minute,
            second: endDt.second,
            timeZone: tz,
            preciseAlarm: true,
            allowWhileIdle: true,
          ),
        );
      }
    }
  }

  /// Schedules a delivery reminder for remaining partial bookings.
  Future<void> scheduleRemainingDeliveryReminder({
    required String docId,
    required String item,
    required String customerName,
    required int remainingQty,
    required String? userBranch,
    required DateTime nextReminderDate,
  }) async {
    try {
      if (!nextReminderDate.isAfter(DateTime.now())) return;
      final notifId = docId.hashCode & 0x7FFFFFFF;
      final tz = await AwesomeNotifications().getLocalTimeZoneIdentifier();
      await NotificationPermissionService.instance.safeCreateNotification(
        content: NotificationContent(
          id: notifId,
          channelKey: 'delivery_reminder_channel',
          title: 'Remaining Delivery Reminder',
          body: 'Reminder: $remainingQty remaining units for customer $customerName ($item)',
          notificationLayout: NotificationLayout.Default,
          customSound: 'resource://raw/delivery_reminder',
          payload: {
            'type': 'supersale_delivery_reminder',
            'docId': docId,
            'branch': userBranch ?? '',
            'item': item,
          },
        ),
        schedule: NotificationCalendar(
          year: nextReminderDate.year,
          month: nextReminderDate.month,
          day: nextReminderDate.day,
          hour: nextReminderDate.hour,
          minute: nextReminderDate.minute,
          second: 0,
          millisecond: 0,
          timeZone: tz,
          repeats: false,
        ),
      );
    } catch (e) {
      debugPrint('Error scheduling remaining delivery reminder: $e');
    }
  }
}
