import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

Future<void> updateCallStatusInFirestore({
  required Map<String, dynamic> customer,
  required BuildContext? context,
  required bool mounted,
}) async {
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) return;
    final now = DateTime.now();
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final monthYear = "${months[now.month - 1]} ${now.year}";
    final docRef = FirebaseFirestore.instance
        .collection('customer_target')
        .doc(monthYear)
        .collection('users')
        .doc(user.email!.toLowerCase());
    final doc = await docRef.get();
    if (doc.exists && doc.data()?['customers'] != null) {
      List customers = List.from(doc.data()!['customers']);
      String? c1 = customer['contact1'] ?? customer['contact'];
      String? c2 = customer['contact2'];
      int idx = customers.indexWhere((c) =>
        (c['contact'] == c1 || c['contact1'] == c1) ||
        (c2 != null && c2.isNotEmpty && (c['contact'] == c2 || c['contact2'] == c2))
      );
      if (idx != -1) {
        customers[idx]['callMade'] = true;
        if (customers[idx]['callDate'] == null) {
          customers[idx]['callDate'] = Timestamp.now();
        }
        await docRef.update({'customers': customers});
      }
    }
  } catch (e) {
    debugPrint('Failed to update callMade in Firestore: $e');
    if (mounted && context != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update call status in Firestore: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
