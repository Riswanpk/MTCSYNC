import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'viewer_marketing_detail.dart';

class ViewerMarketingPage extends StatefulWidget {
  const ViewerMarketingPage({super.key});

  @override
  State<ViewerMarketingPage> createState() => _ViewerMarketingPageState();
}

class _ViewerMarketingPageState extends State<ViewerMarketingPage> {
  String? selectedBranch;
  String? selectedUsername;

  List<String> branches = [];
  List<String> usernames = [];

  @override
  void initState() {
    super.initState();
    fetchBranches();
  }

  Future<void> fetchBranches() async {
    final snapshot = await FirebaseFirestore.instance.collection('marketing').get();
    final allBranches = <String>{};
    for (var doc in snapshot.docs) {
      final branch = doc['branch'] as String?;
      if (branch != null && branch.isNotEmpty) {
        allBranches.add(branch);
      }
    }
    final sortedBranches = allBranches.toList()..sort();
    setState(() {
      branches = sortedBranches;
      if (branches.isNotEmpty && (selectedBranch == null || !branches.contains(selectedBranch))) {
        selectedBranch = branches.first;
      }
    });
    await fetchUsernames();
  }

  Future<void> fetchUsernames() async {
    if (selectedBranch == null) {
      setState(() {
        usernames = [];
        selectedUsername = null;
      });
      return;
    }
    final snapshot = await FirebaseFirestore.instance
        .collection('marketing')
        .where('branch', isEqualTo: selectedBranch)
        .get();
    final allUsers = snapshot.docs.map((doc) => doc['username'] as String? ?? '').toSet().toList();
    allUsers.sort();
    setState(() {
      usernames = allUsers.where((u) => u.isNotEmpty).toList();
      if (usernames.isNotEmpty && (selectedUsername == null || !usernames.contains(selectedUsername))) {
        selectedUsername = usernames.first;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle(
      style: const TextStyle(fontFamily: 'Electorize'),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('View Marketing Forms'),
          backgroundColor: const Color(0xFF2C3E50),
        ),
        backgroundColor: const Color(0xFFE3E8EA),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // Branch Dropdown
              DropdownButtonFormField<String>(
                value: selectedBranch,
                decoration: InputDecoration(
                  labelText: 'Branch',
                  filled: true,
                  fillColor: const Color(0xFFF7F2F2),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                ),
                items: branches
                    .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                    .toList(),
                onChanged: (val) {
                  setState(() {
                    selectedBranch = val;
                    selectedUsername = null;
                    usernames = [];
                  });
                  fetchUsernames();
                },
              ),
              const SizedBox(height: 12),
              // Username Dropdown
              DropdownButtonFormField<String>(
                value: selectedUsername,
                decoration: InputDecoration(
                  labelText: 'Username',
                  filled: true,
                  fillColor: const Color(0xFFF7F2F2),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                ),
                items: usernames
                    .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                    .toList(),
                onChanged: (val) {
                  setState(() {
                    selectedUsername = val;
                  });
                },
              ),
              const SizedBox(height: 20),
              Expanded(
                child: selectedBranch == null || selectedUsername == null
                    ? const Center(child: Text('Select branch and username'))
                    : StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('marketing')
                            .where('branch', isEqualTo: selectedBranch)
                            .where('username', isEqualTo: selectedUsername)
                            .orderBy('timestamp', descending: true)
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          final docs = snapshot.data?.docs ?? [];
                          if (docs.isEmpty) {
                            return const Center(child: Text('No forms found.'));
                          }
                          return ListView.separated(
                            itemCount: docs.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (context, i) {
                              final data = docs[i].data() as Map<String, dynamic>;
                              return Card(
                                color: const Color(0xFFF7F2F2),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                child: ListTile(
                                  title: Text(
                                    data['shopName'] ?? 'No Shop Name',
                                    style: const TextStyle(fontSize: 18, color: Color(0xFF2C3E50)),
                                  ),
                                  subtitle: Text(
                                    data['formType'] ?? '',
                                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                                  ),
                                  trailing: const Icon(Icons.arrow_forward_ios, size: 18),
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ViewerMarketingDetailPage(data: data),
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
        ),
      ),
    );
  }
}