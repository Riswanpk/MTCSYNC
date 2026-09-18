import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:call_log/call_log.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import '../../dme_config.dart';
import 'package:mtcsync/DME/User/dme_user_stats_service.dart';

/// Result object for syncing call logs for a specific reminder
class DmeCallSyncResult {
  final int newAttemptsLogged;
  final int totalTodayAttempts;
  final CallLogEntry? qualifyingEntry;
  final CallLogEntry? latestEntry;
  final bool hasAttendedCall;
  final bool hasShortCall;
  final List<Map<String, dynamic>> recordedLogs;

  DmeCallSyncResult({
    required this.newAttemptsLogged,
    required this.totalTodayAttempts,
    this.qualifyingEntry,
    this.latestEntry,
    required this.hasAttendedCall,
    required this.hasShortCall,
    required this.recordedLogs,
  });
}

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

  /// Logs an individual call attempt to `dme_call_logs` table in Supabase with deduplication.
  static Future<void> logCallAttempt({
    required dynamic reminderId,
    required dynamic customerId,
    String? callerEmail,
    String? callerUid,
    required int ringDuration,
    String callType = 'outgoing',
    required bool isAnswered,
    DateTime? attemptTimestamp,
  }) async {
    try {
      final client = await DmeConfig.getClient();
      if (client == null) {
        debugPrint('[DmeCallScanner] Supabase client is null. Cannot insert to dme_call_logs.');
        return;
      }
      final now = attemptTimestamp ?? DateTime.now();
      final statDate = DateFormat('yyyy-MM-dd').format(now);

      // Deduplication check: prevent inserting duplicate row if already recorded within ±5s
      if (reminderId != null) {
        try {
          final existing = await client
              .from('dme_call_logs')
              .select('id, attempt_timestamp')
              .eq('reminder_id', reminderId);
          final bool alreadyExists = (existing as List).any((row) {
            final rowTs = row['attempt_timestamp']?.toString();
            if (rowTs == null) return false;
            final rowDt = DateTime.tryParse(rowTs);
            if (rowDt == null) return false;
            return (rowDt.millisecondsSinceEpoch - now.millisecondsSinceEpoch).abs() <= 5000;
          });
          if (alreadyExists) {
            debugPrint('[DmeCallScanner] Duplicate call attempt prevented for reminder $reminderId at $now');
            return;
          }
        } catch (_) {}
      }

      await client.from('dme_call_logs').insert({
        if (reminderId != null) 'reminder_id': reminderId,
        if (customerId != null) 'customer_id': customerId,
        'caller_uid': callerUid,
        'caller_email': callerEmail,
        'attempt_timestamp': now.toIso8601String(),
        'ring_duration': ringDuration,
        'call_type': callType,
        'is_answered': isAnswered,
        'call_day': statDate,
      });
      debugPrint('[DmeCallScanner] Successfully inserted call attempt into dme_call_logs (duration: $ringDuration)');
    } catch (e) {
      debugPrint('[DmeCallScanner] dme_call_logs insert FAILED (RLS or schema error): $e');
    }
  }

  /// Ensures phone state and call log permissions are requested and granted.
  static Future<bool> ensureCallLogPermissions() async {
    try {
      var phoneStatus = await Permission.phone.status;
      if (!phoneStatus.isGranted) {
        phoneStatus = await Permission.phone.request();
      }
      return phoneStatus.isGranted;
    } catch (e) {
      debugPrint('ensureCallLogPermissions warning: $e');
      return true;
    }
  }

  /// Fetches all call log entries for a contact today:
  /// - Queries the full duration of today (from 00:00:00 - 1h up to now + 30m).
  /// - Includes fallback for Android 10 OEM devices.
  /// - Returns entries in chronological order.
  static Future<List<CallLogEntry>> fetchTodayCallsForContact(
    String contactPhone, {
    int maxRetries = 2,
    Duration retryDelay = const Duration(milliseconds: 1200),
  }) async {
    await ensureCallLogPermissions();

    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day).subtract(const Duration(hours: 1));
    final endOfToday = now.add(const Duration(minutes: 30));

    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      if (attempt > 0) {
        await Future.delayed(retryDelay);
      }

      try {
        Iterable<CallLogEntry> entries = [];
        try {
          entries = await CallLog.query(
            dateFrom: startOfToday.millisecondsSinceEpoch,
            dateTo: endOfToday.millisecondsSinceEpoch,
          );
        } catch (queryErr) {
          debugPrint('[DmeCallScanner] date-filtered query failed ($queryErr). Falling back to unfiltered query.');
        }

        if (entries.isEmpty) {
          try {
            entries = await CallLog.query();
          } catch (e) {
            debugPrint('[DmeCallScanner] Fallback unfiltered query failed: $e');
          }
        }

        final matching = entries.where((entry) {
          final logNumber = entry.number?.replaceAll(RegExp(r'\D'), '') ?? '';
          if (logNumber.isEmpty) return false;
          return numberMatches(logNumber, contactPhone);
        }).toList();

        if (matching.isEmpty) continue;

        // Filter to entries strictly from today
        final todayMatching = matching.where((entry) {
          final ts = entry.timestamp;
          if (ts == null || ts <= 0) return false;
          return ts >= startOfToday.millisecondsSinceEpoch && ts <= endOfToday.millisecondsSinceEpoch;
        }).toList();

        if (todayMatching.isEmpty) continue;

        // Sort chronologically (oldest to newest)
        todayMatching.sort((a, b) => (a.timestamp ?? 0).compareTo(b.timestamp ?? 0));

        // Keep outgoing calls and qualifying callbacks (customer called back after user attempted call)
        final outgoingList = todayMatching.where((e) => e.callType == CallType.outgoing).toList();
        final firstOutgoingTime = outgoingList.isNotEmpty ? (outgoingList.first.timestamp ?? 0) : -1;

        final relevant = todayMatching.where((entry) {
          if (entry.callType == CallType.outgoing) return true;
          if (entry.callType == CallType.incoming && firstOutgoingTime > 0) {
            return (entry.timestamp ?? 0) >= firstOutgoingTime;
          }
          return false;
        }).toList();

        if (relevant.isNotEmpty) {
          return relevant;
        }
      } catch (e) {
        debugPrint('[DmeCallScanner] Error fetching calls for contact ($attempt): $e');
      }
    }
    return [];
  }

  /// Synchronizes device call logs with `dme_call_logs` table for a specific reminder:
  /// - Fetches all calls today from device call log.
  /// - Checks existing rows in `dme_call_logs` for `reminder_id`.
  /// - Inserts ONLY new, unrecorded call attempts with timestamp and duration.
  /// - Never duplicates attempts or database rows.
  static Future<DmeCallSyncResult> syncCallLogsForReminder({
    required dynamic reminderId,
    required dynamic customerId,
    required String contactPhone,
    String? callerEmail,
    String? callerUid,
    int maxRetries = 2,
  }) async {
    final client = await DmeConfig.getClient();
    final deviceCalls = await fetchTodayCallsForContact(
      contactPhone,
      maxRetries: maxRetries,
    );

    // Fetch existing records from dme_call_logs for this reminder
    List<Map<String, dynamic>> existingLogs = [];
    if (client != null && reminderId != null) {
      try {
        final res = await client
            .from('dme_call_logs')
            .select('*')
            .eq('reminder_id', reminderId)
            .order('attempt_timestamp', ascending: true);
        existingLogs = List<Map<String, dynamic>>.from(res);
      } catch (e) {
        debugPrint('[DmeCallScanner] Error fetching existing call logs: $e');
      }
    }

    int newAttemptsCount = 0;
    final now = DateTime.now();
    final todayStr = DateFormat('yyyy-MM-dd').format(now);

    for (var entry in deviceCalls) {
      final ts = entry.timestamp;
      if (ts == null || ts <= 0) continue;
      final callDt = DateTime.fromMillisecondsSinceEpoch(ts);
      final duration = entry.duration ?? 0;
      final callType = entry.callType == CallType.incoming ? 'incoming' : 'outgoing';

      // Check if this entry is already recorded in existingLogs
      final bool alreadyRecorded = existingLogs.any((log) {
        final logTs = log['attempt_timestamp']?.toString();
        if (logTs == null) return false;
        final logDt = DateTime.tryParse(logTs);
        if (logDt == null) return false;
        // Timestamp within ±5000ms considered the exact same call
        return (logDt.millisecondsSinceEpoch - callDt.millisecondsSinceEpoch).abs() <= 5000;
      });

      if (!alreadyRecorded && client != null) {
        try {
          final inserted = await client.from('dme_call_logs').insert({
            if (reminderId != null) 'reminder_id': reminderId,
            if (customerId != null) 'customer_id': customerId,
            'caller_uid': callerUid,
            'caller_email': callerEmail,
            'attempt_timestamp': callDt.toIso8601String(),
            'ring_duration': duration,
            'call_type': callType,
            'is_answered': duration > 0,
            'call_day': DateFormat('yyyy-MM-dd').format(callDt),
          }).select();

          if ((inserted as List).isNotEmpty) {
            existingLogs.add(Map<String, dynamic>.from(inserted.first));
          } else {
            existingLogs.add({
              'reminder_id': reminderId,
              'customer_id': customerId,
              'caller_uid': callerUid,
              'caller_email': callerEmail,
              'attempt_timestamp': callDt.toIso8601String(),
              'ring_duration': duration,
              'call_type': callType,
              'is_answered': duration > 0,
              'call_day': DateFormat('yyyy-MM-dd').format(callDt),
            });
          }
          newAttemptsCount++;
          debugPrint('[DmeCallScanner] Synced NEW call log: duration=$duration, time=$callDt');
        } catch (insertErr) {
          debugPrint('[DmeCallScanner] Error inserting call log: $insertErr');
        }
      }
    }

    // Determine today's distinct attempts:
    // Count distinct outgoing calls made today from deviceCalls, or from today's dme_call_logs
    final todayDeviceOutgoing = deviceCalls.where((e) => e.callType == CallType.outgoing).length;
    final todayLogs = existingLogs.where((l) {
      final day = l['call_day']?.toString();
      if (day == todayStr) return true;
      final ts = l['attempt_timestamp']?.toString();
      if (ts != null) {
        final dt = DateTime.tryParse(ts);
        if (dt != null && DateFormat('yyyy-MM-dd').format(dt) == todayStr) {
          return true;
        }
      }
      return false;
    }).length;

    final totalTodayAttempts = math.max(todayDeviceOutgoing, todayLogs);

    // Check attended (>10s) and short-attended (<=10s && >0s)
    bool hasAttended = false;
    bool hasShort = false;
    CallLogEntry? qualifyingAttended;
    CallLogEntry? latestOutgoing;

    for (var entry in deviceCalls) {
      final dur = entry.duration ?? 0;
      if (dur > 10) {
        hasAttended = true;
        qualifyingAttended = entry;
      } else if (dur > 0 && dur <= 10) {
        hasShort = true;
      }
      if (entry.callType == CallType.outgoing) {
        latestOutgoing = entry;
      }
    }

    // Also check existingLogs in case call was logged earlier or on another device
    for (var log in existingLogs) {
      final dur = int.tryParse(log['ring_duration']?.toString() ?? '') ?? 0;
      if (dur > 10) {
        hasAttended = true;
      } else if (dur > 0 && dur <= 10) {
        hasShort = true;
      }
    }

    final qualifyingEntry = qualifyingAttended ?? latestOutgoing ?? (deviceCalls.isNotEmpty ? deviceCalls.last : null);
    final latestEntry = deviceCalls.isNotEmpty ? deviceCalls.last : null;

    // Sort existingLogs descending by attempt_timestamp for display
    existingLogs.sort((a, b) {
      final aTs = a['attempt_timestamp']?.toString() ?? '';
      final bTs = b['attempt_timestamp']?.toString() ?? '';
      return bTs.compareTo(aTs);
    });

    return DmeCallSyncResult(
      newAttemptsLogged: newAttemptsCount,
      totalTodayAttempts: totalTodayAttempts,
      qualifyingEntry: qualifyingEntry,
      latestEntry: latestEntry,
      hasAttendedCall: hasAttended,
      hasShortCall: hasShort,
      recordedLogs: existingLogs,
    );
  }

  /// Returns total number of outgoing call attempts to this contact made today.
  static Future<int> getTodayOutgoingAttemptCount(String contactPhone) async {
    try {
      final calls = await fetchTodayCallsForContact(contactPhone, maxRetries: 1);
      return calls.where((e) => e.callType == CallType.outgoing).length;
    } catch (_) {
      return 0;
    }
  }

  /// Fetches the qualifying call log entry for a specific contact today.
  static Future<CallLogEntry?> fetchLatestCallForContact(
    String contactPhone, {
    DateTime? sinceTime,
    int maxRetries = 4,
    Duration retryDelay = const Duration(milliseconds: 1800),
  }) async {
    final calls = await fetchTodayCallsForContact(
      contactPhone,
      maxRetries: maxRetries,
      retryDelay: retryDelay,
    );
    if (calls.isEmpty) return null;

    // Find qualifying attended calls (> 10s)
    final attended = calls.where((e) => (e.duration ?? 0) > 10).toList();
    if (attended.isNotEmpty) {
      return attended.last;
    }

    // Outgoing attempts
    final outgoing = calls.where((e) => e.callType == CallType.outgoing).toList();
    if (outgoing.isNotEmpty) {
      if (sinceTime != null) {
        final sinceMs = sinceTime.subtract(const Duration(minutes: 5)).millisecondsSinceEpoch;
        final recent = outgoing.where((e) => (e.timestamp ?? 0) >= sinceMs).toList();
        if (recent.isNotEmpty) return recent.last;
      }
      return outgoing.last;
    }

    return calls.last;
  }

  /// Scans today's call logs (same day only) against the provided reminders:
  /// - Strictly same day (00:00:00 to now).
  /// - Syncs detected calls into `dme_call_logs` deduplicated.
  /// - Updates reminder status, duration, called_by, and attempt counts.
  static Future<List<Map<String, dynamic>>> scanTodayCallLog(
    List<Map<String, dynamic>> reminders, {
    required String userEmail,
    String? userUid,
  }) async {
    final statDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
    await ensureCallLogPermissions();

    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      Iterable<CallLogEntry> entries = [];
      try {
        entries = await CallLog.query(
          dateFrom: startOfDay.millisecondsSinceEpoch,
          dateTo: now.millisecondsSinceEpoch,
        );
      } catch (_) {}

      if (entries.isEmpty) {
        try {
          entries = await CallLog.query();
        } catch (_) {}
      }

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

        // Filter to entries strictly from today
        final todayMatching = matching.where((entry) {
          final ts = entry.timestamp;
          if (ts == null || ts <= 0) return false;
          return ts >= startOfDay.millisecondsSinceEpoch;
        }).toList();

        if (todayMatching.isEmpty) continue;

        final outgoingList = todayMatching.where((e) => e.callType == CallType.outgoing).toList()
          ..sort((a, b) => (a.timestamp ?? 0).compareTo(b.timestamp ?? 0));
        final incomingList = todayMatching.where((e) => e.callType == CallType.incoming).toList()
          ..sort((a, b) => (a.timestamp ?? 0).compareTo(b.timestamp ?? 0));

        // User must have attempted to call first that same day
        if (outgoingList.isEmpty) continue;

        final firstOutgoingTime = outgoingList.first.timestamp ?? 0;
        final totalTodayAttempts = outgoingList.length;

        // Sync every today's call to dme_call_logs deduplicated
        final remId = reminder['id'];
        final custId = reminder['customer_id'];
        if (client != null && remId != null) {
          for (var callEntry in todayMatching) {
            final cTs = callEntry.timestamp;
            if (cTs == null || cTs <= 0) continue;
            final callDt = DateTime.fromMillisecondsSinceEpoch(cTs);
            final cDur = callEntry.duration ?? 0;
            final isIncoming = callEntry.callType == CallType.incoming;
            if (isIncoming && cTs < firstOutgoingTime) continue;

            await logCallAttempt(
              reminderId: remId,
              customerId: custId,
              callerEmail: userEmail,
              callerUid: userUid,
              ringDuration: cDur,
              callType: isIncoming ? 'incoming' : 'outgoing',
              isAnswered: cDur > 0,
              attemptTimestamp: callDt,
            );
          }
        }

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
          reminder['today_call_attempts'] = totalTodayAttempts;
          reminder['call_attempts'] = totalTodayAttempts;
          reminder['last_call_attempt_timestamp'] = calledTime.toIso8601String();
          reminder['last_call_day'] = statDate;

          if (client != null && remId != null) {
            final payload = <String, dynamic>{
              'call_duration': duration,
              'called_timestamp': calledTime.toIso8601String(),
              'called_by': userEmail,
              'status': 'called',
              'call_attempts': totalTodayAttempts,
              'today_call_attempts': totalTodayAttempts,
              'last_call_attempt_timestamp': calledTime.toIso8601String(),
              'last_call_day': statDate,
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
          detected.add(reminder);
        } else if (totalTodayAttempts > 0) {
          // Update attempt count in DB even if <= 10s, but do NOT mark as 'called'
          reminder['today_call_attempts'] = totalTodayAttempts;
          final lastCallTime = outgoingList.last.timestamp != null
              ? DateTime.fromMillisecondsSinceEpoch(outgoingList.last.timestamp!)
              : now;
          reminder['last_call_attempt_timestamp'] = lastCallTime.toIso8601String();
          reminder['last_call_day'] = statDate;

          if (client != null && remId != null) {
            try {
              await client.from('dme_reminders').update({
                'today_call_attempts': totalTodayAttempts,
                'last_call_attempt_timestamp': lastCallTime.toIso8601String(),
                'last_call_day': statDate,
                'updated_at': now.toIso8601String(),
              }).eq('id', remId);
            } catch (_) {}
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
