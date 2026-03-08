import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
  bool get isLoaded => _loaded;

  /// Loads the user document from Firestore if not already cached.
  /// Safe to call multiple times – only the first call hits Firestore.
  Future<void> ensureLoaded() async {
    if (_loaded) return;
    await refresh();
  }

  /// Force re-fetch user data from Firestore (e.g. after profile update).
  Future<void> refresh() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      clear();
      return;
    }

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    _uid = user.uid;
    _role = doc.data()?['role'];
    _branch = doc.data()?['branch'];
    _email = doc.data()?['email'] ?? user.email;
    _username = doc.data()?['username'] ?? doc.data()?['email'] ?? 'User';
    _loaded = true;
  }

  /// Returns cached list of all user documents (as Maps).
  /// Each map contains: 'uid', 'email', 'username', 'branch', 'role'.
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
    final snapshot =
        await FirebaseFirestore.instance.collection('users').get();
    _allUsers = snapshot.docs.map((doc) {
      final data = doc.data();
      return {
        'uid': doc.id,
        'email': data['email'] ?? '',
        'username': data['username'] ?? '',
        'branch': data['branch'] ?? '',
        'role': data['role'] ?? '',
      };
    }).toList();
    _branches = _allUsers!
        .map((u) => u['branch'] as String)
        .where((b) => b.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    _allUsersLoadedAt = DateTime.now();
  }

  /// Clears all cached data. Call on logout.
  void clear() {
    _uid = null;
    _role = null;
    _branch = null;
    _email = null;
    _username = null;
    _loaded = false;
    _allUsers = null;
    _branches = null;
    _allUsersLoadedAt = null;
  }
}