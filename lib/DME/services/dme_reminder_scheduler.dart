import 'package:intl/intl.dart';
import '../models/dme_reminder.dart';
import 'dme_supabase_service.dart';

/// Service for calculating and managing reminder dates/schedules
class DmeReminderScheduler {
  DmeReminderScheduler._();
  static final DmeReminderScheduler instance = DmeReminderScheduler._();

  static final _svc = DmeSupabaseService.instance;

  /// Calculate reminder date: 30 days after purchase date
  /// Example: Purchase on 27 Mar 2026 → Reminder on 26 Apr 2026
  static DateTime calculateReminderDate(DateTime purchaseDate) {
    return purchaseDate.add(const Duration(days: 30));
  }

  /// Get all reminders that are due on a specific date
  Future<List<DmeReminder>> getRemindersForDate(
    DateTime date, {
    List<int>? branchIds,
  }) async {
    if (branchIds == null || branchIds.isEmpty) {
      return [];
    }
    
    final fromDate = DateTime(date.year, date.month, date.day);
    final toDate = fromDate.add(const Duration(days: 1));
    
    return _svc.getReminders(
      branchIds: branchIds,
      status: 'pending',
      from: fromDate,
      to: toDate,
    );
  }

  /// Get reminders due today
  Future<List<DmeReminder>> getRemindersForToday(List<int> branchIds) async {
    return _svc.getRemindersForToday(branchIds);
  }

  /// Get pending reminders from previous days
  Future<List<DmeReminder>> getPendingFromPreviousDays(List<int> branchIds) async {
    return _svc.getPendingFromPreviousDays(branchIds);
  }

  /// Reschedule reminder if needed based on new purchase date
  /// Returns true if rescheduled, false otherwise
  Future<bool> rescheduleIfNeeded(int customerId, DateTime newPurchaseDate) async {
    return _svc.rescheduleReminderIfNeeded(customerId, newPurchaseDate);
  }

  /// Generate human-friendly reminder message
  static String generateReminderMessage({
    required String customerName,
    required DateTime purchaseDate,
  }) {
    final dateStr = DateFormat('dd MMM yyyy').format(purchaseDate);
    return 'Reminder: Call $customerName - Last purchase: $dateStr';
  }

  /// Check if a reminder is overdue (was supposed to be completed but wasn't)
  static bool isOverdue(DmeReminder reminder) {
    final today = DateTime.now();
    final reminderDateTime = DateTime(
      reminder.reminderDate.year,
      reminder.reminderDate.month,
      reminder.reminderDate.day,
    );
    return reminderDateTime.isBefore(today) && reminder.status == 'pending';
  }

  /// Format reminder date for display
  static String formatReminderDate(DateTime date) {
    return DateFormat('dd MMM yyyy').format(date);
  }

  /// Get days until reminder
  static int daysUntilReminder(DateTime reminderDate) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final reminderDay = DateTime(reminderDate.year, reminderDate.month, reminderDate.day);
    return reminderDay.difference(today).inDays;
  }
}
