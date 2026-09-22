import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../../../Misc/dme_config.dart';
import '../models/dme_analytics_data.dart';

class DmeAnalyticsService {
  static Future<DmeAnalyticsSummary> fetchAnalytics({
    required DateTime startDate,
    required DateTime endDate,
    int? selectedBranchId,
    required List<int> assignedBranches,
  }) async {
    final client = await DmeConfig.getClient();
    if (client == null) {
      return DmeAnalyticsSummary.empty();
    }

    final startStr = DateFormat('yyyy-MM-dd').format(startDate);
    final endStr = DateFormat('yyyy-MM-dd').format(endDate);
    const int pageSize = 1000;

    // 1. Fetch ALL Sales in Date Range (Paginated to bypass 1000-row limit)
    List<dynamic> allSales = [];
    int salesOffset = 0;
    bool hasMoreSales = true;

    while (hasMoreSales) {
      var query = client
          .from('dme_sales')
          .select(
              'id, date, customer_id, purchased_branch, category_id, customer_type_id')
          .gte('date', startStr)
          .lte('date', endStr);

      if (selectedBranchId != null) {
        query = query.eq('purchased_branch', selectedBranchId);
      } else if (assignedBranches.isNotEmpty) {
        query = query.inFilter('purchased_branch', assignedBranches);
      }

      final batch = await query.range(salesOffset, salesOffset + pageSize - 1);
      final list = batch as List;
      allSales.addAll(list);
      if (list.length < pageSize) {
        hasMoreSales = false;
      } else {
        salesOffset += pageSize;
      }
    }

    // 2. Fetch ALL Customers created in date range
    final startIso = DateTime(
      startDate.year,
      startDate.month,
      startDate.day,
      0,
      0,
      0,
    ).toIso8601String();
    final endIso = DateTime(
      endDate.year,
      endDate.month,
      endDate.day,
      23,
      59,
      59,
      999,
    ).toIso8601String();

    List<dynamic> allCreatedCusts = [];
    int custOffset = 0;
    bool hasMoreCusts = true;

    while (hasMoreCusts) {
      var custQuery = client
          .from('dme_customers')
          .select(
              'id, primary_branch, creation_date, created_at, dme_customer_branches(branch_id)')
          .or('and(creation_date.gte.$startStr,creation_date.lte.$endStr),and(creation_date.is.null,created_at.gte.$startIso,created_at.lte.$endIso)');

      final batch = await custQuery.range(custOffset, custOffset + pageSize - 1);
      final list = batch as List;
      allCreatedCusts.addAll(list);
      if (list.length < pageSize) {
        hasMoreCusts = false;
      } else {
        custOffset += pageSize;
      }
    }

    int newCustomersCount = 0;
    for (var c in allCreatedCusts) {
      int? pBranch = c['primary_branch'] as int?;
      if (pBranch == null) {
        final bList = c['dme_customer_branches'] as List?;
        if (bList != null && bList.isNotEmpty) {
          pBranch = bList.first['branch_id'] as int?;
        }
      }

      if (selectedBranchId != null) {
        if (pBranch == selectedBranchId) {
          newCustomersCount++;
        }
      } else if (assignedBranches.isNotEmpty) {
        if (pBranch != null && assignedBranches.contains(pBranch)) {
          newCustomersCount++;
        }
      } else {
        newCustomersCount++;
      }
    }

    // 3. Fetch ALL Completed Call Reminders in Date Range
    List<dynamic> allReminders = [];
    int remOffset = 0;
    bool hasMoreRem = true;

    while (hasMoreRem) {
      var remindersQuery = client
          .from('dme_reminders')
          .select('id, status, updated_at')
          .inFilter('status', ['completed', 'called'])
          .gte('updated_at', '${startStr}T00:00:00')
          .lte('updated_at', '${endStr}T23:59:59');

      if (selectedBranchId != null) {
        remindersQuery = remindersQuery.eq('last_purchase_branch', selectedBranchId);
      } else if (assignedBranches.isNotEmpty) {
        remindersQuery = remindersQuery.inFilter('last_purchase_branch', assignedBranches);
      }

      final batch = await remindersQuery.range(remOffset, remOffset + pageSize - 1);
      final list = batch as List;
      allReminders.addAll(list);
      if (list.length < pageSize) {
        hasMoreRem = false;
      } else {
        remOffset += pageSize;
      }
    }

    // 4. Aggregations
    final Set<int> uniqueCustIds = {};
    final Map<int, int> branchSales = {};
    final Map<int, int> catSales = {};
    final Map<int, int> typeSales = {};

    for (var s in allSales) {
      final custId = s['customer_id'] as int?;
      if (custId != null) {
        uniqueCustIds.add(custId);
      }

      final bId = s['purchased_branch'] as int?;
      if (bId != null) branchSales[bId] = (branchSales[bId] ?? 0) + 1;

      final catId = s['category_id'] as int?;
      if (catId != null) catSales[catId] = (catSales[catId] ?? 0) + 1;

      final tId = s['customer_type_id'] as int?;
      if (tId != null) typeSales[tId] = (typeSales[tId] ?? 0) + 1;
    }

    // If category or type are not recorded directly on sales, aggregate from customer branches
    if (catSales.isEmpty || typeSales.isEmpty) {
      if (uniqueCustIds.isNotEmpty) {
        final custIdList = uniqueCustIds.toList();
        for (int i = 0; i < custIdList.length; i += 500) {
          final chunk = custIdList.sublist(
            i,
            (i + 500 > custIdList.length) ? custIdList.length : i + 500,
          );
          try {
            final custBranchRes = await client
                .from('dme_customer_branches')
                .select('category_id, customer_type_id, branch_id')
                .inFilter('customer_id', chunk);

            for (var cb in (custBranchRes as List)) {
              if (selectedBranchId != null && cb['branch_id'] != selectedBranchId) {
                continue;
              }
              final catId = cb['category_id'] as int?;
              final tId = cb['customer_type_id'] as int?;
              if (catId != null) catSales[catId] = (catSales[catId] ?? 0) + 1;
              if (tId != null) typeSales[tId] = (typeSales[tId] ?? 0) + 1;
            }
          } catch (e) {
            debugPrint('Error resolving customer branches chunk: $e');
          }
        }
      }
    }

    return DmeAnalyticsSummary(
      uniqueCustomersVisited: uniqueCustIds.length,
      newCustomersCreated: newCustomersCount,
      completedRemindersCount: allReminders.length,
      salesByBranch: branchSales,
      salesByCategory: catSales,
      salesByType: typeSales,
    );
  }
}
