import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/dme_user.dart';
import '../../core/services/dme_supabase_service.dart';

class DmeUserService {
  DmeUserService._();
  static final DmeUserService instance = DmeUserService._();

  SupabaseClient get _client => DmeMtcSupabaseService.instance.client;

  DmeUser? _currentUser;

  DmeUser? get cachedCurrentUser => _currentUser;

  Future<DmeUser?> getCurrentUser(String firebaseUid) async {
    await DmeMtcSupabaseService.instance.ensureInitialized();
    if (_currentUser != null && _currentUser!.firebaseUid == firebaseUid) {
      return _currentUser;
    }
    try {
      var res = await _client
          .from('dme_users')
          .select()
          .eq('id', firebaseUid)
          .maybeSingle();

      if (res == null) {
        String email = '';
        String username = '';
        String role = 'dme_admin';

        try {
          final doc = await FirebaseFirestore.instance
              .collection('users')
              .doc(firebaseUid)
              .get();
          if (doc.exists && doc.data() != null) {
            final data = doc.data()!;
            email = data['email'] as String? ?? '';
            username = data['username'] as String? ?? data['name'] as String? ?? '';
            role = data['role'] as String? ?? 'dme_admin';
          }
        } catch (e) {
          debugPrint('Error reading Firestore user profile: $e');
        }

        final fbUser = FirebaseAuth.instance.currentUser;
        if (email.isEmpty && fbUser?.email != null) {
          email = fbUser!.email!;
        }
        if (username.isEmpty && fbUser?.displayName != null) {
          username = fbUser!.displayName!;
        }
        if (username.isEmpty) {
          username = email.contains('@') ? email.split('@').first : 'User';
        }

        try {
          final inserted = await _client.from('dme_users').upsert({
            'id': firebaseUid,
            'firebase_uid': firebaseUid,
            'email': email,
            'username': username,
            'role': role,
          }).select().maybeSingle();

          if (inserted != null) {
            res = inserted;
          } else {
            res = {'id': firebaseUid, 'email': email, 'username': username, 'role': role};
          }
        } catch (e) {
          debugPrint('Error inserting user to Supabase dme_users: $e');
          res = {'id': firebaseUid, 'email': email, 'username': username, 'role': role};
        }
      }

      List<String> branches = [];
      try {
        branches = await getUserBranchNames(res['id'].toString());
      } catch (e) {
        debugPrint('Error fetching user branch names: $e');
      }

      _currentUser = DmeUser.fromMap(res, branches: branches);
      return _currentUser;
    } catch (e) {
      debugPrint('Network error getting current user: $e');
      final fbUser = FirebaseAuth.instance.currentUser;
      if (fbUser != null) {
        final email = fbUser.email ?? 'admin@dme.com';
        final username = fbUser.displayName ?? (email.contains('@') ? email.split('@').first : 'Admin');
        _currentUser = DmeUser(
          id: fbUser.uid,
          firebaseUid: fbUser.uid,
          email: email,
          username: username,
          role: 'dme_admin',
        );
      }
      return _currentUser;
    }
  }

  void clearCache() => _currentUser = null;

  Future<bool> isAdmin(String firebaseUid) async {
    final user = await getCurrentUser(firebaseUid);
    return user?.isAdmin ?? false;
  }

