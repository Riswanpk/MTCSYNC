import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../dme_config.dart';
import '../models/dme_user.dart';
import '../models/dme_product.dart';
import '../models/dme_customer.dart';
import '../models/dme_sale.dart';
import '../models/dme_reminder.dart';

class DmeSupabaseService {
  DmeSupabaseService._();
  static final DmeSupabaseService instance = DmeSupabaseService._();

  bool _supabaseReady = false;

  /// Initializes Supabase exactly once. Safe to call multiple times.
  /// Must be awaited before any Supabase operation is performed.
  Future<void> ensureInitialized() async {
    if (_supabaseReady) return;
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );
    _supabaseReady = true;
  }

  SupabaseClient get _client => Supabase.instance.client;

  // ── Cached current user ──────────────────────────────────────
  DmeUser? _currentUser;
  bool _branchesSynced = false;

  /// Verify Supabase connection and return detailed error info
  Future<Map<String, dynamic>> diagnoseConnection() async {
    await ensureInitialized();
    try {
      final result = await _client.from('dme_users').select('id').limit(1);
      return {'status': 'connected', 'message': 'Supabase connection OK'};
    } on AuthException catch (e) {
      return {
        'status': 'auth_error',
        'message': e.message,
        'hint': 'Check your Supabase anon key in lib/DME/dme_config.dart',
      };
    } catch (e) {
      return {
        'status': 'error',
        'message': e.toString(),
        'hint': 'Verify Supabase URL and anon key are correct',
      };
    }
  }

  Future<DmeUser?> getCurrentUser(String firebaseUid) async {
    await ensureInitialized();
    if (_currentUser != null && _currentUser!.firebaseUid == firebaseUid) {
      return _currentUser;
    }
    final res = await _client
        .from('dme_users')
        .select()
        .eq('firebase_uid', firebaseUid)
        .maybeSingle();
    if (res == null) return null;

    final branches = await getUserBranchNames(res['id'] as String);
    _currentUser = DmeUser.fromMap(res, branches: branches);
    return _currentUser;
  }

  void clearCache() => _currentUser = null;

  Future<bool> isAdmin(String firebaseUid) async {
    final user = await getCurrentUser(firebaseUid);
    return user?.isAdmin ?? false;
  }

  // ── Branches ─────────────────────────────────────────────────

  /// Upserts the fixed app branch list into dme_branches (runs once per session).
  Future<void> _syncAppBranches() async {
    if (_branchesSynced) return;
    await _client.from('dme_branches').upsert(
      kAppBranches.map((name) => {'name': name}).toList(),
      onConflict: 'name',
    );
    _branchesSynced = true;
  }

  Future<List<Map<String, dynamic>>> getBranches() async {
    await ensureInitialized();
    await _syncAppBranches();
    final res =
        await _client.from('dme_branches').select().order('name', ascending: true);
    return List<Map<String, dynamic>>.from(res);
  }

  Future<List<String>> getUserBranchNames(String dmeUserId) async {
    final res = await _client
        .from('dme_user_branches')
        .select('branch_id, dme_branches(name)')
        .eq('user_id', dmeUserId);
    return List<Map<String, dynamic>>.from(res)
        .map((e) => (e['dme_branches'] as Map)['name'] as String)
        .toList();
  }

  Future<List<int>> getUserBranchIds(String dmeUserId) async {
    final res = await _client
        .from('dme_user_branches')
        .select('branch_id')
        .eq('user_id', dmeUserId);
    return List<Map<String, dynamic>>.from(res)
        .map((e) => e['branch_id'] as int)
        .toList();
  }

  // ── DME Users (admin) ────────────────────────────────────────
  Future<List<DmeUser>> getAllDmeUsers() async {
    final res = await _client.from('dme_users').select().order('username');
    final users = <DmeUser>[];
    for (final row in res) {
      final branches = await getUserBranchNames(row['id'] as String);
      users.add(DmeUser.fromMap(row, branches: branches));
    }
    return users;
  }

  Future<DmeUser> createDmeUser({
    required String firebaseUid,
    required String email,
    required String username,
    required String role,
    required List<int> branchIds,
  }) async {
    final row = await _client.from('dme_users').insert({
      'firebase_uid': firebaseUid,
      'email': email,
      'username': username,
      'role': role,
    }).select().single();

    if (branchIds.isNotEmpty) {
      await _client.from('dme_user_branches').insert(
        branchIds.map((bid) => {'user_id': row['id'], 'branch_id': bid}).toList(),
      );
    }
    final branches = await getUserBranchNames(row['id'] as String);
    return DmeUser.fromMap(row, branches: branches);
  }

  Future<void> updateDmeUserRole(String userId, String role) async {
    await _client.from('dme_users').update({'role': role}).eq('id', userId);
  }

  Future<void> setUserBranches(String userId, List<int> branchIds) async {
    await _client.from('dme_user_branches').delete().eq('user_id', userId);
    if (branchIds.isNotEmpty) {
      await _client.from('dme_user_branches').insert(
        branchIds.map((bid) => {'user_id': userId, 'branch_id': bid}).toList(),
      );
    }
    _currentUser = null; // invalidate cache
  }

  Future<void> deleteDmeUser(String userId) async {
    await _client.from('dme_users').delete().eq('id', userId);
  }

  /// Syncs Firebase users with role='dme_user' to Supabase dme_users table.
  /// Only creates new entries in Supabase for users not already present.
  /// Returns a map with sync results.
  Future<Map<String, dynamic>> syncFirebaseUsersToSupabase() async {
    await ensureInitialized();
    
    try {
      // Fetch all Firebase users with role='dme_user'
      final firebaseSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'dme_user')
          .get();

      int addedCount = 0;
      int skippedCount = 0;

      for (final doc in firebaseSnapshot.docs) {
        final firebaseUid = doc.id;
        final email = doc['email'] as String? ?? '';
        final username = doc['username'] as String? ?? '';

        // Check if this user already exists in Supabase dme_users
        final existing = await _client
            .from('dme_users')
            .select('id')
            .eq('firebase_uid', firebaseUid)
            .maybeSingle();

        if (existing == null) {
          // User doesn't exist in Supabase, add them
          try {
            await _client.from('dme_users').insert({
              'firebase_uid': firebaseUid,
              'email': email,
              'username': username,
              'role': 'dme_user',
            });
            addedCount++;
          } catch (e) {
            debugPrint('Error adding user $username: $e');
          }
        } else {
          skippedCount++;
        }
      }

      return {
        'success': true,
        'addedCount': addedCount,
        'skippedCount': skippedCount,
        'totalProcessed': firebaseSnapshot.docs.length,
        'message': 'Synced $addedCount new DME users from Firebase',
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
        'message': 'Error syncing Firebase users: $e',
      };
    }
  }

  // ── Products ─────────────────────────────────────────────────
  Future<List<DmeProduct>> getProducts({String? search}) async {
    var query = _client.from('dme_products').select();
    if (search != null && search.isNotEmpty) {
      query = query.ilike('name', '%$search%');
    }
    final res = await query.order('name');
    return (res as List).map((e) => DmeProduct.fromMap(e)).toList();
  }

  Future<int> getProductCount() async {
    final res =
        await _client.from('dme_products').select('id').count(CountOption.exact);
    return res.count;
  }

  Future<void> upsertProducts(List<DmeProduct> products) async {
    final rows = products.map((p) => p.toInsertMap()).toList();
    await _client.from('dme_products').upsert(rows, onConflict: 'name');
  }

  // ── Categories & Types (Lookup) ──────────────────────────────
  /// Looks up category ID by name. Returns null if not found.
  Future<int?> getCategoryIdByName(String name) async {
    try {
      final res = await _client
          .from('dme_categories')
          .select('id')
          .eq('name', name)
          .maybeSingle();
      return res != null ? res['id'] as int? : null;
    } catch (e) {
      debugPrint('Error looking up category ID for "$name": $e');
      return null;
    }
  }

  /// Looks up customer type ID by name. Returns null if not found.
  Future<int?> getTypeIdByName(String name) async {
    try {
      final res = await _client
          .from('dme_customer_types')
          .select('id')
          .eq('name', name)
          .maybeSingle();
      return res != null ? res['id'] as int? : null;
    } catch (e) {
      debugPrint('Error looking up type ID for "$name": $e');
      return null;
    }
  }

  // ── Customers ────────────────────────────────────────────────
  Future<List<DmeCustomer>> getCustomers({
    List<int>? branchIds,
    String? search,
    int? categoryId,
    int? customerTypeId,
    String? category,      // Deprecated: use categoryId instead
    String? customerType,  // Deprecated: use customerTypeId instead
    int limit = 50,
    int offset = 0,
  }) async {
    var query = _client
        .from('dme_customers')
        .select('*, dme_branches(name), dme_categories(id, name), dme_customer_types(id, name)');

    if (branchIds != null && branchIds.isNotEmpty) {
      query = query.inFilter('branch_id', branchIds);
    }
    if (search != null && search.isNotEmpty) {
      query = query.or('name.ilike.%$search%,phone.ilike.%$search%');
    }
    
    // Support both new FK-based and old TEXT-based filtering for backward compatibility
    if (categoryId != null) {
      query = query.eq('category_id', categoryId);
    } else if (category != null) {
      query = query.eq('category', category);
    }
    
    if (customerTypeId != null) {
      query = query.eq('customer_type_id', customerTypeId);
    } else if (customerType != null) {
      query = query.eq('customer_type', customerType);
    }

    final res = await query
        .order('name', ascending: true)
        .range(offset, offset + limit - 1);
    return (res as List).map((e) => DmeCustomer.fromMap(e)).toList();
  }

  /// Find customer by phone (phone is now the sole unique key).
  Future<DmeCustomer?> findCustomerByPhone(String phone) async {
    final normalized = DmeCustomer.normalizePhone(phone);
    if (normalized.isEmpty) return null;
    final res = await _client
        .from('dme_customers')
        .select('*, dme_branches(name)')
        .eq('phone', normalized)
        .maybeSingle();
    return res != null ? DmeCustomer.fromMap(res) : null;
  }

  Future<DmeCustomer> upsertCustomer(DmeCustomer customer) async {
    final map = customer.toInsertMap();
    map['updated_at'] = DateTime.now().toUtc().toIso8601String();
    final res = await _client
        .from('dme_customers')
        .upsert(map, onConflict: 'phone')
        .select('*, dme_branches(name)')
        .single();
    return DmeCustomer.fromMap(res);
  }

  /// Append an alternate name to a customer's purchased_for field.
  /// Skips if the name is already present (case-insensitive).
  Future<void> appendPurchasedFor(int customerId, String alternateName) async {
    final res = await _client
        .from('dme_customers')
        .select('purchased_for')
        .eq('id', customerId)
        .single();
    final existing = res['purchased_for'] as String? ?? '';
    final parts = existing.isEmpty
        ? <String>[]
        : existing.split(',').map((s) => s.trim()).toList();
    final lowerParts = parts.map((s) => s.toLowerCase()).toSet();
    if (!lowerParts.contains(alternateName.toLowerCase().trim())) {
      parts.add(alternateName.trim());
      await _client.from('dme_customers').update({
        'purchased_for': parts.join(', '),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', customerId);
    }
  }

  Future<void> upsertCustomersBatch(
      List<Map<String, dynamic>> rows, {void Function(int done, int total)? onProgress}) async {
    const batchSize = 500;
    for (var i = 0; i < rows.length; i += batchSize) {
      final batch = rows.sublist(
          i, i + batchSize > rows.length ? rows.length : i + batchSize);
      await _client.from('dme_customers').upsert(batch, onConflict: 'phone');
      onProgress?.call(i + batch.length, rows.length);
    }
  }

  Future<void> updateLastPurchaseDate(int customerId, DateTime date) async {
    await _client.from('dme_customers').update({
      'last_purchase_date': date.toIso8601String().split('T')[0],
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', customerId);
  }

  // ── Sales ────────────────────────────────────────────────────
  Future<int> insertSale(DmeSale sale) async {
    final res = await _client
        .from('dme_sales')
        .upsert(sale.toInsertMap(), onConflict: 'date,customer_id')
        .select('id')
        .single();
    final saleId = res['id'] as int;

    // delete old items if re-upload
    await _client.from('dme_sale_items').delete().eq('sale_id', saleId);

    if (sale.items.isNotEmpty) {
      await _client.from('dme_sale_items').insert(
        sale.items.map((item) => item.toInsertMap(saleId)).toList(),
      );
    }
    return saleId;
  }

  Future<List<DmeSale>> getSalesByDate(DateTime date, {List<int>? branchIds}) async {
    var query = _client
        .from('dme_sales')
        .select('*, dme_customers(name, phone, branch_id), dme_sale_items(*)');

    query = query.eq('date', date.toIso8601String().split('T')[0]);

    final res = await query.order('uploaded_at', ascending: false);
    final sales = (res as List).map((e) => DmeSale.fromMap(e)).toList();
    if (branchIds != null && branchIds.isNotEmpty) {
      return sales
          .where((s) =>
              s.customerId != null &&
              branchIds.contains(
                  (res.firstWhere((r) => r['id'] == s.id)['dme_customers']
                      as Map?)?['branch_id']))
          .toList();
    }
    return sales;
  }

  Future<List<DmeSale>> getSalesForCustomer(int customerId) async {
    final res = await _client
        .from('dme_sales')
        .select('*, dme_sale_items(*)')
        .eq('customer_id', customerId)
        .order('date', ascending: false);
    return (res as List).map((e) => DmeSale.fromMap(e)).toList();
  }

  // ── Purchase Tracking (Branch-based) ────────────────────────

  /// Record a purchase with branch information in dme_customer_purchases table
  Future<void> recordPurchaseWithBranch({
    required int customerId,
    required DateTime purchaseDate,
    required int purchaseForBranchId,
    required String? purchaseForBranchName,
    Map<String, dynamic>? purchaseDetails, // items, salesman, etc.
  }) async {
    try {
      await _client.from('dme_customer_purchases').insert({
        'customer_id': customerId,
        'purchase_date': purchaseDate.toIso8601String().split('T')[0],
        'purchase_for_branch_id': purchaseForBranchId,
        'purchase_for_branch_name': purchaseForBranchName,
        'purchase_details': purchaseDetails,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Error recording purchase with branch: $e');
      rethrow;
    }
  }

  /// Get assigned DME user for a specific branch
  Future<DmeUser?> getDmeUserForBranch(int branchId) async {
    try {
      final res = await _client
          .from('dme_users')
          .select()
          .contains('branch_ids', '[$branchId]')
          .limit(1)
          .maybeSingle();

      if (res == null) return null;
      return DmeUser.fromMap(res);
    } catch (e) {
      debugPrint('Error getting DME user for branch: $e');
      return null;
    }
  }

  // ── Reminders ────────────────────────────────────────────────
  Future<void> upsertReminder({
    required int customerId,
    required DateTime purchaseDate,
    required int purchaseForBranchId,
    String? purchaseForBranchName,
    String? assignedTo,
    Map<String, dynamic>? purchaseDetails,
  }) async {
    // First, record the purchase with branch information
    await recordPurchaseWithBranch(
      customerId: customerId,
      purchaseDate: purchaseDate,
      purchaseForBranchId: purchaseForBranchId,
      purchaseForBranchName: purchaseForBranchName,
      purchaseDetails: purchaseDetails,
    );

    // Check if reminder already exists for this customer
    final existing = await _client
        .from('dme_reminders')
        .select()
        .eq('customer_id', customerId)
        .maybeSingle();

    final reminderDate =
        DateTime(purchaseDate.year, purchaseDate.month + 1, purchaseDate.day);
    final purchaseDateStr = purchaseDate.toIso8601String().split('T')[0];
    final reminderDateStr = reminderDate.toIso8601String().split('T')[0];

    // Determine assigned user based on branch
    String? assignedUser = assignedTo;
    if (assignedUser == null) {
      final assignedDmeUser = await getDmeUserForBranch(purchaseForBranchId);
      if (assignedDmeUser != null) {
        assignedUser = assignedDmeUser.id;
      }
    }

    if (existing == null) {
      // New reminder: create with pending status
      await _client.from('dme_reminders').insert({
        'customer_id': customerId,
        'reminder_date': reminderDateStr,
        'last_purchase_date': purchaseDateStr,
        'purchased_for_branch_id': purchaseForBranchId,
        'purchased_for_branch_name': purchaseForBranchName,
        'status': 'pending',
        'assigned_to': assignedUser,
      });
    } else {
      // Check current status of existing reminder
      final currentStatus = existing['status'] as String? ?? 'pending';
      final existingBranchId = existing['purchased_for_branch_id'] as int?;

      if (currentStatus == 'completed' || currentStatus == 'dismissed') {
        // Reminder was already handled (completed/dismissed): create NEW reminder for this new purchase
        // This allows tracking new cycles after completion
        await _client.from('dme_reminders').insert({
          'customer_id': customerId,
          'reminder_date': reminderDateStr,
          'last_purchase_date': purchaseDateStr,
          'purchased_for_branch_id': purchaseForBranchId,
          'purchased_for_branch_name': purchaseForBranchName,
          'status': 'pending',
          'assigned_to': assignedUser,
        });
      } else {
        // Existing pending reminder: only update if new purchase date is AFTER last purchase date
        final lastPurchaseDateStr = existing['last_purchase_date'] as String?;
        final lastPurchaseDate = lastPurchaseDateStr != null
            ? DateTime.tryParse(lastPurchaseDateStr)
            : null;

        if (lastPurchaseDate == null || purchaseDate.isAfter(lastPurchaseDate)) {
          // New purchase is after last purchase: reschedule the existing reminder
          // If branch changed, also reassign to new branch's user
          await _client.from('dme_reminders').update({
            'reminder_date': reminderDateStr,
            'last_purchase_date': purchaseDateStr,
            'purchased_for_branch_id': purchaseForBranchId,
            'purchased_for_branch_name': purchaseForBranchName,
            'assigned_to': assignedUser,
          }).eq('customer_id', customerId);
        }
      }
    }
  }

  Future<List<DmeReminder>> getReminders({
    List<int>? branchIds,
    String? status,
    DateTime? from,
    DateTime? to,
  }) async {
    var query = _client
        .from('dme_reminders')
        .select('*, dme_customers(name, phone, address, branch_id, salesman)');

    if (status != null) query = query.eq('status', status);
    if (from != null) {
      query = query.gte('reminder_date', from.toIso8601String().split('T')[0]);
    }
    if (to != null) {
      query = query.lte('reminder_date', to.toIso8601String().split('T')[0]);
    }

    final res = await query.order('reminder_date', ascending: true);
    var reminders =
        (res as List).map((e) => DmeReminder.fromMap(e)).toList();

    if (branchIds != null && branchIds.isNotEmpty) {
      reminders = reminders
          .where((r) {
            final raw = res.firstWhere((row) => row['id'] == r.id);
            final custBranch =
                (raw['dme_customers'] as Map?)?['branch_id'] as int?;
            return custBranch != null && branchIds.contains(custBranch);
          })
          .toList();
    }
    return reminders;
  }

  Future<void> updateReminderStatus(int id, String status, {String? notes}) async {
    final map = <String, dynamic>{'status': status};
    if (notes != null) map['notes'] = notes;
    await _client.from('dme_reminders').update(map).eq('id', id);
  }

  /// Fetch sale items for a customer on a specific purchase date.
  /// Returns empty list if no sale exists or items have been deleted.
  Future<List<DmeSaleItem>> getSaleItemsByCustomerDate(
      int customerId, DateTime date) async {
    final dateStr = date.toIso8601String().split('T')[0];
    final res = await _client
        .from('dme_sales')
        .select('id, dme_sale_items(*)')
        .eq('customer_id', customerId)
        .eq('date', dateStr)
        .maybeSingle();
    if (res == null) return [];
    return ((res['dme_sale_items'] as List?) ?? [])
        .map((e) => DmeSaleItem.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// Hard-delete sale items for a customer's purchase date after call+remarks.
  Future<void> deleteSaleItemsByCustomerDate(
      int customerId, DateTime date) async {
    final dateStr = date.toIso8601String().split('T')[0];
    final res = await _client
        .from('dme_sales')
        .select('id')
        .eq('customer_id', customerId)
        .eq('date', dateStr)
        .maybeSingle();
    if (res == null) return;
    final saleId = res['id'] as int;
    await _client.from('dme_sale_items').delete().eq('sale_id', saleId);
  }

  // ── Call Logs ────────────────────────────────────────────────
  /// Deprecated: Call logging is now handled via status updates in updateReminderStatus
  /// This method is kept for backwards compatibility but doesn't perform any action
  Future<void> logCall({
    required int reminderId,
    required String calledBy,
    required DateTime callDate,
    String? remarks,
  }) async {
    // Call detection and logging is now handled through reminder status updates
    // No separate action needed here
  }

  /// Get call logs for a customer (returns reminders with 'called' status)
  Future<List<Map<String, dynamic>>> getCallLogs(int customerId) async {
    final res = await _client
        .from('dme_reminders')
        .select()
        .eq('customer_id', customerId)
        .eq('status', 'called')
        .order('reminder_date', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }

  // ── Dashboard stats ──────────────────────────────────────────
  Future<Map<String, int>> getDashboardCounts({List<int>? branchIds}) async {
    int customerCount = 0;
    int productCount = 0;
    int pendingReminders = 0;

    final cRes = branchIds != null && branchIds.isNotEmpty
        ? await _client
            .from('dme_customers')
            .select('id')
            .inFilter('branch_id', branchIds)
            .count(CountOption.exact)
        : await _client.from('dme_customers').select('id').count(CountOption.exact);
    customerCount = cRes.count;

    final pRes =
        await _client.from('dme_products').select('id').count(CountOption.exact);
    productCount = pRes.count;

    final rRes = await _client
        .from('dme_reminders')
        .select('id')
        .eq('status', 'pending')
        .count(CountOption.exact);
    pendingReminders = rRes.count;

    return {
      'customers': customerCount,
      'products': productCount,
      'pendingReminders': pendingReminders,
    };
  }

  Future<List<Map<String, dynamic>>> getSalesSummaryByBranch({
    required DateTime from,
    required DateTime to,
  }) async {
    final res = await _client
        .from('dme_sales')
        .select('total_quantity, dme_customers(branch_id, dme_branches(name))')
        .gte('date', from.toIso8601String().split('T')[0])
        .lte('date', to.toIso8601String().split('T')[0]);

    final Map<String, double> branchTotals = {};
    for (final row in res) {
      final branchName =
          ((row['dme_customers'] as Map?)?['dme_branches'] as Map?)?['name']
              as String? ??
          'Unknown';
      final qty = (row['total_quantity'] as num?)?.toDouble() ?? 0;
      branchTotals[branchName] = (branchTotals[branchName] ?? 0) + qty;
    }

    return branchTotals.entries
        .map((e) => {'branch': e.key, 'total_quantity': e.value})
        .toList()
      ..sort((a, b) =>
          (b['total_quantity'] as double).compareTo(a['total_quantity'] as double));
  }

  Future<List<Map<String, dynamic>>> getTopSalesmen({
    required DateTime from,
    required DateTime to,
    int limit = 10,
  }) async {
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

  // ── Customer Database Upload (with junction table) ─────────────
  /// Upload customer database from Excel with support for multiple companies per phone.
  /// Returns upload summary: {created: count, linked_to_existing: count, reminders_created: count}
  Future<Map<String, int>> uploadCustomerDatabase({
    required List<DmeCustomer> customers,
    required String branchName,
    void Function(int done, int total)? onProgress,
  }) async {
    int created = 0;
    int linkedToExisting = 0;
    int remindersCreated = 0;
    
    // Get branch ID
    final branchRes = await _client
        .from('dme_branches')
        .select('id')
        .eq('name', branchName)
        .maybeSingle();
    final branchId = branchRes?['id'] as int?;
    
    if (branchId == null) {
      throw Exception('Branch not found: $branchName. Please sync branches first.');
    }

    // Process each customer
    for (int i = 0; i < customers.length; i++) {
      final customer = customers[i];
      
      try {
        // Check if phone already exists
        final existingRes = await _client
            .from('dme_customers')
            .select('id, name, purchased_for')
            .eq('phone', customer.phone)
            .maybeSingle();
        
        int customerId;
        if (existingRes != null) {
          customerId = existingRes['id'] as int;
          // Append alternate name to purchased_for if name differs
          final existingName = (existingRes['name'] as String? ?? '').toLowerCase().trim();
          if (existingName != customer.name.toLowerCase().trim() &&
              customer.name.isNotEmpty) {
            await appendPurchasedFor(customerId, customer.name);
          }
          // Update last_purchase_date and salesman
          await _client.from('dme_customers').update({
            'last_purchase_date': customer.lastPurchaseDate?.toIso8601String().split('T')[0],
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          }).eq('id', customerId);
          linkedToExisting++;
        } else {
          // New customer
          final custMap = customer.toInsertMap();
          custMap['branch_id'] = branchId;
          custMap['updated_at'] = DateTime.now().toUtc().toIso8601String();
          
          final insertRes = await _client
              .from('dme_customers')
              .insert(custMap)
              .select('id')
              .single();
          
          customerId = insertRes['id'] as int;
          created++;
        }
        
        // Create reminder if last_purchase_date provided
        if (customer.lastPurchaseDate != null) {
          final reminderDate = customer.lastPurchaseDate!.add(const Duration(days: 30));
          await _client.from('dme_reminders').upsert({
            'customer_id': customerId,
            'reminder_date': reminderDate.toIso8601String().split('T')[0],
            'last_purchase_date': customer.lastPurchaseDate!.toIso8601String().split('T')[0],
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

  // ── New Reminder Query Methods ───────────────────────────────
  /// Get reminders due today for given branches
  Future<List<DmeReminder>> getRemindersForToday(List<int> branchIds) async {
    final today = DateTime.now();
    final todayStr = today.toIso8601String().split('T')[0];
    
    var query = _client
        .from('dme_reminders')
        .select('*, dme_customers(name, phone, address, branch_id, salesman)')
        .eq('reminder_date', todayStr)
        .eq('status', 'pending');
    
    final res = await query.order('reminder_date', ascending: true);
    var reminders = (res as List).map((e) => DmeReminder.fromMap(e)).toList();
    
    if (branchIds.isNotEmpty) {
      reminders = reminders.where((r) {
        final raw = res.firstWhere((row) => row['id'] == r.id);
        final custBranch = (raw['dme_customers'] as Map?)?['branch_id'] as int?;
        return custBranch != null && branchIds.contains(custBranch);
      }).toList();
    }
    
    return reminders;
  }

  /// Get pending reminders from previous days for given branches
  Future<List<DmeReminder>> getPendingFromPreviousDays(List<int> branchIds) async {
    final today = DateTime.now();
    final todayStr = today.toIso8601String().split('T')[0];
    
    var query = _client
        .from('dme_reminders')
        .select('*, dme_customers(name, phone, address, branch_id, salesman)')
        .lt('reminder_date', todayStr)
        .eq('status', 'pending');
    
    final res = await query.order('reminder_date', ascending: true);
    var reminders = (res as List).map((e) => DmeReminder.fromMap(e)).toList();
    
    if (branchIds.isNotEmpty) {
      reminders = reminders.where((r) {
        final raw = res.firstWhere((row) => row['id'] == r.id);
        final custBranch = (raw['dme_customers'] as Map?)?['branch_id'] as int?;
        return custBranch != null && branchIds.contains(custBranch);
      }).toList();
    }
    
    return reminders;
  }

  /// Get reminder detail with customer info
  Future<DmeReminder?> getReminderDetail(int reminderId) async {
    final res = await _client
        .from('dme_reminders')
        .select('*, dme_customers(name, phone, address, branch_id, salesman)')
        .eq('id', reminderId)
        .maybeSingle();
    
    return res != null ? DmeReminder.fromMap(res) : null;
  }

  /// Mark reminder as complete with optional notes.
  Future<void> completeReminder(int reminderId, {String? notes}) async {
    final map = <String, dynamic>{
      'status': 'completed',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (notes != null && notes.isNotEmpty) map['notes'] = notes;
    await _client.from('dme_reminders').update(map).eq('id', reminderId);
  }

  /// Reschedule reminder if new purchase date is after current reminder date
  Future<bool> rescheduleReminderIfNeeded(int customerId, DateTime newPurchaseDate) async {
    final existing = await _client
        .from('dme_reminders')
        .select('reminder_date, status')
        .eq('customer_id', customerId)
        .maybeSingle();
    
    if (existing == null) {
      return false;
    }

    final currentReminderDate = DateTime.parse(existing['reminder_date'] as String);
    if (newPurchaseDate.isAfter(currentReminderDate)) {
      final newReminderDate = newPurchaseDate.add(Duration(days: 30));
      await _client.from('dme_reminders').update({
        'reminder_date': newReminderDate.toIso8601String().split('T')[0],
        'last_purchase_date': newPurchaseDate.toIso8601String().split('T')[0],
        'status': 'pending',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('customer_id', customerId);
      return true;
    }
    
    return false;
  }
}
