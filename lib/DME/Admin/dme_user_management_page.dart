import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../dme_constants.dart';
import '../dme_config.dart';

class DmeUserManagementPage extends StatefulWidget {
  const DmeUserManagementPage({super.key});

  @override
  State<DmeUserManagementPage> createState() => _DmeUserManagementPageState();
}

class _DmeUserManagementPageState extends State<DmeUserManagementPage> {
  bool _isLoading = true;
  String _searchQuery = '';
  List<Map<String, dynamic>> _dmeUsers = [];

  SupabaseClient? get _supabaseClient {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _initSupabaseAndLoad();
  }

  Future<void> _initSupabaseAndLoad() async {
    if (DmeConfig.isConfigured) {
      try {
        Supabase.instance.client;
      } catch (_) {
        await Supabase.initialize(
          url: DmeConfig.supabaseUrl,
          anonKey: DmeConfig.supabaseAnonKey,
        );
      }
    }
    await _loadDmeUsers();
  }

  Future<void> _loadDmeUsers() async {
    setState(() => _isLoading = true);
    try {
      // 1. Fetch all users from Firestore with role dme_user or dme_admin
      final firestoreSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('role', whereIn: ['dme_user', 'dme_admin'])
          .get();

      // 2. Fetch Supabase dme_users records if supabase configured
      Map<String, Map<String, dynamic>> supabaseUserMap = {};
      final client = _supabaseClient;
      if (client != null && DmeConfig.isConfigured) {
        try {
          final res = await client.from('dme_users').select();
          for (var item in (res as List)) {
            final fbUid = item['firebase_uid']?.toString() ?? item['id']?.toString() ?? '';
            if (fbUid.isNotEmpty) {
              supabaseUserMap[fbUid] = Map<String, dynamic>.from(item);
            }
          }
        } catch (e) {
          debugPrint('Error fetching Supabase dme_users: $e');
        }
      }

      List<Map<String, dynamic>> users = [];

      for (var doc in firestoreSnap.docs) {
        final data = doc.data();
        final uid = doc.id;
        final email = data['email']?.toString() ?? '';
        final username = data['username']?.toString() ?? data['name']?.toString() ?? email.split('@').first;
        final role = data['role']?.toString() ?? 'dme_user';

        // Check assigned branches from Firestore or Supabase
        List<int> assignedBranches = [];
        if (data['assigned_branches'] is List) {
          assignedBranches = (data['assigned_branches'] as List)
              .map((e) => int.tryParse(e.toString()) ?? 0)
              .where((e) => e > 0)
              .toList();
        } else if (supabaseUserMap.containsKey(uid) && supabaseUserMap[uid]!['assigned_branches'] is List) {
          assignedBranches = (supabaseUserMap[uid]!['assigned_branches'] as List)
              .map((e) => int.tryParse(e.toString()) ?? 0)
              .where((e) => e > 0)
              .toList();
        }

        users.add({
          'uid': uid,
          'email': email,
          'username': username,
          'role': role,
          'assigned_branches': assignedBranches,
        });
      }

      setState(() {
        _dmeUsers = users;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading users: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _openBranchAssignmentDialog(Map<String, dynamic> user) {
    final List<int> currentAssigned = List<int>.from(user['assigned_branches'] ?? []);

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user['username'] ?? 'Assign Branches',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  Text(
                    user['email'] ?? '',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Selected: ${currentAssigned.length} / ${DmeConstants.branches.length}',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        Row(
                          children: [
                            TextButton(
                              onPressed: () {
                                setDialogState(() {
                                  currentAssigned.clear();
                                  currentAssigned.addAll(DmeConstants.branches.map((b) => b.id));
                                });
                              },
                              child: const Text('Select All', style: TextStyle(fontSize: 12)),
                            ),
                            TextButton(
                              onPressed: () {
                                setDialogState(() {
                                  currentAssigned.clear();
                                });
                              },
                              child: const Text('Clear', style: TextStyle(fontSize: 12, color: Colors.red)),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const Divider(),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: DmeConstants.branches.map((branch) {
                            final isSelected = currentAssigned.contains(branch.id);
                            return FilterChip(
                              label: Text(
                                branch.name,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  color: isSelected ? Colors.white : Colors.black87,
                                ),
                              ),
                              selected: isSelected,
                              selectedColor: const Color(0xFF005BAC),
                              checkmarkColor: Colors.white,
                              onSelected: (selected) {
                                setDialogState(() {
                                  if (selected) {
                                    currentAssigned.add(branch.id);
                                  } else {
                                    currentAssigned.remove(branch.id);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF005BAC),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    await _saveUserBranches(user['uid'], currentAssigned, user['email'], user['username'], user['role']);
                  },
                  child: const Text('Save Assignments'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _saveUserBranches(String uid, List<int> branches, String email, String username, String role) async {
    setState(() => _isLoading = true);
    String? supabaseError;

    try {
      // 1. Update Firestore
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'assigned_branches': branches,
      });

      // 2. Sync / Upsert into Supabase dme_users
      final client = _supabaseClient;
      if (client != null && DmeConfig.isConfigured) {
        try {
          // Check if record exists by firebase_uid or email
          final existing = await client
              .from('dme_users')
              .select('id')
              .or('firebase_uid.eq.$uid,email.eq.$email')
              .maybeSingle();

          if (existing != null) {
            final rowId = existing['id'];
            await client.from('dme_users').update({
              'username': username,
              'email': email,
              'role': role,
              'assigned_branches': branches,
              'firebase_uid': uid,
            }).eq('id', rowId);
          } else {
            await client.from('dme_users').insert({
              'username': username,
              'email': email,
              'role': role,
              'assigned_branches': branches,
              'firebase_uid': uid,
            });
          }
        } catch (e) {
          debugPrint('Error syncing Supabase dme_users: $e');
          supabaseError = e.toString();
        }
      }

      if (mounted) {
        if (supabaseError != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Updated Firestore, but Supabase error: $supabaseError'),
              backgroundColor: Colors.orange[800],
              duration: const Duration(seconds: 4),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Saved and synced branch assignments for $username in Supabase'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }

      await _loadDmeUsers();
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final filteredUsers = _dmeUsers.where((u) {
      final q = _searchQuery.toLowerCase();
      final name = (u['username'] ?? '').toString().toLowerCase();
      final email = (u['email'] ?? '').toString().toLowerCase();
      return name.contains(q) || email.contains(q);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('DME User Management'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Reload / Sync Users from Supabase',
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              await _loadDmeUsers();
              if (!mounted) return;
              messenger.showSnackBar(
                const SnackBar(
                  content: Text('Refreshed user data from Supabase & Firestore'),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Box
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search DME users by name or email...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: isDark ? Colors.grey[900] : Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onChanged: (val) {
                setState(() => _searchQuery = val);
              },
            ),
          ),

          // User List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredUsers.isEmpty
                    ? Center(
                        child: Text(
                          _dmeUsers.isEmpty
                              ? 'No DME users found in users collection.'
                              : 'No users match "$_searchQuery"',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadDmeUsers,
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          itemCount: filteredUsers.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final user = filteredUsers[index];
                            final List<int> assigned = List<int>.from(user['assigned_branches'] ?? []);
                            final branchNames = assigned
                                .map((id) => DmeConstants.getBranchName(id))
                                .where((name) => name != 'Unknown' && name != 'N/A')
                                .toList();

                            return Card(
                              elevation: 2,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              child: Padding(
                                padding: const EdgeInsets.all(14.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        CircleAvatar(
                                          backgroundColor: const Color(0xFF005BAC),
                                          foregroundColor: Colors.white,
                                          child: Text(
                                            (user['username'] ?? 'U').toString().substring(0, 1).toUpperCase(),
                                            style: const TextStyle(fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Flexible(
                                                    child: Text(
                                                      user['username'] ?? 'User',
                                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: user['role'] == 'dme_admin'
                                                          ? Colors.purple.withValues(alpha: 0.15)
                                                          : const Color(0xFF005BAC).withValues(alpha: 0.15),
                                                      borderRadius: BorderRadius.circular(6),
                                                    ),
                                                    child: Text(
                                                      user['role'] == 'dme_admin' ? 'Admin' : 'Sales User',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.w600,
                                                        color: user['role'] == 'dme_admin' ? Colors.purple : const Color(0xFF005BAC),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                user['email'] ?? '',
                                                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                                              ),
                                            ],
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.edit_location_alt, color: Color(0xFF005BAC)),
                                          tooltip: 'Assign Branches',
                                          onPressed: () => _openBranchAssignmentDialog(user),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    const Divider(height: 1),
                                    const SizedBox(height: 8),
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Icon(Icons.storefront_rounded, size: 16, color: Colors.grey[600]),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: branchNames.isEmpty
                                              ? Text(
                                                  'No branches assigned (Tap edit to assign)',
                                                  style: TextStyle(fontSize: 12, color: Colors.orange[800], fontStyle: FontStyle.italic),
                                                )
                                              : Wrap(
                                                  spacing: 6,
                                                  runSpacing: 4,
                                                  children: branchNames.map((b) {
                                                    return Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: const Color(0xFF8CC63F).withValues(alpha: 0.2),
                                                        borderRadius: BorderRadius.circular(6),
                                                        border: Border.all(color: const Color(0xFF8CC63F).withValues(alpha: 0.4)),
                                                      ),
                                                      child: Text(
                                                        b,
                                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black87),
                                                      ),
                                                    );
                                                  }).toList(),
                                                ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
