import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:collection/collection.dart'; // Add this for groupBy

class ManageUsersPage extends StatefulWidget {
  final String userRole;
  const ManageUsersPage({super.key, required this.userRole});

  @override
  State<ManageUsersPage> createState() => _ManageUsersPageState();
}

class _ManageUsersPageState extends State<ManageUsersPage> {
    bool _filterByVersion = false;
  final List<String> _roles = ['sales', 'manager', 'admin'];
  String? _currentUserId;
  String _searchQuery = ''; // <-- Add this line
  final TextEditingController _searchController = TextEditingController(); // <-- Add this line

  @override
  void initState() {
    super.initState();
    _currentUserId = FirebaseAuth.instance.currentUser?.uid;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _updateUserRole(String uid, String newRole) async {
    await FirebaseFirestore.instance.collection('users').doc(uid).update({'role': newRole});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Role updated to $newRole'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
    setState(() {}); // Refresh UI
  }

  void _confirmDeleteUser(String uid, String email) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete User'),
        content: Text('Are you sure you want to delete user "$email"? This action cannot be undone.'),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(context).pop(),
          ),
          TextButton(
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
            onPressed: () async {
              Navigator.of(context).pop();
              await _deleteUser(uid);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _deleteUser(String docId) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('No authenticated user');
      }

      // Fetch the user document to get the UID (should be same as docId)
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(docId).get();
      final uid = userDoc.id; // Firestore doc ID is the Auth UID

      // Prevent deleting yourself
      if (currentUser.uid == uid) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You cannot delete yourself.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }

      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      // Call Cloud Function - specify region if needed
      final callable = FirebaseFunctions.instanceFor(region: 'asia-south1')
          .httpsCallable('deleteUserFromAuth');
      final result = await callable.call({'uid': uid});

      // Close loading dialog
      if (mounted) Navigator.of(context).pop();

