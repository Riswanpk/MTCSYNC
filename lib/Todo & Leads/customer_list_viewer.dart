import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class CustomerListViewer extends StatefulWidget {
  const CustomerListViewer({super.key});

  @override
  State<CustomerListViewer> createState() => _CustomerListViewerState();
}

class _CustomerListViewerState extends State<CustomerListViewer> {
  String searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer List'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search by name or phone',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: isDark ? const Color(0xFF23262F) : const Color(0xFFF6F7FB),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
              ),
              onChanged: (value) => setState(() => searchQuery = value.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('customer').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data!.docs;
                final filtered = docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final name = (data['name'] ?? '').toString().toLowerCase();
                  final phone = (data['phone'] ?? '').toString().toLowerCase();
                  return searchQuery.isEmpty ||
                      name.contains(searchQuery) ||
                      phone.contains(searchQuery);
                }).toList();

                if (filtered.isEmpty) {
                  return const Center(child: Text('No customers found.'));
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final doc = filtered[index];
                    final data = doc.data() as Map<String, dynamic>;
                    return Material(
                      color: isDark ? const Color(0xFF23262F) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      elevation: 2,
                      child: ListTile(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFFD0F0FD),
                          child: Icon(Icons.person, color: Colors.blue.shade700),
                        ),
                        title: Text(
                          data['name'] ?? '',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                        ),
                        subtitle: Text(
                          data['phone'] ?? '',
                          style: const TextStyle(fontSize: 15, color: Colors.black87),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.redAccent),
                          tooltip: 'Delete Customer',
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Delete Customer'),
                                content: const Text('Are you sure you want to delete this customer?'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('Delete', style: TextStyle(color: Colors.red)),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              await FirebaseFirestore.instance
                                  .collection('customer')
                                  .doc(doc.id)
                                  .delete();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Customer deleted')),
                              );
                            }
                          },
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CustomerProfileViewer(
                                name: data['name'] ?? '',
                                phone: data['phone'] ?? '',
                                address: data['address'] ?? '',
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class CustomerProfileViewer extends StatelessWidget {
  final String name;
  final String phone;
  final String address;

  const CustomerProfileViewer({
    super.key,
    required this.name,
    required this.phone,
    required this.address,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer Profile'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF23262F) : Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              if (!isDark) BoxShadow(color: Colors.black12, blurRadius: 18, offset: Offset(0, 8)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 38,
                backgroundColor: const Color(0xFFD0F0FD),
                child: Icon(Icons.person, size: 44, color: Colors.blue.shade700),
              ),
              const SizedBox(height: 22),
              Text(
                name,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 24),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.phone, color: Colors.blueGrey, size: 22),
                  const SizedBox(width: 10),
                  Text(phone, style: const TextStyle(fontSize: 17)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.location_on, color: Colors.blueGrey, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                            child: Text(address, style: const TextStyle(fontSize: 17)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
        }