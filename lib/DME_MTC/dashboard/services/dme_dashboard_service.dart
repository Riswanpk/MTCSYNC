import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/dme_supabase_service.dart';

class DmeDashboardService {
  DmeDashboardService._();
  static final DmeDashboardService instance = DmeDashboardService._();

  SupabaseClient get _client => DmeMtcSupabaseService.instance.client;

  Future<Map<String, int>> getDashboardCounts() async {
    int customerCount = 0;

    try {
      await DmeMtcSupabaseService.instance.ensureInitialized();

      final response = await _client
          .from('dme_customers')
          .select('id')
          .count(CountOption.exact);

      customerCount = response.count;
      debugPrint('Successfully fetched customer count: $customerCount');
    } catch (e) {
      debugPrint('Error getting customer count: $e');
      customerCount = 0;
    }

    final result = {
      'customers': customerCount,
    };

    debugPrint('getDashboardCounts returning: $result');
    return result;
  }

  Future<List<Map<String, dynamic>>> getSalesSummaryByBranch({
    required DateTime from,
    required DateTime to,
  }) async {
    await DmeMtcSupabaseService.instance.ensureInitialized();
    final res = await _client
        .from('dme_sales')
        .select('total_quantity, purchased_branch, dme_customers(branch_id)')
        .gte('date', from.toIso8601String().split('T')[0])
        .lte('date', to.toIso8601String().split('T')[0]);

    final Map<String, double> branchTotals = {};
    for (final row in res) {
      final bId = (row['purchased_branch'] as int?) ??
          ((row['dme_customers'] as Map?)?['branch_id'] as int?);
      final branchName = bId != null
          ? (await DmeMtcSupabaseService.instance.getBranchNameById(bId) ?? 'Unknown')
          : 'Unknown';
      final qty = (row['total_quantity'] as num?)?.toDouble() ?? 0;
      branchTotals[branchName] = (branchTotals[branchName] ?? 0) + qty;
    }

    return branchTotals.entries
        .map((e) => {'branch': e.key, 'total_quantity': e.value})
        .toList()
      ..sort((a, b) => (b['total_quantity'] as double)
          .compareTo(a['total_quantity'] as double));
  }

  Future<List<Map<String, dynamic>>> getTopSalesmen({
    required DateTime from,
    required DateTime to,
    int limit = 10,
  }) async {
    await DmeMtcSupabaseService.instance.ensureInitialized();
    final res = await _client
        .from('dme_sales')
        .select('salesman, total_quantity')
        .gte('date', from.toIso8601String().split('T')[0])
        .lte('date', to.toIso8601String().split('T')[0]);

    final Map<String, double> salesmanTotals = {};
    for (final row in res) {
      final name = row['salesman'] as String? ?? 'Unknown';
      final qty = (row['total_quantity'] as num?)?.toDouble() ?? 0;
      salesmanTotals[name] = (salesmanTotals[name] ?? 0) + qty;
    }

    final sorted = salesmanTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sorted
        .take(limit)
        .map((e) => {'salesman': e.key, 'total_quantity': e.value})
        .toList();
  }

  Future<Map<String, dynamic>> getCustomerVisitAnalytics({
    required DateTime from,
    required DateTime to,
    List<int>? branchIds,
  }) async {
    await DmeMtcSupabaseService.instance.ensureInitialized();

    final fromStr = from.toIso8601String().split('T')[0];
    final toStr = to.toIso8601String().split('T')[0];
    const batchSize = 1000;
    int batchOffset = 0;

    final Map<int, int> visitCounts = {};

    while (true) {
      var batchQuery = _client
          .from('dme_sales')
          .select('customer_id')
          .gte('date', fromStr)
          .lte('date', toStr);

      if (branchIds != null && branchIds.isNotEmpty) {
        batchQuery = batchQuery.inFilter('purchased_branch', branchIds);
      }

      final batch =
          await batchQuery.range(batchOffset, batchOffset + batchSize - 1);

      if (batch.isEmpty) break;

      for (final row in batch) {
        final customerId = row['customer_id'] as int;
        visitCounts[customerId] = (visitCounts[customerId] ?? 0) + 1;
      }

      if (batch.length < batchSize) break;
      batchOffset += batchSize;
    }

    final int returningCustomers =
        visitCounts.values.where((count) => count >= 2).length;
    final int newCustomers =
        visitCounts.values.where((count) => count == 1).length;
    final int uniqueCustomers = visitCounts.keys.length;

    debugPrint(
        'Customer visit analytics: total=$uniqueCustomers, new=$newCustomers, returning=$returningCustomers, batches=${(batchOffset ~/ batchSize) + 1}');

    return {
      'total_visits': uniqueCustomers,
      'new_customers': newCustomers,
      'returning_customers': returningCustomers,
    };
  }
}
