import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

String customerUniqueKey(Map<String, dynamic> customer) {
  final c1 = customer['contact1'] ?? customer['contact'] ?? '';
  final name = customer['name'] ?? '';
  return '${name}_$c1'.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
}

Future<void> savePendingCallState(Map<String, dynamic> customer, String? pendingCallNumber, DateTime? callStartTime) async {
  final prefs = await SharedPreferences.getInstance();
  final key = customerUniqueKey(customer);
  await prefs.setString('pending_call_number_$key', pendingCallNumber ?? '');
  await prefs.setInt('pending_call_time_$key', callStartTime?.millisecondsSinceEpoch ?? 0);
}

Future<void> clearPendingCallState(Map<String, dynamic> customer) async {
  final prefs = await SharedPreferences.getInstance();
  final key = customerUniqueKey(customer);
  await prefs.remove('pending_call_number_$key');
  await prefs.remove('pending_call_time_$key');
}

Future<void> makeCall(
  BuildContext context,
  Map<String, dynamic> customer,
  String contact1, [
  String? contact2,
  Function(String numberToCall, DateTime startTime)? onCallInitiated,
]) async {
  if (contact1.trim().isEmpty) {
    if (contact2 == null || contact2.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No contact number available')),
      );
      return;
    }
    contact1 = contact2;
    contact2 = null;
  }
  String? numberToCall = contact1;
  if (contact2 != null && contact2.isNotEmpty) {
    numberToCall = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Select Number to Call'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, contact1),
            child: Text(contact1),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, contact2),
            child: Text(contact2!),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (numberToCall == null) return;
  }
  var status = await Permission.phone.request();
  if (!status.isGranted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Phone permission denied')),
    );
    return;
  }
  final uri = Uri(scheme: 'tel', path: numberToCall);
  if (await canLaunchUrl(uri)) {
    final startTime = DateTime.now();
    await savePendingCallState(customer, numberToCall, startTime);
    customer['lastCalledNumber'] = numberToCall;
    if (onCallInitiated != null) {
      onCallInitiated(numberToCall, startTime);
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not launch dialer')),
    );
  }
}
