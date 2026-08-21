import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../../models/dme_customer.dart';
import '../../core/services/dme_supabase_service.dart';
import '../../reminders/services/dme_reminder_service.dart';

class DmeCustomerService {
  DmeCustomerService._();
  static final DmeCustomerService instance = DmeCustomerService._();

  SupabaseClient get _client => DmeMtcSupabaseService.instance.client;

  Future<List<DmeCustomer>> getCustomers({
    List<int>? branchIds,
    String? search,
    int? categoryId,
    int? customerTypeId,
    DateTime? lastPurchaseDateFrom,
    DateTime? lastPurchaseDateTo,
    String? salesman,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      await DmeMtcSupabaseService.instance.ensureInitialized();
      
      const maxRetries = 3;
      final delays = [1000, 2000, 4000];
      
      for (int attempt = 0; attempt < maxRetries; attempt++) {
        try {
          var query = _client.from('dme_customers').select(
              '*, dme_categories(id, name), dme_customer_types(id, name)');

          if (branchIds != null && branchIds.isNotEmpty) {
            final purchaseRows = await _client
                .from('dme_sales')
                .select('customer_id')
                .inFilter('purchased_branch', branchIds);
            final purchasedCustomerIds = (purchaseRows as List)
                .map((e) => (e['customer_id'] ?? e['cust_id']) as int)
                .toSet()
                .toList();

            if (purchasedCustomerIds.isNotEmpty) {
              if (purchasedCustomerIds.length > 200 || branchIds.length > 200) {
                query = query.inFilter('branch_id', branchIds);
              } else {
                query = query.or(
                    'branch_id.in.(${branchIds.join(',')}),id.in.(${purchasedCustomerIds.join(',')})');
              }
            } else {
              query = query.inFilter('branch_id', branchIds);
            }
          }
          if (search != null && search.isNotEmpty) {
            query = query.or('name.ilike.%$search%,phone.ilike.%$search%');
          }

          if (categoryId != null) {
            query = query.eq('category_id', categoryId);
          }

          if (customerTypeId != null) {
            query = query.eq('customer_type_id', customerTypeId);
          }

          if (lastPurchaseDateFrom != null || lastPurchaseDateTo != null) {
            var purchaseQuery =
                _client.from('dme_sales').select('customer_id');

            if (lastPurchaseDateFrom != null) {
              purchaseQuery = purchaseQuery.gte('date',
                  lastPurchaseDateFrom.toIso8601String().split('T')[0]);
            }
            if (lastPurchaseDateTo != null) {
              purchaseQuery = purchaseQuery.lte('date',
                  lastPurchaseDateTo.toIso8601String().split('T')[0]);
            }

            final customerIdSet = <int>{};
            const pageSize = 1000;
            int purchaseOffset = 0;
            bool hasMore = true;

            while (hasMore) {
              final purchaseRows =
                  await purchaseQuery.range(purchaseOffset, purchaseOffset + pageSize - 1);

              if ((purchaseRows as List).isEmpty) {
                hasMore = false;
              } else {
                for (var row in purchaseRows) {
                  final customerId = row['customer_id'] as int?;
                  if (customerId != null) {
                    customerIdSet.add(customerId);
                  }
                }
                purchaseOffset += pageSize;
                hasMore = (purchaseRows as List).length == pageSize;
              }
            }

            if (customerIdSet.isEmpty) {
              return [];
            }

            if (customerIdSet.length > 1000) {
              final customerList = customerIdSet.toList();
              final results = <DmeCustomer>[];
              const batchSize = 1000;
              
              for (int i = 0; i < customerList.length; i += batchSize) {
                final batchEnd = (i + batchSize > customerList.length) 
                    ? customerList.length 
                    : i + batchSize;
                final batch = customerList.sublist(i, batchEnd);
                
                var batchQuery = _client.from('dme_customers').select(
                    '*, dme_categories(id, name), dme_customer_types(id, name)');
                batchQuery = batchQuery.inFilter('id', batch);
                
                if (categoryId != null) {
                  batchQuery = batchQuery.eq('category_id', categoryId);
                }
                if (customerTypeId != null) {
                  batchQuery = batchQuery.eq('customer_type_id', customerTypeId);
                }
                if (salesman != null && salesman.isNotEmpty) {
                  batchQuery = batchQuery.eq('salesman', salesman);
                }
                
                final batchRes = await batchQuery.order('name', ascending: true);
                results.addAll((batchRes as List).map((e) => DmeCustomer.fromMap(e)));
              }
              
              return results;
            } else {
              query = query.inFilter('id', customerIdSet.toList());
            }
          }

          if (salesman != null && salesman.isNotEmpty) {
            query = query.eq('salesman', salesman);
          }

          final res = await query
              .order('name', ascending: true)
              .range(offset, offset + limit - 1);
          return (res as List).map((e) => DmeCustomer.fromMap(e)).toList();
        } catch (e) {
          final errorStr = e.toString();
          final isTransientError = errorStr.contains('Connection reset') ||
              errorStr.contains('connection closed') ||
              errorStr.contains('timeout') ||
              errorStr.contains('SocketException') ||
              errorStr.contains('ClientException');
          
          if (isTransientError && attempt < maxRetries - 1) {
            debugPrint(
                'DME getCustomers - Connection error on attempt ${attempt + 1}, retrying in ${delays[attempt]}ms: $e');
            await Future.delayed(Duration(milliseconds: delays[attempt]));
            continue;
          } else {
            debugPrint('DME getCustomers - Error (final attempt): $e');
            rethrow;
          }
        }
      }
      
      return [];
    } catch (e) {
      debugPrint('Error fetching DME customers: $e');
      FirebaseCrashlytics.instance.recordError(e, StackTrace.current);
      return [];
    }
  }