      if (result.data['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('User deleted successfully.'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
          setState(() {});
        }
      }
    } on FirebaseFunctionsException catch (e) {
      print('Firebase Functions Error: ${e.code} - ${e.message}');
      print('Details: ${e.details}');
      
      // Close loading dialog if open
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      String errorMessage = 'Failed to delete user';
      switch (e.code) {
        case 'unauthenticated':
          errorMessage = 'Authentication failed. Please sign out and sign in again.';
          break;
        case 'permission-denied':
          errorMessage = e.message ?? 'You do not have permission to delete this user.';
          break;
        case 'invalid-argument':
          errorMessage = 'Invalid user ID provided.';
          break;
        case 'not-found':
          errorMessage = 'User not found.';
          break;
        default:
          errorMessage = e.message ?? 'An error occurred while deleting the user.';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      print('General Error: $e');
      
      // Close loading dialog if open
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<Map<String, List<Map<String, dynamic>>>> _fetchUserVersionsByBranch() async {
    final usersSnapshot = await FirebaseFirestore.instance.collection('users').get();
    final versionsSnapshot = await FirebaseFirestore.instance.collection('user_version').get();

    // Map user uid to version info
    final versionMap = {
      for (var doc in versionsSnapshot.docs) doc.id: doc.data()
    };

    // Build user info list with branch and version
    final userInfoList = usersSnapshot.docs.map((doc) {
      final data = doc.data();
      final uid = doc.id;
      return {
        'username': data['username'] ?? '',
        'email': data['email'] ?? '',
        'branch': data['branch'] ?? 'Unknown',
        'version': versionMap[uid]?['appVersion'] ?? 'N/A',
      };
    }).toList();

    // Group by branch
    return groupBy(userInfoList, (user) => user['branch'] as String);
  }

  void _showUserVersionsDialog() async {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return FutureBuilder<Map<String, List<Map<String, dynamic>>>>(
              future: _fetchUserVersionsByBranch(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const AlertDialog(
                    title: Text('User Versions'),
                    content: SizedBox(height: 100, child: Center(child: CircularProgressIndicator())),
                  );
                }
                final branchMap = snapshot.data!;
                // Exclude the "admin" branch and sort the rest
                final sortedBranchEntries = branchMap.entries
                    .where((entry) => entry.key.toLowerCase() != 'admin')
                    .toList()
                  ..sort((a, b) => a.key.compareTo(b.key));

                // Get latest version from app_constants.dart
                const String latestVersion = '1.2.106';

                return AlertDialog(
                  title: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('User Versions'),
                      IconButton(
                        icon: Icon(_filterByVersion ? Icons.filter_alt : Icons.filter_alt_outlined, color: Colors.blue),
                        tooltip: _filterByVersion ? 'Show Unsorted' : 'Sort by Version',
                        onPressed: () {
                          setStateDialog(() {
                            _filterByVersion = !_filterByVersion;
                          });
                        },
                      ),
                    ],
                  ),
                  content: SizedBox(
                    width: 350,
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: sortedBranchEntries.map((entry) {
                          final branch = entry.key;
                          List<Map<String, dynamic>> users = List<Map<String, dynamic>>.from(entry.value);
                          if (_filterByVersion) {
                            users.sort((a, b) {
                              String vA = a['version'] ?? '';
                              String vB = b['version'] ?? '';
                              // Place latest version at the end (ascending order)
                              int parseVersion(String v) {
                                // Converts version string to int for comparison, e.g. 1.2.106 -> 000100020098
                                return int.tryParse(v.replaceAll('.', '').padLeft(8, '0')) ?? 0;
                              }
                              return parseVersion(vA).compareTo(parseVersion(vB));
                            });
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8.0),
                                child: Text(
                                  branch,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: Colors.blue,
                                  ),
                                ),
                              ),
                              ...users.map((user) => ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(user['username'] ?? ''),
                                    subtitle: Text(user['email'] ?? ''),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          user['version'] ?? 'N/A',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: (user['version'] == latestVersion)
                                                ? Colors.green
                                                : null,
                                          ),
                                        ),
                                        if (user['version'] == latestVersion)
                                          const Padding(
                                            padding: EdgeInsets.only(left: 4.0),
                                            child: Icon(Icons.check_circle, color: Colors.green, size: 18),
                                          ),
                                      ],
                                    ),
                                  )),
                              const Divider(),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  /// Fetches the branch for a user by matching their email in the users collection.
  Future<String?> getBranchByEmail(String email) async {
    final query = await FirebaseFirestore.instance
        .collection('users')
        .where('email', isEqualTo: email)
        .limit(1)
        .get();
    if (query.docs.isNotEmpty) {
      return query.docs.first.data()['branch'] as String?;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      // Not logged in, redirect to login page
      Future.microtask(() {
        Navigator.of(context).pushReplacementNamed('/login');
      });
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Users'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Show User Versions',
            onPressed: _showUserVersionsDialog,
          ),
        ],
      ),
      backgroundColor: isDark ? const Color(0xFF181A20) : const Color(0xFFF6F7FB),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Search Bar
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by name or email',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: isDark ? const Color(0xFF23272F) : Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value.trim().toLowerCase();
                });
              },
            ),
            const SizedBox(height: 16),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('users').snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return const Center(child: Text('No users found.'));
                  }
                  // Filter out the current user
                  final users = snapshot.data!.docs
                      .where((doc) => doc.id != _currentUserId)
                      .where((doc) {
                        final username = (doc['username'] ?? '').toString().toLowerCase();
                        final email = (doc['email'] ?? '').toString().toLowerCase();
                        return _searchQuery.isEmpty ||
                            username.contains(_searchQuery) ||
                            email.contains(_searchQuery);
                      })
                      .toList();
                  if (users.isEmpty) {
                    return const Center(child: Text('No users match your search.'));
                  }
                  return Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: users.length,
                      separatorBuilder: (_, __) => const Divider(height: 24),
                      itemBuilder: (context, index) {
                        final user = users[index];
                        final username = user['username'] ?? '';
                        final email = user['email'] ?? '';
                        final role = user['role'] ?? 'sales';
                        final docId = user.id; // <-- Use document ID

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFF005BAC),
                            child: Text(
                              username.isNotEmpty ? username[0].toUpperCase() : '?',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                          title: Text(
                            username,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                          subtitle: Text(
                            email,
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              DropdownButton<String>(
                                value: role,
                                borderRadius: BorderRadius.circular(12),
                                dropdownColor: isDark ? const Color(0xFF23272F) : Colors.white,
                                style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 13,
                                ),
                                underline: Container(),
                                items: _roles
                                    .map((r) => DropdownMenuItem(
                                          value: r,
                                          child: Row(
                                            children: [
                                              Icon(
                                                r == 'admin'
                                                    ? Icons.security
                                                    : r == 'manager'
                                                        ? Icons.supervisor_account
                                                        : Icons.person,
                                                color: r == 'admin'
                                                    ? Colors.deepPurple
                                                    : r == 'manager'
                                                        ? Colors.orange
                                                        : Colors.green,
                                                size: 20,
                                              ),
                                              const SizedBox(width: 8),
                                              Text(r[0].toUpperCase() + r.substring(1)),
                                            ],
                                          ),
                                        ))
                                    .toList(),
                                onChanged: (newRole) {
                                  if (newRole != null && newRole != role) {
                                    _updateUserRole(user.id, newRole);
                                  }
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                tooltip: 'Delete User',
                                onPressed: () => _confirmDeleteUser(docId, email), // <-- Pass document ID
                              ),
                            ],
                          ),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          tileColor: isDark ? const Color(0xFF23272F) : Colors.grey[100],
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}