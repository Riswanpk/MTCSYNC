import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:audioplayers/audioplayers.dart';
import 'presentfollowup.dart';
import 'leadsform.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
// Add these imports for Excel export
import 'package:excel/excel.dart' hide TextSpan;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'customer_list.dart'; // Import the customer list page


class LeadsPage extends StatefulWidget {
  final String branch;

  const LeadsPage({super.key, required this.branch});

  @override
  State<LeadsPage> createState() => _LeadsPageState();
}

class _LeadsPageState extends State<LeadsPage> {
  String searchQuery = '';
  String selectedStatus = 'All';
  String? selectedBranch;
  String? selectedUser; // <-- NEW: selected user for filter
  List<String> availableBranches = [];
  List<Map<String, dynamic>> availableUsers = []; // <-- NEW: list of users for dropdown
  final ValueNotifier<bool> _isHovering = ValueNotifier(false);

  final List<String> statusOptions = [
    'All',
    'In Progress',
    'Completed',
    'High',
    'Medium',
    'Low',
  ];

  // Add this for sort order
  bool sortAscending = false;

  late Future<Map<String, dynamic>?> _currentUserData;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    _currentUserData = FirebaseFirestore.instance.collection('users').doc(uid).get().then((doc) => doc.data());
    _fetchBranches();
    // Only fetch users for the current branch for manager/sales
    _currentUserData.then((userData) {
      if (userData != null) {
        final role = userData['role'] ?? 'sales';
        final branch = userData['branch'] ?? '';
        if (role == 'admin') {
          // Do NOT fetch users here for admin, wait for branch selection
          // _fetchUsers(); <-- REMOVE THIS LINE
        } else {
          _fetchUsers(branch); // manager/sales: only fetch for their branch
          setState(() {
            selectedBranch = branch;
          });
        }
      }
    });
    // Auto delete completed leads at end of month
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final userData = await _currentUserData;
      if (userData != null) {
        await autoDeleteCompletedLeads(userData['branch'] ?? '');
      }
    });
  }

  Future<void> _fetchBranches() async {
    final snapshot = await FirebaseFirestore.instance.collection('users').get();
    final branches = snapshot.docs
        .map((doc) => doc.data()['branch'] as String?)
        .where((branch) => branch != null)
        .toSet()
        .cast<String>()
        .toList();
    setState(() {
      availableBranches = branches;
      if (branches.isNotEmpty && selectedBranch == null) {
        selectedBranch = branches.first;
      }
    });
  }

  // NEW: Fetch users for filter dropdown
  Future<void> _fetchUsers([String? branch]) async {
    Query query = FirebaseFirestore.instance.collection('users');
    if (branch != null && branch.isNotEmpty) {
      query = query.where('branch', isEqualTo: branch);
    }
    final snapshot = await query.get();
    setState(() {
      availableUsers = snapshot.docs
          .map((doc) => {
                'id': doc.id,
                'username': (doc.data() as Map<String, dynamic>)['username'] ?? 'Unknown'
              })
          .toList();
    });
  }

  // Add this method for Excel export
  Future<String?> _downloadLeadsExcel(BuildContext context, {String? branch}) async {
    try {
      final excel = Excel.createExcel();
      excel.delete('Sheet1'); // Remove default sheet

      // Fetch all leads (or only for a specific branch)
      QuerySnapshot query;
      if (branch != null) {
        query = await FirebaseFirestore.instance
            .collection('follow_ups')
            .where('branch', isEqualTo: branch)
            .get();
      } else {
        query = await FirebaseFirestore.instance.collection('follow_ups').get();
      }

      // Fetch all users to map userId -> username
      final usersSnapshot = await FirebaseFirestore.instance.collection('users').get();
      final userIdToUsername = {
        for (var doc in usersSnapshot.docs)
          doc.id: (doc.data() as Map<String, dynamic>)['username'] ?? 'Unknown'
      };

      // Group leads by branch
      final Map<String, List<Map<String, dynamic>>> branchLeads = {};
      for (final doc in query.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final branchName = (data['branch'] ?? 'Unknown') as String;
        branchLeads.putIfAbsent(branchName, () => []).add(data);
      }

      // For each branch, create a sheet and add leads
      for (final entry in branchLeads.entries) {
        final branchName = entry.key;
        final leads = entry.value;
        final sheet = excel[branchName];

        // Add header row (Username first)
        sheet.appendRow([
          TextCellValue('Username'),
          TextCellValue('Name'),
          TextCellValue('Company'),
          TextCellValue('Address'),
          TextCellValue('Phone'),
          TextCellValue('Status'),
          TextCellValue('Comments'),
        ]);

        // Add data rows
        for (final data in leads) {
          final createdBy = data['created_by'] ?? '';
          final username = userIdToUsername[createdBy] ?? 'Unknown';
          sheet.appendRow([
            TextCellValue(username),
            TextCellValue(data['name']?.toString() ?? ''),
            TextCellValue(data['company']?.toString() ?? ''),
            TextCellValue(data['address']?.toString() ?? ''),
            TextCellValue(data['phone']?.toString() ?? ''),
            TextCellValue(data['status']?.toString() ?? ''),
            TextCellValue(data['comments']?.toString() ?? ''),
          ]);
        }
      }

      // Save to temp directory for sharing
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/leads_${DateTime.now().millisecondsSinceEpoch}.xlsx');
      final fileBytes = await excel.encode(); // <-- now async in v4.x
      await file.writeAsBytes(fileBytes!);

      return file.path;
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to generate Excel: $e')),
      );
      return null;
    }
  }

  Future<void> autoDeleteCompletedLeads(String branch) async {
    final now = DateTime.now();
    final lastDay = DateTime(now.year, now.month + 1, 0).day;
    if (now.day == lastDay) {
      final query = await FirebaseFirestore.instance
          .collection('follow_ups')
          .where('branch', isEqualTo: branch)
          .where('status', isEqualTo: 'Completed')
          .get();
      for (final doc in query.docs) {
        await doc.reference.delete();
      }
    }
  }

 @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _currentUserData,
      builder: (context, userSnapshot) {
        if (!userSnapshot.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final userData = userSnapshot.data!;
        final currentUserId = FirebaseAuth.instance.currentUser?.uid;
        final role = userData['role'] ?? 'sales';
        final managerBranch = userData['branch'];
        final branchToShow = role == 'admin' ? selectedBranch ?? '' : widget.branch;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Leads Follow Up'),
            backgroundColor: const Color(0xFF005BAC),
            foregroundColor: Colors.white,
            actions: [
              // Move Customer List button to right-side burger menu for all roles
              Builder(
                builder: (context) => IconButton(
                  icon: const Icon(Icons.menu),
                  tooltip: 'Menu',
                  onPressed: () => Scaffold.of(context).openEndDrawer(),
                ),
              ),
            ],
          ),
          endDrawer: Drawer(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                DrawerHeader(
                  decoration: const BoxDecoration(
                    color: Color(0xFF005BAC),
                  ),
                  child: const Text(
                    'Menu',
                    style: TextStyle(color: Colors.white, fontSize: 24),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.people_outline),
                  title: const Text('Customer List'),
                  onTap: () {
                    Navigator.pop(context); // Close the drawer
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const CustomerListPage()),
                    );
                  },
                ),
                if (role == 'admin' || role == 'manager')
                  ListTile(
                    leading: const Icon(Icons.delete_forever, color: Colors.red),
                    title: const Text('Delete All Completed Leads'),
                    onTap: () async {
                      Navigator.pop(context);
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Delete All Completed Leads?'),
                          content: const Text(
                            'Are you sure you want to delete all completed leads for this branch? This action cannot be undone.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(true),
                              child: const Text('Delete', style: TextStyle(color: Colors.red)),
                            ),
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              child: const Text('Cancel'),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        final branch = role == 'admin' ? (selectedBranch ?? '') : managerBranch;
                        final query = await FirebaseFirestore.instance
                            .collection('follow_ups')
                            .where('branch', isEqualTo: branch)
                            .where('status', isEqualTo: 'Completed')
                            .get();
                        for (final doc in query.docs) {
                          await doc.reference.delete();
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('All completed leads deleted')),
                        );
                      }
                    },
                  ),
                if (role == 'admin' || role == 'manager')
                  ListTile(
                    leading: const Icon(Icons.download, color: Colors.green),
                    title: const Text('Excel'),
                    onTap: () async {
                      Navigator.pop(context);
                      final excelPath = await _downloadLeadsExcel(
                        context,
                        branch: role == 'admin' ? null : managerBranch,
                      );
                      if (excelPath != null) {
                        Share.shareXFiles([XFile(excelPath)], text: 'Leads Excel Report');
                      }
                    },
                  ),
                // ...add other menu items if needed...
              ],
            ),
          ),
          body: Stack(
            children: [
              // Background logo
              Center(
                child: Opacity(
                  opacity: 0.05,
                  child: Image.asset(
                    'assets/images/logo.png',
                    width: 250,
                  ),
                ),
              ),
              Column(
                children: [
                  // --- TOP FILTERS ROW ---
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: role == 'admin'
                        ? Column(
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    flex: 1,
                                    child: SizedBox(
                                      height: 36,
                                      child: DropdownButtonFormField<String>(
                                        value: selectedBranch,
                                        items: availableBranches
                                            .map((branch) => DropdownMenuItem(
                                                  value: branch,
                                                  child: Text(
                                                    branch,
                                                    style: const TextStyle(fontSize: 9),
                                                  ),
                                                ))
                                            .toList(),
                                        onChanged: (val) {
                                          setState(() {
                                            selectedBranch = val;
                                            selectedUser = null;
                                          });
                                          // Only fetch users after branch is selected
                                          if (val != null) {
                                            _fetchUsers(val);
                                          } else {
                                            setState(() {
                                              availableUsers = [];
                                            });
                                          }
                                        },
                                        decoration: InputDecoration(
                                          labelText: 'Branch',
                                          labelStyle: const TextStyle(fontSize: 9),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(8),
                                            borderSide: BorderSide.none,
                                          ),
                                          filled: true,
                                          fillColor: const Color.fromARGB(255, 229, 237, 229),
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                        ),
                                        style: const TextStyle(fontSize: 10, color: Colors.black),
                                        dropdownColor: Colors.white,
                                        icon: const Icon(Icons.arrow_drop_down, size: 14),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                  Flexible(
                                    flex: 1,
                                    child: SizedBox(
                                      height: 36,
                                      child: DropdownButtonFormField<String>(
                                        value: selectedUser,
                                        items: [
                                          const DropdownMenuItem(
                                            value: null,
                                            child: Text('All Users', style: TextStyle(fontSize: 9)),
                                          ),
                                          ...availableUsers.map((user) => DropdownMenuItem(
                                                value: user['id'],
                                                child: Text(
                                                  user['username'],
                                                  style: const TextStyle(fontSize: 9),
                                                ),
                                              )),
                                        ],
                                        onChanged: (val) {
                                          setState(() {
                                            selectedUser = val;
                                          });
                                        },
                                        decoration: InputDecoration(
                                          labelText: 'User',
                                          labelStyle: const TextStyle(fontSize: 9),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(8),
                                            borderSide: BorderSide.none,
                                          ),
                                          filled: true,
                                          fillColor: const Color.fromARGB(255, 229, 237, 229),
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 1, vertical: 10),
                                        ),
                                        style: const TextStyle(fontSize: 8, color: Colors.black),
                                        dropdownColor: Colors.white,
                                        icon: const Icon(Icons.arrow_drop_down, size: 14),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Flexible(
                                    flex: 1,
                                    child: SizedBox(
                                      height: 36,
                                      child: DropdownButtonFormField<String>(
                                        value: selectedStatus,
                                        items: statusOptions.map((status) {
                                          return DropdownMenuItem<String>(
                                            value: status,
                                            child: Text(
                                              status,
                                              style: const TextStyle(fontSize: 10),
                                            ),
                                          );
                                        }).toList(),
                                        onChanged: (val) {
                                          setState(() {
                                            selectedStatus = val!;
                                          });
                                        },
                                        decoration: InputDecoration(
                                          labelText: 'Status',
                                          labelStyle: const TextStyle(fontSize: 9),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(8),
                                            borderSide: BorderSide.none,
                                          ),
                                          filled: true,
                                          fillColor: const Color.fromARGB(255, 229, 237, 229),
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                        ),
                                        style: const TextStyle(fontSize: 10, color: Colors.black),
                                        dropdownColor: Colors.white,
                                        icon: const Icon(Icons.arrow_drop_down, size: 14),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                  Flexible(
                                    flex: 1,
                                    child: SizedBox(
                                      height: 36,
                                      child: DropdownButtonFormField<bool>(
                                        value: sortAscending,
                                        items: const [
                                          DropdownMenuItem(
                                            value: false,
                                            child: Text('Newest', style: TextStyle(fontSize: 10)),
                                          ),
                                          DropdownMenuItem(
                                            value: true,
                                            child: Text('Oldest', style: TextStyle(fontSize: 10)),
                                          ),
                                        ],
                                        onChanged: (val) {
                                          setState(() {
                                            sortAscending = val!;
                                          });
                                        },
                                        decoration: InputDecoration(
                                          labelText: 'Sort',
                                          labelStyle: const TextStyle(fontSize: 9),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(8),
                                            borderSide: BorderSide.none,
                                          ),
                                          filled: true,
                                          fillColor: const Color.fromARGB(255, 229, 237, 229),
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                        ),
                                        style: const TextStyle(fontSize: 10, color: Colors.black),
                                        dropdownColor: Colors.white,
                                        icon: const Icon(Icons.arrow_drop_down, size: 14),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              // --- USER FILTER DROPDOWN ---
                              Flexible(
                                flex: 1,
                                child: SizedBox(
                                  height: 36,
                                  child: DropdownButtonFormField<String>(
                                    value: selectedUser,
                                    items: [
                                      const DropdownMenuItem(
                                        value: null,
                                        child: Text('All Users', style: TextStyle(fontSize: 9)),
                                      ),
                                      ...availableUsers.map((user) => DropdownMenuItem(
                                            value: user['id'],
                                            child: Text(
                                              user['username'],
                                              style: const TextStyle(fontSize: 9),
                                            ),
                                          )),
                                    ],
                                    onChanged: (val) {
                                      setState(() {
                                        selectedUser = val;
                                      });
                                    },
                                    decoration: InputDecoration(
                                      labelText: 'User',
                                      labelStyle: const TextStyle(fontSize: 9),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide.none,
                                      ),
                                      filled: true,
                                      fillColor: const Color.fromARGB(255, 229, 237, 229),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 1, vertical: 10),
                                    ),
                                    style: const TextStyle(fontSize: 8, color: Colors.black),
                                    dropdownColor: Colors.white,
                                    icon: const Icon(Icons.arrow_drop_down, size: 14),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 2),
                              Flexible(
                                flex: 1,
                                child: SizedBox(
                                  height: 36,
                                  child: DropdownButtonFormField<String>(
                                    value: selectedStatus,
                                    items: statusOptions.map((status) {
                                      return DropdownMenuItem<String>(
                                        value: status,
                                        child: Text(
                                          status,
                                          style: const TextStyle(fontSize: 10),
                                        ),
                                      );
                                    }).toList(),
                                    onChanged: (val) {
                                      setState(() {
                                        selectedStatus = val!;
                                      });
                                    },
                                    decoration: InputDecoration(
                                      labelText: 'Status',
                                      labelStyle: const TextStyle(fontSize: 9),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide.none,
                                      ),
                                      filled: true,
                                      fillColor: const Color.fromARGB(255, 229, 237, 229),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                    ),
                                    style: const TextStyle(fontSize: 10, color: Colors.black),
                                    dropdownColor: Colors.white,
                                    icon: const Icon(Icons.arrow_drop_down, size: 14),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 2),
                              Flexible(
                                flex: 1,
                                child: SizedBox(
                                  height: 36,
                                  child: DropdownButtonFormField<bool>(
                                    value: sortAscending,
                                    items: const [
                                      DropdownMenuItem(
                                        value: false,
                                        child: Text('Newest', style: TextStyle(fontSize: 10)),
                                      ),
                                      DropdownMenuItem(
                                        value: true,
                                        child: Text('Oldest', style: TextStyle(fontSize: 10)),
                                      ),
                                    ],
                                    onChanged: (val) {
                                      setState(() {
                                        sortAscending = val!;
                                      });
                                    },
                                    decoration: InputDecoration(
                                      labelText: 'Sort',
                                      labelStyle: const TextStyle(fontSize: 9),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide.none,
                                      ),
                                      filled: true,
                                      fillColor: const Color.fromARGB(255, 229, 237, 229),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                    ),
                                    style: const TextStyle(fontSize: 10, color: Colors.black),
                                    dropdownColor: Colors.white,
                                    icon: const Icon(Icons.arrow_drop_down, size: 14),
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                  // --- LEADS LIST ---
                  Expanded(
                    child: role == 'manager'
                        ? FutureBuilder<QuerySnapshot>(
                            future: FirebaseFirestore.instance
                                .collection('users')
                                .where('branch', isEqualTo: managerBranch)
                                .get(),
                            builder: (context, usersSnapshot) {
                              if (!usersSnapshot.hasData) {
                                return const Center(child: CircularProgressIndicator());
                              }
                              final branchUserIds = usersSnapshot.data!.docs.map((doc) => doc.id).toSet();

                              return StreamBuilder<QuerySnapshot>(
                                stream: FirebaseFirestore.instance
                                    .collection('follow_ups')
                                    .where('branch', isEqualTo: widget.branch)
                                    .snapshots(),
                                builder: (context, snapshot) {
                                  if (snapshot.connectionState == ConnectionState.waiting) {
                                    return const Center(child: CircularProgressIndicator());
                                  }
                                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                                    return const Center(child: Text("No leads available."));
                                  }
                                  final allLeads = snapshot.data!.docs;

                                  // Show only leads created by users in the same branch
                                  final visibleLeads = allLeads.where((doc) {
                                    final data = doc.data() as Map<String, dynamic>;
                                    return branchUserIds.contains(data['created_by']);
                                  }).toList();

                                  // --- USER FILTER ---
                                  final userFilteredLeads = selectedUser == null
                                      ? visibleLeads
                                      : visibleLeads.where((doc) {
                                          final data = doc.data() as Map<String, dynamic>;
                                          return data['created_by'] == selectedUser;
                                        }).toList();

                                  final filteredLeads = userFilteredLeads.where((doc) {
                                    final data = doc.data() as Map<String, dynamic>;
                                    final name = (data['name'] ?? '').toString().toLowerCase();
                                    final status = (data['status'] ?? 'Unknown').toString();
                                    final priority = (data['priority'] ?? 'High').toString();
                                    final matchesSearch = name.contains(searchQuery);
                                    final matchesStatus = selectedStatus == 'All'
                                        || status == selectedStatus
                                        || priority == selectedStatus;
                                    return matchesSearch && matchesStatus;
                                  }).toList();

                                  // Add sorting here
                                  filteredLeads.sort((a, b) {
                                    final aData = a.data() as Map<String, dynamic>;
                                    final bData = b.data() as Map<String, dynamic>;
                                    final aDate = DateTime.tryParse(aData['date'] ?? '') ?? DateTime(2000);
                                    final bDate = DateTime.tryParse(bData['date'] ?? '') ?? DateTime(2000);
                                    return sortAscending
                                        ? aDate.compareTo(bDate)
                                        : bDate.compareTo(aDate);
                                  });

                                  if (filteredLeads.isEmpty) {
                                    return const Center(child: Text("No leads match your criteria."));
                                  }

                                  return ListView.builder(
                                    padding: const EdgeInsets.all(16),
                                    itemCount: filteredLeads.length,
                                    itemBuilder: (context, index) {
                                      final data = filteredLeads[index].data() as Map<String, dynamic>;
                                      final name = data['name'] ?? 'No Name';
                                      final status = data['status'] ?? 'Unknown';
                                      final date = data['date'] ?? 'No Date';
                                      final docId = filteredLeads[index].id;
                                      final reminder = data['reminder'] ?? 'No Reminder';
                                      final createdById = data['created_by'] ?? '';
                                      final priority = data['priority'] ?? 'High'; // <-- Add this

                                      return FutureBuilder<DocumentSnapshot>(
                                        future: FirebaseFirestore.instance.collection('users').doc(createdById).get(),
                                        builder: (context, userSnapshot) {
                                          String creatorUsername = 'Unknown';
                                          if (userSnapshot.connectionState == ConnectionState.done && userSnapshot.hasData) {
                                            final userData = userSnapshot.data!.data() as Map<String, dynamic>?;
                                            if (userData != null && userData['username'] != null) {
                                              creatorUsername = userData['username'];
                                            }
                                          }
                                          return LeadCard(
                                            name: name,
                                            status: status,
                                            date: date,
                                            docId: docId,
                                            createdBy: creatorUsername,
                                            reminder: reminder,
                                            priority: priority, // <-- Pass priority
                                          );
                                        },
                                      );
                                    },
                                  );
                                },
                              );
                            },
                          )
                        : role == 'admin'
                            ? StreamBuilder<QuerySnapshot>(
                                stream: branchToShow.isNotEmpty
                                    ? FirebaseFirestore.instance
                                        .collection('follow_ups')
                                        .where('branch', isEqualTo: branchToShow)
                                        .snapshots()
                                    : const Stream.empty(), // Prevent loading until branch selected
                                builder: (context, snapshot) {
                                  if (branchToShow.isEmpty) {
                                    return const Center(child: Text("Please select a branch."));
                                  }
                                  if (snapshot.connectionState == ConnectionState.waiting) {
                                    return const Center(child: CircularProgressIndicator());
                                  }
                                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                                    return const Center(child: Text("No leads available."));
                                  }
                                  final allLeads = snapshot.data!.docs;

                                  // --- USER FILTER ---
                                  final userFilteredLeads = selectedUser == null
                                      ? allLeads
                                      : allLeads.where((doc) {
                                          final data = doc.data() as Map<String, dynamic>;
                                          return data['created_by'] == selectedUser;
                                        }).toList();

                                  final filteredLeads = userFilteredLeads.where((doc) {
                                    final data = doc.data() as Map<String, dynamic>;
                                    final name = (data['name'] ?? '').toString().toLowerCase();
                                    final status = (data['status'] ?? 'Unknown').toString();
                                    final priority = (data['priority'] ?? 'High').toString();
                                    final matchesSearch = name.contains(searchQuery);
                                    final matchesStatus = selectedStatus == 'All'
                                        || status == selectedStatus
                                        || priority == selectedStatus;
                                    return matchesSearch && matchesStatus;
                                  }).toList();

                                  // Add sorting here
                                  filteredLeads.sort((a, b) {
                                    final aData = a.data() as Map<String, dynamic>;
                                    final bData = b.data() as Map<String, dynamic>;
                                    final aDate = DateTime.tryParse(aData['date'] ?? '') ?? DateTime(2000);
                                    final bDate = DateTime.tryParse(bData['date'] ?? '') ?? DateTime(2000);
                                    return sortAscending
                                        ? aDate.compareTo(bDate)
                                        : bDate.compareTo(aDate);
                                  });

                                  if (filteredLeads.isEmpty) {
                                    return const Center(child: Text("No leads match your criteria."));
                                  }

                                  return ListView.builder(
                                    padding: const EdgeInsets.all(16),
                                    itemCount: filteredLeads.length,
                                    itemBuilder: (context, index) {
                                      final data = filteredLeads[index].data() as Map<String, dynamic>;
                                      final name = data['name'] ?? 'No Name';
                                      final status = data['status'] ?? 'Unknown';
                                      final date = data['date'] ?? 'No Date';
                                      final docId = filteredLeads[index].id;
                                      final reminder = data['reminder'] ?? 'No Reminder';
                                      final createdById = data['created_by'] ?? '';

                                      return FutureBuilder<DocumentSnapshot>(
                                        future: FirebaseFirestore.instance.collection('users').doc(createdById).get(),
                                        builder: (context, userSnapshot) {
                                          String creatorUsername = 'Unknown';
                                          if (userSnapshot.connectionState == ConnectionState.done && userSnapshot.hasData) {
                                            final userData = userSnapshot.data!.data() as Map<String, dynamic>?;
                                            if (userData != null && userData['username'] != null) {
                                              creatorUsername = userData['username'];
                                            }
                                          }
                                          return LeadCard(
                                            name: name,
                                            status: status,
                                            date: date,
                                            docId: docId,
                                            reminder: reminder,
                                            createdBy: creatorUsername,
                                            priority: data['priority'] ?? 'High',
                                          );
                                        },
                                      );
                                    },
                                  );
                                },
                              )
                            : StreamBuilder<QuerySnapshot>(
                                stream: FirebaseFirestore.instance
                                    .collection('follow_ups')
                                    .where('branch', isEqualTo: widget.branch)
                                    .snapshots(),
                                builder: (context, snapshot) {
                                  if (snapshot.connectionState == ConnectionState.waiting) {
                                    return const Center(child: CircularProgressIndicator());
                                  }
                                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                                    return const Center(child: Text("No leads available."));
                                  }
                                  final allLeads = snapshot.data!.docs;

                                  // Only leads created by current sales user
                                  final visibleLeads = allLeads.where((doc) {
                                    final data = doc.data() as Map<String, dynamic>;
                                    return data['branch'] == widget.branch;
                                  }).toList();

                                  // --- USER FILTER ---
                                  final userFilteredLeads = selectedUser == null
                                      ? visibleLeads
                                      : visibleLeads.where((doc) {
                                          final data = doc.data() as Map<String, dynamic>;
                                          return data['created_by'] == selectedUser;
                                        }).toList();

                                  final filteredLeads = userFilteredLeads.where((doc) {
                                    final data = doc.data() as Map<String, dynamic>;
                                    final name = (data['name'] ?? '').toString().toLowerCase();
                                    final status = (data['status'] ?? 'Unknown').toString();
                                    final priority = (data['priority'] ?? 'High').toString();
                                    final matchesSearch = name.contains(searchQuery);
                                    final matchesStatus = selectedStatus == 'All'
                                        || status == selectedStatus
                                        || priority == selectedStatus;
                                    return matchesSearch && matchesStatus;
                                  }).toList();

                                  // Add sorting here
                                  filteredLeads.sort((a, b) {
                                    final aData = a.data() as Map<String, dynamic>;
                                    final bData = b.data() as Map<String, dynamic>;
                                    final aDate = DateTime.tryParse(aData['date'] ?? '') ?? DateTime(2000);
                                    final bDate = DateTime.tryParse(bData['date'] ?? '') ?? DateTime(2000);
                                    return sortAscending
                                        ? aDate.compareTo(bDate)
                                        : bDate.compareTo(aDate);
                                  });

                                  if (filteredLeads.isEmpty) {
                                    return const Center(child: Text("No leads match your criteria."));
                                  }

                                  return ListView.builder(
                                    padding: const EdgeInsets.all(16),
                                    itemCount: filteredLeads.length,
                                    itemBuilder: (context, index) {
                                      final data = filteredLeads[index].data() as Map<String, dynamic>;
                                      final name = data['name'] ?? 'No Name';
                                      final status = data['status'] ?? 'Unknown';
                                      final date = data['date'] ?? 'No Date';
                                      final docId = filteredLeads[index].id;
                                      final reminder = data['reminder'] ?? 'No Reminder';
                                      final createdById = data['created_by'] ?? '';

                                      return FutureBuilder<DocumentSnapshot>(
                                        future: FirebaseFirestore.instance.collection('users').doc(createdById).get(),
                                        builder: (context, userSnapshot) {
                                          String creatorUsername = 'Unknown';
                                          if (userSnapshot.connectionState == ConnectionState.done && userSnapshot.hasData) {
                                            final userData = userSnapshot.data!.data() as Map<String, dynamic>?;
                                            if (userData != null && userData['username'] != null) {
                                              creatorUsername = userData['username'];
                                            }
                                          }
                                          return LeadCard(
                                            name: name,
                                            status: status,
                                            date: date,
                                            docId: docId,
                                            reminder: reminder,
                                            createdBy: creatorUsername,
                                            priority: data['priority'] ?? 'High',
                                          );
                                        },
                                      );
                                    },
                                  );
                                },
                              ),
                  ),
                  // --- SEARCH BAR AT BOTTOM ---
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                    child: TextField(
                      onChanged: (val) {
                        setState(() {
                          searchQuery = val.toLowerCase();
                        });
                      },
                      decoration: InputDecoration(
                        hintText: 'Search by name...',
                        hintStyle: const TextStyle(color: Colors.green),
                        prefixIcon: const Icon(Icons.search, color: Colors.green),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                      ),
                      style: const TextStyle(color: Colors.green),
                    ),
                  ),
                ],
              ),
            ],
          ),
          floatingActionButton: MouseRegion(
            onEnter: (_) => _isHovering.value = true,
            onExit: (_) => _isHovering.value = false,
            cursor: SystemMouseCursors.click,
            child: ValueListenableBuilder<bool>(
              valueListenable: _isHovering,
              builder: (_, isHovered, child) {
                return Transform.scale(
                  scale: isHovered ? 1.15 : 1.0,
                  child: StatefulBuilder(
                    builder: (context, setState) {
                      Color buttonColor = isHovered ? const Color(0xFF77B72E) : const Color(0xFF8CC63F);

                      return FloatingActionButton(
                        backgroundColor: buttonColor,
                        elevation: isHovered ? 10 : 6,
                        child: const Icon(Icons.add),
                        onPressed: () {
                          setState(() {
                            buttonColor = const Color(0xFF005BAC);
                          });
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const FollowUpForm()),
                          );
                        },
                      );
                    },
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class LeadCard extends StatelessWidget {
  final String name;
  final String status;
  final String date;
  final String docId;
  final String createdBy;
  final String priority;
  final String reminder;

  const LeadCard({
    super.key,
    required this.name,
    required this.status,
    required this.date,
    required this.docId,
    required this.createdBy,
    required this.priority,
    required this.reminder,
  });

  Color getPriorityColor(String priority) {
    switch (priority) {
      case 'High':
        return Colors.red;
      case 'Medium':
        return Colors.amber;
      case 'Low':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  Color getPriorityBackgroundColor(String priority, bool isDark) {
    if (isDark) {
      switch (priority) {
        case 'High':
          return const Color(0xFF3B2323); // Dark red shade
        case 'Medium':
          return const Color(0xFF39321A); // Dark amber shade
        case 'Low':
          return const Color(0xFF1B3223); // Dark green shade
        default:
          return Colors.grey.shade800;
      }
    } else {
      switch (priority) {
        case 'High':
          return const Color(0xFFFFEBEE); // Light red
        case 'Medium':
          return const Color(0xFFFFF8E1); // Light amber/yellow
        case 'Low':
          return const Color(0xFFE8F5E9); // Light green
        default:
          return Colors.grey.shade100;
      }
    }
  }

  Future<void> _playClickSound() async {
    final player = AudioPlayer();
    await player.play(AssetSource('sounds/click.mp3'), volume: 0.5);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    String formattedDate = date;
    try {
      if (date.isNotEmpty) {
        final parsedDate = DateTime.parse(date);
        formattedDate = DateFormat('dd-MM-yyyy').format(parsedDate);
      }
    } catch (e) {
      // Keep original date string if parsing fails
    }

    String formattedReminder = reminder;
    try {
      if (reminder.isNotEmpty && reminder != 'No Reminder') {
        // Assuming reminder format is 'YYYY-MM-DD ...'
        final datePart = reminder.split(' ')[0];
        final parsedReminderDate = DateTime.parse(datePart);
        formattedReminder = DateFormat('dd-MM-yyyy').format(parsedReminderDate);
      }
    } catch (e) {
      // Keep original reminder string if parsing fails
    }

    return Slidable(
      key: ValueKey(docId),
      startActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.28,
        children: [
          SlidableAction(
            onPressed: (context) async {
              String newStatus = status == 'In Progress' ? 'Completed' : 'In Progress';
              await FirebaseFirestore.instance
                  .collection('follow_ups')
                  .doc(docId)
                  .update({'status': newStatus});
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Status changed to $newStatus')),
              );
            },
            backgroundColor: status == 'In Progress'
                ? Colors.green.shade400
                : Colors.orange.shade400,
            foregroundColor: Colors.white,
            icon: status == 'In Progress' ? Icons.check_circle : Icons.refresh,
            label: status == 'In Progress' ? 'Completed' : 'In Progress',
            borderRadius: BorderRadius.circular(20),
          ),
        ],
      ),
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.25,
        children: [
          SlidableAction(
            onPressed: (context) async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Delete Lead?'),
                  content: const Text('Are you sure you want to delete this lead? This action cannot be undone.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: Text('Delete', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                // Get lead data before deleting
                final docSnap = await FirebaseFirestore.instance.collection('follow_ups').doc(docId).get();
                final data = docSnap.data();
                String? userEmail = data?['userEmail'] ?? data?['email'];
                final userId = data?['created_by'];
                final timestamp = data?['created_at'] ?? data?['timestamp'];
                // Fallback: fetch user email from users collection if missing
                if (userEmail == null && userId != null) {
                  final userDoc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
                  userEmail = userDoc.data()?['email'];
                }
                if (userEmail != null && timestamp != null) {
                  final date = (timestamp is Timestamp) ? timestamp.toDate() : DateTime.tryParse(timestamp.toString());
                  final now = DateTime.now();
                  if (date == null) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Error: Invalid lead date.')),
                      );
                    }
                    return;
                  }
                  final dateStr = "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
                  await FirebaseFirestore.instance.collection('follow_ups').doc(docId).delete();

                  // Only update daily_report if deleted within 24 hours of creation
                  
                  
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Lead deleted')),
                    );
                  }
                } else {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Error: Could not delete lead. Missing user or date.')),
                    );
                  }
                }
              }
            },
            backgroundColor: Colors.red.shade400,
            foregroundColor: Colors.white,
            icon: Icons.delete,
            label: 'Delete',
            borderRadius: BorderRadius.circular(20),
          ),
        ],
      ),
      child: GestureDetector(
        onTap: () async {
          await _playClickSound();
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PresentFollowUp(docId: docId),
            ),
          );
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: getPriorityBackgroundColor(priority, isDark), // <-- Use isDark
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: theme.shadowColor.withOpacity(isDark ? 0.2 : 0.05),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              // Priority dot
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: getPriorityColor(priority),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      text: TextSpan(
                        style: theme.textTheme.bodyLarge?.copyWith(fontSize: 16),
                        children: [
                          TextSpan(
                            text: name,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const TextSpan(text: ' '),
                          TextSpan(
                            text: '($status)',
                            style: TextStyle(color: theme.hintColor),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Date: $formattedDate',
                      style: theme.textTheme.bodySmall?.copyWith(fontSize: 13, color: theme.hintColor),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Created by: $createdBy',
                      style: theme.textTheme.bodySmall?.copyWith(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Reminder: $formattedReminder',
                      style: theme.textTheme.bodySmall?.copyWith(fontSize: 12, color: Colors.blueGrey),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
