import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ManageUsersPage extends StatefulWidget {
  const ManageUsersPage({super.key});

  @override
  State<ManageUsersPage> createState() => _ManageUsersPageState();
}

class _ManageUsersPageState extends State<ManageUsersPage> {
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Users'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
        elevation: 0,
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
                          trailing: DropdownButton<String>(
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