import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../dme_config.dart';
import '../models/dme_user.dart';
import '../models/dme_customer.dart';
import '../models/dme_sale.dart';
import '../models/dme_reminder.dart';
import '../models/dme_complaint.dart';

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
    await ensureInitialized();
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

  /// Get branch name by ID
  Future<String?> getBranchNameById(int branchId) async {
    await ensureInitialized();
    try {
      final res = await _client
          .from('dme_branches')
          .select('name')
          .eq('id', branchId)
          .maybeSingle();
      return res != null ? res['name'] as String? : null;
    } catch (e) {
      debugPrint('Error getting branch name for ID $branchId: $e');
      return null;
    }
  }

  /// Get customer's default branch name
  Future<String?> getCustomerBranchName(int customerId) async {
    await ensureInitialized();
    try {
      final res = await _client
          .from('dme_customers')
          .select('branch_id, dme_branches(name)')
          .eq('id', customerId)
          .maybeSingle();
      
      if (res != null && res['dme_branches'] is Map) {
        return (res['dme_branches'] as Map)['name'] as String?;
      }
      return null;
    } catch (e) {
      debugPrint('Error getting customer branch name for ID $customerId: $e');
      return null;
    }
  }

  Future<List<String>> getUserBranchNames(String dmeUserId) async {
    await ensureInitialized();
    final res = await _client
        .from('dme_user_branches')
        .select('branch_id, dme_branches(name)')
        .eq('user_id', dmeUserId);
    return List<Map<String, dynamic>>.from(res)
        .map((e) => (e['dme_branches'] as Map)['name'] as String)
        .toList();
  }

  Future<List<int>> getUserBranchIds(String dmeUserId) async {
    await ensureInitialized();
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
    await ensureInitialized();
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
    await ensureInitialized();
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
    await ensureInitialized();
    await _client.from('dme_users').update({'role': role}).eq('id', userId);
  }

  Future<void> setUserBranches(String userId, List<int> branchIds) async {
    await ensureInitialized();
    await _client.from('dme_user_branches').delete().eq('user_id', userId);
    if (branchIds.isNotEmpty) {
      await _client.from('dme_user_branches').insert(
        branchIds.map((bid) => {'user_id': userId, 'branch_id': bid}).toList(),
      );
    }
    _currentUser = null; // invalidate cache
  }

  Future<void> deleteDmeUser(String userId) async {
    await ensureInitialized();
    await _client.from('dme_users').delete().eq('id', userId);
  }

  /// Get all users assigned to a specific branch
  Future<List<DmeUser>> getUsersByBranch(String branchName) async {
    await ensureInitialized();
    try {
      // First get the branch ID from branch name
      final branchRes = await _client
          .from('dme_branches')
          .select('id')
          .eq('name', branchName)
          .maybeSingle();

      if (branchRes == null) {
        return [];
      }

      final branchId = branchRes['id'] as int;

      // Now get all users assigned to this branch
      final res = await _client
          .from('dme_user_branches')
          .select('dme_users(*)')
          .eq('branch_id', branchId);

      final users = <DmeUser>[];
      for (final row in res) {
        final userData = row['dme_users'] as Map<String, dynamic>;
        final branches = await getUserBranchNames(userData['id'] as String);
        users.add(DmeUser.fromMap(userData, branches: branches));
      }
      return users;
    } catch (e) {
      debugPrint('Error getting users for branch: $e');
      return [];
    }
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



  // ── Categories & Types (Lookup) ──────────────────────────────
  /// Looks up category ID by name. Returns null if not found.
  Future<int?> getCategoryIdByName(String name) async {
    await ensureInitialized();
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
    await ensureInitialized();
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
    DateTime? lastPurchaseDateFrom,
    DateTime? lastPurchaseDateTo,
    String? salesman,
    int limit = 50,
    int offset = 0,
  }) async {
    await ensureInitialized();
    var query = _client
        .from('dme_customers')
        .select('*, dme_branches(name), dme_categories(id, name), dme_customer_types(id, name)');

    if (branchIds != null && branchIds.isNotEmpty) {
      // Get customer IDs that have a purchase record for any of these branches
      final purchaseRows = await _client
          .from('dme_customer_purchases')
          .select('customer_id')
          .inFilter('purchase_for_branch_id', branchIds);
      final purchasedCustomerIds = (purchaseRows as List)
          .map((e) => e['customer_id'] as int)
          .toSet()
          .toList();

      if (purchasedCustomerIds.isNotEmpty) {
        // Include customers whose primary branch matches OR who have a purchase from these branches
        query = query.or('branch_id.in.(${branchIds.join(',')}),id.in.(${purchasedCustomerIds.join(',')})');
      } else {
        query = query.inFilter('branch_id', branchIds);
      }
    }
    if (search != null && search.isNotEmpty) {
      query = query.or('name.ilike.%$search%,phone.ilike.%$search%');
    }
    
    // Filter by FK columns only (TEXT columns removed from DB)
    if (categoryId != null) {
      query = query.eq('category_id', categoryId);
    }
    
    if (customerTypeId != null) {
      query = query.eq('customer_type_id', customerTypeId);
    }

    // Date range filter for last purchase date
    if (lastPurchaseDateFrom != null) {
      query = query.gte('last_purchase_date', lastPurchaseDateFrom.toIso8601String().split('T')[0]);
    }
    if (lastPurchaseDateTo != null) {
      query = query.lte('last_purchase_date', lastPurchaseDateTo.toIso8601String().split('T')[0]);
    }

    // Salesman filter
    if (salesman != null && salesman.isNotEmpty) {
      query = query.eq('salesman', salesman);
    }

    final res = await query
        .order('name', ascending: true)
        .range(offset, offset + limit - 1);
    return (res as List).map((e) => DmeCustomer.fromMap(e)).toList();
  }

  /// Find customer by phone (phone is now the sole unique key).
  Future<DmeCustomer?> findCustomerByPhone(String phone) async {
    await ensureInitialized();
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
    await ensureInitialized();
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
    await ensureInitialized();
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
    await ensureInitialized();
    const batchSize = 500;
    for (var i = 0; i < rows.length; i += batchSize) {
      final batch = rows.sublist(
          i, i + batchSize > rows.length ? rows.length : i + batchSize);
      await _client.from('dme_customers').upsert(batch, onConflict: 'phone');
      onProgress?.call(i + batch.length, rows.length);
    }
  }

  Future<void> updateLastPurchaseDate(int customerId, DateTime date) async {
    await ensureInitialized();
    await _client.from('dme_customers').update({
      'last_purchase_date': date.toIso8601String().split('T')[0],
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', customerId);
  }

  // ── Sales ────────────────────────────────────────────────────
  Future<int> insertSale(DmeSale sale) async {
    await ensureInitialized();
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
    await ensureInitialized();
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
    await ensureInitialized();
    final res = await _client
        .from('dme_sales')
        .select('*, dme_sale_items(*)')
        .eq('customer_id', customerId)
        .order('date', ascending: false);
    return (res as List).map((e) => DmeSale.fromMap(e)).toList();
  }

  /// Get all branches a customer has purchases from with salesman and count info
  /// Returns list of {branch_id, branch_name, salesman, purchase_count, last_purchase_date}
  Future<List<Map<String, dynamic>>> getCustomerBranchesWithPurchases(int customerId) async {
    try {
      await ensureInitialized();
      
      // Get primary branch
      final customer = await _client
          .from('dme_customers')
          .select('id, branch_id, salesman, dme_branches(id, name)')
          .eq('id', customerId)
          .maybeSingle();
      
      if (customer == null) return [];
      
      final branches = <String, Map<String, dynamic>>{};
      
      // Add primary branch
      final primaryBranchId = customer['branch_id'] as int?;
      if (primaryBranchId != null && customer['dme_branches'] is Map) {
        final branchData = customer['dme_branches'] as Map;
        branches[primaryBranchId.toString()] = {
          'branch_id': primaryBranchId,
          'branch_name': branchData['name'] ?? 'Unknown',
          'salesman': customer['salesman'] ?? 'Not Assigned',
          'purchase_count': 0,
          'last_purchase_date': null,
          'is_primary': true,
        };
      }
      
      // Get purchases from other branches
      final purchases = await _client
          .from('dme_customer_purchases')
          .select('purchase_for_branch_id, purchase_for_branch_name, purchase_date, purchase_details')
          .eq('customer_id', customerId)
          .order('purchase_date', ascending: false);
      
      for (final purchase in purchases) {
        final branchId = purchase['purchase_for_branch_id'] as int;
        final branchName = purchase['purchase_for_branch_name'] as String?;
        final purchaseDate = purchase['purchase_date'] as String?;
        final details = purchase['purchase_details'] as Map?;
        final salesman = (details != null ? details['salesman'] : null) as String?;
        
        final key = branchId.toString();
        if (branches.containsKey(key)) {
          // Update existing branch with purchase info
          branches[key]!['purchase_count'] = (branches[key]!['purchase_count'] as int) + 1;
          if (branches[key]!['last_purchase_date'] == null) {
            branches[key]!['last_purchase_date'] = purchaseDate;
          }
        } else {
          // Add new branch
          branches[key] = {
            'branch_id': branchId,
            'branch_name': branchName ?? 'Unknown',
            'salesman': salesman ?? 'Not Assigned',
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

  // ── Purchase Tracking (Branch-based) ────────────────────────

  /// Record a purchase with branch information in dme_customer_purchases table.
  /// Returns true if inserted, false if already exists (ignored).
  Future<bool> recordPurchaseWithBranch({
    required int customerId,
    required DateTime purchaseDate,
    required int purchaseForBranchId,
    required String? purchaseForBranchName,
    Map<String, dynamic>? purchaseDetails, // items, salesman, etc.
  }) async {
    try {
      await ensureInitialized();
      final purchaseDateStr = purchaseDate.toIso8601String().split('T')[0];
      
      // Check if purchase already exists
      final existing = await _client
          .from('dme_customer_purchases')
          .select()
          .eq('customer_id', customerId)
          .eq('purchase_date', purchaseDateStr)
          .eq('purchase_for_branch_id', purchaseForBranchId)
          .maybeSingle();
      
      if (existing != null) {
        // Already exists, ignore it
        return false;
      }
      
      // Insert new record
      await _client.from('dme_customer_purchases').insert({
        'customer_id': customerId,
        'purchase_date': purchaseDateStr,
        'purchase_for_branch_id': purchaseForBranchId,
        'purchase_for_branch_name': purchaseForBranchName,
        'purchase_details': purchaseDetails,
        'created_at': DateTime.now().toIso8601String(),
      });
      return true;
    } catch (e) {
      debugPrint('Error recording purchase with branch: $e');
      rethrow;
    }
  }

  /// Get assigned DME user for a specific branch
  Future<DmeUser?> getDmeUserForBranch(int branchId) async {
    try {
      await ensureInitialized();
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
  Future<bool> upsertReminder({
    required int customerId,
    required DateTime purchaseDate,
    required int purchaseForBranchId,
    String? purchaseForBranchName,
    String? assignedTo,
    Map<String, dynamic>? purchaseDetails,
  }) async {
    await ensureInitialized();
    // First, record the purchase with branch information
    // Returns false if purchase already existed (duplicate)
    final purchaseIsNew = await recordPurchaseWithBranch(
      customerId: customerId,
      purchaseDate: purchaseDate,
      purchaseForBranchId: purchaseForBranchId,
      purchaseForBranchName: purchaseForBranchName,
      purchaseDetails: purchaseDetails,
    );
    
    // If purchase already existed, we should not process the reminder further
    // (it was already processed before)
    if (!purchaseIsNew) {
      return false;
    }

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
      return true;
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
        return true;
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
          return true;
        }
        return true;
      }
    }
  }

  Future<List<DmeReminder>> getReminders({
    List<int>? branchIds,
    String? status,
    DateTime? from,
    DateTime? to,
  }) async {
    await ensureInitialized();
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
    debugPrint('getReminders raw response: ${res.toString()}');
    
    var reminders =
        (res as List).map((e) {
          debugPrint('Mapping reminder: purchased_for_branch_id=${e['purchased_for_branch_id']}, purchased_for_branch_name=${e['purchased_for_branch_name']}');
          return DmeReminder.fromMap(e);
        }).toList();

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
    await ensureInitialized();
    final map = <String, dynamic>{'status': status};
    if (notes != null) map['notes'] = notes;
    await _client.from('dme_reminders').update(map).eq('id', id);
  }

  /// Fetch sale items for a customer on a specific purchase date.
  /// Returns empty list if no sale exists or items have been deleted.
  Future<List<DmeSaleItem>> getSaleItemsByCustomerDate(
      int customerId, DateTime date) async {
    await ensureInitialized();
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
    await ensureInitialized();
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
    await ensureInitialized();
    final res = await _client
        .from('dme_reminders')
        .select()
        .eq('customer_id', customerId)
        .eq('status', 'called')
        .order('reminder_date', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }

  // ── Dashboard stats ──────────────────────────────────────────
  Future<Map<String, int>> getDashboardCounts() async {
    // Fetch TOTAL customer count using count() to avoid 1000 row limit
    int customerCount = 0;
    
    try {
      await ensureInitialized();
      
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
    await ensureInitialized();
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
    await ensureInitialized();
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

  // ── Customer Visit Analytics ─────────────────────────────────
  /// Get customer visit analytics for a branch within a date range
  /// Returns map with total visits and new customer count
  Future<Map<String, dynamic>> getCustomerVisitAnalytics({
    required DateTime from,
    required DateTime to,
    List<int>? branchIds,
  }) async {
    await ensureInitialized();
    // Get unique customers from purchases within date range
    var purchaseQuery = _client
        .from('dme_customer_purchases')
        .select('customer_id, dme_customers(created_at, branch_id)')
        .gte('purchase_date', from.toIso8601String().split('T')[0])
        .lte('purchase_date', to.toIso8601String().split('T')[0]);

    if (branchIds != null && branchIds.isNotEmpty) {
      purchaseQuery = purchaseQuery.inFilter('purchase_for_branch_id', branchIds);
    }

    final purchases = await purchaseQuery;
    
    Set<int> visitedCustomers = {};
    int newCustomers = 0;
    
    for (final row in purchases) {
      final customerId = row['customer_id'] as int;
      visitedCustomers.add(customerId);
      
      final custData = row['dme_customers'] as Map?;
      if (custData != null) {
        final createdAt = custData['created_at'] as String?;
        if (createdAt != null) {
          final createdDate = DateTime.parse(createdAt);
          if (createdDate.isAfter(from) && createdDate.isBefore(to.add(const Duration(days: 1)))) {
            newCustomers++;
          }
        }
      }
    }

    return {
      'total_visits': visitedCustomers.length,
      'new_customers': newCustomers,
    };
  }

  // ── Customer Database Upload (with junction table) ─────────────
  /// Upload customer database from Excel with support for multiple companies per phone.
  /// Returns upload summary: {created: count, linked_to_existing: count, reminders_created: count}
  Future<Map<String, int>> uploadCustomerDatabase({
    required List<DmeCustomer> customers,
    required String branchName,
    void Function(int done, int total)? onProgress,
  }) async {
    await ensureInitialized();
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
        // Look up category and type IDs
        int? categoryId;
        int? typeId;
        if (customer.category != null && customer.category!.isNotEmpty) {
          categoryId = await getCategoryIdByName(customer.category!);
        }
        if (customer.customerType != null && customer.customerType!.isNotEmpty) {
          typeId = await getTypeIdByName(customer.customerType!);
        }
        
        // Check if phone already exists
        final existingRes = await _client
            .from('dme_customers')
            .select('id, name, purchased_for, branch_id')
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
          
          // Update last_purchase_date, category_id, customer_type_id
          final updateMap = {
            'last_purchase_date': customer.lastPurchaseDate?.toIso8601String().split('T')[0],
            'category_id': categoryId,
            'customer_type_id': typeId,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          };
          
          await _client.from('dme_customers').update(updateMap).eq('id', customerId);
          linkedToExisting++;
        } else {
          // New customer
          final custMap = customer.toInsertMap();
          custMap['branch_id'] = branchId;
          custMap['category_id'] = categoryId;      // Add FK ID
          custMap['customer_type_id'] = typeId;     // Add FK ID
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
    
    debugPrint('getReminderDetail result: $res');
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
