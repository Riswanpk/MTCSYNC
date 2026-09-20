import 'package:call_log/call_log.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class CallScannerService {
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

  /// Scans today's call logs and returns a list of customers that match the call criteria
  /// (outgoing call initiated today, and any call >= outgoing call time lasting >15 seconds).
  static Future<List<Map<String, dynamic>>> scanTodayCallLog(
      List<Map<String, dynamic>> customers) async {
    final permStatus = await Permission.phone.status;
    if (!permStatus.isGranted) return [];

    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final startEpoch = startOfDay.millisecondsSinceEpoch - (5 * 60 * 1000); // 5 min buffer for clock drift
      final endEpoch = now.millisecondsSinceEpoch + (30 * 60 * 1000);

      Iterable<CallLogEntry> entries = [];
      try {
        entries = await CallLog.query(
          dateFrom: startEpoch,
          dateTo: endEpoch,
        );
      } catch (e) {
        debugPrint('CallScannerService: Parameterized query failed on device, falling back to unfiltered: $e');
      }

      // Older Android fallback: some Android ROMs return empty or throw on parameterized CallLog.query
      if (entries.isEmpty) {
        try {
          final allEntries = await CallLog.query();
          entries = allEntries.where((e) {
            final ts = normalizeTimestamp(e.timestamp);
            return ts >= startEpoch && ts <= endEpoch;
          }).toList();
        } catch (e) {
          debugPrint('CallScannerService: Unfiltered query fallback failed: $e');
        }
      }

      final List<Map<String, dynamic>> matchedCustomers = [];

      for (var customer in customers) {
        if (customer['callMade'] == true) continue;

        String? c1 = customer['contact1'] ?? customer['contact'];
        String? c2 = customer['contact2'];

        int latestOutgoingTime = -1;
        for (final entry in entries) {
          if (entry.callType != CallType.outgoing) continue;
          String logNumber = entry.number?.replaceAll(RegExp(r'\D'), '') ?? '';
          if (logNumber.isEmpty) continue;
          if (numberMatches(logNumber, c1) || numberMatches(logNumber, c2)) {
            final ts = normalizeTimestamp(entry.timestamp);
            if (ts > latestOutgoingTime) {
              latestOutgoingTime = ts;
            }
          }
        }
        if (latestOutgoingTime == -1) continue;

        bool hasLongCall = entries.any((entry) {
          final ts = normalizeTimestamp(entry.timestamp);
          if (ts < latestOutgoingTime) return false;
          String logNumber = entry.number?.replaceAll(RegExp(r'\D'), '') ?? '';
          if (logNumber.isEmpty) return false;
          bool longEnough = (entry.duration ?? 0) > 15;
          return (numberMatches(logNumber, c1) || numberMatches(logNumber, c2)) && longEnough;
        });

        if (hasLongCall) {
          matchedCustomers.add(customer);
        }
      }

      return matchedCustomers;
    } catch (e) {
      debugPrint('Error scanning call log: $e');
      return [];
    }
  }
}