  Future<DmeCustomer?> getCustomerById(int customerId) async {
    await DmeMtcSupabaseService.instance.ensureInitialized();
    final res = await _client
        .from('dme_customers')
        .select('*')
        .eq('id', customerId)
        .maybeSingle();
    return res != null ? DmeCustomer.fromMap(res) : null;
  }

  Future<DmeCustomer?> findCustomerByPhone(String phone) async {
    await DmeMtcSupabaseService.instance.ensureInitialized();
    final normalized = DmeCustomer.normalizePhone(phone);
    if (normalized.isEmpty) return null;
    final res = await _client
        .from('dme_customers')
        .select('*')
        .eq('phone', normalized)
        .maybeSingle();
    return res != null ? DmeCustomer.fromMap(res) : null;
  }

  Future<DmeCustomer> upsertCustomer(DmeCustomer customer) async {
    await DmeMtcSupabaseService.instance.ensureInitialized();
    final map = customer.toInsertMap();
    map['updated_at'] = DateTime.now().toUtc().toIso8601String();
    final res = await _client
        .from('dme_customers')
        .upsert(map, onConflict: 'phone')
        .select('*')
        .single();
    return DmeCustomer.fromMap(res);
  }

  Future<void> updateCustomer({
    required int customerId,
    required String name,
    required String phone,
    String? address,
    String? category,
    String? customerType,
    int? categoryId,
    int? customerTypeId,
    String? salesman,
    int? branchId,
  }) async {
    await DmeMtcSupabaseService.instance.ensureInitialized();
    final map = <String, dynamic>{
      'name': name,
      'phone': DmeCustomer.normalizePhone(phone),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    if (address != null) map['address'] = address;
    if (category != null) map['category'] = category;
    if (customerType != null) map['customer_type'] = customerType;
    if (categoryId != null) map['category_id'] = categoryId;
    if (customerTypeId != null) map['customer_type_id'] = customerTypeId;
    if (salesman != null) map['salesman'] = salesman;
    if (branchId != null) map['branch_id'] = branchId;

    try {
      await _client.from('dme_customers').update(map).eq('id', customerId);
    } catch (e) {
      debugPrint('Network error updating customer $customerId: $e');
      rethrow;
    }
  }

  Future<String?> getCustomerBranchName(int customerId) async {
    await DmeMtcSupabaseService.instance.ensureInitialized();
    try {
      final res = await _client
          .from('dme_customers')
          .select('branch_id')
          .eq('id', customerId)
          .maybeSingle();

      if (res != null && res['branch_id'] != null) {
        return DmeMtcSupabaseService.instance.getBranchNameById(res['branch_id'] as int);
      }
      return null;
    } catch (e) {
      debugPrint('Error getting customer branch name for ID $customerId: $e');
      return null;
    }
  }

  Future<void> insertCustomerBranch({
    required int customerId,
    required int branchId,
    int? categoryId,
    int? customerTypeId,
  }) async {
    await DmeMtcSupabaseService.instance.ensureInitialized();
    try {
      final map = <String, dynamic>{
        'customer_id': customerId,
        'branch_id': branchId,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      };
      if (categoryId != null) map['category_id'] = categoryId;
      if (customerTypeId != null) map['customer_type_id'] = customerTypeId;

      await _client.from('dme_customer_branches').upsert(
            map,
            onConflict: 'customer_id,branch_id',
          );
    } catch (e) {
      debugPrint('Error inserting customer branch for customer $customerId: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getCustomerBranches(int customerId) async {
    await DmeMtcSupabaseService.instance.ensureInitialized();
    try {
      final res = await _client
          .from('dme_customer_branches')
          .select('*, dme_categories(name), dme_customer_types(name)')
          .eq('customer_id', customerId);
      return List<Map<String, dynamic>>.from(res as List);
    } catch (e) {
      debugPrint('Error getting customer branches for customer $customerId: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getCustomerBranchesWithPurchases(
      int customerId) async {
    try {
      await DmeMtcSupabaseService.instance.ensureInitialized();

      final customer = await _client
          .from('dme_customers')
          .select('id, branch_id, salesman')
          .eq('id', customerId)
          .maybeSingle();

      if (customer == null) return [];

      final branches = <String, Map<String, dynamic>>{};

      final primaryBranchId = customer['branch_id'] as int?;
      if (primaryBranchId != null) {
        final branchName = await DmeMtcSupabaseService.instance.getBranchNameById(primaryBranchId) ?? 'Unknown';
        branches[primaryBranchId.toString()] = {
          'branch_id': primaryBranchId,
          'branch_name': branchName,
          'salesman': customer['salesman'] ?? 'Not Assigned',
          'purchase_count': 0,
          'last_purchase_date': null,
          'is_primary': true,
        };
      }

      final purchases = await _client
          .from('dme_sales')
          .select('purchased_branch, date, salesman')
          .eq('customer_id', customerId)
          .order('date', ascending: false);

      final branchesList = await DmeMtcSupabaseService.instance.getBranches();
      final branchMap = {
        for (final b in branchesList) (b['id'] as int): (b['name'] as String)
      };

      for (final purchase in purchases) {
        final branchId = purchase['purchased_branch'] as int? ?? 0;
        final branchName = branchMap[branchId] ?? 'Unknown';
        final purchaseDate = purchase['date'] as String?;
        final salesman = purchase['salesman'] as String? ?? 'Not Assigned';

        final key = branchId.toString();
        if (branches.containsKey(key)) {
          branches[key]!['purchase_count'] =
              (branches[key]!['purchase_count'] as int) + 1;
          if (branches[key]!['last_purchase_date'] == null) {
            branches[key]!['last_purchase_date'] = purchaseDate;
          }
        } else {
          branches[key] = {
            'branch_id': branchId,
            'branch_name': branchName,
            'salesman': salesman,
            'purchase_count': 1,
            'last_purchase_date': purchaseDate,
            'is_primary': false,
          };
        }
      }

      return branches.values.toList();
    } catch (e) {
      debugPrint('Error getting customer branch purchases: $e');
      return [];
    }
  }

  Future<void> upsertCustomersBatch(List<Map<String, dynamic>> rows,
      {void Function(int done, int total)? onProgress}) async {
    await DmeMtcSupabaseService.instance.ensureInitialized();
    const batchSize = 500;
    try {
      for (var i = 0; i < rows.length; i += batchSize) {
        final batch = rows.sublist(
            i, i + batchSize > rows.length ? rows.length : i + batchSize);
        await _client.from('dme_customers').upsert(batch, onConflict: 'phone');
        onProgress?.call(i + batch.length, rows.length);
      }
    } catch (e) {
      debugPrint('Network error upserting customer batch: $e');
      rethrow;
    }
  }

  Future<void> updateLastPurchaseDate(int customerId, DateTime date) async {
    await DmeMtcSupabaseService.instance.ensureInitialized();
    try {
      await _client.from('dme_customers').update({
        'last_purchase_date': date.toIso8601String().split('T')[0],
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', customerId);
    } catch (e) {
      debugPrint('Network error updating last purchase date for customer $customerId: $e');
      rethrow;
    }
  }

  Future<Map<String, int>> uploadCustomerDatabase({
    required List<DmeCustomer> customers,
    required String branchName,
    void Function(int done, int total)? onProgress,
  }) async {
    await DmeMtcSupabaseService.instance.ensureInitialized();
    int created = 0;
    int linkedToExisting = 0;
    int remindersCreated = 0;

    final branchRes = await _client
        .from('dme_branches')
        .select('id')
        .eq('name', branchName)
        .maybeSingle();
    final branchId = branchRes?['id'] as int?;

    if (branchId == null) {
      throw Exception(
          'Branch not found: $branchName. Please sync branches first.');
    }

    for (int i = 0; i < customers.length; i++) {
      final customer = customers[i];

      try {
        final existingRes = await _client
            .from('dme_customers')
            .select('id, name, purchased_for')
            .eq('phone', customer.phone)
            .maybeSingle();

        int customerId;
        if (existingRes != null) {
          customerId = existingRes['id'] as int;

          if (customer.lastPurchaseDate != null) {
            await updateLastPurchaseDate(customerId, customer.lastPurchaseDate!);
          }
          linkedToExisting++;
        } else {
          final custMap = customer.toInsertMap();
          custMap['updated_at'] = DateTime.now().toUtc().toIso8601String();

          final insertRes = await _client
              .from('dme_customers')
              .insert(custMap)
              .select('id')
              .single();

          customerId = insertRes['id'] as int;
          created++;
        }

        if (customer.lastPurchaseDate != null) {
          final reminderDate =
              customer.lastPurchaseDate!.add(const Duration(days: 28));
          await _client.from('dme_reminders').upsert({
            'customer_id': customerId,
            'reminder_date': reminderDate.toIso8601String().split('T')[0],
            'last_purchase_date':
                customer.lastPurchaseDate!.toIso8601String().split('T')[0],
            'last_purchase_branch': branchId,
            'status': 'pending',
          }, onConflict: 'customer_id');
          remindersCreated++;
        }
      } catch (e) {
        debugPrint('Error uploading customer ${customer.name}: $e');
        rethrow;
      }

      onProgress?.call(i + 1, customers.length);
    }

    return {
      'created': created,
      'linked_to_existing': linkedToExisting,
      'reminders_created': remindersCreated,
    };
  }
}
