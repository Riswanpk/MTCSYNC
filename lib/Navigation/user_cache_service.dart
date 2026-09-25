import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Singleton service that caches the current user's Firestore document
/// to avoid repeated reads of the same data (role, branch, email, username).
///
/// Also caches the full users list and branches to avoid repeated
/// `.collection('users').get()` calls across 10+ screens.
///
/// Usage:
///   final cache = UserCacheService.instance;
///   await cache.ensureLoaded();           // loads once, no-op after
///   final role = cache.role;              // 'admin' | 'manager' | 'sales'
///   final branch = cache.branch;
///   final email = cache.email;
///   final username = cache.username;
///   final uid = cache.uid;
///
///   final allUsers = await cache.getAllUsers();     // cached users list
///   final branches = await cache.getBranches();     // cached branch list
///
///   await cache.refresh();               // force re-fetch from Firestore
///   cache.clear();                       // call on logout
class UserCacheService {
  UserCacheService._();
  static final UserCacheService instance = UserCacheService._();

  String? _uid;
  String? _role;
  String? _branch;
  String? _email;
  String? _username;
  String? _yuPulseId;
  bool _loaded = false;

  // --- All-users cache ---
  List<Map<String, dynamic>>? _allUsers;
  List<String>? _branches;
  DateTime? _allUsersLoadedAt;
  static const _allUsersTtl = Duration(minutes: 10);

  // --- Getters ---
  String? get uid => _uid;
  String? get role => _role;
  String? get branch => _branch;
  String? get email => _email;
  String? get username => _username;
  String? get yuPulseId => _yuPulseId;
  String? get yupassId => _yuPulseId;
  static const _prefUidKey = 'cached_user_uid';
  static const _prefRoleKey = 'cached_user_role';
  static const _prefBranchKey = 'cached_user_branch';
  static const _prefEmailKey = 'cached_user_email';
  static const _prefUsernameKey = 'cached_user_username';
  static const _prefYuPulseIdKey = 'cached_user_yupulse_id';

  bool get isLoaded => _loaded;

  /// Loads the user document from Firestore if not already cached.
  /// Safe to call multiple times – only the first call hits Firestore.
  Future<void> ensureLoaded() async {
    if (_loaded) return;
    await refresh();
  }

