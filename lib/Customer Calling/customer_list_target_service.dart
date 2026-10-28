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

  static String _normalizePhone(dynamic phone) {
    if (phone == null) return '';
    final cleaned = phone.toString().replaceAll(RegExp(r'\D'), '');
    if (cleaned.length > 10) {
      return cleaned.substring(cleaned.length - 10);
    }
    return cleaned;
  }

  static bool _matchesCustomer(
    Map c,
    String targetName,
    String targetContact1Norm,
    String targetContact2Norm,
  ) {
    final cName = (c['name'] ?? '').toString().trim().toLowerCase();
    final c1Norm = _normalizePhone(c['contact1'] ?? c['contact'] ?? c['phone']);
    final c2Norm = _normalizePhone(c['contact2']);

    final hasTargetPhone =
        targetContact1Norm.isNotEmpty || targetContact2Norm.isNotEmpty;
    bool phoneMatch = false;
    if (hasTargetPhone) {
      if (targetContact1Norm.isNotEmpty &&
          (c1Norm == targetContact1Norm || c2Norm == targetContact1Norm)) {
        phoneMatch = true;
      }
      if (targetContact2Norm.isNotEmpty &&
          (c1Norm == targetContact2Norm || c2Norm == targetContact2Norm)) {
        phoneMatch = true;
      }
    }

    final nameMatch = targetName.isNotEmpty && cName == targetName;

    if (hasTargetPhone && targetName.isNotEmpty) {
      return phoneMatch || nameMatch;
    } else if (hasTargetPhone) {
      return phoneMatch;
    } else {
      return nameMatch;
    }
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
      // Show loading dialog
      if (context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => const Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(20.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(width: 16),
                    Text('Submitting request...'),
                  ],
                ),
              ),
            ),
          ),
        );
      }

      final user = FirebaseAuth.instance.currentUser;
      final effectiveDocId = docId ?? user?.email?.toLowerCase();
      final now = DateTime.now();
      final monthYear = "${monthName(now.month)} ${now.year}";

      try {
        await UserCacheService.instance.ensureLoaded();
      } catch (e) {
        debugPrint('UserCacheService.ensureLoaded error: $e');
      }

      final reqUsername =
          UserCacheService.instance.username ?? user?.displayName ?? user?.email ?? '';
      final reqBranch = UserCacheService.instance.branch ?? '';

      // Mark pendingDeletion locally
      customer['pendingDeletion'] = true;

      try {
        // 1. Create the customer_deletion_requests doc
        final docRef = await FirebaseFirestore.instance
            .collection('customer_deletion_requests')
            .add({
          'monthYear': monthYear,
          'userDocId': effectiveDocId,
          'userEmail': user?.email ?? '',
          'userName': reqUsername,
          'userBranch': reqBranch,
          'customerData': customer,
          'reason': reasonResult,
          'requestedAt': FieldValue.serverTimestamp(),
          'status': 'pending',
          'type': 'deletion',
        });

        // 2. Persist customer['pendingDeletion'] = true directly to Firestore on the latest server list
        //    so we never overwrite previously approved deletions/edits from a stale local list.
        try {
          if (effectiveDocId != null && effectiveDocId.isNotEmpty) {
            final usersRef = FirebaseFirestore.instance
                .collection('customer_target')
                .doc(monthYear)
                .collection('users');

            var targetDocRef = usersRef.doc(effectiveDocId);
            final directSnap = await targetDocRef.get();
            if (!directSnap.exists || directSnap.data()?['customers'] == null) {
              final querySnap = await usersRef.get();
              for (final d in querySnap.docs) {
                if (d.id.toLowerCase() == effectiveDocId.toLowerCase()) {
                  targetDocRef = usersRef.doc(d.id);
                  break;
                }
              }
            }

            final targetName =
                (customer['name'] ?? '').toString().trim().toLowerCase();
            final targetContact1Norm = _normalizePhone(
                customer['contact1'] ?? customer['contact'] ?? customer['phone']);
            final targetContact2Norm = _normalizePhone(customer['contact2']);

            await FirebaseFirestore.instance.runTransaction((transaction) async {
              final snapshot = await transaction.get(targetDocRef);
              if (snapshot.exists && snapshot.data()?['customers'] is List) {
                final List<dynamic> serverCustomers =
                    List<dynamic>.from(snapshot.data()!['customers']);
                bool updated = false;
                for (var c in serverCustomers) {
                  if (c is Map &&
                      _matchesCustomer(
                          c, targetName, targetContact1Norm, targetContact2Norm)) {
                    c['pendingDeletion'] = true;
                    updated = true;
                  }
                }
                if (updated) {
                  transaction.update(targetDocRef, {
                    'customers': serverCustomers,
                    'updated': FieldValue.serverTimestamp(),
                  });
                }
              }
            });
          } else {
            await onUpdateFirestore();
          }
        } catch (e) {
          debugPrint('Warning: Firestore update failed after deletion request creation: $e');
        }

        // Close loading dialog
        if (context.mounted) {
          Navigator.of(context, rootNavigator: true).pop();
        }

        // Trigger FCM notification asynchronously without blocking UI
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
      } catch (e) {
        // Rollback local status on failure
        customer['pendingDeletion'] = false;

        // Dismiss loading dialog if open
        if (context.mounted) {
          Navigator.of(context, rootNavigator: true).pop();
        }

        debugPrint('Error submitting customer deletion request: $e');
        if (context.mounted) {
          showDialog(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Request Failed'),
              content: Text(
                  'Failed to submit deletion request: $e\nPlease check your internet connection and try again.'),
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
}
