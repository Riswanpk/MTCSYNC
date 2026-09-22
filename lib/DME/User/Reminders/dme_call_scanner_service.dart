import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:call_log/call_log.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import '../../Misc/dme_config.dart';
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
  /// Robust phone number matching for India:
  /// - Exact match
  /// - Suffix match
  /// - Stripping leading zeros (e.g. 09497062072 -> 9497062072)
  /// - Stripping country codes (+91, 91, 091)
  /// - Last 10 digits match (standard Indian mobile / STD length)
  static bool numberMatches(String logNumber, String? contact) {
    if (contact == null || contact.isEmpty) return false;
    final cleanContact = contact.replaceAll(RegExp(r'\D'), '');
    final cleanLog = logNumber.replaceAll(RegExp(r'\D'), '');
    if (cleanContact.isEmpty || cleanLog.isEmpty) return false;

    if (cleanLog == cleanContact) return true;
    if (cleanLog.endsWith(cleanContact) || cleanContact.endsWith(cleanLog)) return true;

    // Remove leading zeros (e.g. 09497062072 -> 9497062072)
    final stripZeroContact = cleanContact.replaceFirst(RegExp(r'^0+'), '');
    final stripZeroLog = cleanLog.replaceFirst(RegExp(r'^0+'), '');
    if (stripZeroContact.isNotEmpty && stripZeroLog.isNotEmpty) {
      if (stripZeroContact == stripZeroLog) return true;
      if (stripZeroLog.endsWith(stripZeroContact) || stripZeroContact.endsWith(stripZeroLog)) return true;
    }

    // Strip Indian country code prefix 91 or 091
    String stripIndiaCode(String s) {
      if (s.startsWith('91') && s.length > 10) return s.substring(2);
      if (s.startsWith('091') && s.length > 11) return s.substring(3);
      return s;
    }

    final cNo91 = stripIndiaCode(stripZeroContact);
    final lNo91 = stripIndiaCode(stripZeroLog);
    if (cNo91.isNotEmpty && lNo91.isNotEmpty) {
      if (cNo91 == lNo91) return true;
      if (lNo91.endsWith(cNo91) || cNo91.endsWith(lNo91)) return true;
    }

    // Match last 10 digits (standard Indian mobile/STD format)
    if (cleanContact.length >= 10 && cleanLog.length >= 10) {
      final subContact = cleanContact.substring(cleanContact.length - 10);
      final subLog = cleanLog.substring(cleanLog.length - 10);
      return subContact == subLog;
    }

    return false;
  }

  /// Normalizes timestamps that may be reported in seconds on older Android devices to milliseconds.
  static int normalizeTimestamp(int? rawTs) {
    if (rawTs == null || rawTs <= 0) return 0;
    if (rawTs < 10000000000) {
      return rawTs * 1000;
    }
    return rawTs;
  }

  /// Compares two DateTime instances to determine if they represent the same call attempt.
  /// Checks:
  /// 1. UTC epoch millisecond difference <= 90 seconds.
  /// 2. Wall-clock difference <= 90 seconds (handles cases where a timestamp was stored as local without UTC offset).
  static bool isSameCall(DateTime a, DateTime b) {
    if ((a.toUtc().millisecondsSinceEpoch - b.toUtc().millisecondsSinceEpoch).abs() <= 90000) {
      return true;
    }
    final aWall = DateTime(a.year, a.month, a.day, a.hour, a.minute, a.second);
    final bWall = DateTime(b.year, b.month, b.day, b.hour, b.minute, b.second);
    if ((aWall.millisecondsSinceEpoch - bWall.millisecondsSinceEpoch).abs() <= 90000) {
      return true;
    }
    return false;
  }

  /// Logs an individual call attempt to `dme_call_logs` table in Supabase with strict deduplication.
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

      // Deduplication check: prevent inserting duplicate row if already recorded within ±90s
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
            return isSameCall(rowDt, now);
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
        'attempt_timestamp': now.toUtc().toIso8601String(),
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

  /// Fetches call log entries for a contact covering yesterday and today:
  /// - Queries from yesterday 00:00:00 up to now + 30m.
  /// - Includes fallback to unfiltered CallLog.query() for older Android / OEM devices.
  /// - Normalizes timestamps (seconds vs milliseconds).
  /// - Returns entries in chronological order.
  static Future<List<CallLogEntry>> fetchTodayCallsForContact(
    String contactPhone, {
    int maxRetries = 2,
    Duration retryDelay = const Duration(milliseconds: 1200),
  }) async {
    await ensureCallLogPermissions();

    final now = DateTime.now();
    final startOfPeriod = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1));
    final endOfPeriod = now.add(const Duration(minutes: 30));

    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      if (attempt > 0) {
        await Future.delayed(retryDelay);
      }

      try {
        Iterable<CallLogEntry> entries = [];
        try {
          entries = await CallLog.query(
            dateFrom: startOfPeriod.millisecondsSinceEpoch,
            dateTo: endOfPeriod.millisecondsSinceEpoch,
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

        // Filter to entries strictly within the period (yesterday 00:00 to now + 30m)
        final periodMatching = matching.where((entry) {
          final ts = normalizeTimestamp(entry.timestamp);
          if (ts <= 0) return false;
          return ts >= startOfPeriod.millisecondsSinceEpoch && ts <= endOfPeriod.millisecondsSinceEpoch;
        }).toList();

        if (periodMatching.isEmpty) continue;

        // Sort chronologically (oldest to newest)
        periodMatching.sort((a, b) => normalizeTimestamp(a.timestamp).compareTo(normalizeTimestamp(b.timestamp)));

        // Keep outgoing calls and qualifying callbacks (customer called back after user attempted call)
        final outgoingList = periodMatching.where((e) => e.callType == CallType.outgoing).toList();
        final firstOutgoingTime = outgoingList.isNotEmpty ? normalizeTimestamp(outgoingList.first.timestamp) : -1;

        final relevant = periodMatching.where((entry) {
          if (entry.callType == CallType.outgoing) return true;
          if (entry.callType == CallType.incoming && firstOutgoingTime > 0) {
            return normalizeTimestamp(entry.timestamp) >= firstOutgoingTime;
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
  /// - Fetches calls from yesterday and today from device call log.
  /// - Deduplicates existing records in `dme_call_logs` in memory so old database duplicates do not inflate count.
  /// - Inserts ONLY new, unrecorded call attempts with UTC timestamp and duration.
  /// - Accurately counts distinct outgoing attempts made today.
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
    List<Map<String, dynamic>> rawExistingLogs = [];
    if (client != null && reminderId != null) {
      try {
        final res = await client
            .from('dme_call_logs')
            .select('*')
            .eq('reminder_id', reminderId)
            .order('attempt_timestamp', ascending: true);
        rawExistingLogs = List<Map<String, dynamic>>.from(res);
      } catch (e) {
        debugPrint('[DmeCallScanner] Error fetching existing call logs: $e');
      }
    }

    // Deduplicate existingLogs in memory to handle any previous duplicate rows in database
    final List<Map<String, dynamic>> existingLogs = [];
    for (var log in rawExistingLogs) {
      final ts = log['attempt_timestamp']?.toString();
      final dt = ts != null ? DateTime.tryParse(ts) : null;
      final bool dup = dt != null && existingLogs.any((u) {
        final uTs = u['attempt_timestamp']?.toString();
        final uDt = uTs != null ? DateTime.tryParse(uTs) : null;
        return uDt != null && isSameCall(dt, uDt);
      });
      if (!dup) {
        existingLogs.add(log);
      }
    }

    int newAttemptsCount = 0;
    final now = DateTime.now();
    final todayStr = DateFormat('yyyy-MM-dd').format(now);

    for (var entry in deviceCalls) {
      final ts = normalizeTimestamp(entry.timestamp);
      if (ts <= 0) continue;
      final callDt = DateTime.fromMillisecondsSinceEpoch(ts);
      final duration = entry.duration ?? 0;
      final callType = entry.callType == CallType.incoming ? 'incoming' : 'outgoing';

      // Check if this entry is already recorded in existingLogs
      final bool alreadyRecorded = existingLogs.any((log) {
        final logTs = log['attempt_timestamp']?.toString();
        if (logTs == null) return false;
        final logDt = DateTime.tryParse(logTs);
        if (logDt == null) return false;
        return isSameCall(logDt, callDt);
      });

      if (!alreadyRecorded && client != null) {
        try {
          final inserted = await client.from('dme_call_logs').insert({
            if (reminderId != null) 'reminder_id': reminderId,
            if (customerId != null) 'customer_id': customerId,
            'caller_uid': callerUid,
            'caller_email': callerEmail,
            'attempt_timestamp': callDt.toUtc().toIso8601String(),
            'ring_duration': duration,
            'call_type': callType,
            'is_answered': duration > 0,
            'call_day': DateFormat('yyyy-MM-dd').format(callDt),
          }).select();

          final newRecord = (inserted as List).isNotEmpty
              ? Map<String, dynamic>.from(inserted.first)
              : {
                  'reminder_id': reminderId,
                  'customer_id': customerId,
                  'caller_uid': callerUid,
                  'caller_email': callerEmail,
                  'attempt_timestamp': callDt.toUtc().toIso8601String(),
                  'ring_duration': duration,
                  'call_type': callType,
                  'is_answered': duration > 0,
                  'call_day': DateFormat('yyyy-MM-dd').format(callDt),
                };

          existingLogs.add(newRecord);
          newAttemptsCount++;
          debugPrint('[DmeCallScanner] Synced NEW call log: duration=$duration, time=$callDt');
        } catch (insertErr) {
          debugPrint('[DmeCallScanner] Error inserting call log: $insertErr');
        }
      }
    }

    // Determine today's distinct attempts:
    // Count distinct outgoing calls made today from deviceCalls or from today's deduplicated dme_call_logs
    final todayDeviceOutgoing = deviceCalls.where((e) {
      if (e.callType != CallType.outgoing) return false;
      final ts = normalizeTimestamp(e.timestamp);
      final dt = DateTime.fromMillisecondsSinceEpoch(ts);
      return DateFormat('yyyy-MM-dd').format(dt) == todayStr;
    }).length;

    final todayLogs = existingLogs.where((l) {
      if (l['call_type'] != 'outgoing') return false;
      final day = l['call_day']?.toString();
      if (day == todayStr) return true;
      final ts = l['attempt_timestamp']?.toString();
      if (ts != null) {
        final dt = DateTime.tryParse(ts);
        if (dt != null && DateFormat('yyyy-MM-dd').format(dt.toLocal()) == todayStr) {
          return true;
        }
      }
      return false;
    }).length;

    final totalTodayAttempts = math.max(todayDeviceOutgoing, todayLogs);

    // Check attended (>10s) and short-attended (<=10s && >0s)
    // Supports calls from yesterday and today
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
      final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      return calls.where((e) {
        if (e.callType != CallType.outgoing) return false;
        final ts = normalizeTimestamp(e.timestamp);
        final dt = DateTime.fromMillisecondsSinceEpoch(ts);
        return DateFormat('yyyy-MM-dd').format(dt) == todayStr;
      }).length;
    } catch (_) {
      return 0;
    }
  }

  /// Fetches the qualifying call log entry for a specific contact (yesterday or today).
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
        final recent = outgoing.where((e) => normalizeTimestamp(e.timestamp) >= sinceMs).toList();
        if (recent.isNotEmpty) return recent.last;
      }
      return outgoing.last;
    }

    return calls.last;
  }

  /// Scans call logs for yesterday and today against the provided reminders:
  /// - Extended to yesterday 00:00:00 through now + 30m.
  /// - Allows customer callbacks (>10s) following an attempt to mark reminder as 'called'.
  /// - Syncs detected calls into `dme_call_logs` deduplicated.
  /// - Updates reminder status, duration, called_by, and accurate attempt counts.
  static Future<List<Map<String, dynamic>>> scanTodayCallLog(
    List<Map<String, dynamic>> reminders, {
    required String userEmail,
    String? userUid,
  }) async {
    final now = DateTime.now();
    final statDate = DateFormat('yyyy-MM-dd').format(now);
    await ensureCallLogPermissions();

    try {
      final startOfPeriod = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1));
      final endOfPeriod = now.add(const Duration(minutes: 30));

      Iterable<CallLogEntry> entries = [];
      try {
        entries = await CallLog.query(
          dateFrom: startOfPeriod.millisecondsSinceEpoch,
          dateTo: endOfPeriod.millisecondsSinceEpoch,
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

        // Filter to entries strictly from yesterday 00:00 through now + 30m
        final periodMatching = matching.where((entry) {
          final ts = normalizeTimestamp(entry.timestamp);
          if (ts <= 0) return false;
          return ts >= startOfPeriod.millisecondsSinceEpoch && ts <= endOfPeriod.millisecondsSinceEpoch;
        }).toList();

        if (periodMatching.isEmpty) continue;

        final outgoingList = periodMatching.where((e) => e.callType == CallType.outgoing).toList()
          ..sort((a, b) => normalizeTimestamp(a.timestamp).compareTo(normalizeTimestamp(b.timestamp)));
        final incomingList = periodMatching.where((e) => e.callType == CallType.incoming).toList()
          ..sort((a, b) => normalizeTimestamp(a.timestamp).compareTo(normalizeTimestamp(b.timestamp)));

        // Must have an outgoing attempt either from device logs (yesterday/today) or previously recorded in reminder DB
        final prevRecordedAttempts = int.tryParse(reminder['call_attempts']?.toString() ?? '') ?? 0;
        final hasOutgoingAttempt = outgoingList.isNotEmpty || prevRecordedAttempts > 0;
        if (!hasOutgoingAttempt) continue;

        final firstOutgoingTime = outgoingList.isNotEmpty
            ? normalizeTimestamp(outgoingList.first.timestamp)
            : startOfPeriod.millisecondsSinceEpoch;

        // Distinct outgoing calls made today
        final todayOutgoingList = outgoingList.where((e) {
          final ts = normalizeTimestamp(e.timestamp);
          final dt = DateTime.fromMillisecondsSinceEpoch(ts);
          return DateFormat('yyyy-MM-dd').format(dt) == statDate;
        }).toList();
        final totalTodayAttempts = todayOutgoingList.length;

        // Sync every call to dme_call_logs deduplicated
        final remId = reminder['id'];
        final custId = reminder['customer_id'];
        if (client != null && remId != null) {
          for (var callEntry in periodMatching) {
            final cTs = normalizeTimestamp(callEntry.timestamp);
            if (cTs <= 0) continue;
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
          if ((inc.duration ?? 0) > 10 && normalizeTimestamp(inc.timestamp) >= firstOutgoingTime) {
            qualifyingAttended.add(inc);
          }
        }

        qualifyingAttended.sort((a, b) => normalizeTimestamp(b.timestamp).compareTo(normalizeTimestamp(a.timestamp)));

        // Calculate accurate attempt counts
        final int prevDaysAttempts = (reminder['last_call_day'] == statDate)
            ? ((int.tryParse(reminder['call_attempts']?.toString() ?? '') ?? 0) -
                    (int.tryParse(reminder['today_call_attempts']?.toString() ?? '') ?? 0))
                .clamp(0, 9999)
            : (int.tryParse(reminder['call_attempts']?.toString() ?? '') ?? 0);
        final int computedTotalAttempts = prevDaysAttempts + totalTodayAttempts;

        if (qualifyingAttended.isNotEmpty) {
          final matchedEntry = qualifyingAttended.first;
          final duration = matchedEntry.duration ?? 0;
          final calledTime = matchedEntry.timestamp != null
              ? DateTime.fromMillisecondsSinceEpoch(normalizeTimestamp(matchedEntry.timestamp))
              : now;

          reminder['call_duration'] = duration;
          reminder['called_timestamp'] = calledTime.toIso8601String();
          reminder['called_by'] = userEmail;
          reminder['status'] = 'called';
          reminder['today_call_attempts'] = totalTodayAttempts;
          reminder['call_attempts'] = computedTotalAttempts;
          reminder['last_call_attempt_timestamp'] = calledTime.toIso8601String();
          reminder['last_call_day'] = statDate;

          if (client != null && remId != null) {
            final payload = <String, dynamic>{
              'call_duration': duration,
              'called_timestamp': calledTime.toIso8601String(),
              'called_by': userEmail,
              'status': 'called',
              'call_attempts': computedTotalAttempts,
              'today_call_attempts': totalTodayAttempts,
              'last_call_attempt_timestamp': calledTime.toUtc().toIso8601String(),
              'last_call_day': statDate,
              'updated_at': now.toUtc().toIso8601String(),
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
          reminder['call_attempts'] = computedTotalAttempts;
          reminder['called_by'] = userEmail;
          final lastCallTime = outgoingList.last.timestamp != null
              ? DateTime.fromMillisecondsSinceEpoch(normalizeTimestamp(outgoingList.last.timestamp))
              : now;
          reminder['last_call_attempt_timestamp'] = lastCallTime.toIso8601String();
          reminder['last_call_day'] = statDate;

          if (client != null && remId != null) {
            try {
              await client.from('dme_reminders').update({
                'call_attempts': computedTotalAttempts,
                'today_call_attempts': totalTodayAttempts,
                'last_call_attempt_timestamp': lastCallTime.toUtc().toIso8601String(),
                'last_call_day': statDate,
                'called_by': userEmail,
                'updated_at': now.toUtc().toIso8601String(),
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
