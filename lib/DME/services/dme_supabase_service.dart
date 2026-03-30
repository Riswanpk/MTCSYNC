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
            print('Error adding user $username: $e');
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

  // ── Customers ────────────────────────────────────────────────
  Future<List<DmeCustomer>> getCustomers({
    List<int>? branchIds,
    String? search,
    String? category,
    String? customerType,
    int limit = 50,
    int offset = 0,
  }) async {
    var query = _client
        .from('dme_customers')
        .select('*, dme_branches(name)');

    if (branchIds != null && branchIds.isNotEmpty) {
      query = query.inFilter('branch_id', branchIds);
    }
    if (search != null && search.isNotEmpty) {
      query = query.or('name.ilike.%$search%,phone.ilike.%$search%');
    }
    if (category != null) query = query.eq('category', category);
    if (customerType != null) query = query.eq('customer_type', customerType);

    final res = await query
        .order('name', ascending: true)
        .range(offset, offset + limit - 1);
    return (res as List).map((e) => DmeCustomer.fromMap(e)).toList();
  }

  /// Find customer by phone. If [company] is also provided, first tries an
  /// exact (phone + company) match; falls back to phone-only for backward
  /// compatibility with records that have no company set.
  Future<DmeCustomer?> findCustomerByPhone(String phone, {String? company}) async {
    final normalized = DmeCustomer.normalizePhone(phone);
    if (normalized.isEmpty) return null;

    // Try exact match on (phone, company) when company is available
    if (company != null && company.isNotEmpty) {
      final exact = await _client
          .from('dme_customers')
          .select('*, dme_branches(name)')
          .eq('phone', normalized)
          .eq('company', company)
          .maybeSingle();
      if (exact != null) return DmeCustomer.fromMap(exact);
    }

    // Fallback: any record with this phone
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
    // Upsert on (phone, company) composite key — allows one person to have
    // multiple company entries while deduplicating exact (phone+company) pairs.
    final res = await _client
        .from('dme_customers')
        .upsert(map, onConflict: 'phone,company')
        .select('*, dme_branches(name)')
        .single();
    return DmeCustomer.fromMap(res);
  }

  /// Plain INSERT — creates a new customer row even if the same phone already
  /// exists (used when a user chooses "Add as separate company" for a conflict).
  Future<DmeCustomer> insertCustomer(DmeCustomer customer) async {
    final map = customer.toInsertMap();
    map['updated_at'] = DateTime.now().toUtc().toIso8601String();
    final res = await _client
        .from('dme_customers')
        .insert(map)
        .select('*, dme_branches(name)')
        .single();
    return DmeCustomer.fromMap(res);
  }

  Future<void> upsertCustomersBatch(
      List<Map<String, dynamic>> rows, {void Function(int done, int total)? onProgress}) async {
    const batchSize = 500;
    for (var i = 0; i < rows.length; i += batchSize) {
      final batch = rows.sublist(
          i, i + batchSize > rows.length ? rows.length : i + batchSize);
      await _client.from('dme_customers').upsert(batch, onConflict: 'phone,company');
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

  // ── Reminders ────────────────────────────────────────────────
  Future<void> upsertReminder({
    required int customerId,
    required DateTime purchaseDate,
    String? assignedTo,
  }) async {
    final reminderDate =
        DateTime(purchaseDate.year, purchaseDate.month + 1, purchaseDate.day);
    await _client.from('dme_reminders').upsert({
      'customer_id': customerId,
      'reminder_date': reminderDate.toIso8601String().split('T')[0],
      'last_purchase_date': purchaseDate.toIso8601String().split('T')[0],
      'status': 'pending',
      'assigned_to': assignedTo,
    }, onConflict: 'customer_id');
  }

  Future<List<DmeReminder>> getReminders({
    List<int>? branchIds,
    String? status,
    DateTime? from,
    DateTime? to,
  }) async {
    var query = _client
        .from('dme_reminders')
        .select('*, dme_customers(name, phone, address, branch_id)');

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

  // ── Call Logs ────────────────────────────────────────────────
  Future<void> logCall({
    required int customerId,
    required String calledBy,
    required DateTime callDate,
    int? durationSeconds,
    String? remarks,
  }) async {
    await _client.from('dme_call_logs').insert({
      'customer_id': customerId,
      'called_by': calledBy,
      'call_date': callDate.toIso8601String().split('T')[0],
      'duration_seconds': durationSeconds,
      'remarks': remarks,
    });
  }

  Future<List<Map<String, dynamic>>> getCallLogs(int customerId) async {
    final res = await _client
        .from('dme_call_logs')
        .select()
        .eq('customer_id', customerId)
        .order('created_at', ascending: false);
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
        // Check if this (phone, company) pair already exists
        final existingRes = await _client
            .from('dme_customers')
            .select('id')
            .eq('phone', customer.phone)
            .eq('company', customer.company ?? '')
            .maybeSingle();
        
        int customerId;
        if (existingRes != null) {
          // Phone exists, add to junction table if not already linked
          customerId = existingRes['id'] as int;
          
          // Check if this customer-phone pair already mapped in junction
          final junctionRes = await _client
              .from('dme_customer_phone')
              .select('id')
              .eq('customer_id', customerId)
              .eq('phone_number', customer.phone)
              .maybeSingle();
          
          if (junctionRes == null) {
            // Add to junction table
            await _client.from('dme_customer_phone').insert({
              'customer_id': customerId,
              'phone_number': customer.phone,
              'created_at': DateTime.now().toIso8601String(),
            });
            linkedToExisting++;
          }
        } else {
          // New customer: insert and create junction
          final custMap = customer.toInsertMap();
          custMap['branch_id'] = branchId;
          custMap['updated_at'] = DateTime.now().toUtc().toIso8601String();
          
          final insertRes = await _client
              .from('dme_customers')
              .insert(custMap)
              .select('id')
              .single();
          
          customerId = insertRes['id'] as int;
          
          // Add to junction table
          await _client.from('dme_customer_phone').insert({
            'customer_id': customerId,
            'phone_number': customer.phone,
            'created_at': DateTime.now().toIso8601String(),
          });
          
          created++;
        }
        
        // Create reminder if last_purchase_date provided
        if (customer.lastPurchaseDate != null) {
          final reminderDate = customer.lastPurchaseDate!.add(Duration(days: 30));
          await _client.from('dme_reminders').upsert({
            'customer_id': customerId,
            'reminder_date': reminderDate.toIso8601String().split('T')[0],
            'last_purchase_date': customer.lastPurchaseDate!.toIso8601String().split('T')[0],
            'status': 'pending',
          }, onConflict: 'customer_id');
          remindersCreated++;
        }
        
      } catch (e) {
        print('Error uploading customer ${customer.name}: $e');
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
        .select('*, dme_customers(name, phone, address, branch_id)')
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
        .select('*, dme_customers(name, phone, address, branch_id)')
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
        .select('*, dme_customers(name, phone, address, branch_id)')
        .eq('id', reminderId)
        .maybeSingle();
    
    return res != null ? DmeReminder.fromMap(res) : null;
  }

  /// Mark reminder as complete
  Future<void> completeReminder(int reminderId) async {
    await _client.from('dme_reminders').update({
      'status': 'completed',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', reminderId);
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
