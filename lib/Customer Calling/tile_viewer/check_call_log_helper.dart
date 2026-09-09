import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:call_log/call_log.dart';
import 'make_call.dart';
import 'update_call_status_in_firestore.dart';

bool _matchNumbers(String logNumber, String? contact) {
  if (contact == null || contact.isEmpty) return false;
  String cleanContact = contact.replaceAll(RegExp(r'\D'), '');
  String cleanLog = logNumber.replaceAll(RegExp(r'\D'), '');
  if (cleanContact.isEmpty || cleanLog.isEmpty) return false;

  if (cleanLog == cleanContact) return true;
  if (cleanLog.endsWith(cleanContact) || cleanContact.endsWith(cleanLog)) return true;
  if (cleanContact.length >= 10 && cleanLog.length >= 10) {
    String subContact = cleanContact.substring(cleanContact.length - 10);
    String subLog = cleanLog.substring(cleanLog.length - 10);
    return subContact == subLog;
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
    final Iterable<CallLogEntry> entries = await CallLog.query(
      dateFrom: callStartTime.millisecondsSinceEpoch,
      dateTo: now.millisecondsSinceEpoch,
    );
    String? c1 = customer['contact1'] ?? customer['contact'];
    String? c2 = customer['contact2'];
    bool callMade = entries.any((entry) {
      String logNumber = entry.number ?? '';
      bool wasConnected = (entry.duration ?? 0) > 15;
      bool matches = _matchNumbers(logNumber, c1) || _matchNumbers(logNumber, c2) || _matchNumbers(logNumber, pendingCallNumber);
      return matches && wasConnected;
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
      if (mounted && context != null) {
        ScaffoldMessenger.of(context).showSnackBar(
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
    final Iterable<CallLogEntry> entries = await CallLog.query(
      dateFrom: startOfDay.millisecondsSinceEpoch,
      dateTo: now.millisecondsSinceEpoch,
    );
    String? c1 = customer['contact1'] ?? customer['contact'];
    String? c2 = customer['contact2'];

    int latestOutgoingTime = -1;
    for (final entry in entries) {
      if (entry.callType != CallType.outgoing) continue;
      String logNumber = entry.number ?? '';
      if (logNumber.isEmpty) continue;
      if (_matchNumbers(logNumber, c1) || _matchNumbers(logNumber, c2)) {
        if (entry.timestamp != null && entry.timestamp! > latestOutgoingTime) {
          latestOutgoingTime = entry.timestamp!;
        }
      }
    }
    if (latestOutgoingTime == -1) return false;

    bool hasLongCall = entries.any((entry) {
      if (entry.timestamp == null || entry.timestamp! < latestOutgoingTime) return false;
      String logNumber = entry.number ?? '';
      if (logNumber.isEmpty) return false;
      bool longEnough = (entry.duration ?? 0) > 15;
      return (_matchNumbers(logNumber, c1) || _matchNumbers(logNumber, c2)) && longEnough;
    });
    if (hasLongCall) {
      customer['callMade'] = true;
      customer['callDate'] = Timestamp.now();
      await clearPendingCallState(customer);
      await updateCallStatusInFirestore(
        customer: customer,
        context: context,
        mounted: mounted,
      );
      onCallDetected();
      if (mounted && context != null) {
        ScaffoldMessenger.of(context).showSnackBar(
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Call already marked.'), backgroundColor: Colors.green),
    );
    return;
  }
  if (!await _ensurePermissions()) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
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
    final Iterable<CallLogEntry> entries = await CallLog.query(
      dateFrom: startOfDay.millisecondsSinceEpoch,
      dateTo: now.millisecondsSinceEpoch,
    );
    String? c1 = customer['contact1'] ?? customer['contact'];
    String? c2 = customer['contact2'];

    bool hasOutgoingLongCall = entries.any((entry) {
      if (entry.callType != CallType.outgoing) return false;
      String logNumber = entry.number ?? '';
      if (logNumber.isEmpty) return false;
      bool longEnough = (entry.duration ?? 0) > 15;
      return (_matchNumbers(logNumber, c1) || _matchNumbers(logNumber, c2)) && longEnough;
    });

    if (hasOutgoingLongCall) {
      customer['callMade'] = true;
      customer['callDate'] = Timestamp.now();
      await clearPendingCallState(customer);
      await updateCallStatusInFirestore(
        customer: customer,
        context: context,
        mounted: mounted,
      );
      onCallDetected();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Call detected! Please add remarks.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No outgoing call (>15s) found today.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  } catch (e) {
    debugPrint('Error reloading call status: $e');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error checking call log: $e'), backgroundColor: Colors.red),
      );
    }
  }
}
