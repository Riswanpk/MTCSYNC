import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

Future<List<Map<String, String>>> fetchLastRemarks({
  required Map<String, dynamic> customer,
}) async {
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) {
      return [];
    }
    final contact1 = customer['contact1'] ?? customer['contact'];
    final contact2 = customer['contact2'];
    if ((contact1 == null || contact1.isEmpty) && (contact2 == null || contact2.isEmpty)) {
      return [];
    }

    final now = DateTime.now();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final List<Map<String, String>> results = [];

    final futures = <Future<DocumentSnapshot>>[];
    final monthYears = <String>[];
    for (int i = 1; i <= 3; i++) {
      final prev = DateTime(now.year, now.month - i, 1);
      final monthYear = "${months[prev.month - 1]} ${prev.year}";
      monthYears.add(monthYear);
      futures.add(FirebaseFirestore.instance
          .collection('customer_target')
          .doc(monthYear)
          .collection('users')
          .doc(user.email!.toLowerCase())
          .get());
    }
    final docs = await Future.wait(futures);

    for (int i = 0; i < docs.length; i++) {
      final doc = docs[i];
      final monthYear = monthYears[i];
      if (doc.exists && doc.data() != null && (doc.data() as Map<String, dynamic>)['customers'] != null) {
        final List customerList = (doc.data() as Map<String, dynamic>)['customers'];
        dynamic prevCustomer;
        if (contact1 != null && contact1.isNotEmpty) {
          prevCustomer = customerList.firstWhere(
            (c) => c['contact'] == contact1 || c['contact1'] == contact1,
            orElse: () => null,
          );
        }
        if ((prevCustomer == null || prevCustomer['remarks'] == null || prevCustomer['remarks'].toString().trim().isEmpty) &&
            contact2 != null && contact2.isNotEmpty) {
          prevCustomer = customerList.firstWhere(
            (c) => c['contact'] == contact2 || c['contact2'] == contact2,
            orElse: () => null,
          );
        }
        if (prevCustomer != null && prevCustomer['remarks'] != null && prevCustomer['remarks'].toString().trim().isNotEmpty) {
          results.add({'monthYear': monthYear, 'remarks': prevCustomer['remarks'].toString()});
        }
      }
    }
    return results;
  } catch (e) {
    return [];
  }
}
