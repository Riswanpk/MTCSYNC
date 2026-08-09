import 'dart:io';
import 'package:android_intent_plus/android_intent.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Service for managing notification permissions and safe creation
class NotificationPermissionService {
  static final NotificationPermissionService _instance =
      NotificationPermissionService._internal();

  static NotificationPermissionService get instance => _instance;

  bool _notificationPermissionGranted = false;

  NotificationPermissionService._internal();

  /// Check if notifications permission is granted
  Future<bool> isNotificationPermissionGranted() async {
    final isAllowed = await AwesomeNotifications().isNotificationAllowed();
    _notificationPermissionGranted = isAllowed;
    return _notificationPermissionGranted;
  }

  /// Request notification permission from user
  /// AwesomeNotifications requestPermissionToSendNotifications covers both
  /// POST_NOTIFICATIONS and exact alarm permissions in one call.
  Future<bool> requestNotificationPermission() async {
    try {
      final isAllowed = await AwesomeNotifications().isNotificationAllowed();
      if (!isAllowed) {
        _notificationPermissionGranted = await AwesomeNotifications().requestPermissionToSendNotifications();
      } else {
        _notificationPermissionGranted = true;
      }
      return _notificationPermissionGranted;
    } catch (e) {
      if (kDebugMode) {
        print('Error requesting notification permission: $e');
      }
      return false;
    }
  }

  /// Safely create a notification with permission handling
  /// Returns true if successful, false if permission denied or error occurred
  Future<bool> safeCreateNotification({
    required NotificationContent content,
    NotificationSchedule? schedule,
  }) async {
    // Check permission first
    if (!_notificationPermissionGranted) {
      final permissionGranted = await isNotificationPermissionGranted();
      if (!permissionGranted) {
        if (kDebugMode) {
          print(
            'Notification permission not granted. '
            'Notification "${content.title}" could not be sent.',
          );
        }
        return false;
      }
    }

    try {
      await AwesomeNotifications().createNotification(
        content: content,
        schedule: schedule,
      );
      return true;
    } on PlatformException catch (e) {
      if (kDebugMode) {
        print('PlatformException creating notification: ${e.code} - ${e.message}');
      }

      // Handle missing channel error dynamically by setting channel and retrying
      if (e.code == 'INVALID_ARGUMENTS' || (e.message?.contains('does not exist') ?? false)) {
        if (content.channelKey != null) {
          await ensureChannelExists(content.channelKey!);
        }
        try {
          await AwesomeNotifications().createNotification(
            content: content,
            schedule: schedule,
          );
          return true;
        } catch (retryErr) {
          if (kDebugMode) {
            print('Channel auto-creation retry failed: $retryErr');
          }
          return false;
        }
      }

      // Handle specific permission error
      if (e.code == 'INSUFFICIENT_PERMISSIONS') {
        _notificationPermissionGranted = false;
        // Try requesting permission and retry once
        final permitted = await requestNotificationPermission();
        if (permitted) {
          try {
            await AwesomeNotifications().createNotification(
              content: content,
              schedule: schedule,
            );
            return true;
          } catch (retryError) {
            if (kDebugMode) {
              print('Retry failed: $retryError');
            }
            return false;
          }
        }
      }
      return false;
    } catch (e) {
      if (kDebugMode) {
        print('Error creating notification: $e');
      }
      return false;
    }
  }

  /// Ensure a notification channel exists dynamically
  Future<void> ensureChannelExists(String channelKey) async {
    try {
      final soundSourceMap = <String, String>{
        'basic_channel_v2': 'resource://raw/leadsreminder',
        'basic_channel': 'resource://raw/leadsreminder',
        'todo_reminder_channel': 'resource://raw/todo_reminder',
        'todos_pending_channel': 'resource://raw/you_have_todos_pending',
        'reminder_channel_v2': 'resource://raw/you_have_todos_pending',
        'task_assignment_channel': 'resource://raw/you_have_been_assigned_a_task',
        'sme_lead_channel': 'resource://raw/sme_leads_assigned',
        'task_completion_channel': 'resource://raw/task_completed',
        'dme_complaints_channel': 'resource://raw/complaint_raised',
        'delivery_reminder_channel': 'resource://raw/delivery_reminder',
        'supersale_open_channel': 'resource://raw/supersale_bookings_open',
        'supersale_closed_channel': 'resource://raw/supersale_bookins_closed',
      };

      final sound = soundSourceMap[channelKey] ?? 'resource://raw/leadsreminder';
      try {
        await AwesomeNotifications().setChannel(
          NotificationChannel(
            channelKey: channelKey,
            channelName: channelKey.replaceAll('_', ' ').toUpperCase(),
            channelDescription: 'Notification channel for $channelKey',
            soundSource: sound,
            importance: NotificationImportance.High,
            channelShowBadge: true,
            criticalAlerts: true,
            playSound: true,
          ),
        );
      } catch (soundErr) {
        if (kDebugMode) {
          print('Setting channel $channelKey with sound $sound failed: $soundErr. Retrying without custom sound.');
        }
        await AwesomeNotifications().setChannel(
          NotificationChannel(
            channelKey: channelKey,
            channelName: channelKey.replaceAll('_', ' ').toUpperCase(),
            channelDescription: 'Notification channel for $channelKey',
            importance: NotificationImportance.High,
            channelShowBadge: true,
            criticalAlerts: true,
            playSound: true,
          ),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error ensuring channel $channelKey exists: $e');
      }
    }
  }

  /// Request Battery Optimization exemption on Android
  Future<void> requestBatteryOptimizationExemption() async {
    if (!Platform.isAndroid) return;
    try {
      final isIgnoring = await Permission.ignoreBatteryOptimizations.isGranted;
      if (!isIgnoring) {
        await Permission.ignoreBatteryOptimizations.request();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Battery optimization exemption request failed: $e');
      }
    }
  }

  /// Prompt OEM Autostart setting screen for Xiaomi / Oppo / Vivo / Huawei devices
  Future<void> openOemAutostartSettings() async {
    if (!Platform.isAndroid) return;
    try {
      const intent = AndroidIntent(
        action: 'android.settings.SETTINGS',
      );
      await intent.launch();
    } catch (e) {
      if (kDebugMode) {
        print('Could not launch settings intent: $e');
      }
    }
  }
}
