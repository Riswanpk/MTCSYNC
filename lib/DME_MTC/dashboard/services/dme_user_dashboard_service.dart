import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/dme_supabase_service.dart';

import '../../users/services/dme_user_service.dart';

/// Data model for a single category's purchase breakdown
class CategoryPurchaseStat {
  final String categoryName;
  final int purchaseCount; // unique customers purchased in period
  final int uniqueCustomers;

  const CategoryPurchaseStat({
    required this.categoryName,
    required this.purchaseCount,
    required this.uniqueCustomers,
  });
}

/// Data model for a single customer type's purchase breakdown
class CustomerTypeStat {
  final String typeName;
  final int uniqueCustomers;

  const CustomerTypeStat({
    required this.typeName,
    required this.uniqueCustomers,
  });
}

/// Data model for a single branch's purchase stat
class BranchPurchaseStat {
  final String branchName;
  final int totalPurchases;
  final int uniqueCustomers;

  const BranchPurchaseStat({
    required this.branchName,
    required this.totalPurchases,
    required this.uniqueCustomers,
  });
}

/// Aggregated dashboard data returned from the service
class DmeUserDashboardData {
  /// Total unique customers who purchased in the date range (across selected branches)
  final int totalUniqueCustomers;

  /// Total purchase records in the date range
  final int totalPurchaseRecords;

  /// Customers who purchased more than once in the range (returning)
  final int returningCustomers;

  /// Breakdown by category (from purchase_details.category in dme_customer_purchases)
  final List<CategoryPurchaseStat> byCategory;

  /// Breakdown by branch
  final List<BranchPurchaseStat> byBranch;

  /// Breakdown by customer type (from purchase_details.customer_type)
  final List<CustomerTypeStat> byCustomerType;

  /// Daily trend: date string → unique customer count
  final Map<String, int> dailyTrend;

  const DmeUserDashboardData({
    required this.totalUniqueCustomers,
    required this.totalPurchaseRecords,
    required this.returningCustomers,
    required this.byCategory,
    required this.byBranch,
    required this.byCustomerType,
    required this.dailyTrend,
  });

  static DmeUserDashboardData empty() => const DmeUserDashboardData(
        totalUniqueCustomers: 0,
        totalPurchaseRecords: 0,
        returningCustomers: 0,
        byCategory: [],
        byBranch: [],
        byCustomerType: [],
        dailyTrend: {},
      );
}

/// Service that fetches purchase-based dashboard data for dme_users.
/// Keeps all Supabase queries separate from the UI.
class DmeUserDashboardService {
  DmeUserDashboardService._();
  static final DmeUserDashboardService instance = DmeUserDashboardService._();

  final _svc = DmeMtcSupabaseService.instance;

  SupabaseClient get _client => DmeMtcSupabaseService.instance.client;

