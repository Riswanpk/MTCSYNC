import 'package:cloud_firestore/cloud_firestore.dart';

class _CachedCounts {
  final Map<String, int> counts;
  final DateTime timestamp;
  _CachedCounts(this.counts, this.timestamp);
}

final Map<String, _CachedCounts> _dashboardCountsMemoryCache = {};
const Duration _cacheDuration = Duration(minutes: 30);

Future<Map<String, int>> fetchDashboardCounts({
  String? branch,
  bool forceRefresh = false,
}) async {
  final cacheKey = branch ?? '__all__';

  if (!forceRefresh) {
    final cached = _dashboardCountsMemoryCache[cacheKey];
    if (cached != null &&
        DateTime.now().difference(cached.timestamp) < _cacheDuration) {
      return cached.counts;
    }
  }

  final now = DateTime.now();
  final monthStart = DateTime(now.year, now.month, 1);
  final todayStart = DateTime(now.year, now.month, now.day);
  final todayEnd = todayStart.add(const Duration(days: 1));

  Query followUps = FirebaseFirestore.instance.collection('follow_ups');

  if (branch != null && branch.isNotEmpty) {
    followUps = followUps.where('branch', isEqualTo: branch);
  }

  final leadsResults = await Future.wait([
    followUps.count().get(),
    followUps
        .where('created_at',
            isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
        .count()
        .get(),
    followUps
        .where('created_at',
            isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart))
        .where('created_at', isLessThan: Timestamp.fromDate(todayEnd))
        .count()
        .get(),
  ]);

  int pendingTodosCount = 0;
  try {
    if (branch != null && branch.isNotEmpty) {
      final usersSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('branch', isEqualTo: branch)
          .get();
      final emails = usersSnap.docs
          .map((d) => d.data()['email'] as String? ?? '')
          .where((e) => e.isNotEmpty)
          .toList();
      if (emails.isNotEmpty) {
        final todosSnap = await FirebaseFirestore.instance
            .collection('todo')
            .where('status', isEqualTo: 'pending')
            .where('email', whereIn: emails.length > 30 ? emails.sublist(0, 30) : emails)
            .count()
            .get();
        pendingTodosCount = todosSnap.count ?? 0;
      }
    } else {
      final todosSnap = await FirebaseFirestore.instance
          .collection('todo')
          .where('status', isEqualTo: 'pending')
          .count()
          .get();
      pendingTodosCount = todosSnap.count ?? 0;
    }
  } catch (_) {}

  final result = {
    'totalLeads': leadsResults[0].count ?? 0,
    'monthLeads': leadsResults[1].count ?? 0,
    'todayLeads': leadsResults[2].count ?? 0,
    'pendingTodos': pendingTodosCount,
  };

  _dashboardCountsMemoryCache[cacheKey] = _CachedCounts(result, DateTime.now());

  return result;
}
