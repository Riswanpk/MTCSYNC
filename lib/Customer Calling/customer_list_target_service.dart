import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../Navigation/user_cache_service.dart';

class CustomerListTargetService {
  static String monthName(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return months[month - 1];
  }

  static Future<void> requestCustomerDeletion({
    required BuildContext context,
    required Map<String, dynamic> customer,
    required String? docId,
    required Future<void> Function() onUpdateFirestore,
  }) async {
    final reasonController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final reasonResult = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Request Deletion'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Please provide a mandatory reason for deleting this customer:'),
              const SizedBox(height: 12),
              TextFormField(
                controller: reasonController,
                maxLines: 3,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Enter deletion reason...',
                  border: OutlineInputBorder(),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Reason is required';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, null),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(dialogContext, reasonController.text.trim());
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Submit Request', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (reasonResult != null && reasonResult.isNotEmpty) {
      customer['pendingDeletion'] = true;
      await onUpdateFirestore();

      final user = FirebaseAuth.instance.currentUser;
      final now = DateTime.now();
      final monthYear = "${monthName(now.month)} ${now.year}";

      await UserCacheService.instance.ensureLoaded();
      final reqUsername =
          UserCacheService.instance.username ?? user?.displayName ?? user?.email ?? '';
      final reqBranch = UserCacheService.instance.branch ?? '';

      final docRef = await FirebaseFirestore.instance
          .collection('customer_deletion_requests')
          .add({
        'monthYear': monthYear,
        'userDocId': docId,
        'userEmail': user?.email ?? '',
        'userName': reqUsername,
        'userBranch': reqBranch,
        'customerData': customer,
        'reason': reasonResult,
        'requestedAt': FieldValue.serverTimestamp(),
        'status': 'pending',
      });

      unawaited(() async {
        try {
          final syncHeadQuery = await FirebaseFirestore.instance
              .collection('users')
              .where('role', whereIn: ['sync_head', 'Sync Head'])
              .get();

          final custName = (customer['name'] ?? 'Customer').toString();
          final reqUserBranchStr =
              reqBranch.isNotEmpty ? '$reqUsername ($reqBranch)' : reqUsername;

          for (final doc in syncHeadQuery.docs) {
            final recipientUid = doc.id;
            try {
              await FirebaseFunctions.instanceFor(region: 'asia-south1')
                  .httpsCallable('sendLeadAssignmentNotification')
                  .call(<String, dynamic>{
                'recipientUid': recipientUid,
                'title': 'Customer Deletion Request',
                'body': '$reqUserBranchStr requested deletion of customer "$custName".',
                'notifType': 'customer_deletion_request',
                'leadDocId': docRef.id,
              });
            } catch (e) {
              debugPrint('FCM Warning: failed to send deletion notification to $recipientUid: $e');
            }
          }
        } catch (e) {
          debugPrint('Error triggering deletion request notifications: $e');
        }
      }());

      if (context.mounted) {
        showDialog(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Deletion Request Sent'),
            content: const Text(
                'Deletion request has been sent for approval to the Sync Head.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }
}
