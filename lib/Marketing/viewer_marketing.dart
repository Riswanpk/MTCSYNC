import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'viewer_marketing_detail.dart';
import 'report_marketing.dart';
import 'package:intl/intl.dart'; // Add for date formatting

class ViewerMarketingPage extends StatefulWidget {
  const ViewerMarketingPage({super.key});

  @override
  State<ViewerMarketingPage> createState() => _ViewerMarketingPageState();
}

class _ViewerMarketingPageState extends State<ViewerMarketingPage> {
  String? selectedBranch;
  String? selectedUsername;
  DateTimeRange? selectedDateRange;

  List<String> branches = [];
  List<String> usernames = [];

  @override
  void initState() {
    super.initState();
    // Set default date range to today
    final now = DateTime.now();
    selectedDateRange = DateTimeRange(
      start: DateTime(now.year, now.month, now.day),
      end: DateTime(now.year, now.month, now.day, 23, 59, 59, 999),
    );
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
      usernames = ['All Users', ...allUsers.where((u) => u.isNotEmpty)];
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
      labelStyle: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black54),
      filled: true,
      fillColor: theme.cardColor,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DefaultTextStyle(
      style: const TextStyle(fontFamily: 'Electorize'),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('View Marketing Forms', selectionColor: Colors.white70),
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
          padding: const EdgeInsets.all(12.0),
          child: Column(
            children: [
              // Branch & Username in 1 row
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: selectedBranch,
                      decoration: _dropdownDecoration(context, 'Branch'),
                      dropdownColor: theme.cardColor,
                      style: theme.textTheme.bodyMedium,
                      items: branches
                          .map((b) => DropdownMenuItem(
                              value: b, child: Text(b, style: theme.textTheme.bodyMedium)))
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
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: selectedUsername,
                      decoration: _dropdownDecoration(context, 'Username'),
                      dropdownColor: theme.cardColor,
                      style: theme.textTheme.bodyMedium,
                      items: usernames
                          .map((u) => DropdownMenuItem(
                              value: u, child: Text(u, style: theme.textTheme.bodyMedium)))
                          .toList(),
                      onChanged: (val) {
                        setState(() {
                          selectedUsername = val;
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Date range filter in 1 row
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        final now = DateTime.now();
                        final picked = await showDateRangePicker(
                          context: context,
                          initialDateRange: selectedDateRange,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(now.year + 1),
                        );
                        if (picked != null) {
                          setState(() {
                            selectedDateRange = picked;
                          });
                        }
                      },
                      child: AbsorbPointer(
                        child: TextFormField(
                          decoration: _dropdownDecoration(context, 'Date Range')
                              .copyWith(
                                suffixIcon: const Icon(Icons.calendar_today, size: 18),
                              ),
                          controller: TextEditingController(
                            text: selectedDateRange == null
                                ? ''
                                : selectedDateRange!.start == selectedDateRange!.end
                                    ? DateFormat('yyyy-MM-dd').format(selectedDateRange!.start)
                                    : '${DateFormat('yyyy-MM-dd').format(selectedDateRange!.start)}'
                                      ' to '
                                      '${DateFormat('yyyy-MM-dd').format(selectedDateRange!.end)}',
                          ),
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ),
                  ),
                  if (selectedDateRange != null)
                    IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      tooltip: "Clear Date Range",
                      onPressed: () {
                        setState(() {
                          selectedDateRange = null;
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: selectedBranch == null || selectedUsername == null
                    ? const Center(child: Text('Select branch and username'))
                    : StreamBuilder<QuerySnapshot>(
                        stream: _filteredStream(),
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

  // Helper to build the Firestore query with filters
  Stream<QuerySnapshot> _filteredStream() {
    var query = FirebaseFirestore.instance
        .collection('marketing')
        .where('branch', isEqualTo: selectedBranch);

    if (selectedUsername != null && selectedUsername != 'All Users') {
      query = query.where('username', isEqualTo: selectedUsername);
    }

    if (selectedDateRange != null) {
      final start = DateTime(
        selectedDateRange!.start.year,
        selectedDateRange!.start.month,
        selectedDateRange!.start.day,
      );
      final end = DateTime(
        selectedDateRange!.end.year,
        selectedDateRange!.end.month,
        selectedDateRange!.end.day,
        23, 59, 59, 999,
      );
      query = query
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(end));
    }

    return query.orderBy('timestamp', descending: true).snapshots();
  }
}
