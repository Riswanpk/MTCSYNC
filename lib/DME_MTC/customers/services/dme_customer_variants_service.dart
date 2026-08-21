import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/dme_supabase_service.dart';
import '../../users/services/dme_user_service.dart';

/// Data model for a customer with multiple categories/types
class CustomerVariant {
  final int customerId;
  final String customerName;
  final String customerPhone;
  final Set<String> categories;
  final Set<String> types;
  final int purchaseCount;

  const CustomerVariant({
    required this.customerId,
    required this.customerName,
    required this.customerPhone,
    required this.categories,
    required this.types,
    required this.purchaseCount,
  });

  bool get hasMultipleCategories => categories.length >= 2;
  bool get hasMultipleTypes => types.length >= 2;
}

/// Service to fetch customers with 2+ categories or 2+ types
class DmeCustomerVariantsService {
  DmeCustomerVariantsService._();
  static final DmeCustomerVariantsService instance =
      DmeCustomerVariantsService._();

  final _svc = DmeMtcSupabaseService.instance;

  SupabaseClient get _client => DmeMtcSupabaseService.instance.client;

  /// Fetch customers with 2+ categories OR 2+ types within a date range
  /// [branchIds] null/empty means no branch filter (admin view).
  Future<List<CustomerVariant>> fetchCustomersWithVariants({
    required DateTime from,
    required DateTime to,
    List<int>? branchIds,
  }) async {
    await _svc.ensureInitialized();

    final fromStr = from.toIso8601String().split('T')[0];
    final toStr = to.toIso8601String().split('T')[0];

    // Fetch all purchases in date range
    const batchSize = 1000;
    int offset = 0;

    // customer_id → {customer_name, phone, categories set, types set, purchase count}
    final Map<int, _CustomerAccum> customers = {};

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
          .select(
              'customer_id, date, category_id, customer_type_id, dme_customers(id, name, phone)')
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
        final customerData =
            row['dme_customers'] as Map<String, dynamic>? ?? {};
        final customerName = customerData['name'] as String? ?? 'Unknown';
        final customerPhone = customerData['phone'] as String? ?? '';

        final categoryId = row['category_id'] as int? ?? 0;
        final typeId = row['customer_type_id'] as int? ?? 0;

        final category = categoryMap[categoryId] ?? 'Uncategorised';
        final type = typeMap[typeId] ?? 'Uncategorised';

        customers.putIfAbsent(customerId, () {
          return _CustomerAccum(
            customerId: customerId,
            customerName: customerName,
            customerPhone: customerPhone,
          );
        });

        customers[customerId]!
          ..categories.add(category)
          ..types.add(type)
          ..purchaseCount += 1;
      }

      if (batch.length < batchSize) break;
      offset += batchSize;
    }

    // Filter for customers with 2+ categories OR 2+ types
    final variants = customers.values
        .where((c) => c.categories.length >= 2 || c.types.length >= 2)
        .map((c) => CustomerVariant(
              customerId: c.customerId,
              customerName: c.customerName,
              customerPhone: c.customerPhone,
              categories: c.categories,
              types: c.types,
              purchaseCount: c.purchaseCount,
            ))
        .toList();

    // Sort by purchase count descending
    variants.sort((a, b) => b.purchaseCount.compareTo(a.purchaseCount));

    debugPrint(
        'DmeCustomerVariants: found ${variants.length} customers with multiple categories/types');

    return variants;
  }

  /// Convenience: get all branches the user can see.
  Future<List<int>> getUserBranchIds(String dmeUserId) =>
      DmeUserService.instance.getUserBranchIds(dmeUserId);

  /// All branches (for admins).
  Future<List<Map<String, dynamic>>> getAllBranches() =>
      _svc.getBranches();
}

// ── Internal accumulator ─────────────────────────────────────────────────────

class _CustomerAccum {
  final int customerId;
  final String customerName;
  final String customerPhone;
  final Set<String> categories = {};
  final Set<String> types = {};
  int purchaseCount = 0;

  _CustomerAccum({
    required this.customerId,
    required this.customerName,
    required this.customerPhone,
  });
}