  /// Fetch all dashboard stats for the given date range and branches.
  /// [branchIds] null/empty means no branch filter (admin view).
  Future<DmeUserDashboardData> fetchDashboardData({
    required DateTime from,
    required DateTime to,
    List<int>? branchIds,
  }) async {
    await _svc.ensureInitialized();

    final fromStr = from.toIso8601String().split('T')[0];
    final toStr = to.toIso8601String().split('T')[0];

    // ── Page through all purchases in the date range ─────────────────────
    const batchSize = 1000;
    int offset = 0;

    // customer_id → purchase count in period
    final Map<int, int> customerPurchaseCount = {};

    // category → {set of unique customer ids}
    final Map<String, Set<int>> categoryCustomers = {};

    // customer_type → {set of unique customer ids}
    final Map<String, Set<int>> customerTypeCustomers = {};

    // branch → {purchase count, unique customer ids}
    final Map<String, _BranchAccum> branchAccum = {};

    // date string → set of unique customer ids
    final Map<String, Set<int>> dailyCustomers = {};

    final branchesList = await _svc.getBranches();
    final branchMap = {
      for (final b in branchesList) (b['id'] as int): (b['name'] as String)
    };

    final categoriesList = await _svc.getCategories();
    final categoryMap = {
      for (final c in categoriesList) (c['id'] as int): (c['name'] as String)
    };

    final typesList = await _svc.getCustomerTypes();
    final typeMap = {
      for (final t in typesList) (t['id'] as int): (t['name'] as String)
    };

    while (true) {
      var query = _client
          .from('dme_sales')
          .select('customer_id, date, purchased_branch, category_id, customer_type_id')
          .gte('date', fromStr)
          .lte('date', toStr);

      if (branchIds != null && branchIds.isNotEmpty) {
        query = query.inFilter('purchased_branch', branchIds);
      }

      final batch =
          await query.range(offset, offset + batchSize - 1) as List<dynamic>;

      if (batch.isEmpty) break;

      for (final row in batch) {
        final customerId = (row['customer_id'] ?? row['cust_id']) as int? ?? 0;
        final dateStr = row['date'] as String? ?? '';
        final branchId = row['purchased_branch'] as int? ?? 0;
        final categoryId = row['category_id'] as int? ?? 0;
        final typeId = row['customer_type_id'] as int? ?? 0;

        final branchName = branchMap[branchId] ?? 'Unknown';
        final category = categoryMap[categoryId] ?? 'Uncategorised';
        final customerType = typeMap[typeId] ?? 'Uncategorised';

        // --- Customer counts ---
        customerPurchaseCount[customerId] =
            (customerPurchaseCount[customerId] ?? 0) + 1;

        // --- Category breakdown ---
        categoryCustomers.putIfAbsent(category, () => <int>{}).add(customerId);

        // --- Customer type breakdown ---
        customerTypeCustomers
            .putIfAbsent(customerType, () => <int>{})
            .add(customerId);

        // --- Branch breakdown ---
        branchAccum.putIfAbsent(
            branchName, () => _BranchAccum(branchName: branchName));
        branchAccum[branchName]!.addPurchase(customerId);

        // --- Daily trend ---
        if (dateStr.isNotEmpty) {
          dailyCustomers.putIfAbsent(dateStr, () => <int>{}).add(customerId);
        }
      }

      if (batch.length < batchSize) break;
      offset += batchSize;
    }

    // ── Aggregate ─────────────────────────────────────────────────────────
    final totalUnique = customerPurchaseCount.keys.length;
    final totalRecords =
        customerPurchaseCount.values.fold(0, (a, b) => a + b);
    final returning = customerPurchaseCount.values.where((c) => c >= 2).length;

    final byCategory = categoryCustomers.entries.map((e) {
      return CategoryPurchaseStat(
        categoryName: e.key,
        purchaseCount: e.value.length,
        uniqueCustomers: e.value.length,
      );
    }).toList()
      ..sort((a, b) => b.purchaseCount.compareTo(a.purchaseCount));

    final byBranch = branchAccum.values.map((b) {
      return BranchPurchaseStat(
        branchName: b.branchName,
        totalPurchases: b.totalPurchases,
        uniqueCustomers: b.uniqueCustomerIds.length,
      );
    }).toList()
      ..sort((a, b) => b.totalPurchases.compareTo(a.totalPurchases));

    final byCustomerType = customerTypeCustomers.entries.map((e) {
      return CustomerTypeStat(
        typeName: e.key,
        uniqueCustomers: e.value.length,
      );
    }).toList()
      ..sort((a, b) => b.uniqueCustomers.compareTo(a.uniqueCustomers));

    // Convert daily map: date → unique customer count, sorted by date
    final Map<String, int> dailyTrend = {};
    final sortedDates = dailyCustomers.keys.toList()..sort();
    for (final d in sortedDates) {
      dailyTrend[d] = dailyCustomers[d]!.length;
    }

    debugPrint(
        'DmeUserDashboard: total=$totalUnique, returning=$returning, categories=${byCategory.length}, branches=${byBranch.length}, types=${byCustomerType.length}');

    return DmeUserDashboardData(
      totalUniqueCustomers: totalUnique,
      totalPurchaseRecords: totalRecords,
      returningCustomers: returning,
      byCategory: byCategory,
      byBranch: byBranch,
      byCustomerType: byCustomerType,
      dailyTrend: dailyTrend,
    );
  }

  /// Convenience: get all branches the user can see.
  Future<List<Map<String, dynamic>>> getUserBranches(String dmeUserId) =>
      _svc.getBranches().then((all) async {
        final ids = await DmeUserService.instance.getUserBranchIds(dmeUserId);
        return all.where((b) => ids.contains(b['id'] as int?)).toList();
      });

  Future<List<int>> getUserBranchIds(String dmeUserId) =>
      DmeUserService.instance.getUserBranchIds(dmeUserId);

  /// All branches (for admins).
  Future<List<Map<String, dynamic>>> getAllBranches() => _svc.getBranches();
}

// ── Internal accumulator ─────────────────────────────────────────────────────

class _BranchAccum {
  final String branchName;
  int totalPurchases = 0;
  final Set<int> uniqueCustomerIds = {};

  _BranchAccum({required this.branchName});

  void addPurchase(int customerId) {
    totalPurchases++;
    uniqueCustomerIds.add(customerId);
  }
}
