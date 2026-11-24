import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Top-level function to cancel any previously scheduled 9 AM local task reminders.
Future<void> syncTaskReminders(String userId) async {
  try {
    final snapshot = await FirebaseFirestore.instance
        .collection('core_tasks')
        .where('assigned_to', isEqualTo: userId)
        .get();

    for (var doc in snapshot.docs) {
      final int notifId = doc.id.hashCode & 0x7FFFFFFF;
      try {
        await AwesomeNotifications().cancel(notifId);
      } catch (e) {
        debugPrint('Warning: Failed to cancel task reminder: $e');
      }
    }
  } catch (e) {
    debugPrint('Error cancelling task reminders: $e');
  }
}
