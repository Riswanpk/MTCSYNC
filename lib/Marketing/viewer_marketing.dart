import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'viewer_marketing_detail.dart';
import 'report_marketing.dart'; // ✅ Import your ReportMarketingPage


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

  InputDecoration _dropdownDecoration(BuildContext context, String label) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
      filled: true,
      fillColor: theme.cardColor,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return DefaultTextStyle(
      style: const TextStyle(fontFamily: 'Electorize'),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('View Marketing Forms',selectionColor:Colors.white70),
          backgroundColor: theme.colorScheme.primary,
          foregroundColor: theme.colorScheme.onPrimary,
          actions: [
            IconButton(
              icon: const Icon(Icons.insert_chart_outlined),
              tooltip: "Go to Reports",
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ReportMarketingPage()),
                );
              },
            ),
          ],
        ),
        backgroundColor: theme.scaffoldBackgroundColor,
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // Branch Dropdown
              DropdownButtonFormField<String>(
                value: selectedBranch,
                decoration: _dropdownDecoration(context, 'Branch'),
                dropdownColor: theme.cardColor,
                items: branches
                    .map((b) => DropdownMenuItem(
                        value: b, child: Text(b, style: theme.textTheme.bodyLarge)))
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
                decoration: _dropdownDecoration(context, 'Username'),
                dropdownColor: theme.cardColor,
                items: usernames
                    .map((u) => DropdownMenuItem(
                        value: u, child: Text(u, style: theme.textTheme.bodyLarge)))
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
                                color: theme.cardColor,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                child: ListTile(
                                  title: Text(
                                    data['shopName'] ?? 'No Shop Name',
                                    style: theme.textTheme.titleMedium,
                                  ),
                                  subtitle: Text(
                                    data['formType'] ?? '',
                                    style: theme.textTheme.bodySmall,
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
