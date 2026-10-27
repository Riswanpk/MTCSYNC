import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:call_log/call_log.dart';
import 'make_call.dart';
import 'update_call_status_in_firestore.dart';

bool _matchNumbers(String logNumber, String? contact) {
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

  // Match last 10 digits
  if (cleanContact.length >= 10 && cleanLog.length >= 10) {
    final subContact = cleanContact.substring(cleanContact.length - 10);
    final subLog = cleanLog.substring(cleanLog.length - 10);
    return subContact == subLog;
  }
  return false;
}

int _normalizeTs(int? ts) {
  if (ts == null || ts <= 0) return 0;
  if (ts < 10000000000) return ts * 1000;
  return ts;
}


/// Fetches call log robustly. Some OEMs (e.g. Xiaomi HyperOS) return partial
/// or empty results for date-filtered queries, so merge with an unfiltered query.
Future<List<CallLogEntry>> _fetchEntries(DateTime from, DateTime to) async {
  final Map<String, CallLogEntry> merged = {};
  void add(Iterable<CallLogEntry> list) {
    for (final e in list) {
      merged['${e.timestamp}_${e.number}_${e.duration}'] = e;
    }
  }

  try {
    add(await CallLog.query(
      dateFrom: from.millisecondsSinceEpoch,
      dateTo: to.millisecondsSinceEpoch,
    ));
  } catch (_) {}
  try {
    add(await CallLog.get());
  } catch (_) {}
  return merged.values.toList();
}

/// Outgoing-like: anything that is not clearly incoming/missed/rejected/blocked.
bool _isOutgoingLike(CallLogEntry e) {
  final t = e.callType;
  return t != CallType.incoming &&
      t != CallType.missed &&
      t != CallType.rejected &&
      t != CallType.blocked &&
      t != CallType.voiceMail &&
      t != CallType.answeredExternally;
}

bool _numberMatches(CallLogEntry e, String? c1, String? c2, [String? c3]) {
  for (final n in [e.number, e.formattedNumber]) {
    if (n == null || n.isEmpty) continue;
    if (_matchNumbers(n, c1) || _matchNumbers(n, c2) || (c3 != null && _matchNumbers(n, c3))) return true;
  }
  return false;
}
Future<bool> _ensurePermissions() async {
  var status = await Permission.phone.status;
  if (!status.isGranted) {
    status = await Permission.phone.request();
  }
  return status.isGranted;
}

Future<bool> checkIfCallWasMade({
  required Map<String, dynamic> customer,
  required String? pendingCallNumber,
  required DateTime? callStartTime,
  required BuildContext? context,
  required bool mounted,
  required Function() onCallDetected,
}) async {
  if (pendingCallNumber == null || callStartTime == null) return false;
  if (!await _ensurePermissions()) return false;
  try {
    final now = DateTime.now();
    // Allow 5 minutes prior to callStartTime to tolerate dialer latency and clock skew
    final queryStart = callStartTime.subtract(const Duration(minutes: 5));
    final queryEnd = now.add(const Duration(minutes: 30));

    
    final entries = await _fetchEntries(queryStart, queryEnd);
    String? c1 = customer['contact1'] ?? customer['contact'];
    String? c2 = customer['contact2'];
    bool callMade = entries.any((entry) {
      final ts = _normalizeTs(entry.timestamp);
      if (ts < queryStart.millisecondsSinceEpoch) return false;
      bool wasConnected = (entry.duration ?? 0) > 15;
      return _isOutgoingLike(entry) && wasConnected && _numberMatches(entry, c1, c2, pendingCallNumber);
    });
    if (callMade) {
      customer['callMade'] = true;
      customer['callDate'] = Timestamp.now();
      await clearPendingCallState(customer);
      await updateCallStatusInFirestore(
        customer: customer,
        context: context,
        mounted: mounted,
      );
      onCallDetected();
      if (context != null && context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text('Call detected! Please add remarks.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
      return true;
    }
  } catch (e) {
    debugPrint('Error checking call log: $e');
  }
  return false;
}

Future<bool> checkForAnyRecentCall({
  required Map<String, dynamic> customer,
  required BuildContext? context,
  required bool mounted,
  required Function() onCallDetected,
}) async {
  if (customer['callMade'] == true) return false;
  if (!await _ensurePermissions()) return false;
  try {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfPeriod = now.add(const Duration(minutes: 30));

    
    final entries = await _fetchEntries(startOfDay, endOfPeriod);
    String? c1 = customer['contact1'] ?? customer['contact'];
    String? c2 = customer['contact2'];

    int latestOutgoingTime = -1;
    for (final entry in entries) {
      if (!_isOutgoingLike(entry)) continue;
      final ts = _normalizeTs(entry.timestamp);
      if (ts < startOfDay.millisecondsSinceEpoch) continue;
      if (_numberMatches(entry, c1, c2)) {
        if (ts > latestOutgoingTime) {
          latestOutgoingTime = ts;
        }
      }
    }
    if (latestOutgoingTime == -1) return false;

    bool hasLongCall = entries.any((entry) {
      final ts = _normalizeTs(entry.timestamp);
      if (ts < latestOutgoingTime) return false;
      bool longEnough = (entry.duration ?? 0) > 15;
      return longEnough && _numberMatches(entry, c1, c2);
    });
    if (hasLongCall) {
      customer['callMade'] = true;
      customer['callDate'] = Timestamp.now();
      await clearPendingCallState(customer);
      await updateCallStatusInFirestore(
        customer: customer,
        context: context,
        mounted: context != null && context.mounted,
      );
      onCallDetected();
      if (context != null && context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text('Call detected! Please add remarks.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
      return true;
    }
  } catch (e) {
    debugPrint('Error scanning today call log: $e');
  }
  return false;
}

Future<void> reloadCallStatus({
  required Map<String, dynamic> customer,
  required bool called,
  required BuildContext context,
  required bool mounted,
  required Function() onCallDetected,
}) async {
  if (called) {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Call already marked.'), backgroundColor: Colors.green),
      );
    }
    return;
  }
  if (!await _ensurePermissions()) {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Call Log permission is required to detect calls.'),
          backgroundColor: Colors.red,
        ),
      );
    }
    return;
  }
  try {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfPeriod = now.add(const Duration(minutes: 30));

    
    final entries = await _fetchEntries(startOfDay, endOfPeriod);
    String? c1 = customer['contact1'] ?? customer['contact'];
    String? c2 = customer['contact2'];

    bool hasOutgoingLongCall = entries.any((entry) {
      if (!_isOutgoingLike(entry)) return false;
      final ts = _normalizeTs(entry.timestamp);
      if (ts < startOfDay.millisecondsSinceEpoch) return false;
      bool longEnough = (entry.duration ?? 0) > 15;
      return longEnough && _numberMatches(entry, c1, c2);
    });

    if (hasOutgoingLongCall) {
      customer['callMade'] = true;
      customer['callDate'] = Timestamp.now();
      await clearPendingCallState(customer);
      await updateCallStatusInFirestore(
        customer: customer,
        context: context,
        mounted: context.mounted,
      );
      onCallDetected();
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text('Call detected! Please add remarks.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } else {
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text('No outgoing call (>15s) found today.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  } catch (e) {
    debugPrint('Error reloading call status: $e');
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Error checking call log: $e'), backgroundColor: Colors.red),
      );
    }
  }
}

