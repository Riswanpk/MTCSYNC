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
          Icon(icon, color: const Color.fromARGB(255, 123, 139, 96), size: 22),
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
  String? userId;

  @override
  void initState() {
    super.initState();
    _fetchUserInfo();
  }

  Future<void> _fetchUserInfo() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      setState(() {
        userBranch = userDoc.data()?['branch'];
        userRole = userDoc.data()?['role'];
        userId = user.uid;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (userBranch == null || userRole == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Always fetch all customer, filter in Dart for matching branch
    final customerQuery = FirebaseFirestore.instance.collection('customer');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer List'),
        backgroundColor: const Color(0xFF005BAC),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: customerQuery.snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data!.docs;
          // Filter by branch in Dart
          final filteredDocs = docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final branch = (data['branch'] ?? '').toString();
            final name = (data['name'] ?? '').toString().toLowerCase();
            // Admin: show all, others: only matching branch
            final branchMatch = userRole == 'admin' ? true : branch == userBranch;
            final nameMatch = searchQuery.isEmpty || name.contains(searchQuery);
            return branchMatch && nameMatch;
          }).toList();

          if (filteredDocs.isEmpty) {
            return const Center(child: Text('No customers found.'));
          }

          return ListView.builder(
            itemCount: filteredDocs.length,
            itemBuilder: (context, index) {
              final doc = filteredDocs[index];
              final data = doc.data() as Map<String, dynamic>;
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color.fromARGB(255, 0, 0, 0), width: 1.2),
                  borderRadius: BorderRadius.circular(14),
                  color: isDark ? const Color(0xFF23262F) : Colors.white,
                ),
                child: ListTile(
                  title: Text(data['name'] ?? ''),
                  subtitle: Text(data['branch'] ?? ''),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Color.fromARGB(255, 148, 220, 47)),
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
                        builder: (_) => CustomerProfilePage(customer: data),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class ShrinkOnTouchCard extends StatefulWidget {
  final Widget child;
  const ShrinkOnTouchCard({super.key, required this.child});

  @override
  _ShrinkOnTouchCardState createState() => _ShrinkOnTouchCardState();
}

class _ShrinkOnTouchCardState extends State<ShrinkOnTouchCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  void _onTapDown(TapDownDetails details) {
    setState(() => _pressed = true);
    _controller.forward();
  }

  void _onTapUp(TapUpDetails details) {
    setState(() => _pressed = false);
    _controller.reverse();
  }

  void _onTapCancel() {
    setState(() => _pressed = false);
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: GestureDetector(
        onTapDown: _onTapDown,
        onTapUp: _onTapUp,
        onTapCancel: _onTapCancel,
        child: Card(
          color: _pressed
              ? const Color(0xFFD0F0FD) // Light blue when pressed
              : const Color.fromARGB(255, 215, 243, 213), // Light green when not pressed
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: widget.child,
        ),
      ),
    );
  }
}