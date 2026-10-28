import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// In-memory cache of past months' customer lists keyed by `<email>_<monthYear>`
/// to avoid re-fetching and re-parsing 3 large documents on every tile tap.
final Map<String, List<dynamic>> _pastMonthsCache = {};
final Map<String, Future<List<dynamic>>> _inFlightFetches = {};

Future<List<dynamic>> _getPastMonthCustomers(String email, String monthYear) {
  final cacheKey = '${email}_$monthYear';
  if (_pastMonthsCache.containsKey(cacheKey)) {
    return Future.value(_pastMonthsCache[cacheKey]!);
  }
  if (_inFlightFetches.containsKey(cacheKey)) {
    return _inFlightFetches[cacheKey]!;
  }
  final future = FirebaseFirestore.instance
      .collection('customer_target')
      .doc(monthYear)
      .collection('users')
      .doc(email)
      .get()
      .then((doc) {
    final data = doc.data();
    final List<dynamic> list =
        (doc.exists && data != null && data['customers'] is List)
            ? data['customers'] as List<dynamic>
            : const [];
    _pastMonthsCache[cacheKey] = list;
    _inFlightFetches.remove(cacheKey);
    return list;
  }).catchError((_) {
    _inFlightFetches.remove(cacheKey);
    return const <dynamic>[];
  });
  _inFlightFetches[cacheKey] = future;
  return future;
}

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

    final email = user.email!.toLowerCase();
    final now = DateTime.now();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final List<Map<String, String>> results = [];

    final futures = <Future<List<dynamic>>>[];
    final monthYears = <String>[];
    for (int i = 1; i <= 3; i++) {
      final prev = DateTime(now.year, now.month - i, 1);
      final monthYear = "${months[prev.month - 1]} ${prev.year}";
      monthYears.add(monthYear);
      futures.add(_getPastMonthCustomers(email, monthYear));
    }
    final lists = await Future.wait(futures);

    for (int i = 0; i < lists.length; i++) {
      final customerList = lists[i];
      final monthYear = monthYears[i];
      if (customerList.isNotEmpty) {
        dynamic prevCustomer;
        if (contact1 != null && contact1.isNotEmpty) {
          prevCustomer = customerList.firstWhere(
            (c) => c is Map && (c['contact'] == contact1 || c['contact1'] == contact1),
            orElse: () => null,
          );
        }
        if ((prevCustomer == null || prevCustomer['remarks'] == null || prevCustomer['remarks'].toString().trim().isEmpty) &&
            contact2 != null && contact2.isNotEmpty) {
          prevCustomer = customerList.firstWhere(
            (c) => c is Map && (c['contact'] == contact2 || c['contact2'] == contact2),
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
