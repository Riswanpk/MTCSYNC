import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// --- Customer Profile Page ---
class CustomerProfilePage extends StatelessWidget {
  final Map<String, dynamic> customer;
  const CustomerProfilePage({super.key, required this.customer});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: Text(customer['name'] ?? 'Customer Profile'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF23262F) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                if (!isDark) BoxShadow(color: Colors.black12, blurRadius: 16, offset: Offset(0, 8)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundColor: Colors.blue.shade100,
                  child: Icon(Icons.person, size: 40, color: Colors.blue.shade700),
                ),
                const SizedBox(height: 18),
                Text(
                  customer['name'] ?? '',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
                ),
                const SizedBox(height: 8),
                Text(customer['company'] ?? '', style: const TextStyle(fontSize: 16)),
                const Divider(height: 32),
                _profileRow(Icons.phone, 'Phone', customer['phone']),
                _profileRow(Icons.location_on, 'Address', customer['address']),
                _profileRow(Icons.business, 'Branch', customer['branch']),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _profileRow(IconData icon, String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(icon, color: Colors.blueGrey, size: 22),
          const SizedBox(width: 14),
          Text('$label:', style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(value ?? '-', style: const TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }
}

// --- Customer List Page ---
class CustomerListPage extends StatefulWidget {
  const CustomerListPage({super.key});

  @override
  State<CustomerListPage> createState() => _CustomerListPageState();
}

class _CustomerListPageState extends State<CustomerListPage> {
  String searchQuery = '';
  String? userBranch;
  String? userRole;

  @override
  void initState() {
    super.initState();
    _fetchUserBranch();
  }

  Future<void> _fetchUserBranch() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      setState(() {
        userBranch = doc.data()?['branch'];
        userRole = doc.data()?['role'];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (userBranch == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer & Leads List'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                hintText: 'Search by phone or name...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (val) {
                setState(() {
                  searchQuery = val.trim().toLowerCase();
                });
              },
            ),
            const SizedBox(height: 12),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _fetchCombinedData(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final docs = snapshot.data!;
                  if (docs.isEmpty) {
                    return const Center(child: Text('No customers or leads found.'));
                  }
                  return Column(
                    children: [
                      Container(
                        color: Colors.blue.shade100,
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                        child: Row(
                          children: const [
                            Expanded(
                              flex: 2,
                              child: Text('Phone', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                            Expanded(
                              flex: 3,
                              child: Text('Name', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                            SizedBox(width: 32), // For arrow icon
                          ],
                        ),
                      ),
                      const Divider(height: 0, thickness: 1),
                      Expanded(
                        child: ListView.separated(
                          itemCount: docs.length,
                          separatorBuilder: (_, __) => const Divider(height: 0),
                          itemBuilder: (context, idx) {
                            final data = docs[idx];
                            return InkWell(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => CustomerProfilePage(customer: data),
                                  ),
                                );
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 2,
                                      child: Text(data['phone'] ?? '-', style: const TextStyle(fontSize: 16)),
                                    ),
                                    Expanded(
                                      flex: 3,
                                      child: Text(data['name'] ?? '-', style: const TextStyle(fontSize: 16)),
                                    ),
                                    const Icon(Icons.arrow_forward_ios, size: 18, color: Colors.blueGrey),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _fetchCombinedData() async {
    final customerSnap = await FirebaseFirestore.instance
        .collection('customer')
        .where('branch', isEqualTo: userBranch)
        .get();
    final followUpSnap = await FirebaseFirestore.instance
        .collection('follow_ups')
        .where('branch', isEqualTo: userBranch)
        .get();

    final List<Map<String, dynamic>> combined = [];

    for (var doc in customerSnap.docs) {
      final data = doc.data();
      data['type'] = 'Customer';
      combined.add(data);
    }
    for (var doc in followUpSnap.docs) {
      final data = doc.data();
      data['type'] = 'Lead';
      combined.add(data);
    }

    // Filter by search query
    return combined.where((data) {
      final phone = (data['phone'] ?? '').toString().toLowerCase();
      final name = (data['name'] ?? '').toString().toLowerCase();
      return searchQuery.isEmpty ||
          phone.contains(searchQuery) ||
          name.contains(searchQuery);
    }).toList();
  }
}