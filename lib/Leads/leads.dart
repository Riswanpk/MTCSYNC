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
import 'customer_list.dart'; 


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
  bool _isSearching = false;
  List<Map<String, dynamic>> availableUsers = []; // <-- NEW: list of users for dropdown
  final ValueNotifier<bool> _isHovering = ValueNotifier(false);

  final List<String> statusOptions = [
    'All',
    'In Progress',
    'Sale',
    'Closed',
    'High',
    'Medium',
    'Low',
  ];

  // Add this for sort order
  bool sortAscending = false;

  // --- NEW: State for Pagination ---
  List<DocumentSnapshot> _leads = [];
  DocumentSnapshot? _lastDocument; // Cursor for the next page
  bool _isLoading = false;
  int _currentPage = 1;
  final int _leadsPerPage = 15; // Number of leads per page
  final Map<int, DocumentSnapshot?> _pageStartCursors = {1: null}; // To enable "Previous"

  late Future<Map<String, dynamic>?> _currentUserData;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    _currentUserData = FirebaseFirestore.instance.collection('users').doc(uid).get().then((doc) => doc.data());
    _initialize();
  }

  Future<void> _initialize() async {
    await _fetchBranches();
    final userData = await _currentUserData;
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (mounted) {
      if (userData != null) {
        final role = userData['role'] ?? 'sales';
        final branch = userData['branch'] ?? '';
        if (role != 'admin') {
          await _fetchUsers(branch, uid);
          _applyDefaultFiltersAndFetch(role, branch, uid);
        }
      }
    }
    // Auto delete completed leads at end of month
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final userData = await _currentUserData;
      if (userData != null) {
        await autoDeleteCompletedLeads(userData['branch'] ?? '');
      }
    });
  }

  void _applyDefaultFiltersAndFetch(String role, String branch, String? uid) {
    if (role != 'admin') {
      setState(() {
        selectedBranch = branch;
        if (uid != null) {
          selectedUser = uid;
        }
        selectedStatus = 'In Progress';
        sortAscending = false;
      });
    }
    // Initial fetch
    _fetchLeadsPage();
  }

  Future<void> _fetchBranches() async {
    final snapshot = await FirebaseFirestore.instance.collection('users').get();
    final branches = snapshot.docs
        .map((doc) => doc.data()['branch'] as String?)
        .where((branch) => branch != null)
        .toSet()
        .cast<String>()
        .toList()
      ..sort();
    setState(() {
      availableBranches = branches;
      // Do not auto-select a branch or load leads here
      // selectedBranch remains null until user selects
    });
  }

  // NEW: Fetch users for filter dropdown
  Future<void> _fetchUsers([String? branch, String? ensureUserId]) async {
    Query query = FirebaseFirestore.instance.collection('users');
    if (branch != null && branch.isNotEmpty) {
      query = query.where('branch', isEqualTo: branch);
    }
    final snapshot = await query.get();
    final users = snapshot.docs
        .map((doc) => {
              'id': doc.id,
              'username': (doc.data() as Map<String, dynamic>)['username'] ?? 'Unknown'
            })
        .toList();

    // If we need to ensure a specific user (current user) appears in the list,
    // and they weren't returned by the branch-limited query, fetch and insert them.
    if (ensureUserId != null && !users.any((u) => u['id'] == ensureUserId)) {
      final doc = await FirebaseFirestore.instance.collection('users').doc(ensureUserId).get();
      if (doc.exists) {
        final d = doc.data() as Map<String, dynamic>?;
        users.insert(0, {
          'id': doc.id,
          'username': d?['username'] ?? 'You',
        });
      }
    }

    setState(() {
      availableUsers = users;
    });
  }

  // --- NEW: Pagination Logic ---
  Future<void> _fetchLeadsPage({bool nextPage = false, bool prevPage = false, bool isSearch = false}) async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
    });

    final userData = await _currentUserData;
    final role = userData?['role'] ?? 'sales';
    final branch = role == 'admin' ? selectedBranch : userData?['branch'];

    if (branch == null || branch.isEmpty) {
      setState(() {
        _isLoading = false;
        _leads = [];
      });
      return;
    }

    Query query = FirebaseFirestore.instance.collection('follow_ups').where('branch', isEqualTo: branch);

    // If searching, we will do a client-side filter after fetching all data for the branch.
    if (isSearch && searchQuery.isNotEmpty) {
      // No server-side filters when searching, except for branch
    } else {

    // Apply filters
    if (selectedUser != null) {
      query = query.where('created_by', isEqualTo: selectedUser);
    }
    if (selectedStatus != 'All') {
      if (['In Progress', 'Sale', 'Closed'].contains(selectedStatus)) {
        query = query.where('status', isEqualTo: selectedStatus);
      } else {
        query = query.where('priority', isEqualTo: selectedStatus);
      }
    }
    }

    // Apply sorting
    query = query.orderBy('created_at', descending: !sortAscending);

    QuerySnapshot snapshot;

    if (isSearch && searchQuery.isNotEmpty) {
      // For search, fetch all documents for the branch and filter locally
      snapshot = await query.get();
    } else {
      // For normal browsing, use pagination
      DocumentSnapshot? cursor;
      if (nextPage) {
        cursor = _lastDocument;
        _currentPage++;
      } else if (prevPage) {
        if (_currentPage > 1) {
          _currentPage--;
        }
        cursor = _pageStartCursors[_currentPage];
      }

      if (cursor != null) {
        query = query.startAfterDocument(cursor);
      }

      snapshot = await query.limit(_leadsPerPage).get();
    }

    if (snapshot.docs.isNotEmpty) {
      // Only update pagination cursors if not in search mode
      if (!isSearch || searchQuery.isEmpty) {
        _lastDocument = snapshot.docs.last;
        _pageStartCursors[_currentPage + 1] = _lastDocument;
      } else {
        _lastDocument = null;
      }
    } else {
      _lastDocument = null;
    }

    setState(() {
      _leads = snapshot.docs;
      _isLoading = false;
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
      for (final closedStatus in ['Sale', 'Closed']) {
        final query = await FirebaseFirestore.instance
            .collection('follow_ups')
            .where('branch', isEqualTo: branch)
            .where('status', isEqualTo: closedStatus)
            .get();
        for (final doc in query.docs) {
          await doc.reference.delete();
        }
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
            title: _isSearching
                ? TextField(
                    autofocus: true,
                    style: const TextStyle(color: Colors.white),
                    cursorColor: Colors.white,
                    decoration: const InputDecoration(
                      hintText: 'Search by name...',
                      hintStyle: TextStyle(color: Colors.white54),
                      border: InputBorder.none,
                    ),
                    onChanged: (val) {
                      String trimmedVal = val.toLowerCase().trim();
                      setState(() {
                        searchQuery = trimmedVal;
                      });
                      _fetchLeadsPage(isSearch: true);
                    },
                  )
                : const Text('Leads Follow Up'),
            backgroundColor: const Color(0xFF005BAC),
            foregroundColor: Colors.white,
            actions: [
              IconButton(
                icon: Icon(_isSearching ? Icons.close : Icons.search),
                tooltip: 'Search',
                onPressed: () {
                  setState(() {
                    _isSearching = !_isSearching;
                    if (!_isSearching) {
                      searchQuery = '';
                      _fetchLeadsPage(isSearch: true); // Refresh list
                    }
                  });
                },
              ),
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
                                            _pageStartCursors.clear();
                                            _pageStartCursors[1] = null;
                                            _currentPage = 1;
                                            availableUsers = [];
                                            _leads = [];
                                            _lastDocument = null;
                                          });
                                          if (val != null) {
                                            _fetchUsers(val).then((_) => _fetchLeadsPage());
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
                                            _pageStartCursors.clear();
                                            _pageStartCursors[1] = null;
                                           _currentPage = 1;
                                          });
                                          _fetchLeadsPage();
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
                                            _pageStartCursors.clear();
                                            _pageStartCursors[1] = null;
                                           _currentPage = 1;
                                          });
                                          _fetchLeadsPage();
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
                                            _pageStartCursors.clear();
                                            _pageStartCursors[1] = null;
                                           _currentPage = 1;
                                          });
                                          _fetchLeadsPage();
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
                                        _pageStartCursors.clear();
                                        _pageStartCursors[1] = null;
                                       _currentPage = 1;
                                      });
                                      _fetchLeadsPage();
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
                                        _pageStartCursors.clear();
                                        _pageStartCursors[1] = null;
                                       _currentPage = 1;
                                      });
                                      _fetchLeadsPage();
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
                                        _pageStartCursors.clear();
                                        _pageStartCursors[1] = null;
                                       _currentPage = 1;
                                      });
                                      _fetchLeadsPage();
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
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : _leads.isEmpty
                            ? const Center(child: Text("No leads match your criteria."))
                            : ListView.builder(
                                padding: const EdgeInsets.all(16),
                                itemCount: _leads.length,
                                itemBuilder: (context, index) {
                                  final doc = _leads[index];
                                  final data = doc.data() as Map<String, dynamic>;
                                  final name = data['name'] ?? 'No Name';
                                  final status = data['status'] ?? 'Unknown';
                                  final date = data['date'] ?? 'No Date';
                                  final docId = doc.id;
                                  final reminder = data['reminder'] ?? 'No Reminder';
                                  final createdById = data['created_by'] ?? '';
                                  final priority = data['priority'] ?? 'High';

                                  // Client-side search filtering
                                  if (searchQuery.isNotEmpty &&
                                      !name.toLowerCase().contains(searchQuery)) {
                                    return const SizedBox.shrink();
                                  }

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
                                        priority: priority,
                                      );
                                    },
                                  );
                                },
                              ),
                  ),
                  // --- SEARCH BAR AT BOTTOM ---
                  // --- NEW: Pagination Controls ---
                  if (!_isLoading && searchQuery.isEmpty) // Hide pagination when searching
                    Padding( 
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back),
                            onPressed: _currentPage > 1
                                ? () => _fetchLeadsPage(prevPage: true)
                                : null,
                          ),
                          Text('$_currentPage', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          IconButton(
                            icon: const Icon(Icons.arrow_forward),
                            onPressed: _lastDocument != null && _leads.length == _leadsPerPage
                                ? () => _fetchLeadsPage(nextPage: true) : null,
                          ),
                        ],
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
  final dynamic date;
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

    String formattedDate = '';
    DateTime? parsedDate;
    if (date is Timestamp) { // Handle Firestore Timestamp
      parsedDate = date.toDate();
    } else if (date is DateTime) { // Handle DateTime object
      parsedDate = date;
    } else if (date is String && date.isNotEmpty) { // Handle String
      try {
        // Try parsing as ISO first, fallback to dd-MM-yyyy
        try {
          parsedDate = DateTime.parse(date);
        } catch (_) {
          parsedDate = DateFormat('dd-MM-yyyy').parse(date);
        }
      } catch (e) {
        parsedDate = null;
      }
    }

    if (parsedDate != null) {
      formattedDate = DateFormat('dd-MM-yyyy').format(parsedDate);
    } else {
      formattedDate = 'No Date';
    }

    String formattedReminder = reminder;
    try {
      if (reminder.isNotEmpty && reminder != 'No Reminder') {
        // Try parsing reminder as date
        DateTime? reminderDate;
        try {
          reminderDate = DateTime.parse(reminder.split(' ')[0]);
        } catch (_) {
          final parts = reminder.split(' ');
          if (parts.isNotEmpty) {
            reminderDate = DateFormat('dd-MM-yyyy').parse(parts[0]);
          }
        }
        if (reminderDate != null) {
          formattedReminder = DateFormat('dd-MM-yyyy').format(reminderDate);
        }
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
              await FirebaseFirestore.instance
                  .collection('follow_ups')
                  .doc(docId)
                  .update({
                'status': 'Sale',
                'completed_at': FieldValue.serverTimestamp(),
              });
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Marked as Sale')),
                );
              }
            },
            backgroundColor: Colors.green.shade500,
            foregroundColor: Colors.white,
            icon: Icons.handshake_rounded,
            label: 'Sale',
            borderRadius: BorderRadius.circular(20),
          ),
        ],
      ),
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.28,
        children: [
          SlidableAction(
            onPressed: (context) async {
              await FirebaseFirestore.instance
                  .collection('follow_ups')
                  .doc(docId)
                  .update({
                'status': 'Closed',
                'completed_at': FieldValue.serverTimestamp(),
              });
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Marked as Closed')),
                );
              }
            },
            backgroundColor: Colors.red.shade400,
            foregroundColor: Colors.white,
            icon: Icons.cancel_rounded,
            label: 'Closed',
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
