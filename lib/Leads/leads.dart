import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'dart:math';
import 'leadsform.dart';
import 'leads_widgets.dart';
import 'customer_list.dart'; 
import '../Navigation/user_cache_service.dart';

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
    'Sold',
    'Cancelled',
  ];

  final List<String> priorityOptions = [
    'All',
    'High',
    'Medium',
    'Low',
    'SME Only',
  ];

  // Add this for sort order
  bool sortAscending = false;
  String selectedPriority = 'All';

  Timer? _searchDebounce;
  Map<String, String> _creatorUsernameCache = {};

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
        final isAdminLike = role == 'admin' || role == 'sync_head' || role == 'Sync Head';
        if (!isAdminLike) {
          if (role == 'manager' || role == 'asst_manager') {
            await _fetchUsers(branch, uid);
          }
          _applyDefaultFiltersAndFetch(role, branch, uid);
        }
      }
    }
    // Auto-reschedule current user's leads
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final userData = await _currentUserData;
      if (userData != null) {
        final branch = userData['branch'] ?? '';
        await autoRescheduleLeads(uid, branch);
      }
    });
  }

  void _applyDefaultFiltersAndFetch(String role, String branch, String? uid) {
    final isAdminLike = role == 'admin' || role == 'sync_head' || role == 'Sync Head';
    if (!isAdminLike) {
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
    final branches = await UserCacheService.instance.getBranches();
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
    final branch = (role == 'admin' || role == 'Sync Head' || role == 'sync_head') ? selectedBranch : userData?['branch'];

    if (branch == null || branch.isEmpty) {
      setState(() {
        _isLoading = false;
        _leads = [];
      });
      return;
    }

    Query query = FirebaseFirestore.instance.collection('follow_ups').where('branch', isEqualTo: branch);

    // Apply filters — always applied, including during search
    if (selectedUser != null) {
      // Include leads created by OR assigned to the selected user
      query = query.where(
        Filter.or(
          Filter('created_by', isEqualTo: selectedUser),
          Filter('assigned_to', isEqualTo: selectedUser),
        ),
      );
    }
    if (selectedStatus != 'All') {
      if (selectedStatus == 'Sold') {
        query = query.where('status', isEqualTo: 'Sale');
      } else if (selectedStatus == 'Cancelled') {
        query = query.where('status', isEqualTo: 'Cancelled');
      } else if (selectedStatus == 'In Progress') {
        query = query.where('status', isEqualTo: 'In Progress');
      }
    }
    if (selectedPriority == 'SME Only') {
      query = query.where('source', isEqualTo: 'sme');
    } else if (selectedPriority != 'All') {
      query = query.where('priority', isEqualTo: selectedPriority);
    }

    // Apply sorting
    query = query.orderBy('created_at', descending: !sortAscending);

    QuerySnapshot snapshot;

    if (isSearch && searchQuery.isNotEmpty) {
      // For search, fetch all matching documents and filter locally by name
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

    // Batch-fetch creator usernames to avoid N+1 reads in itemBuilder
    await _prefetchCreatorUsernames(snapshot.docs);
  }

  Future<void> _prefetchCreatorUsernames(List<DocumentSnapshot> docs) async {
    final ids = docs
        .map((d) => (d.data() as Map<String, dynamic>)['created_by'] as String?)
        .whereType<String>()
        .where((id) => id.isNotEmpty && !_creatorUsernameCache.containsKey(id))
        .toSet()
        .toList();
    if (ids.isEmpty) return;

    // Fetch in batches of 30 (Firestore whereIn limit)
    for (var i = 0; i < ids.length; i += 30) {
      final batch = ids.sublist(i, i + 30 > ids.length ? ids.length : i + 30);
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where(FieldPath.documentId, whereIn: batch)
          .get();
      final map = <String, String>{};
      for (final doc in snap.docs) {
        final username =
            (doc.data() as Map<String, dynamic>)['username'] as String? ?? 'Unknown';
        map[doc.id] = username;
      }
      if (mounted) {
        setState(() => _creatorUsernameCache.addAll(map));
      }
    }
  }

  Future<void> autoRescheduleLeads(String? currentUserId, String? branch) async {
    if (currentUserId == null || branch == null || branch.isEmpty) return;

    final now = DateTime.now();

    try {
      // Fetch only this user's "In Progress" leads server-side to avoid downloading the entire branch
      final createdByQuery = await FirebaseFirestore.instance
          .collection('follow_ups')
          .where('branch', isEqualTo: branch)
          .where('status', isEqualTo: 'In Progress')
          .where('created_by', isEqualTo: currentUserId)
          .get();

      final assignedToQuery = await FirebaseFirestore.instance
          .collection('follow_ups')
          .where('branch', isEqualTo: branch)
          .where('status', isEqualTo: 'In Progress')
          .where('assigned_to', isEqualTo: currentUserId)
          .get();

      // Merge and deduplicate by document ID
      final seenIds = <String>{};
      final allDocs = [
        ...createdByQuery.docs,
        ...assignedToQuery.docs,
      ].where((doc) => seenIds.add(doc.id)).toList();

      for (final doc in allDocs) {
        final data = doc.data();

        // Check if reminder should be rescheduled
        final reminderDateChanged = data['reminder_date_changed'] as bool? ?? false;
        if (reminderDateChanged) continue; // Skip if manually changed

        final originalReminderDate = data['original_reminder_date'];
        if (originalReminderDate == null) continue; // Skip if no original date

        final originalDate = (originalReminderDate is Timestamp)
            ? originalReminderDate.toDate()
            : DateTime.tryParse(originalReminderDate.toString());

        if (originalDate == null) continue;

        // Check if the reminder has been past for more than 2 days without a status change
        if (originalDate.isBefore(now.subtract(const Duration(days: 2)))) {
          // Reschedule 7 days ahead of the original reminder date
          final rescheduledDate = originalDate.add(const Duration(days: 7));

          final newReminderText =
              DateFormat('dd-MM-yyyy hh:mm a').format(rescheduledDate);

          // Update the follow-up document
          await doc.reference.update({
            'reminder': newReminderText,
            'original_reminder_date': Timestamp.fromDate(rescheduledDate),
            // Don't set reminder_date_changed to true since this is auto-reschedule
          });

          debugPrint(
              'Auto-rescheduled lead ${doc.id} from ${DateFormat('dd-MM-yyyy').format(originalDate)} to ${DateFormat('dd-MM-yyyy').format(rescheduledDate)}');
        }
      }
    } catch (e) {
      debugPrint('Error in autoRescheduleLeads: $e');
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
        final branchToShow = (role == 'admin' || role == 'Sync Head' || role == 'sync_head') ? selectedBranch ?? '' : widget.branch;

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
                      _searchDebounce?.cancel();
                      _searchDebounce = Timer(const Duration(milliseconds: 400), () {
                        _fetchLeadsPage(isSearch: true);
                      });
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
                    child: (role == 'admin' || role == 'Sync Head' || role == 'sync_head')
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
                                      child: DropdownButtonFormField<String>(
                                        value: selectedPriority,
                                        items: priorityOptions.map((priority) {
                                          return DropdownMenuItem<String>(
                                            value: priority,
                                            child: Text(
                                              priority,
                                              style: const TextStyle(fontSize: 10),
                                            ),
                                          );
                                        }).toList(),
                                        onChanged: (val) {
                                          setState(() {
                                            selectedPriority = val!;
                                            _pageStartCursors.clear();
                                            _pageStartCursors[1] = null;
                                            _currentPage = 1;
                                          });
                                          _fetchLeadsPage();
                                        },
                                        decoration: InputDecoration(
                                          labelText: 'Priority',
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
                        : (role == 'manager' || role == 'asst_manager')
                            ? Column(
                                children: [
                                  Row(
                                    children: [
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
                                            value: selectedPriority,
                                            items: priorityOptions.map((priority) {
                                              return DropdownMenuItem<String>(
                                                value: priority,
                                                child: Text(
                                                  priority,
                                                  style: const TextStyle(fontSize: 10),
                                                ),
                                              );
                                            }).toList(),
                                            onChanged: (val) {
                                              setState(() {
                                                selectedPriority = val!;
                                                _pageStartCursors.clear();
                                                _pageStartCursors[1] = null;
                                                _currentPage = 1;
                                              });
                                              _fetchLeadsPage();
                                            },
                                            decoration: InputDecoration(
                                              labelText: 'Priority',
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
                            : Column(
                            children: [
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
                                      child: DropdownButtonFormField<String>(
                                        value: selectedPriority,
                                        items: priorityOptions.map((priority) {
                                          return DropdownMenuItem<String>(
                                            value: priority,
                                            child: Text(
                                              priority,
                                              style: const TextStyle(fontSize: 10),
                                            ),
                                          );
                                        }).toList(),
                                        onChanged: (val) {
                                          setState(() {
                                            selectedPriority = val!;
                                            _pageStartCursors.clear();
                                            _pageStartCursors[1] = null;
                                            _currentPage = 1;
                                          });
                                          _fetchLeadsPage();
                                        },
                                        decoration: InputDecoration(
                                          labelText: 'Priority',
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
                                  final source = data['source'] as String?;

                                  // Client-side search filtering
                                  if (searchQuery.isNotEmpty &&
                                      !name.toLowerCase().contains(searchQuery)) {
                                    return const SizedBox.shrink();
                                  }

                                  final creatorUsername =
                                      _creatorUsernameCache[createdById] ?? '';

                                  return LeadCard(
                                    name: name,
                                    status: status,
                                    date: date,
                                    docId: docId,
                                    createdBy: creatorUsername,
                                    reminder: reminder,
                                    priority: priority,
                                    source: source,
                                    onStatusChanged: () => _fetchLeadsPage(),
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


