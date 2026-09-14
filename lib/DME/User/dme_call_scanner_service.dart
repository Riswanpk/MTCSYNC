import 'package:flutter/foundation.dart';
import 'package:call_log/call_log.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import '../dme_config.dart';
import 'package:mtcsync/DME/User/dme_user_stats_service.dart';

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

    // Remove leading zero if present (e.g. 09497062072 vs 9497062072)
    final stripZeroContact = cleanContact.replaceFirst(RegExp(r'^0+'), '');
    final stripZeroLog = cleanLog.replaceFirst(RegExp(r'^0+'), '');
    if (stripZeroContact.isNotEmpty && stripZeroContact == stripZeroLog) return true;

    if (cleanContact.length >= 10 && cleanLog.length >= 10) {
      final subContact = cleanContact.substring(cleanContact.length - 10);
      final subLog = cleanLog.substring(cleanLog.length - 10);
      return subContact == subLog;
    }
    return false;
  }

  /// Returns total number of outgoing call attempts to this contact made today.
  static Future<int> getTodayOutgoingAttemptCount(String contactPhone) async {
    try {
      final now = DateTime.now();
      final startOfToday = DateTime(now.year, now.month, now.day);
      final Iterable<CallLogEntry> entries = await CallLog.query(
        dateFrom: startOfToday.millisecondsSinceEpoch,
        dateTo: now.add(const Duration(minutes: 2)).millisecondsSinceEpoch,
      );
      final matching = entries.where((entry) {
        if (entry.callType != CallType.outgoing) return false;
        final logNumber = entry.number?.replaceAll(RegExp(r'\D'), '') ?? '';
        if (logNumber.isEmpty) return false;
        return numberMatches(logNumber, contactPhone);
      });
      return matching.length;
    } catch (_) {
      return 0;
    }
  }

  /// Fetches the qualifying call log entry for a specific contact today:
  /// - Strictly checks call logs for today (same day only: startOfToday to now).
  /// - Remarks require a call duration > 10 seconds.
  /// - If the customer calls back with duration > 10s, it only qualifies if the user
  ///   attempted to call the customer first that same day.
  /// - If no call > 10s exists, returns the latest outgoing attempt today (duration <= 10s)
  ///   so an attempt can be tracked without allowing remarks.
  static Future<CallLogEntry?> fetchLatestCallForContact(
    String contactPhone, {
    DateTime? sinceTime,
    int maxRetries = 2,
    Duration retryDelay = const Duration(milliseconds: 1500),
  }) async {
    var permStatus = await Permission.phone.status;
    if (!permStatus.isGranted) {
      permStatus = await Permission.phone.request();
      if (!permStatus.isGranted) return null;
    }

    final now = DateTime.now();
    // Strictly same day only: from 00:00:00 of today
    final startOfToday = DateTime(now.year, now.month, now.day);

    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      if (attempt > 0) {
        await Future.delayed(retryDelay);
      }

      try {
        final currentNow = DateTime.now().add(const Duration(minutes: 2));
        final Iterable<CallLogEntry> entries = await CallLog.query(
          dateFrom: startOfToday.millisecondsSinceEpoch,
          dateTo: currentNow.millisecondsSinceEpoch,
        );

        final matching = entries.where((entry) {
          final logNumber = entry.number?.replaceAll(RegExp(r'\D'), '') ?? '';
          if (logNumber.isEmpty) return false;
          return numberMatches(logNumber, contactPhone);
        }).toList();

        if (matching.isEmpty) continue;

        // Separate outgoing and incoming calls today
        final outgoingList = matching
            .where((e) => e.callType == CallType.outgoing)
            .toList()
          ..sort((a, b) => (a.timestamp ?? 0).compareTo(b.timestamp ?? 0)); // chronological

        final incomingList = matching
            .where((e) => e.callType == CallType.incoming)
            .toList()
          ..sort((a, b) => (a.timestamp ?? 0).compareTo(b.timestamp ?? 0));

        final bool hasOutgoingAttemptToday = outgoingList.isNotEmpty;
        final int firstOutgoingTime = hasOutgoingAttemptToday
            ? (outgoingList.first.timestamp ?? 0)
            : -1;

        // Qualifying attended calls must have duration > 10:
        // 1. Outgoing call with duration > 10
        // 2. Incoming callback with duration > 10 ONLY IF user attempted to call first today
        final List<CallLogEntry> qualifyingAttended = [];

        for (var out in outgoingList) {
          if ((out.duration ?? 0) > 10) {
            qualifyingAttended.add(out);
          }
        }

        if (hasOutgoingAttemptToday) {
          for (var inc in incomingList) {
            if ((inc.duration ?? 0) > 10 && (inc.timestamp ?? 0) >= firstOutgoingTime) {
              qualifyingAttended.add(inc);
            }
          }
        }

        qualifyingAttended.sort((a, b) => (b.timestamp ?? 0).compareTo(a.timestamp ?? 0));

        // If an attended call (> 10s) was found, return it immediately
        if (qualifyingAttended.isNotEmpty) {
          return qualifyingAttended.first;
        }

        // If no attended call > 10s was found, but the user attempted an outgoing call:
        if (hasOutgoingAttemptToday) {
          if (sinceTime != null) {
            // Check if there is an outgoing call around/after sinceTime
            final sinceMs = sinceTime.subtract(const Duration(seconds: 15)).millisecondsSinceEpoch;
            final recentOutgoing = outgoingList.where((e) => (e.timestamp ?? 0) >= sinceMs).toList();
            if (recentOutgoing.isNotEmpty) {
              return recentOutgoing.last;
            }
          } else {
            return outgoingList.last;
          }
        }
      } catch (e) {
        debugPrint('Error querying call log attempt $attempt: $e');
      }
    }
    return null;
  }

  /// Scans today's call logs (same day only) against the provided reminders:
  /// - Strictly same day (00:00:00 to now).
  /// - Outgoing calls are checked.
  /// - Incoming callbacks with duration > 10s only count if an outgoing attempt was made first today.
  /// - Only calls with duration > 10 seconds are marked as status = 'called'.
  static Future<List<Map<String, dynamic>>> scanTodayCallLog(
    List<Map<String, dynamic>> reminders, {
    required String userEmail,
    String? userUid,
  }) async {
    final statDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
    var permStatus = await Permission.phone.status;
    if (!permStatus.isGranted) {
      permStatus = await Permission.phone.request();
      if (!permStatus.isGranted) return [];
    }

    try {
      final now = DateTime.now();
      // Strictly same day only
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

        final matching = entries.where((entry) {
          final logNumber = entry.number?.replaceAll(RegExp(r'\D'), '') ?? '';
          if (logNumber.isEmpty) return false;
          return numberMatches(logNumber, phone);
        }).toList();

        if (matching.isEmpty) continue;

        final outgoingList = matching.where((e) => e.callType == CallType.outgoing).toList()
          ..sort((a, b) => (a.timestamp ?? 0).compareTo(b.timestamp ?? 0));
        final incomingList = matching.where((e) => e.callType == CallType.incoming).toList()
          ..sort((a, b) => (a.timestamp ?? 0).compareTo(b.timestamp ?? 0));

        // User must have attempted to call first that same day
        if (outgoingList.isEmpty) continue;

        final firstOutgoingTime = outgoingList.first.timestamp ?? 0;
        final totalAttempts = outgoingList.length;

        // Find qualifying attended calls (> 10s)
        final List<CallLogEntry> qualifyingAttended = [];
        for (var out in outgoingList) {
          if ((out.duration ?? 0) > 10) qualifyingAttended.add(out);
        }
        for (var inc in incomingList) {
          if ((inc.duration ?? 0) > 10 && (inc.timestamp ?? 0) >= firstOutgoingTime) {
            qualifyingAttended.add(inc);
          }
        }

        qualifyingAttended.sort((a, b) => (b.timestamp ?? 0).compareTo(a.timestamp ?? 0));

        if (qualifyingAttended.isNotEmpty) {
          final matchedEntry = qualifyingAttended.first;
          final duration = matchedEntry.duration ?? 0;
          final calledTime = matchedEntry.timestamp != null
              ? DateTime.fromMillisecondsSinceEpoch(matchedEntry.timestamp!)
              : now;

          reminder['call_duration'] = duration;
          reminder['called_timestamp'] = calledTime.toIso8601String();
          reminder['called_by'] = userEmail;
          reminder['status'] = 'called';
          reminder['call_attempts'] = totalAttempts;

          if (client != null) {
            final remId = reminder['id'];
            if (remId != null) {
              final payload = <String, dynamic>{
                'call_duration': duration,
                'called_timestamp': calledTime.toIso8601String(),
                'called_by': userEmail,
                'status': 'called',
                'call_attempts': totalAttempts,
                'updated_at': now.toIso8601String(),
              };

              try {
                await client.from('dme_reminders').update(payload).eq('id', remId);
                final uid = userUid ?? userEmail;
                await DmeUserStatsService.incrementCallCount(
                  userUid: uid,
                  userEmail: userEmail,
                  statDate: statDate,
                );
              } catch (err) {
                if (err.toString().contains('called_by')) {
                  payload.remove('called_by');
                  await client.from('dme_reminders').update(payload).eq('id', remId);
                  final uid = userUid ?? userEmail;
                  await DmeUserStatsService.incrementCallCount(
                    userUid: uid,
                    userEmail: userEmail,
                    statDate: statDate,
                  );
                }
              }
            }
          }
          detected.add(reminder);
        } else if (totalAttempts > 0) {
          // Update attempt count in DB even if <= 10s, but do NOT mark as 'called'
          reminder['call_attempts'] = totalAttempts;
          if (client != null) {
            final remId = reminder['id'];
            if (remId != null) {
              try {
                await client.from('dme_reminders').update({
                  'call_attempts': totalAttempts,
                  'updated_at': now.toIso8601String(),
                }).eq('id', remId);
              } catch (_) {}
            }
          }
        }
      }

      return detected;
    } catch (e) {
      debugPrint('Error scanning DME call log: $e');
      return [];
    }
  }
}
