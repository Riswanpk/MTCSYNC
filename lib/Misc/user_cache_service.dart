import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Singleton service that caches the current user's Firestore document
/// to avoid repeated reads of the same data (role, branch, email, username).
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

  /// Clears all cached data. Call on logout.
  void clear() {
    _uid = null;
    _role = null;
    _branch = null;
    _email = null;
    _username = null;
    _loaded = false;
  }
}
