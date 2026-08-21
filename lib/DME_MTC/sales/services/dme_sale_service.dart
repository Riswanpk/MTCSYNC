import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/dme_sale.dart';
import '../../core/services/dme_supabase_service.dart';

class DmeSaleService {
  DmeSaleService._();
  static final DmeSaleService instance = DmeSaleService._();

  SupabaseClient get _client => DmeMtcSupabaseService.instance.client;

  Future<int> insertSale(DmeSale sale) async {
    await DmeMtcSupabaseService.instance.ensureInitialized();
    try {
      final res = await _client
          .from('dme_sales')
          .upsert(sale.toInsertMap(), onConflict: 'date,customer_id')
          .select('id')
          .single();
      final saleId = res['id'] as int;

      await _client.from('dme_sales_detail').delete().eq('sale_id', saleId);

      if (sale.items.isNotEmpty) {
        final productsJson = sale.items.map((item) => {
          'product_name': item.productName,
          'quantity': item.quantity
        }).toList();
        
        await _client.from('dme_sales_detail').insert({
          'sale_id': saleId,
          'products': productsJson
        });
      }
      return saleId;
    } catch (e) {
      debugPrint('Network error inserting sale: $e');
      rethrow;
    }
  }

  Future<List<DmeSale>> getSalesByDate(DateTime date,
      {List<int>? branchIds}) async {
    await DmeMtcSupabaseService.instance.ensureInitialized();
    var query = _client
        .from('dme_sales')
        .select('*, dme_customers(name, phone, branch_ids), dme_sales_detail(*)');

    query = query.eq('date', date.toIso8601String().split('T')[0]);

    final allSales = <DmeSale>[];
    final rawRows = <Map<String, dynamic>>[];
    const pageSize = 1000;
    int offset = 0;
    bool hasMore = true;

    while (hasMore) {
      final res = await query
          .order('uploaded_at', ascending: false)
          .range(offset, offset + pageSize - 1);

      if ((res as List).isEmpty) {
        hasMore = false;
      } else {
        for (var row in res) {
          allSales.add(DmeSale.fromMap(row as Map<String, dynamic>));
          rawRows.add(row as Map<String, dynamic>);
        }
        offset += pageSize;
        hasMore = (res as List).length == pageSize;
      }
    }

    if (branchIds != null && branchIds.isNotEmpty) {
      return allSales.where((s) {
        try {
          final raw = rawRows.firstWhere((r) => r['id'] == s.id);
          final custBranch =
              (raw['dme_customers'] as Map?)?['branch_id'] as int?;
          return s.customerId != null &&
              custBranch != null &&
              branchIds.contains(custBranch);
        } catch (e) {
          return false;
        }
      }).toList();
    }
    return allSales;
  }

  Future<List<DmeSale>> getSalesForCustomer(int customerId) async {
    await DmeMtcSupabaseService.instance.ensureInitialized();
    final res = await _client
        .from('dme_sales')
        .select('*, dme_sales_detail(*)')
        .eq('customer_id', customerId)
        .order('date', ascending: false);
    return (res as List).map((e) => DmeSale.fromMap(e)).toList();
  }

  Future<List<DmeSaleItem>> getSaleItemsByCustomerDate(
      int customerId, DateTime date) async {
    await DmeMtcSupabaseService.instance.ensureInitialized();
    final dateStr = date.toIso8601String().split('T')[0];
    final res = await _client
        .from('dme_sales')
        .select('id, dme_sales_detail(*)')
        .eq('customer_id', customerId)
        .eq('date', dateStr)
        .maybeSingle();
    if (res == null) return [];
    final detailsList = res['dme_sales_detail'] as List?;
    if (detailsList == null || detailsList.isEmpty) return [];
    final firstDetail = detailsList.first as Map<String, dynamic>?;
    final productsJson = firstDetail?['products'] as List?;
    if (productsJson == null) return [];
    return productsJson
        .map((e) => DmeSaleItem.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> deleteSaleItemsByCustomerDate(
      int customerId, DateTime date) async {
    await DmeMtcSupabaseService.instance.ensureInitialized();
    final dateStr = date.toIso8601String().split('T')[0];
    final res = await _client
        .from('dme_sales')
        .select('id')
        .eq('customer_id', customerId)
        .eq('date', dateStr)
        .maybeSingle();
    if (res == null) return;
    final saleId = res['id'] as int;
    await _client.from('dme_sales_detail').delete().eq('sale_id', saleId);
  }
}
