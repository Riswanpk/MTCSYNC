import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

class DmeNotificationService {
  static final DmeNotificationService instance = DmeNotificationService._internal();
  DmeNotificationService._internal();

  /// Notify all DME admins that a new request has been raised by a user.
  /// Uses audio: you_have_a_request.mp3 (channel: dme_requests_channel)
  Future<void> notifyAdminsOnRequestRaised({
    required String customerName,
    required String requestType,
    required String requestedBy,
    String? requestId,
  }) async {
    try {
      final adminSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'dme_admin')
          .get();

      final adminUids = adminSnap.docs.map((doc) => doc.id).toSet();

      // Also check role in uppercase or alternate casing if any
      final altAdminSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'DME_ADMIN')
          .get();
      for (final doc in altAdminSnap.docs) {
        adminUids.add(doc.id);
      }

      if (adminUids.isEmpty) {
        debugPrint('DmeNotificationService: No dme_admin found to notify.');
        return;
      }

      String friendlyType;
      switch (requestType) {
        case 'phone_number_change':
          friendlyType = 'Phone Number Change';
          break;
        case 'edit_customer_details':
          friendlyType = 'Customer Details Edit';
          break;
        case 'preference_change':
          friendlyType = 'Contact Preference Change';
          break;
        case 'call_completion':
          friendlyType = 'Call Completion';
          break;
        default:
          friendlyType = 'Request';
      }

      final title = 'New DME Request Raised';
      final body = '$requestedBy raised a $friendlyType request for $customerName.';

      for (final uid in adminUids) {
        try {
          await FirebaseFunctions.instanceFor(region: 'asia-south1')
              .httpsCallable('sendLeadAssignmentNotification')
              .call(<String, dynamic>{
            'recipientUid': uid,
            'title': title,
            'body': body,
            'notifType': 'dme_request_raised',
            'leadDocId': requestId ?? '',
            'requestId': requestId ?? '',
          });
        } catch (callErr) {
          debugPrint('DmeNotificationService: Error notifying admin $uid: $callErr');
        }
      }
    } catch (e) {
      debugPrint('DmeNotificationService: Error in notifyAdminsOnRequestRaised: $e');
    }
  }

  /// Notify the requesting user that their request has been approved or rejected.
  /// Uses audio:
  /// - request_has_been_approved.mp3 (channel: dme_requests_approved_channel)
  /// - request_has_been_rejected.mp3 (channel: dme_requests_rejected_channel)
  Future<void> notifyUserOnRequestDecision({
    required String? requestedByUid,
    required String? requestedByEmail,
    required String customerName,
    required String requestType,
    required bool isApproved,
    String? rejectionReason,
    String? requestId,
  }) async {
    try {
      String targetUid = requestedByUid ?? '';

      // If user UID is not directly available, resolve it via Firestore query on email
      if (targetUid.isEmpty && requestedByEmail != null && requestedByEmail.isNotEmpty) {
        final userQuery = await FirebaseFirestore.instance
            .collection('users')
            .where('email', isEqualTo: requestedByEmail)
            .limit(1)
            .get();

        if (userQuery.docs.isNotEmpty) {
          targetUid = userQuery.docs.first.id;
        }
      }

      if (targetUid.isEmpty) {
        debugPrint('DmeNotificationService: Cannot find recipient UID for $requestedByEmail');
        return;
      }

      String friendlyType;
      switch (requestType) {
        case 'phone_number_change':
          friendlyType = 'Phone number';
          break;
        case 'edit_customer_details':
          friendlyType = 'Customer details';
          break;
        case 'preference_change':
          friendlyType = 'Preference change';
          break;
        case 'call_completion':
          friendlyType = 'Call completion';
          break;
        default:
          friendlyType = 'Request';
      }

      final notifType = isApproved ? 'dme_request_approved' : 'dme_request_rejected';
      final title = isApproved
          ? 'Request Approved: $friendlyType'
          : 'Request Rejected: $friendlyType';

      String body;
      if (isApproved) {
        body = 'Your $friendlyType request for "$customerName" has been approved.';
      } else {
        final reasonSuffix = (rejectionReason != null && rejectionReason.trim().isNotEmpty)
            ? ' Reason: ${rejectionReason.trim()}'
            : '';
        body = 'Your $friendlyType request for "$customerName" has been rejected.$reasonSuffix';
      }

      await FirebaseFunctions.instanceFor(region: 'asia-south1')
          .httpsCallable('sendLeadAssignmentNotification')
          .call(<String, dynamic>{
        'recipientUid': targetUid,
        'title': title,
        'body': body,
        'notifType': notifType,
        'leadDocId': requestId ?? '',
        'requestId': requestId ?? '',
      });
    } catch (e) {
      debugPrint('DmeNotificationService: Error in notifyUserOnRequestDecision: $e');
    }
  }
}
