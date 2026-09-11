import 'package:flutter/foundation.dart';
import 'package:call_log/call_log.dart';
import 'package:permission_handler/permission_handler.dart';
import '../dme_config.dart';

class DmeCallScannerService {
  /// Robust phone number matching:
  /// - Exact match
  /// - Suffix match (e.g. ignoring country codes like +91, +971, 0091)
  /// - Last 10 digits match (standard mobile number length)
  static bool numberMatches(String logNumber, String? contact) {
    if (contact == null || contact.isEmpty) return false;
    final cleanContact = contact.replaceAll(RegExp(r'\D'), '');
    final cleanLog = logNumber.replaceAll(RegExp(r'\D'), '');
    if (cleanContact.isEmpty || cleanLog.isEmpty) return false;

    if (cleanLog == cleanContact) return true;
    if (cleanLog.endsWith(cleanContact) || cleanContact.endsWith(cleanLog)) return true;

    if (cleanContact.length >= 10 && cleanLog.length >= 10) {
      final subContact = cleanContact.substring(cleanContact.length - 10);
      final subLog = cleanLog.substring(cleanLog.length - 10);
      return subContact == subLog;
    }
    return false;
  }

  /// Scans today's call logs and checks against the provided reminders.
  /// For any reminder where an outgoing call was initiated today:
  /// - Finds the latest call and its duration.
  /// - If duration > 0 (attended call), updates `dme_reminders` in Supabase with
  ///   `call_duration`, `called_timestamp`, and `called_by`.
  /// - Returns the list of reminders with detected calls.
  static Future<List<Map<String, dynamic>>> scanTodayCallLog(
    List<Map<String, dynamic>> reminders, {
    required String userEmail,
  }) async {
    var permStatus = await Permission.phone.status;
    if (!permStatus.isGranted) {
      permStatus = await Permission.phone.request();
      if (!permStatus.isGranted) return [];
    }

    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final Iterable<CallLogEntry> entries = await CallLog.query(
        dateFrom: startOfDay.millisecondsSinceEpoch,
        dateTo: now.millisecondsSinceEpoch,
      );

      final client = await DmeConfig.getClient();
      final List<Map<String, dynamic>> detected = [];

      for (var reminder in reminders) {
        final phone = reminder['customer_phone']?.toString();
        if (phone == null || phone.isEmpty) continue;

        // Skip if already completed with remarks
        final remarks = (reminder['remarks'] ?? '').toString().trim();
        final status = (reminder['status'] ?? '').toString().toLowerCase();
        if (remarks.isNotEmpty && (status == 'completed' || status == 'called')) {
          continue;
        }

        int latestOutgoingTime = -1;
        for (final entry in entries) {
          if (entry.callType != CallType.outgoing) continue;
          final logNumber = entry.number?.replaceAll(RegExp(r'\D'), '') ?? '';
          if (logNumber.isEmpty) continue;
          if (numberMatches(logNumber, phone)) {
            if (entry.timestamp != null && entry.timestamp! > latestOutgoingTime) {
              latestOutgoingTime = entry.timestamp!;
            }
          }
        }

        if (latestOutgoingTime == -1) continue;

        // Find the call entry starting from or after the outgoing call initiation
        CallLogEntry? matchedEntry;
        for (final entry in entries) {
          if (entry.timestamp == null || entry.timestamp! < latestOutgoingTime) continue;
          final logNumber = entry.number?.replaceAll(RegExp(r'\D'), '') ?? '';
          if (logNumber.isEmpty) continue;
          if (numberMatches(logNumber, phone)) {
            matchedEntry = entry;
            break;
          }
        }

        if (matchedEntry != null) {
          final duration = matchedEntry.duration ?? 0;
          final calledTime = matchedEntry.timestamp != null
              ? DateTime.fromMillisecondsSinceEpoch(matchedEntry.timestamp!)
              : now;

          reminder['call_duration'] = duration;
          reminder['called_timestamp'] = calledTime.toIso8601String();
          reminder['called_by'] = userEmail;

          // Update Supabase if client available
          if (client != null) {
            final remId = reminder['id'];
            if (remId != null) {
              final payload = <String, dynamic>{
                'call_duration': duration,
                'called_timestamp': calledTime.toIso8601String(),
                'called_by': userEmail,
                'updated_at': now.toIso8601String(),
              };

              try {
                await client.from('dme_reminders').update(payload).eq('id', remId);
              } catch (err) {
                if (err.toString().contains('called_by')) {
                  payload.remove('called_by');
                  await client.from('dme_reminders').update(payload).eq('id', remId);
                }
              }
            }
          }

          detected.add(reminder);
        }
      }

      return detected;
    } catch (e) {
      debugPrint('Error scanning DME call log: $e');
      return [];
    }
  }
}
