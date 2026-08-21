import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../dme_config.dart';

/// Base Supabase service handling client initialization & branch caching.
class DmeMtcSupabaseService {
  DmeMtcSupabaseService._();
  static final DmeMtcSupabaseService instance = DmeMtcSupabaseService._();

  late final SupabaseClient _client = SupabaseClient(
    supabaseUrl,
    supabaseAnonKey,
  );

  SupabaseClient get client => _client;

  Future<void> ensureInitialized() async {
    // Client is ready on instantiation
  }

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
      await _client.from('dme_users').select('id').limit(1);
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
      return _branchesCache ?? [];
    }
  }

  Future<List<Map<String, dynamic>>> getCategories() async {
    await ensureInitialized();
    try {
      final res = await _client.from('dme_categories').select().order('name');
      return List<Map<String, dynamic>>.from(res);
    } catch (e) {
      debugPrint('Error fetching categories: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getCustomerTypes() async {
    await ensureInitialized();
    try {
      final res = await _client.from('dme_customer_types').select().order('name');
      return List<Map<String, dynamic>>.from(res);
    } catch (e) {
      debugPrint('Error fetching customer types: $e');
      return [];
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
}
