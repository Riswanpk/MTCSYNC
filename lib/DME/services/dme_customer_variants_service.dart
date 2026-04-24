import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dme_supabase_service.dart';

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

  final _svc = DmeSupabaseService.instance;

  SupabaseClient get _client => Supabase.instance.client;

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

    while (true) {
      var query = _client
          .from('dme_customer_purchases')
          .select(
              'customer_id, purchase_date, dme_customers(id, name, phone), purchase_details')
          .gte('purchase_date', fromStr)
          .lte('purchase_date', toStr);

      if (branchIds != null && branchIds.isNotEmpty) {
        query = query.inFilter('purchase_for_branch_id', branchIds);
      }

      final batch =
          await query.range(offset, offset + batchSize - 1) as List<dynamic>;

      if (batch.isEmpty) break;

      for (final row in batch) {
        final customerId = row['customer_id'] as int;
        final customerData =
            row['dme_customers'] as Map<String, dynamic>? ?? {};
        final customerName = customerData['name'] as String? ?? 'Unknown';
        final customerPhone = customerData['phone'] as String? ?? '';
        final details = row['purchase_details'] as Map<String, dynamic>?;

        final category = details?['category'] as String? ?? 'Uncategorised';
        final type = details?['customer_type'] as String? ?? 'Uncategorised';

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
      _svc.getUserBranchIds(dmeUserId);

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
