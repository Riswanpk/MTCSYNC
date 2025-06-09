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

  Future<void> _deleteEntry(Map<String, dynamic> data) async {
    String? phone = data['phone'];
    if (phone == null) return;
    // Find the document by phone (assuming phone is unique)
    Query query = FirebaseFirestore.instance
        .collection('customer')
        .where('phone', isEqualTo: phone);
    // Only filter by branch if not admin
    if (userRole != 'admin') {
      query = query.where('branch', isEqualTo: userBranch);
    }
    final snap = await query.get();
    for (var doc in snap.docs) {
      await doc.reference.delete();
    }
    setState(() {}); // Refresh list
  }

  @override
  Widget build(BuildContext context) {
    if (userBranch == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer & Leads List'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
        elevation: 2,
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Container(
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 2))],
              ),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search by phone or name...',
                  prefixIcon: Icon(Icons.search, color: Colors.blueGrey),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                ),
                onChanged: (val) {
                  setState(() {
                    searchQuery = val.trim().toLowerCase();
                  });
                },
              ),
            ),
            const SizedBox(height: 16),
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
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: Text('Phone', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey[800], fontFamily: 'Montserrat')),
                            ),
                            Expanded(
                              flex: 3,
                              child: Text('Name', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey[800], fontFamily: 'Montserrat')),
                            ),
                            if (userRole == 'admin')
                              const SizedBox(width: 40), // For delete button
                            const SizedBox(width: 24), // For arrow icon
                          ],
                        ),
                      ),
                      const Divider(height: 0, thickness: 1),
                      Expanded(
                        child: ListView.separated(
                          itemCount: docs.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, idx) {
                            final data = docs[idx];
                            return Card(
                              elevation: 2,
                              color: Colors.green.shade100, // Light green card color
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => CustomerProfilePage(customer: data),
                                    ),
                                  );
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                          data['phone'] ?? '-',
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontFamily: 'Montserrat',
                                            color: Colors.black, // Hard black text
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 3,
                                        child: Text(
                                          data['name'] ?? '-',
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w500,
                                            fontFamily: 'Montserrat',
                                            color: Colors.black, // Hard black text
                                          ),
                                        ),
                                      ),
                                      if (userRole == 'admin')
                                        IconButton(
                                          icon: const Icon(Icons.delete, color: Colors.redAccent),
                                          tooltip: 'Delete',
                                          onPressed: () async {
                                            final confirm = await showDialog<bool>(
                                              context: context,
                                              builder: (ctx) => AlertDialog(
                                                title: const Text('Delete Entry'),
                                                content: Text('Are you sure you want to delete this Customer?'),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () => Navigator.pop(ctx, false),
                                                    child: const Text('Cancel'),
                                                  ),
                                                  ElevatedButton(
                                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                                    onPressed: () => Navigator.pop(ctx, true),
                                                    child: const Text('Delete'),
                                                  ),
                                                ],
                                              ),
                                            );
                                            if (confirm == true) {
                                              await _deleteEntry(data);
                                            }
                                          },
                                        ),
                                      const Icon(Icons.arrow_forward_ios, size: 18, color: Colors.blueGrey),
                                    ],
                                  ),
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
    Query customerQuery = FirebaseFirestore.instance.collection('customer');
    // If not admin, filter by branch
    if (userRole != 'admin') {
      customerQuery = customerQuery.where('branch', isEqualTo: userBranch);
    }

    final customerSnap = await customerQuery.get();

    final List<Map<String, dynamic>> customers = [];

    for (var doc in customerSnap.docs) {
      final data = doc.data();
      if (data != null) {
        final mapData = data as Map<String, dynamic>;
        mapData['type'] = 'Customer'; // Optional, can be removed if not used
        customers.add(mapData);
      }
    }

    // Filter by search query
    final filtered = customers.where((data) {
      final phone = (data['phone'] ?? '').toString().toLowerCase();
      final name = (data['name'] ?? '').toString().toLowerCase();
      return searchQuery.isEmpty ||
          phone.contains(searchQuery) ||
          name.contains(searchQuery);
    }).toList();

    // Sort alphabetically by name
    filtered.sort((a, b) => (a['name'] ?? '').toString().toLowerCase().compareTo((b['name'] ?? '').toString().toLowerCase()));

    return filtered;
  }
}