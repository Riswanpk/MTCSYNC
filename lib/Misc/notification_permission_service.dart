import 'dart:io';
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
  /// For Android 13+, this checks POST_NOTIFICATIONS permission
  /// For Android 12 and below, always returns true
  Future<bool> isNotificationPermissionGranted() async {
    if (!Platform.isAndroid) {
      // iOS and other platforms don't have strict notification permissions
      return true;
    }

    // Request permission and cache the result
    final status = await Permission.notification.request();
    _notificationPermissionGranted =
        status.isGranted || status.isDenied == false;

    return _notificationPermissionGranted;
  }

  /// Request notification permission from user
  /// Returns true if granted, false otherwise
  Future<bool> requestNotificationPermission() async {
    if (!Platform.isAndroid) {
      return true;
    }

    try {
      final status = await Permission.notification.request();
      _notificationPermissionGranted = status.isGranted;
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

      // Handle specific permission error
      if (e.code == 'INSUFFICIENT_PERMISSIONS' ||
          e.message?.contains('disabled') == true) {
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
}
