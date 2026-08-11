import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> autoRescheduleLeads(String? currentUserId, String? branch) async {
  if (currentUserId == null || branch == null || branch.isEmpty) return;

  try {
    final prefs = await SharedPreferences.getInstance();
    final lastCheckMillis = prefs.getInt('last_reschedule_check_$currentUserId') ?? 0;
    final nowMillis = DateTime.now().millisecondsSinceEpoch;
    if (nowMillis - lastCheckMillis < 86400000) {
      return; // Run at most once per 24 hours
    }
    await prefs.setInt('last_reschedule_check_$currentUserId', nowMillis);

    final now = DateTime.now();
    final createdByQuery = await FirebaseFirestore.instance
        .collection('follow_ups')
        .where('branch', isEqualTo: branch)
        .where('status', isEqualTo: 'In Progress')
        .where('created_by', isEqualTo: currentUserId)
        .get();

    final assignedToQuery = await FirebaseFirestore.instance
        .collection('follow_ups')
        .where('branch', isEqualTo: branch)
        .where('status', isEqualTo: 'In Progress')
        .where('assigned_to', isEqualTo: currentUserId)
        .get();

    final seenIds = <String>{};
    final allDocs = [
      ...createdByQuery.docs,
      ...assignedToQuery.docs,
    ].where((doc) => seenIds.add(doc.id)).toList();

    for (final doc in allDocs) {
      final data = doc.data();

      final reminderDateChanged = data['reminder_date_changed'] as bool? ?? false;
      if (reminderDateChanged) continue;

      final originalReminderDate = data['original_reminder_date'];
      if (originalReminderDate == null) continue;

      final originalDate = (originalReminderDate is Timestamp)
          ? originalReminderDate.toDate()
          : DateTime.tryParse(originalReminderDate.toString());

      if (originalDate == null) continue;

      if (originalDate.isBefore(now.subtract(const Duration(days: 2)))) {
        final rescheduledDate = originalDate.add(const Duration(days: 7));
        final newReminderText =
            DateFormat('dd-MM-yyyy hh:mm a').format(rescheduledDate);

        await doc.reference.update({
          'reminder': newReminderText,
          'original_reminder_date': Timestamp.fromDate(rescheduledDate),
        });

        debugPrint(
            'Auto-rescheduled lead ${doc.id} from ${DateFormat('dd-MM-yyyy').format(originalDate)} to ${DateFormat('dd-MM-yyyy').format(rescheduledDate)}');
      }
    }
  } catch (e) {
    debugPrint('Error in autoRescheduleLeads: $e');
  }
}
