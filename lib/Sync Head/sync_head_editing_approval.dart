import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../Navigation/user_cache_service.dart';
import '../Customer Calling/customer_list_target_service.dart';

export 'sync_head_customer_list_deletion_approval.dart';

class SyncHeadEditingApprovalService {
  /// Prompts user for a reason, marks customer as pendingEditing, and submits edit request to Firestore.
  static Future<bool> requestCustomerEdit({
    required BuildContext context,
    required Map<String, dynamic> customer,
    required Map<String, dynamic> updatedFields,
    required Map<String, dynamic> widgetCustomer,
    required String? docId,
  }) async {
    final reasonController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final reasonResult = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Request Edit Approval'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Please provide a mandatory reason for editing this customer:'),
              const SizedBox(height: 12),
              TextFormField(
                controller: reasonController,
                maxLines: 3,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Enter reason for changes...',
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
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF005BAC)),
            child: const Text('Submit Request', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (reasonResult == null || reasonResult.isEmpty) {
      return false;
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      final effectiveDocId = docId ?? user?.email?.toLowerCase();
      final now = DateTime.now();
      final monthYear = "${CustomerListTargetService.monthName(now.month)} ${now.year}";

      // Mark the customer as pendingEditing in customer_target collection
      if (effectiveDocId != null) {
        final usersRef = FirebaseFirestore.instance
            .collection('customer_target')
            .doc(monthYear)
            .collection('users');

        var docRef = usersRef.doc(effectiveDocId);
        var doc = await docRef.get();

        // If not found with direct effectiveDocId, search case-insensitively
        if (!doc.exists || doc.data()?['customers'] == null) {
          final querySnap = await usersRef.get();
          for (final d in querySnap.docs) {
            if (d.id.toLowerCase() == effectiveDocId.toLowerCase()) {
              docRef = usersRef.doc(d.id);
              doc = d;
              break;
            }
          }
        }

        if (doc.exists && doc.data()?['customers'] != null) {
          List customers = List.from(doc.data()!['customers']);

          final wName = (widgetCustomer['name'] ?? customer['name'] ?? '')
              .toString()
              .trim()
              .toLowerCase();
          final wContact1 = (widgetCustomer['contact1'] ??
                  widgetCustomer['contact'] ??
                  customer['contact1'] ??
                  customer['contact'] ??
                  '')
              .toString()
              .replaceAll(RegExp(r'\s+'), '');
          final wContact2 = (widgetCustomer['contact2'] ?? customer['contact2'] ?? '')
              .toString()
              .replaceAll(RegExp(r'\s+'), '');

          int idx = customers.indexWhere((c) {
            if (c is! Map) return false;
            final cName = (c['name'] ?? '').toString().trim().toLowerCase();
            final cContact1 = (c['contact1'] ?? c['contact'] ?? '')
                .toString()
                .replaceAll(RegExp(r'\s+'), '');
            final cContact2 =
                (c['contact2'] ?? '').toString().replaceAll(RegExp(r'\s+'), '');

            final nameMatch = cName == wName;
            final phoneMatch = (wContact1.isNotEmpty && (cContact1 == wContact1 || cContact2 == wContact1)) ||
                (wContact2.isNotEmpty && (cContact1 == wContact2 || cContact2 == wContact2));

            return nameMatch && (phoneMatch || wContact1.isEmpty);
          });

          // Fallback: match by phone if name was slightly edited, or by name if only 1 matching name
          if (idx == -1 && wContact1.isNotEmpty) {
            idx = customers.indexWhere((c) {
              if (c is! Map) return false;
              final cContact1 = (c['contact1'] ?? c['contact'] ?? '')
                  .toString()
                  .replaceAll(RegExp(r'\s+'), '');
              final cContact2 =
                  (c['contact2'] ?? '').toString().replaceAll(RegExp(r'\s+'), '');
              return cContact1 == wContact1 || cContact2 == wContact1;
            });
          }

          if (idx != -1) {
            customers[idx]['pendingEditing'] = true;
            await docRef.update({'customers': customers});
          }
        }
      }

      await UserCacheService.instance.ensureLoaded();
      String reqUsername =
          UserCacheService.instance.username ?? user?.displayName ?? user?.email ?? '';
      String reqBranch = UserCacheService.instance.branch ?? '';

      // Fallback branch / username resolution if user cache had empty branch
      if (reqBranch.isEmpty && effectiveDocId != null) {
        try {
          final allUsers = await UserCacheService.instance.getAllUsers();
          final matchedUser = allUsers.firstWhere(
            (u) =>
                (u['email'] as String? ?? '').toLowerCase() == effectiveDocId.toLowerCase() ||
                (u['uid'] as String? ?? '').toLowerCase() == effectiveDocId.toLowerCase(),
            orElse: () => {},
          );
          if (matchedUser.isNotEmpty) {
            if (reqUsername.isEmpty || reqUsername.contains('@')) {
              final uName = (matchedUser['username'] as String? ?? '').trim();
              if (uName.isNotEmpty) reqUsername = uName;
            }
            final uBranch = (matchedUser['branch'] as String? ?? '').trim();
            if (uBranch.isNotEmpty) reqBranch = uBranch;
          }
        } catch (_) {}
      }

      final editReqRef = await FirebaseFirestore.instance
          .collection('customer_editing_requests')
          .add({
        'monthYear': monthYear,
        'userDocId': effectiveDocId,
        'userEmail': user?.email ?? '',
        'userName': reqUsername,
        'userBranch': reqBranch,
        'customerData': customer,
        'updatedCustomerData': updatedFields,
        'reason': reasonResult,
        'requestedAt': FieldValue.serverTimestamp(),
        'status': 'pending',
        'type': 'editing',
      });

      // Send FCM notification to Sync Head users
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
                'title': 'Customer Edit Request',
                'body': '$reqUserBranchStr requested edit of customer "$custName".',
                'notifType': 'customer_editing_request',
                'leadDocId': editReqRef.id,
              });
            } catch (e) {
              debugPrint('FCM Warning: failed to send edit notification to $recipientUid: $e');
            }
          }
        } catch (e) {
          debugPrint('Error triggering edit request notifications: $e');
        }
      }());

      if (context.mounted) {
        showDialog(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Edit Request Sent'),
            content: const Text(
                'Customer edit request has been sent for approval to the Sync Head. The changes will be applied after approval.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
      return true;
    } catch (e) {
      debugPrint('Error submitting customer edit request: $e');
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text('Failed to submit edit request: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }
  }

  /// Approves the customer edit request and updates customer_target in Firestore.
  static Future<void> approveEditing({
    required String reqId,
    required Map<String, dynamic> data,
    required BuildContext context,
    required bool mounted,
  }) async {
    final monthYear = data['monthYear'] as String?;
    final userDocId = data['userDocId'] as String?;
    final customerData = data['customerData'] as Map<String, dynamic>?;
    final updatedCustomerData = data['updatedCustomerData'] as Map<String, dynamic>?;

    if (monthYear == null || userDocId == null || customerData == null || updatedCustomerData == null) {
      throw Exception('Invalid edit request payload format');
    }

    final usersRef = FirebaseFirestore.instance
        .collection('customer_target')
        .doc(monthYear)
        .collection('users');

    var userDocRef = usersRef.doc(userDocId);
    var docSnap = await userDocRef.get();
    if (!docSnap.exists) {
      final querySnap = await usersRef.get();
      for (final d in querySnap.docs) {
        if (d.id.toLowerCase() == userDocId.toLowerCase()) {
          userDocRef = usersRef.doc(d.id);
          break;
        }
      }
    }

    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final snapshot = await transaction.get(userDocRef);
      if (snapshot.exists && snapshot.data() != null) {
        final docData = snapshot.data()!;
        final List<dynamic> customers = List<dynamic>.from(docData['customers'] ?? []);

        final targetName = (customerData['name'] ?? '').toString().trim().toLowerCase();
        final targetContact =
            (customerData['contact1'] ?? customerData['contact'] ?? '')
                .toString()
                .replaceAll(RegExp(r'\s+'), '');

        for (var c in customers) {
          if (c is Map) {
            final cName = (c['name'] ?? '').toString().trim().toLowerCase();
            final cContact =
                (c['contact1'] ?? c['contact'] ?? '').toString().replaceAll(RegExp(r'\s+'), '');
            final cContact2 = (c['contact2'] ?? '').toString().replaceAll(RegExp(r'\s+'), '');

            final isMatch = (cName == targetName && (cContact == targetContact || targetContact.isEmpty)) ||
                (targetContact.isNotEmpty && (cContact == targetContact || cContact2 == targetContact));

            if (isMatch) {
              c['name'] = updatedCustomerData['name'] ?? c['name'];
              c['address'] = updatedCustomerData['address'] ?? c['address'];
              c['contact1'] = updatedCustomerData['contact1'] ?? c['contact1'];
              c['contact2'] = updatedCustomerData['contact2'] ?? c['contact2'];
              c['contact'] = updatedCustomerData['contact'] ?? c['contact'];
              c['pendingEditing'] = false;
              c['editApproved'] = true;
              c['isEdited'] = true;
              break;
            }
          }
        }

        transaction.update(userDocRef, {'customers': customers});
      }

      final reqRef = FirebaseFirestore.instance
          .collection('customer_editing_requests')
          .doc(reqId);

      transaction.update(reqRef, {
        'status': 'approved',
        'approvedAt': FieldValue.serverTimestamp(),
      });
    });

    if (mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Customer edit approved & changes applied.'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  /// Rejects the customer edit request and clears pendingEditing status.
  static Future<void> rejectEditing({
    required String reqId,
    required Map<String, dynamic> data,
    required BuildContext context,
    required bool mounted,
  }) async {
    final monthYear = data['monthYear'] as String?;
    final userDocId = data['userDocId'] as String?;
    final customerData = data['customerData'] as Map<String, dynamic>?;

    if (monthYear != null && userDocId != null && customerData != null) {
      final usersRef = FirebaseFirestore.instance
          .collection('customer_target')
          .doc(monthYear)
          .collection('users');

      var userDocRef = usersRef.doc(userDocId);
      var docSnap = await userDocRef.get();
      if (!docSnap.exists) {
        final querySnap = await usersRef.get();
        for (final d in querySnap.docs) {
          if (d.id.toLowerCase() == userDocId.toLowerCase()) {
            userDocRef = usersRef.doc(d.id);
            break;
          }
        }
      }

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snapshot = await transaction.get(userDocRef);
        if (snapshot.exists && snapshot.data() != null) {
          final docData = snapshot.data()!;
          final List<dynamic> customers = List<dynamic>.from(docData['customers'] ?? []);

          final targetName = (customerData['name'] ?? '').toString().trim().toLowerCase();
          final targetContact =
              (customerData['contact1'] ?? customerData['contact'] ?? '')
                  .toString()
                  .replaceAll(RegExp(r'\s+'), '');

          for (var c in customers) {
            if (c is Map) {
              final cName = (c['name'] ?? '').toString().trim().toLowerCase();
              final cContact =
                  (c['contact1'] ?? c['contact'] ?? '').toString().replaceAll(RegExp(r'\s+'), '');
              final cContact2 = (c['contact2'] ?? '').toString().replaceAll(RegExp(r'\s+'), '');

              final isMatch = (cName == targetName && (cContact == targetContact || targetContact.isEmpty)) ||
                  (targetContact.isNotEmpty && (cContact == targetContact || cContact2 == targetContact));

              if (isMatch) {
                c['pendingEditing'] = false;
                c['editApproved'] = false;
                c['isEdited'] = false;
                break;
              }
            }
          }

          transaction.update(userDocRef, {'customers': customers});
        }

        final reqRef = FirebaseFirestore.instance
            .collection('customer_editing_requests')
            .doc(reqId);

        transaction.update(reqRef, {
          'status': 'rejected',
          'rejectedAt': FieldValue.serverTimestamp(),
        });
      });
    }

    if (mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Customer edit request rejected.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }
}
