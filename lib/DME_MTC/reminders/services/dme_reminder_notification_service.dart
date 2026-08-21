import 'package:flutter/foundation.dart';

class DmeReminderNotificationService {
  static final DmeReminderNotificationService instance =
      DmeReminderNotificationService._internal();

  DmeReminderNotificationService._internal();

  Future<void> initialize() async {
    debugPrint('DmeReminderNotificationService initialized.');
  }

  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    debugPrint('Notification [$id]: $title - $body');
  }
}