  /// Force re-fetch user data from Firestore (e.g. after profile update).
  /// If offline or unavailable, attempts to fall back to SharedPreferences
  /// or Firestore local cache without throwing unhandled exceptions.
  Future<void> refresh() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      clear();
      return;
    }

    DocumentSnapshot<Map<String, dynamic>>? doc;

    try {
      // First attempt normal fetch (server with cache fallback according to Firestore settings)
      doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
    } on FirebaseException catch (fe) {
      debugPrint('UserCacheService.refresh() failed: ${fe.code} - ${fe.message}');
      // If server is unreachable/offline, try loading directly from Firestore local cache
      try {
        doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get(const GetOptions(source: Source.cache));
      } catch (cacheErr) {
        debugPrint('UserCacheService.refresh() cache fallback failed: $cacheErr');
      }
    } catch (e) {
      debugPrint('UserCacheService.refresh() unexpected error: $e');
    }

    if (doc != null && doc.exists && doc.data() != null) {
      final data = doc.data()!;
      _uid = user.uid;
      _role = data['role'];
      _branch = data['branch'];
      _email = data['email'] ?? user.email;
      _username = data['username'] ?? data['email'] ?? 'User';
      _yuPulseId = data['YuPulseID'] ?? data['yupass_id'];
      _loaded = true;

      // Persist to SharedPreferences so the app can start even with no network and empty cache
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefUidKey, _uid ?? '');
        if (_role != null) await prefs.setString(_prefRoleKey, _role!);
        if (_branch != null) await prefs.setString(_prefBranchKey, _branch!);
        if (_email != null) await prefs.setString(_prefEmailKey, _email!);
        if (_username != null) await prefs.setString(_prefUsernameKey, _username!);
        if (_yuPulseId != null) await prefs.setString(_prefYuPulseIdKey, _yuPulseId!);
      } catch (_) {}
      return;
    }

    // Fallback: If doc could not be retrieved from network or Firestore cache, restore from SharedPreferences
    if (!_loaded) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final savedUid = prefs.getString(_prefUidKey);
        if (savedUid == user.uid) {
          _uid = user.uid;
          _role = prefs.getString(_prefRoleKey);
          _branch = prefs.getString(_prefBranchKey);
          _email = prefs.getString(_prefEmailKey) ?? user.email;
          _username = prefs.getString(_prefUsernameKey) ?? user.displayName ?? 'User';
          _yuPulseId = prefs.getString(_prefYuPulseIdKey);
          _loaded = true;
          return;
        }
      } catch (_) {}
    }

    // Minimal fallback from currentUser so app doesn't crash
    _uid ??= user.uid;
    _email ??= user.email;
    _username ??= user.displayName ?? user.email?.split('@').first ?? 'User';
    _loaded = true;
  }

  /// Returns cached list of all user documents (as Maps).
  /// Each map contains: 'uid', 'email', 'username', 'branch', 'role', 'YuPulseID', 'yupass_id'.
  /// Cached for [_allUsersTtl]. Call [refreshAllUsers] to force reload.
  Future<List<Map<String, dynamic>>> getAllUsers({bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _allUsers != null &&
        _allUsersLoadedAt != null &&
        DateTime.now().difference(_allUsersLoadedAt!) < _allUsersTtl) {
      return _allUsers!;
    }
    await refreshAllUsers();
    return _allUsers!;
  }

  /// Returns cached sorted list of distinct non-empty branch names.
  Future<List<String>> getBranches({bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _branches != null &&
        _allUsersLoadedAt != null &&
        DateTime.now().difference(_allUsersLoadedAt!) < _allUsersTtl) {
      return _branches!;
    }
    await refreshAllUsers();
    return _branches!;
  }

  /// Force re-fetch the full users list from Firestore.
  Future<void> refreshAllUsers() async {
    try {
      final snapshot =
          await FirebaseFirestore.instance.collection('users').get();
      _allUsers = snapshot.docs.map((doc) {
        final data = doc.data();
        final pulseId = (data['YuPulseID'] ?? data['yupass_id'] ?? '').toString();
        return {
          'uid': doc.id,
          'email': data['email'] ?? '',
          'username': data['username'] ?? '',
          'branch': data['branch'] ?? '',
          'role': data['role'] ?? '',
          'YuPulseID': pulseId,
          'yupass_id': pulseId,
        };
      }).toList();
      _branches = _allUsers!
          .map((u) => u['branch'] as String)
          .where((b) => b.isNotEmpty && b.trim().toLowerCase() != 'admin')
          .toSet()
          .toList()
        ..sort();
      _allUsersLoadedAt = DateTime.now();
    } on FirebaseException catch (fe) {
      debugPrint('UserCacheService.refreshAllUsers() failed: ${fe.code} - ${fe.message}');
      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('users')
            .get(const GetOptions(source: Source.cache));
        if (snapshot.docs.isNotEmpty) {
          _allUsers = snapshot.docs.map((doc) {
            final data = doc.data();
            final pulseId = (data['YuPulseID'] ?? data['yupass_id'] ?? '').toString();
            return {
              'uid': doc.id,
              'email': data['email'] ?? '',
              'username': data['username'] ?? '',
              'branch': data['branch'] ?? '',
              'role': data['role'] ?? '',
              'YuPulseID': pulseId,
              'yupass_id': pulseId,
            };
          }).toList();
          _branches = _allUsers!
              .map((u) => u['branch'] as String)
              .where((b) => b.isNotEmpty && b.trim().toLowerCase() != 'admin')
              .toSet()
              .toList()
            ..sort();
          _allUsersLoadedAt = DateTime.now();
        }
      } catch (cacheErr) {
        debugPrint('UserCacheService.refreshAllUsers() cache fallback failed: $cacheErr');
      }
      _allUsers ??= [];
      _branches ??= [];
    } catch (e) {
      debugPrint('UserCacheService.refreshAllUsers() unexpected error: $e');
      _allUsers ??= [];
      _branches ??= [];
    }
  }

  /// Clears all cached data. Call on logout.
  void clear() {
    _uid = null;
    _role = null;
    _branch = null;
    _email = null;
    _username = null;
    _yuPulseId = null;
    _loaded = false;
    _allUsers = null;
    _branches = null;
    _allUsersLoadedAt = null;
  }
}