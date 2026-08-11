import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:call_log/call_log.dart';
import 'make_call.dart';
import 'update_call_status_in_firestore.dart';

Future<bool> checkIfCallWasMade({
  required Map<String, dynamic> customer,
  required String? pendingCallNumber,
  required DateTime? callStartTime,
  required BuildContext? context,
  required bool mounted,
  required Function() onCallDetected,
}) async {
  if (pendingCallNumber == null || callStartTime == null) return false;
  final permStatus = await Permission.phone.status;
  if (!permStatus.isGranted) return false;
  try {
    final now = DateTime.now();
    final Iterable<CallLogEntry> entries = await CallLog.query(
      dateFrom: callStartTime.millisecondsSinceEpoch,
      dateTo: now.millisecondsSinceEpoch,
    );
    String? c1 = customer['contact1'] ?? customer['contact'];
    String? c2 = customer['contact2'];
    bool callMade = entries.any((entry) {
      String logNumber = entry.number?.replaceAll(RegExp(r'\D'), '') ?? '';
      bool wasConnected = (entry.duration ?? 0) > 15;
      bool matches1 = c1 != null && logNumber.endsWith(c1.replaceAll(RegExp(r'\D'), ''));
      bool matches2 = c2 != null && c2.isNotEmpty && logNumber.endsWith(c2.replaceAll(RegExp(r'\D'), ''));
      return (matches1 || matches2) && wasConnected;
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
  final permStatus = await Permission.phone.status;
  if (!permStatus.isGranted) return false;
  try {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final Iterable<CallLogEntry> entries = await CallLog.query(
      dateFrom: startOfDay.millisecondsSinceEpoch,
      dateTo: now.millisecondsSinceEpoch,
    );
    String? c1 = customer['contact1'] ?? customer['contact'];
    String? c2 = customer['contact2'];

    bool numberMatches(String logNumber, String? contact) {
      if (contact == null || contact.isEmpty) return false;
      String clean = contact.replaceAll(RegExp(r'\D'), '');
      return logNumber.endsWith(clean) || clean.endsWith(logNumber);
    }

    int latestOutgoingTime = -1;
    for (final entry in entries) {
      if (entry.callType != CallType.outgoing) continue;
      String logNumber = entry.number?.replaceAll(RegExp(r'\D'), '') ?? '';
      if (logNumber.isEmpty) continue;
      if (numberMatches(logNumber, c1) || numberMatches(logNumber, c2)) {
        if (entry.timestamp != null && entry.timestamp! > latestOutgoingTime) {
          latestOutgoingTime = entry.timestamp!;
        }
      }
    }
    if (latestOutgoingTime == -1) return false;

    bool hasLongCall = entries.any((entry) {
      if (entry.timestamp == null || entry.timestamp! < latestOutgoingTime) return false;
      String logNumber = entry.number?.replaceAll(RegExp(r'\D'), '') ?? '';
      if (logNumber.isEmpty) return false;
      bool longEnough = (entry.duration ?? 0) > 15;
      return (numberMatches(logNumber, c1) || numberMatches(logNumber, c2)) && longEnough;
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
  final permStatus = await Permission.phone.request();
  if (!permStatus.isGranted) return;
  try {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final Iterable<CallLogEntry> entries = await CallLog.query(
      dateFrom: startOfDay.millisecondsSinceEpoch,
      dateTo: now.millisecondsSinceEpoch,
    );
    String? c1 = customer['contact1'] ?? customer['contact'];
    String? c2 = customer['contact2'];

    bool numberMatches(String logNumber, String? contact) {
      if (contact == null || contact.isEmpty) return false;
      String clean = contact.replaceAll(RegExp(r'\D'), '');
      return logNumber.endsWith(clean) || clean.endsWith(logNumber);
    }

    bool hasOutgoingLongCall = entries.any((entry) {
      if (entry.callType != CallType.outgoing) return false;
      String logNumber = entry.number?.replaceAll(RegExp(r'\D'), '') ?? '';
      if (logNumber.isEmpty) return false;
      bool longEnough = (entry.duration ?? 0) > 15;
      return (numberMatches(logNumber, c1) || numberMatches(logNumber, c2)) && longEnough;
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
