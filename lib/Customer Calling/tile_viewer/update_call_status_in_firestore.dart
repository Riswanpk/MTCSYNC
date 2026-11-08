import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../customer_list_target_service.dart';

Future<void> updateCallStatusInFirestore({
  required Map<String, dynamic> customer,
  required BuildContext? context,
  required bool mounted,
  String? docId,
}) async {
  try {
    final user = FirebaseAuth.instance.currentUser;
    final effectiveDocId = (docId != null && docId.isNotEmpty)
        ? docId.toLowerCase()
        : user?.email?.toLowerCase();
    if (effectiveDocId == null || effectiveDocId.isEmpty) return;

    final now = DateTime.now();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final monthYear = "${months[now.month - 1]} ${now.year}";
    final usersRef = FirebaseFirestore.instance
        .collection('customer_target')
        .doc(monthYear)
        .collection('users');

    var doc = await usersRef.doc(effectiveDocId).get();
    String finalDocId = effectiveDocId;

    if (!doc.exists || doc.data()?['customers'] == null) {
      final querySnap = await usersRef.get();
      for (final d in querySnap.docs) {
        if (d.id.toLowerCase() == effectiveDocId) {
          doc = d;
          finalDocId = d.id;
          break;
        }
      }
    }

    if (doc.exists && doc.data()?['customers'] != null) {
      List customers = List.from(doc.data()!['customers']);

      int idx = customers.indexWhere((c) {
        if (c is! Map) return false;
        return CustomerListTargetService.isSameCustomer(c, customer);
      });

      if (idx != -1) {
        customers[idx]['callMade'] = true;
        if (customers[idx]['callDate'] == null) {
          customers[idx]['callDate'] = Timestamp.now();
        }
        await usersRef.doc(finalDocId).update({
          'customers': customers,
          'updated': FieldValue.serverTimestamp(),
        });
      }
    }
  } catch (e) {
    debugPrint('Failed to update callMade in Firestore: $e');
    if (context != null && context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text('Failed to update call status in Firestore: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