  Future<List<String>> getUserBranchNames(String dmeUserId) async {
    await DmeMtcSupabaseService.instance.ensureInitialized();
    try {
      final branchIds = await getUserBranchIds(dmeUserId);
      if (branchIds.isEmpty) return [];
      final branches = await DmeMtcSupabaseService.instance.getBranches();
      final idToName = {
        for (final b in branches) (b['id'] as int): (b['name'] as String)
      };
      return branchIds
          .map((id) => idToName[id] ?? '')
          .where((name) => name.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('Network error fetching user branch names for $dmeUserId: $e');
      return [];
    }
  }

  Future<List<int>> getUserBranchIds(String dmeUserId) async {
    await DmeMtcSupabaseService.instance.ensureInitialized();
    try {
      final userRes = await _client
          .from('dme_users')
          .select('assigned_branches')
          .eq('id', dmeUserId)
          .maybeSingle();
      if (userRes != null && userRes['assigned_branches'] != null) {
        return List<int>.from(userRes['assigned_branches'] as List);
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching user branch IDs for $dmeUserId: $e');
      return [];
    }
  }

  Future<List<DmeUser>> getAllDmeUsers() async {
    await DmeMtcSupabaseService.instance.ensureInitialized();
    try {
      final res = await _client
          .from('dme_users')
          .select()
          .order('username');

      final branches = await DmeMtcSupabaseService.instance.getBranches();
      final idToName = {
        for (final b in branches) (b['id'] as int): (b['name'] as String)
      };

      return List<Map<String, dynamic>>.from(res).map((row) {
        final bIds = (row['assigned_branches'] as List?)?.cast<int>() ?? [];
        final bNames = bIds.map((id) => idToName[id] ?? '').where((s) => s.isNotEmpty).toList();
        return DmeUser.fromMap(row, branches: bNames);
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
    await DmeMtcSupabaseService.instance.ensureInitialized();
    try {
      final row = await _client
          .from('dme_users')
          .insert({
            'id': firebaseUid,
            'firebase_uid': firebaseUid,
            'email': email,
            'username': username,
            'role': role,
            'assigned_branches': branchIds,
          })
          .select()
          .single();

      final branches = await getUserBranchNames(row['id'].toString());
      return DmeUser.fromMap(row, branches: branches);
    } catch (e) {
      debugPrint('Network error creating DME user: $e');
      rethrow;
    }
  }

  Future<void> updateDmeUserRole(String userId, String role) async {
    await DmeMtcSupabaseService.instance.ensureInitialized();
    try {
      await _client.from('dme_users').update({'role': role}).eq('id', userId);
    } catch (e) {
      debugPrint('Network error updating user role: $e');
      rethrow;
    }
  }

  Future<void> setUserBranches(String userId, List<int> branchIds) async {
    await DmeMtcSupabaseService.instance.ensureInitialized();
    try {
      await _client
          .from('dme_users')
          .update({'assigned_branches': branchIds})
          .eq('id', userId);
      _currentUser = null;
    } catch (e) {
      debugPrint('Network error setting user branches: $e');
      rethrow;
    }
  }

  Future<void> deleteDmeUser(String userId) async {
    try {
      await _client.from('dme_users').delete().eq('id', userId);
    } catch (e) {
      debugPrint('Network error deleting DME user: $e');
      rethrow;
    }
  }

  Future<List<DmeUser>> getUsersByBranch(String branchName) async {
    await DmeMtcSupabaseService.instance.ensureInitialized();
    try {
      final branchId = await DmeMtcSupabaseService.instance.getBranchIdByNameCached(branchName);
      if (branchId == null) return [];
      return getUsersForBranch(branchId);
    } catch (e) {
      debugPrint('Error getting users for branch: $e');
      return [];
    }
  }

  Future<List<DmeUser>> getUsersForBranch(int branchId) async {
    await DmeMtcSupabaseService.instance.ensureInitialized();
    try {
      final res = await _client
          .from('dme_users')
          .select()
          .contains('assigned_branches', [branchId]);

      final branches = await DmeMtcSupabaseService.instance.getBranches();
      final idToName = {
        for (final b in branches) (b['id'] as int): (b['name'] as String)
      };

      return List<Map<String, dynamic>>.from(res).map((row) {
        final bIds = (row['assigned_branches'] as List?)?.cast<int>() ?? [];
        final bNames = bIds.map((id) => idToName[id] ?? '').where((s) => s.isNotEmpty).toList();
        return DmeUser.fromMap(row, branches: bNames);
      }).toList();
    } catch (e) {
      debugPrint('Error getting users for branch: $e');
      return [];
    }
  }

  Future<DmeUser?> getDmeUserForBranch(int branchId) async {
    try {
      await DmeMtcSupabaseService.instance.ensureInitialized();
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

  Future<Map<String, dynamic>> syncFirebaseUsersToSupabase() async {
    await DmeMtcSupabaseService.instance.ensureInitialized();

    try {
      final firebaseSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('role', whereIn: ['dme_user', 'dme_admin'])
          .get();

      int addedCount = 0;
      int skippedCount = 0;

      for (final doc in firebaseSnapshot.docs) {
        final firebaseUid = doc.id;
        final email = doc['email'] as String? ?? '';
        final username = doc['username'] as String? ?? doc['name'] as String? ?? '';
        final role = doc['role'] as String? ?? '';

        if (role != 'dme_admin' && role != 'dme_user') {
          continue;
        }

        final existing = await _client
            .from('dme_users')
            .select('id')
            .eq('id', firebaseUid)
            .maybeSingle();

        if (existing == null) {
          try {
            await _client.from('dme_users').insert({
              'id': firebaseUid,
              'firebase_uid': firebaseUid,
              'email': email,
              'username': username,
              'role': role,
            });
            addedCount++;
          } catch (e) {
            debugPrint('Error adding user $username ($firebaseUid): $e');
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
        'message': 'Synced $addedCount new users from Firebase (including admins)',
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
        'message': 'Error syncing Firebase users: $e',
      };
    }
  }

  Future<Map<String, dynamic>> syncDmeAdminUsers() async {
    await DmeMtcSupabaseService.instance.ensureInitialized();

    try {
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

        final existing = await _client
            .from('dme_users')
            .select('id')
            .eq('firebase_uid', firebaseUid)
            .maybeSingle();

        if (existing == null) {
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
}
