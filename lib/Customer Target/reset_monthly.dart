import 'package:cloud_firestore/cloud_firestore.dart';

/// Call this function at the start of every new month to copy all users' customer lists
/// from the previous month to the new month, with remarks cleared and callMade set to false.
Future<void> resetCustomerTargetsForNewMonth() async {
  final now = DateTime.now();
  final months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  // Get previous and current month-year strings
  final prev = DateTime(now.year, now.month - 1, 1);
  final prevMonthYear = "${months[prev.month - 1]} ${prev.year}";
  final currMonthYear = "${months[now.month - 1]} ${now.year}";

  final prevUsersRef = FirebaseFirestore.instance
      .collection('customer_target')
      .doc(prevMonthYear)
      .collection('users');

  final currUsersRef = FirebaseFirestore.instance
      .collection('customer_target')
      .doc(currMonthYear)
      .collection('users');

  final prevUsersSnapshot = await prevUsersRef.get();

  for (final userDoc in prevUsersSnapshot.docs) {
    final prevData = userDoc.data();
    final prevCustomers = prevData['customers'] as List<dynamic>? ?? [];

    // Prepare new customers list: clear remarks and callMade
    final newCustomers = prevCustomers.map((customer) {
      final map = Map<String, dynamic>.from(customer);
      map['remarks'] = '';
      map['callMade'] = false;
      return map;
    }).toList();

    // Copy other fields if needed (e.g., branch, user)
    final newData = {
      ...prevData,
      'customers': newCustomers,
      'updated': FieldValue.serverTimestamp(),
    };

    await currUsersRef.doc(userDoc.id).set(newData);
  }
}