import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

final RegExp _nonDigitRegex = RegExp(r'\D');

String _normalizePhone(dynamic phone) {
  if (phone == null) return '';
  final cleaned = phone.toString().replaceAll(_nonDigitRegex, '');
  if (cleaned.length > 10) {
    return cleaned.substring(cleaned.length - 10);
  }
  return cleaned;
}

Future<void> updateRemarksInFirestore({
  required Map<String, dynamic> customer,
  required String remarks,
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
      final c1Norm = _normalizePhone(customer['contact1'] ?? customer['contact'] ?? customer['phone']);
      final c2Norm = _normalizePhone(customer['contact2']);
      final cName = (customer['name'] ?? '').toString().trim().toLowerCase();

      int idx = customers.indexWhere((c) {
        if (c is! Map) return false;
        final p1 = _normalizePhone(c['contact1'] ?? c['contact'] ?? c['phone']);
        final p2 = _normalizePhone(c['contact2']);
        if (c1Norm.isNotEmpty && (p1 == c1Norm || p2 == c1Norm)) return true;
        if (c2Norm.isNotEmpty && (p1 == c2Norm || p2 == c2Norm)) return true;
        if (cName.isNotEmpty && (c['name'] ?? '').toString().trim().toLowerCase() == cName) return true;
        return false;
      });

      if (idx != -1) {
        customers[idx]['remarks'] = remarks;
        if (customers[idx]['callDate'] == null) {
          customers[idx]['callDate'] = Timestamp.now();
        }
        await usersRef.doc(finalDocId).update({'customers': customers});
      }
    }
  } catch (e) {
    debugPrint('Failed to update remarks in Firestore: $e');
    if (context != null && context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text('Failed to save remarks: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

