import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../dme_config.dart';
import '../models/dme_user.dart';
import '../models/dme_customer.dart';
import '../models/dme_sale.dart';
import '../models/dme_reminder.dart';
import '../models/dme_complaint.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../../Misc/firebase_storage_helper.dart';

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

  // ── Branch cache (avoids repeated DB hits across screens) ────
  List<Map<String, dynamic>>? _branchesCache;
  DateTime? _branchesCacheTime;
  static const _branchesCacheTtl = Duration(minutes: 5);

  bool get _branchesCacheValid =>
      _branchesCache != null &&
      _branchesCacheTime != null &&
      DateTime.now().difference(_branchesCacheTime!) < _branchesCacheTtl;

  /// Invalidates the branch cache (call after any branch write).
  void invalidateBranchCache() {
    _branchesCache = null;
    _branchesCacheTime = null;
  }

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
      final errorString = e.toString().toLowerCase();
      if (errorString.contains('host lookup') ||
          errorString.contains('socket') ||
          errorString.contains('no address associated') ||
          errorString.contains('failed to connect') ||
          errorString.contains('network')) {
        return {
          'status': 'network_error',
          'message': 'Cannot reach Supabase server',
          'error': e.toString(),
          'hint': 'Check internet connection. Supabase URL: $supabaseUrl',
        };
      }
      return {
        'status': 'error',
        'message': e.toString(),
        'hint': 'Verify Supabase URL and anon key in lib/DME/dme_config.dart',
      };
    }
  }

  Future<DmeUser?> getCurrentUser(String firebaseUid) async {
    await ensureInitialized();
    if (_currentUser != null && _currentUser!.firebaseUid == firebaseUid) {
      return _currentUser;
    }
    try {
      final res = await _client
          .from('dme_users')
          .select()
          .eq('firebase_uid', firebaseUid)
          .maybeSingle();
      if (res == null) return null;

      final branches = await getUserBranchNames(res['id'] as String);
      _currentUser = DmeUser.fromMap(res, branches: branches);
      return _currentUser;
    } catch (e) {
      debugPrint('Network error getting current user: $e');
      // Return cached user if available, otherwise null
      return _currentUser;
    }
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
    try {
      await _client.from('dme_branches').upsert(
            kAppBranches.map((name) => {'name': name}).toList(),
            onConflict: 'name',
          );
      _branchesSynced = true;
    } catch (e) {
      debugPrint('Network error syncing app branches: $e');
      // Log but don't rethrow - allow app to continue with cached branches
      // The upsert failure is not critical to app functionality
    }
  }

  Future<List<Map<String, dynamic>>> getBranches() async {
    await ensureInitialized();
    if (_branchesCacheValid) return _branchesCache!;
    try {
      await _syncAppBranches();
      final res = await _client
          .from('dme_branches')
          .select()
          .order('name', ascending: true);
      _branchesCache = List<Map<String, dynamic>>.from(res);
      _branchesCacheTime = DateTime.now();
      return _branchesCache!;
    } catch (e) {
      debugPrint('Network error fetching branches: $e');
      // Return stale cache if available, else empty
      return _branchesCache ?? [];
    }
  }

  /// Get branch name by ID — uses branch cache to avoid extra DB round-trips.
  Future<String?> getBranchNameById(int branchId) async {
    final branches = await getBranches();
    final match = branches.where((b) => b['id'] == branchId).firstOrNull;
    return match?['name'] as String?;
  }

  /// Get branch ID by name — uses branch cache to avoid extra DB round-trips.
  Future<int?> getBranchIdByNameCached(String branchName) async {
    final branches = await getBranches();
    final match =
        branches.where((b) => b['name'] == branchName).firstOrNull;
    return match?['id'] as int?;
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
    try {
      final res = await _client
          .from('dme_user_branches')
          .select('branch_id, dme_branches(name)')
          .eq('user_id', dmeUserId);
      return List<Map<String, dynamic>>.from(res)
          .map((e) => (e['dme_branches'] as Map)['name'] as String)
          .toList();
    } catch (e) {
      debugPrint('Network error fetching user branches for $dmeUserId: $e');
      // Return empty list on network error - allow graceful degradation
      return [];
    }
  }

  Future<List<int>> getUserBranchIds(String dmeUserId) async {
    await ensureInitialized();
    try {
      final res = await _client
          .from('dme_user_branches')
          .select('branch_id')
          .eq('user_id', dmeUserId);
      return List<Map<String, dynamic>>.from(res)
          .map((e) => e['branch_id'] as int)
          .toList();
    } catch (e) {
      debugPrint('Network error fetching user branch IDs for $dmeUserId: $e');
      // Return empty list on network error
      return [];
    }
  }

  // ── DME Users (admin) ────────────────────────────────────────
  Future<List<DmeUser>> getAllDmeUsers() async {
    await ensureInitialized();
    try {
      // Single query: fetch all users + their branch names via join (avoids N+1).
      final res = await _client
          .from('dme_users')
          .select('*, dme_user_branches(branch_id, dme_branches(name))')
          .order('username');

      return List<Map<String, dynamic>>.from(res).map((row) {
        final branchRows =
            row['dme_user_branches'] as List<dynamic>? ?? [];
        final branches = branchRows
            .map((b) =>
                ((b as Map)['dme_branches'] as Map?)?['name'] as String?)
            .whereType<String>()
            .toList();
        return DmeUser.fromMap(row, branches: branches);
      }).toList();
    } catch (e) {
      debugPrint('Network error fetching all DME users: $e');
      return [];
    }
  }

  Future<DmeUser> createDmeUser({
    required String firebaseUid,
    required String email,
    required String username,
    required String role,
    required List<int> branchIds,
  }) async {
    await ensureInitialized();
    try {
      final row = await _client
          .from('dme_users')
          .insert({
            'firebase_uid': firebaseUid,
            'email': email,
            'username': username,
            'role': role,
          })
          .select()
          .single();

      if (branchIds.isNotEmpty) {
        await _client.from('dme_user_branches').insert(
              branchIds
                  .map((bid) => {'user_id': row['id'], 'branch_id': bid})
                  .toList(),
            );
      }
      final branches = await getUserBranchNames(row['id'] as String);
      return DmeUser.fromMap(row, branches: branches);
    } catch (e) {
      debugPrint('Network error creating DME user: $e');
      rethrow; // Let caller handle critical creation failures
    }
  }

  Future<void> updateDmeUserRole(String userId, String role) async {
    await ensureInitialized();
    try {
      await _client.from('dme_users').update({'role': role}).eq('id', userId);
    } catch (e) {
      debugPrint('Network error updating user role: $e');
      rethrow; // Let caller handle critical update failures
    }
  }

  Future<void> setUserBranches(String userId, List<int> branchIds) async {
    await ensureInitialized();
    try {
      await _client.from('dme_user_branches').delete().eq('user_id', userId);
      if (branchIds.isNotEmpty) {
        await _client.from('dme_user_branches').insert(
              branchIds
                  .map((bid) => {'user_id': userId, 'branch_id': bid})
                  .toList(),
            );
      }
      _currentUser = null; // invalidate cache
    } catch (e) {
      debugPrint('Network error setting user branches: $e');
      rethrow; // Let caller handle critical update failures
    }
  }

  Future<void> deleteDmeUser(String userId) async {
    await ensureInitialized();
    try {
      await _client.from('dme_users').delete().eq('id', userId);
    } catch (e) {
      debugPrint('Network error deleting DME user: $e');
      rethrow; // Let caller handle critical delete failures
    }
  }

  /// Get all users assigned to a specific branch
  Future<List<DmeUser>> getUsersByBranch(String branchName) async {
    await ensureInitialized();
    try {
      // Use cached branch lookup instead of a separate DB query
      final branchId = await getBranchIdByNameCached(branchName);
      if (branchId == null) return [];

      // Single query: users + their branches via join (no N+1)
      final res = await _client
          .from('dme_user_branches')
          .select('dme_users(*, dme_user_branches(branch_id, dme_branches(name)))')
          .eq('branch_id', branchId);

      return List<Map<String, dynamic>>.from(res).map((row) {
        final userData = row['dme_users'] as Map<String, dynamic>;
        final branchRows =
            userData['dme_user_branches'] as List<dynamic>? ?? [];
        final branches = branchRows
            .map((b) =>
                ((b as Map)['dme_branches'] as Map?)?['name'] as String?)
            .whereType<String>()
            .toList();
        return DmeUser.fromMap(userData, branches: branches);
      }).toList();
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

  /// Syncs Firebase users with role='dme_admin' to Supabase dme_users table.
  /// Only creates new entries in Supabase for admins not already present.
  /// Returns a map with sync results.
  Future<Map<String, dynamic>> syncDmeAdminUsers() async {
    await ensureInitialized();

    try {
      // Fetch all Firebase users with role='dme_admin'
      final firebaseSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'dme_admin')
          .get();

      int addedCount = 0;
      int skippedCount = 0;

      for (final doc in firebaseSnapshot.docs) {
        final firebaseUid = doc.id;
        final email = doc['email'] as String? ?? '';
        final username = doc['username'] as String? ?? '';

        // Check if this admin already exists in Supabase dme_users
        final existing = await _client
            .from('dme_users')
            .select('id')
            .eq('firebase_uid', firebaseUid)
            .maybeSingle();

        if (existing == null) {
          // Admin doesn't exist in Supabase, add them with empty branch list
          try {
            await _client.from('dme_users').insert({
              'firebase_uid': firebaseUid,
              'email': email,
              'username': username,
              'role': 'dme_admin',
            });
            addedCount++;
          } catch (e) {
            debugPrint('Error adding admin $username: $e');
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
        'message': 'Synced $addedCount new DME admin users from Firebase',
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
        'message': 'Error syncing DME admin users: $e',
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
    try {
      await ensureInitialized();
      
      // Retry logic with exponential backoff for connection issues
      const maxRetries = 3;
      final delays = [1000, 2000, 4000]; // milliseconds
      
      for (int attempt = 0; attempt < maxRetries; attempt++) {
        try {
          var query = _client.from('dme_customers').select(
              '*, dme_branches(name), dme_categories(id, name), dme_customer_types(id, name)');

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
              // Split large ID lists to avoid URL overflow and connection issues
              // Supabase has URL length limits; keep individual OR clauses reasonable
              if (purchasedCustomerIds.length > 200 || branchIds.length > 200) {
                // For very large ID lists, use batch approach instead of single OR clause
                query = query.inFilter('branch_id', branchIds);
              } else {
                // Include customers whose primary branch matches OR who have a purchase from these branches
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

          // Filter by FK columns only (TEXT columns removed from DB)
          if (categoryId != null) {
            query = query.eq('category_id', categoryId);
          }

          if (customerTypeId != null) {
            query = query.eq('customer_type_id', customerTypeId);
          }

          // Date range filter - get customers with ANY purchase in the date range from dme_customer_purchases
          if (lastPurchaseDateFrom != null || lastPurchaseDateTo != null) {
            var purchaseQuery =
                _client.from('dme_customer_purchases').select('customer_id');

            if (lastPurchaseDateFrom != null) {
              purchaseQuery = purchaseQuery.gte('purchase_date',
                  lastPurchaseDateFrom.toIso8601String().split('T')[0]);
            }
            if (lastPurchaseDateTo != null) {
              purchaseQuery = purchaseQuery.lte('purchase_date',
                  lastPurchaseDateTo.toIso8601String().split('T')[0]);
            }

            // Paginate through all purchase records to avoid hitting the 1000 row limit
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
              return []; // No purchases in the date range
            }

            // For large ID sets, batch them to avoid URL overflow
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
                    '*, dme_branches(name), dme_categories(id, name), dme_customer_types(id, name)');
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

          // Salesman filter
          if (salesman != null && salesman.isNotEmpty) {
            query = query.eq('salesman', salesman);
          }

          final res = await query
              .order('name', ascending: true)
              .range(offset, offset + limit - 1);
          return (res as List).map((e) => DmeCustomer.fromMap(e)).toList();
        } catch (e) {
          final errorStr = e.toString();
          // Check for transient network errors (connection reset, timeout, etc.)
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
      // Log to Crashlytics but don't crash the app
      FirebaseCrashlytics.instance.recordError(e, StackTrace.current);
      return [];
    }
  }

  /// Find customer by ID
  Future<DmeCustomer?> getCustomerById(int customerId) async {
    await ensureInitialized();
    final res = await _client
        .from('dme_customers')
        .select('*, dme_branches(name)')
        .eq('id', customerId)
        .maybeSingle();
    return res != null ? DmeCustomer.fromMap(res) : null;
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

  /// Update customer details by ID
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
    await ensureInitialized();
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

  /// Append an alternate name to a customer's purchased_for field.
  /// Skips if the name is already present (case-insensitive).
  Future<void> appendPurchasedFor(int customerId, String alternateName) async {
    await ensureInitialized();
    try {
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
    } catch (e) {
      debugPrint('Network error appending purchased_for for customer $customerId: $e');
      rethrow;
    }
  }

  Future<void> upsertCustomersBatch(List<Map<String, dynamic>> rows,
      {void Function(int done, int total)? onProgress}) async {
    await ensureInitialized();
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
    await ensureInitialized();
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

  // ── Sales ────────────────────────────────────────────────────
  Future<int> insertSale(DmeSale sale) async {
    await ensureInitialized();
    try {
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
    } catch (e) {
      debugPrint('Network error inserting sale: $e');
      rethrow;
    }
  }

  Future<List<DmeSale>> getSalesByDate(DateTime date,
      {List<int>? branchIds}) async {
    await ensureInitialized();
    var query = _client
        .from('dme_sales')
        .select('*, dme_customers(name, phone, branch_id), dme_sale_items(*)');

    query = query.eq('date', date.toIso8601String().split('T')[0]);

    // Paginate through all sales for the date to avoid hitting the 1000 row limit
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
  Future<List<Map<String, dynamic>>> getCustomerBranchesWithPurchases(
      int customerId) async {
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
          .select(
              'purchase_for_branch_id, purchase_for_branch_name, purchase_date, purchase_details')
          .eq('customer_id', customerId)
          .order('purchase_date', ascending: false);

      for (final purchase in purchases) {
        final branchId = purchase['purchase_for_branch_id'] as int;
        final branchName = purchase['purchase_for_branch_name'] as String?;
        final purchaseDate = purchase['purchase_date'] as String?;
        final details = purchase['purchase_details'] as Map?;
        final salesman =
            (details != null ? details['salesman'] : null) as String?;

        final key = branchId.toString();
        if (branches.containsKey(key)) {
          // Update existing branch with purchase info
          branches[key]!['purchase_count'] =
              (branches[key]!['purchase_count'] as int) + 1;
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

    // Calculate reminder date as 28 days after purchase date
    final reminderDate = purchaseDate.add(const Duration(days: 28));
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

        if (lastPurchaseDate == null ||
            purchaseDate.isAfter(lastPurchaseDate)) {
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
    List<String>? statuses,
    DateTime? from,
    DateTime? to,
    DateTime? updatedFrom,
    DateTime? updatedTo,
  }) async {
    await ensureInitialized();
    var query = _client
        .from('dme_reminders')
        .select('*, dme_customers(name, phone, address, branch_id, salesman)');

    if (statuses != null && statuses.isNotEmpty) {
      query = query.inFilter('status', statuses);
    } else if (status != null) {
      query = query.eq('status', status);
    }
    if (from != null) {
      query = query.gte('reminder_date', from.toIso8601String().split('T')[0]);
    }
    if (to != null) {
      query = query.lte('reminder_date', to.toIso8601String().split('T')[0]);
    }

    // Filter by branch directly on purchased_for_branch_id (DB-level, avoids full table scan)
    if (branchIds != null && branchIds.isNotEmpty) {
      query = query.inFilter('purchased_for_branch_id', branchIds);
    }

    // Cap at 500 rows per request to protect Supabase RAM
    const rowLimit = 500;
    final res = await query
        .order('reminder_date', ascending: true)
        .limit(rowLimit);

    return (res as List)
        .map((row) => DmeReminder.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  Future<void> updateReminderStatus(int id, String status,
      {String? notes}) async {
    await ensureInitialized();
    final map = <String, dynamic>{'status': status};
    if (notes != null) map['notes'] = notes;
    await _client.from('dme_reminders').update(map).eq('id', id);
  }

  Future<void> deleteReminder(int id) async {
    await ensureInitialized();
    await _client.from('dme_reminders').delete().eq('id', id);
  }

  Future<DmeReminder?> getReminderById(int id) async {
    await ensureInitialized();
    final res = await _client
        .from('dme_reminders')
        .select('*, dme_customers(name, phone, address, branch_id, salesman)')
        .eq('id', id)
        .maybeSingle();
    if (res == null) return null;
    return DmeReminder.fromMap(res as Map<String, dynamic>);
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

  /// Get call logs for a customer (returns reminders with 'completed' status)
  Future<List<Map<String, dynamic>>> getCallLogs(int customerId) async {
    await ensureInitialized();
    final res = await _client
        .from('dme_reminders')
        .select()
        .eq('customer_id', customerId)
        .eq('status', 'completed')
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
      final branchName = ((row['dme_customers'] as Map?)?['dme_branches']
              as Map?)?['name'] as String? ??
          'Unknown';
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

    final fromStr = from.toIso8601String().split('T')[0];
    final toStr = to.toIso8601String().split('T')[0];
    const batchSize = 1000;
    int batchOffset = 0;

    // customer_id -> number of purchases in period
    final Map<int, int> visitCounts = {};

    // Paginate through ALL purchases — Supabase defaults to 1000 rows per request
    while (true) {
      var batchQuery = _client
          .from('dme_customer_purchases')
          .select('customer_id')
          .gte('purchase_date', fromStr)
          .lte('purchase_date', toStr);

      if (branchIds != null && branchIds.isNotEmpty) {
        batchQuery = batchQuery.inFilter('purchase_for_branch_id', branchIds);
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

    // Returning = visited 2+ times in the period
    final int returningCustomers =
        visitCounts.values.where((count) => count >= 2).length;
    // New = visited only once in the period
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
      throw Exception(
          'Branch not found: $branchName. Please sync branches first.');
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
        if (customer.customerType != null &&
            customer.customerType!.isNotEmpty) {
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
          final existingName =
              (existingRes['name'] as String? ?? '').toLowerCase().trim();
          if (existingName != customer.name.toLowerCase().trim() &&
              customer.name.isNotEmpty) {
            await appendPurchasedFor(customerId, customer.name);
          }

          // Update last_purchase_date, category_id, customer_type_id
          final updateMap = {
            'last_purchase_date':
                customer.lastPurchaseDate?.toIso8601String().split('T')[0],
            'category_id': categoryId,
            'customer_type_id': typeId,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          };

          await _client
              .from('dme_customers')
              .update(updateMap)
              .eq('id', customerId);
          linkedToExisting++;
        } else {
          // New customer
          final custMap = customer.toInsertMap();
          custMap['branch_id'] = branchId;
          custMap['category_id'] = categoryId; // Add FK ID
          custMap['customer_type_id'] = typeId; // Add FK ID
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
          final reminderDate =
              customer.lastPurchaseDate!.add(const Duration(days: 28));
          await _client.from('dme_reminders').upsert({
            'customer_id': customerId,
            'reminder_date': reminderDate.toIso8601String().split('T')[0],
            'last_purchase_date':
                customer.lastPurchaseDate!.toIso8601String().split('T')[0],
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

    if (branchIds.isNotEmpty) {
      query = query.inFilter('purchased_for_branch_id', branchIds);
    }

    final res = await query
        .order('reminder_date', ascending: true)
        .limit(500);
    return (res as List).map((e) => DmeReminder.fromMap(e)).toList();
  }

  /// Get pending reminders from previous days for given branches
  Future<List<DmeReminder>> getPendingFromPreviousDays(
      List<int> branchIds) async {
    final today = DateTime.now();
    final todayStr = today.toIso8601String().split('T')[0];

    var query = _client
        .from('dme_reminders')
        .select('*, dme_customers(name, phone, address, branch_id, salesman)')
        .lt('reminder_date', todayStr)
        .eq('status', 'pending');

    if (branchIds.isNotEmpty) {
      query = query.inFilter('purchased_for_branch_id', branchIds);
    }

    final res = await query
        .order('reminder_date', ascending: true)
        .limit(500);
    return (res as List).map((e) => DmeReminder.fromMap(e)).toList();
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
  Future<bool> rescheduleReminderIfNeeded(
      int customerId, DateTime newPurchaseDate) async {
    final existing = await _client
        .from('dme_reminders')
        .select('reminder_date, status')
        .eq('customer_id', customerId)
        .maybeSingle();

    if (existing == null) {
      return false;
    }

    final currentReminderDate =
        DateTime.parse(existing['reminder_date'] as String);
    if (newPurchaseDate.isAfter(currentReminderDate)) {
      final newReminderDate = newPurchaseDate.add(const Duration(days: 28));
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

  /// Upload WhatsApp proof screenshot to Supabase storage and save reference
  Future<String?> uploadWhatsAppProof({
    required int reminderId,
    required int customerId,
    required Uint8List compressedImageBytes,
    required String remarks,
  }) async {
    await ensureInitialized();
    try {
      // Generate unique filename
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filename = 'whatsapp_proof_${customerId}_$timestamp.jpg';
      final path = 'dme_reminders/$reminderId/$filename';

      // Try Supabase buckets first, then Firebase Storage fallback if bucket is missing.
      final uploadResult = await _uploadProofWithFallback(
        path: path,
        bytes: compressedImageBytes,
      );

      // Save proof reference to database
      await _insertWhatsAppProofRecord(
        reminderId: reminderId,
        customerId: customerId,
        uploadPath: uploadResult.path,
        uploadUrl: uploadResult.publicUrl,
        remarks: remarks,
      );

      return uploadResult.path;
    } catch (e) {
      debugPrint('Error uploading WhatsApp proof: $e');
      rethrow;
    }
  }

  Future<_ProofUploadResult> _uploadProofWithFallback({
    required String path,
    required Uint8List bytes,
  }) async {
    const supabaseBuckets = ['dme-proofs', 'dme_proofs', 'proofs'];
    Object? lastBucketError;

    for (final bucket in supabaseBuckets) {
      try {
        final uploadedPath = await _client.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(contentType: 'image/jpeg'),
        );
        if (uploadedPath.isEmpty) continue;
        return _ProofUploadResult(
          path: uploadedPath,
          publicUrl: _client.storage.from(bucket).getPublicUrl(path),
        );
      } catch (e) {
        final message = e.toString().toLowerCase();
        final isBucketMissing =
            message.contains('bucket not found') || message.contains('bucket_not_found');
        if (!isBucketMissing) rethrow;
        lastBucketError = e;
      }
    }

    // Final fallback: Firebase Storage, so upload can still succeed even if
    // Supabase storage bucket is not provisioned.
    for (final storage in FirebaseStorageHelper.storageCandidates()) {
      try {
        final ref = storage.ref().child('dme_whatsapp_proofs').child(path);
        await ref.putData(
          bytes,
          SettableMetadata(contentType: 'image/jpeg'),
        );
        final url = await ref.getDownloadURL();
        return _ProofUploadResult(
          path: ref.fullPath,
          publicUrl: url,
        );
      } catch (e) {
        lastBucketError = e;
      }
    }

    throw Exception(
      'Proof upload failed. Supabase proof bucket is missing and Firebase upload fallback also failed. '
      'Original error: ${lastBucketError ?? 'unknown'}',
    );
  }

  Future<void> _insertWhatsAppProofRecord({
    required int reminderId,
    required int customerId,
    required String uploadPath,
    required String uploadUrl,
    required String remarks,
  }) async {
    final uploadedAt = DateTime.now().toUtc().toIso8601String();

    final base = <String, dynamic>{
      'reminder_id': reminderId,
      'customer_id': customerId,
    };

    final metaVariants = <Map<String, dynamic>>[
      {'remarks': remarks, 'uploaded_at': uploadedAt},
      {'notes': remarks, 'uploaded_at': uploadedAt},
      {'remarks': remarks},
      {'notes': remarks},
      {'uploaded_at': uploadedAt},
      {},
    ];

    final locationVariants = <Map<String, dynamic>>[
      {'image_path': uploadPath, 'image_url': uploadUrl},
      {'proof_path': uploadPath, 'proof_url': uploadUrl},
      {'file_path': uploadPath, 'file_url': uploadUrl},
      {'path': uploadPath, 'url': uploadUrl},
      {'image_url': uploadUrl},
      {'proof_url': uploadUrl},
      {'file_url': uploadUrl},
      {'url': uploadUrl},
      {'image_path': uploadPath},
      {'proof_path': uploadPath},
      {'file_path': uploadPath},
      {'path': uploadPath},
      {},
    ];

    Object? lastError;
    for (final meta in metaVariants) {
      for (final location in locationVariants) {
        final payload = <String, dynamic>{
          ...base,
          ...meta,
          ...location,
        };
        try {
          await _client.from('dme_whatsapp_proofs').insert(payload);
          return;
        } catch (e) {
          lastError = e;
          if (_isSchemaMismatchError(e) || _isNotNullConstraintError(e)) {
            continue;
          }
          rethrow;
        }
      }
    }

    throw Exception(
      'Upload succeeded but saving proof record failed due to table schema mismatch in dme_whatsapp_proofs. '
      'Last error: ${lastError ?? 'unknown'}',
    );
  }

  bool _isSchemaMismatchError(Object error) {
    final msg = error.toString().toLowerCase();
    return msg.contains('pgrst204') ||
        (msg.contains('could not find') && msg.contains('column')) ||
        msg.contains('column of') && msg.contains('in the schema cache');
  }

  bool _isNotNullConstraintError(Object error) {
    final msg = error.toString().toLowerCase();
    return msg.contains("null value in column") ||
        msg.contains('violates not-null constraint') ||
        msg.contains("code: 23502");
  }

  /// Update reminder status to waiting for proof
  Future<void> setReminderWaitingForProof(int reminderId) async {
    // No status change needed — proof is tracked via dme_whatsapp_proofs table.
    // 'waiting_for_proof' is not an allowed value in dme_reminders_status_check.
  }

  Future<List<Map<String, dynamic>>> getAllBranches() => getBranches();
}

class _ProofUploadResult {
  final String path;
  final String publicUrl;

  const _ProofUploadResult({required this.path, required this.publicUrl});
}
