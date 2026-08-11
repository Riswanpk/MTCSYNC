import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'leadsform.dart';
import 'leads_widgets.dart';
import 'customer_list.dart'; 
import '../Navigation/user_cache_service.dart';
import 'components/leads_filter_header.dart';
import 'components/leads_pagination_footer.dart';
import 'components/auto_reschedule_service.dart';

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
  String? selectedUser;
  List<String> availableBranches = [];
  bool _isSearching = false;
  List<Map<String, dynamic>> availableUsers = [];
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
  ];

  final List<String> sourceOptions = [
    'All',
    'Sales',
    'DME',
    'CC',
    'SME',
  ];

  bool sortAscending = false;
  String selectedPriority = 'All';
  String selectedSource = 'All';

  Timer? _searchDebounce;
  final Map<String, String> _creatorUsernameCache = {};

  List<DocumentSnapshot> _leads = [];
  DocumentSnapshot? _lastDocument;
  bool _isLoading = false;
  int _currentPage = 1;
  final int _leadsPerPage = 15;
  final Map<int, DocumentSnapshot?> _pageStartCursors = {1: null};

  late Future<Map<String, dynamic>?> _currentUserData;

  @override
  void initState() {
    super.initState();
    _currentUserData = UserCacheService.instance.ensureLoaded().then((_) {
      return {
        'role': UserCacheService.instance.role,
        'branch': UserCacheService.instance.branch,
        'username': UserCacheService.instance.username,
      };
    });
    _initialize();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
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
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final userData = await _currentUserData;
      if (userData != null) {
        final branch = userData['branch'] ?? '';
        await autoRescheduleLeads(uid, branch);
      }
    });
  }

  void _applyDefaultFiltersAndFetch(String role, String branch, String? uid) {
    if (!mounted) return;
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
    _fetchLeadsPage();
  }

  Future<void> _fetchBranches() async {
    final branches = await UserCacheService.instance.getBranches();
    if (!mounted) return;
    setState(() {
      availableBranches = branches;
    });
  }

  Future<void> _fetchUsers([String? branch, String? ensureUserId]) async {
    Query query = FirebaseFirestore.instance.collection('users');
    if (branch != null && branch.isNotEmpty) {
      query = query.where('branch', isEqualTo: branch);
    }
    final snapshot = await query.get();
    final users = snapshot.docs
        .map((doc) {
          final data = doc.data() as Map<String, dynamic>?;
          return {
            'id': doc.id,
            'username': data?['username'] ?? 'Unknown'
          };
        })
        .toList();

    if (ensureUserId != null && !users.any((u) => u['id'] == ensureUserId)) {
      final doc = await FirebaseFirestore.instance.collection('users').doc(ensureUserId).get();
      if (doc.exists) {
        final d = doc.data();
        users.insert(0, {
          'id': doc.id,
          'username': d?['username'] ?? 'You',
        });
      }
    }

    if (!mounted) return;
    setState(() {
      availableUsers = users;
    });
  }

  Future<void> _fetchLeadsPage({bool nextPage = false, bool prevPage = false, bool isSearch = false, bool isRefresh = false}) async {
    if (!mounted) return;
    if (_isLoading) return;
    if (!isRefresh) {
      setState(() {
        _isLoading = true;
      });
    }

    final userData = await _currentUserData;
    final role = userData?['role'] ?? 'sales';
    final branch = (role == 'admin' || role == 'Sync Head' || role == 'sync_head') ? selectedBranch : userData?['branch'];

    if (branch == null || branch.isEmpty) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _leads = [];
      });
      return;
    }

    Query query = FirebaseFirestore.instance.collection('follow_ups').where('branch', isEqualTo: branch);

    if (selectedUser != null) {
      query = query.where(
        Filter.or(
          Filter('created_by', isEqualTo: selectedUser),
          Filter('assigned_to', isEqualTo: selectedUser),
          Filter('screened_by', isEqualTo: selectedUser),
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
    if (selectedPriority != 'All') {
      query = query.where('priority', isEqualTo: selectedPriority);
    }
    if (selectedSource != 'All') {
      query = query.where('source', whereIn: [selectedSource, selectedSource.toLowerCase()]);
    }

    query = query.orderBy('created_at', descending: !sortAscending);

    try {
      QuerySnapshot snapshot;

      if (isSearch && searchQuery.isNotEmpty) {
        snapshot = await query.get();
      } else {
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
        if (!isSearch || searchQuery.isEmpty) {
          _lastDocument = snapshot.docs.last;
          _pageStartCursors[_currentPage + 1] = _lastDocument;
        } else {
          _lastDocument = null;
        }
      } else {
        _lastDocument = null;
      }

      if (!mounted) return;
      setState(() {
        _leads = snapshot.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final screening = data['screening_status']?.toString().toLowerCase();
          return screening == null || screening == 'promoted';
        }).toList();
        _isLoading = false;
      });

      await _prefetchCreatorUsernames(snapshot.docs);
    } catch (e, stack) {
      debugPrint('Error fetching leads in leads.dart: $e\n$stack');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _leads = [];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading leads: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 8),
        ),
      );
    }
  }

  Future<void> _prefetchCreatorUsernames(List<DocumentSnapshot> docs) async {
    final ids = docs
        .map((d) => (d.data() as Map<String, dynamic>)['created_by'] as String?)
        .whereType<String>()
        .where((id) => id.isNotEmpty && !_creatorUsernameCache.containsKey(id))
        .toSet()
        .toList();
    if (ids.isEmpty) return;

    for (var i = 0; i < ids.length; i += 30) {
      final batch = ids.sublist(i, i + 30 > ids.length ? ids.length : i + 30);
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where(FieldPath.documentId, whereIn: batch)
          .get();
      final map = <String, String>{};
      for (final doc in snap.docs) {
        final username =
            doc.data()['username'] as String? ?? 'Unknown';
        map[doc.id] = username;
      }
      if (mounted) {
        setState(() => _creatorUsernameCache.addAll(map));
      }
    }
  }

  Future<void> _handleRefresh() async {
    setState(() {
      _pageStartCursors.clear();
      _pageStartCursors[1] = null;
      _currentPage = 1;
      _lastDocument = null;
    });
    await _fetchLeadsPage(isRefresh: true);
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
        final role = userData['role'] ?? 'sales';

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
                      _fetchLeadsPage(isSearch: true);
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
                const DrawerHeader(
                  decoration: BoxDecoration(
                    color: Color(0xFF005BAC),
                  ),
                  child: Text(
                    'Menu',
                    style: TextStyle(color: Colors.white, fontSize: 24),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.people_outline),
                  title: const Text('Customer List'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const CustomerListPage()),
                    );
                  },
                ),
              ],
            ),
          ),
          body: Stack(
            children: [
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
                  LeadsFilterHeader(
                    role: role,
                    selectedBranch: selectedBranch,
                    availableBranches: availableBranches,
                    onBranchChanged: (val) {
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
                    selectedUser: selectedUser,
                    availableUsers: availableUsers,
                    onUserChanged: (val) {
                      setState(() {
                        selectedUser = val;
                        _pageStartCursors.clear();
                        _pageStartCursors[1] = null;
                        _currentPage = 1;
                      });
                      _fetchLeadsPage();
                    },
                    selectedStatus: selectedStatus,
                    statusOptions: statusOptions,
                    onStatusChanged: (val) {
                      setState(() {
                        selectedStatus = val!;
                        _pageStartCursors.clear();
                        _pageStartCursors[1] = null;
                        _currentPage = 1;
                      });
                      _fetchLeadsPage();
                    },
                    selectedPriority: selectedPriority,
                    priorityOptions: priorityOptions,
                    onPriorityChanged: (val) {
                      setState(() {
                        selectedPriority = val!;
                        _pageStartCursors.clear();
                        _pageStartCursors[1] = null;
                        _currentPage = 1;
                      });
                      _fetchLeadsPage();
                    },
                    sortAscending: sortAscending,
                    onSortChanged: (val) {
                      setState(() {
                        sortAscending = val!;
                        _pageStartCursors.clear();
                        _pageStartCursors[1] = null;
                        _currentPage = 1;
                      });
                      _fetchLeadsPage();
                    },
                    selectedSource: selectedSource,
                    sourceOptions: sourceOptions,
                    onSourceChanged: (val) {
                      setState(() {
                        selectedSource = val!;
                        _pageStartCursors.clear();
                        _pageStartCursors[1] = null;
                        _currentPage = 1;
                      });
                      _fetchLeadsPage();
                    },
                  ),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _handleRefresh,
                      child: _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : _leads.isEmpty
                              ? ListView(
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  children: const [
                                    SizedBox(height: 100),
                                    Center(child: Text("No leads match your criteria.")),
                                  ],
                                )
                              : ListView.builder(
                                  physics: const AlwaysScrollableScrollPhysics(),
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
                  ),
                  LeadsPaginationFooter(
                    isLoading: _isLoading,
                    searchQuery: searchQuery,
                    currentPage: _currentPage,
                    canGoBack: _currentPage > 1,
                    canGoNext: _lastDocument != null && _leads.length == _leadsPerPage,
                    onPreviousPressed: () => _fetchLeadsPage(prevPage: true),
                    onNextPressed: () => _fetchLeadsPage(nextPage: true),
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
