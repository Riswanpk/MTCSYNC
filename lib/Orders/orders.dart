import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../Navigation/user_cache_service.dart';
import 'orders_form.dart';
import 'orders_widgets.dart';

class OrdersPage extends StatefulWidget {
  final String branch;

  const OrdersPage({super.key, required this.branch});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  String searchQuery = '';
  String selectedStatus = 'All';
  String? selectedBranch;
  String? selectedUser;
  bool _isSearching = false;
  bool _isLoading = false;
  List<DocumentSnapshot> _orders = [];
  List<String> availableBranches = [];
  List<Map<String, dynamic>> availableUsers = [];
  Timer? _searchDebounce;

  final Map<String, String> _creatorUsernameCache = {};

  late Future<Map<String, dynamic>?> _currentUserData;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _currentUserData = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get()
          .then((doc) => doc.data());
    } else {
      _currentUserData = Future.value(null);
    }
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
    final role = userData?['role'] ?? 'sales';
    final branch = userData?['branch'] ?? widget.branch;

    if (!mounted) return;

    setState(() {
      if (role == 'admin' || role == 'sync_head' || role == 'Sync Head') {
        selectedBranch = selectedBranch;
      } else {
        selectedBranch = branch;
        selectedUser = uid;
      }
      selectedStatus = 'In Progress';
    });

    if (role == 'manager' || role == 'asst_manager') {
      await _fetchUsers(branch, uid);
    }

    await _fetchOrders();
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
        .map((doc) => {
              'id': doc.id,
              'username': (doc.data() as Map<String, dynamic>)['username'] ?? 'Unknown',
            })
        .toList();

    if (ensureUserId != null && !users.any((u) => u['id'] == ensureUserId)) {
      final doc = await FirebaseFirestore.instance.collection('users').doc(ensureUserId).get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>?;
        users.insert(0, {
          'id': doc.id,
          'username': data?['username'] ?? 'You',
        });
      }
    }

    if (!mounted) return;
    setState(() => availableUsers = users);
  }

  Future<void> _fetchOrders() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    final userData = await _currentUserData;
    final role = userData?['role'] ?? 'sales';

    String? branch;
    if (role == 'admin' || role == 'sync_head' || role == 'Sync Head') {
      branch = selectedBranch;
    } else {
      branch = userData?['branch'] ?? widget.branch;
    }

    if (branch == null || branch.isEmpty) {
      if (!mounted) return;
      setState(() {
        _orders = [];
        _isLoading = false;
      });
      return;
    }

    Query query = FirebaseFirestore.instance
        .collection('follow_ups')
        .where('branch', isEqualTo: branch)
        .where('lead_type', isEqualTo: 'order_confirmed');

    if (selectedUser != null) {
      query = query.where(
        Filter.or(
          Filter('created_by', isEqualTo: selectedUser),
          Filter('assigned_to', isEqualTo: selectedUser),
        ),
      );
    }

    if (selectedStatus != 'All') {
      query = query.where('status', isEqualTo: selectedStatus);
    }

    query = query.orderBy('created_at', descending: true);

    final snapshot = await query.get();

    if (!mounted) return;
    setState(() {
      _orders = snapshot.docs;
      _isLoading = false;
    });

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

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _currentUserData,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final userData = snapshot.data!;
        final role = userData['role'] ?? 'sales';
        final isAdminLike = role == 'admin' || role == 'sync_head' || role == 'Sync Head';
        final isManagerLike = role == 'manager' || role == 'asst_manager';

        return Scaffold(
          appBar: AppBar(
            title: _isSearching
                ? TextField(
                    autofocus: true,
                    style: const TextStyle(color: Colors.white),
                    cursorColor: Colors.white,
                    decoration: const InputDecoration(
                      hintText: 'Search by customer name...',
                      hintStyle: TextStyle(color: Colors.white70),
                      border: InputBorder.none,
                    ),
                    onChanged: (value) {
                      setState(() => searchQuery = value.trim().toLowerCase());
                      _searchDebounce?.cancel();
                      _searchDebounce = Timer(const Duration(milliseconds: 300), () {
                        if (mounted) setState(() {});
                      });
                    },
                  )
                : const Text('Confirmed Orders'),
            backgroundColor: const Color(0xFF005BAC),
            foregroundColor: Colors.white,
            actions: [
              IconButton(
                icon: Icon(_isSearching ? Icons.close : Icons.search),
                onPressed: () {
                  setState(() {
                    _isSearching = !_isSearching;
                    if (!_isSearching) searchQuery = '';
                  });
                },
              ),
            ],
          ),
          body: Stack(
            children: [
              Center(
                child: Opacity(
                  opacity: 0.05,
                  child: Image.asset('assets/images/logo.png', width: 240),
                ),
              ),
              Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      children: [
                        if (isAdminLike)
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: selectedBranch,
                                  hint: const Text('Select Branch'),
                                  items: availableBranches
                                      .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                                      .toList(),
                                  onChanged: (value) {
                                    setState(() {
                                      selectedBranch = value;
                                      selectedUser = null;
                                    });
                                    if (value != null) {
                                      _fetchUsers(value).then((_) => _fetchOrders());
                                    } else {
                                      _fetchOrders();
                                    }
                                  },
                                  decoration: InputDecoration(
                                    labelText: 'Branch',
                                    filled: true,
                                    fillColor: const Color.fromARGB(255, 229, 237, 229),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: selectedUser,
                                  items: [
                                    const DropdownMenuItem(value: null, child: Text('All Users')),
                                    ...availableUsers.map((u) => DropdownMenuItem(value: u['id'], child: Text(u['username']))),
                                  ],
                                  onChanged: (value) {
                                    setState(() => selectedUser = value);
                                    _fetchOrders();
                                  },
                                  decoration: InputDecoration(
                                    labelText: 'User',
                                    filled: true,
                                    fillColor: const Color.fromARGB(255, 229, 237, 229),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        if (isManagerLike)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: DropdownButtonFormField<String>(
                              value: selectedUser,
                              items: [
                                const DropdownMenuItem(value: null, child: Text('All Users')),
                                ...availableUsers.map((u) => DropdownMenuItem(value: u['id'], child: Text(u['username']))),
                              ],
                              onChanged: (value) {
                                setState(() => selectedUser = value);
                                _fetchOrders();
                              },
                              decoration: InputDecoration(
                                labelText: 'User',
                                filled: true,
                                fillColor: const Color.fromARGB(255, 229, 237, 229),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                          ),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: selectedStatus,
                                items: const [
                                  DropdownMenuItem(value: 'All', child: Text('All')),
                                  DropdownMenuItem(value: 'In Progress', child: Text('In Progress')),
                                  DropdownMenuItem(value: 'Completed', child: Text('Completed')),
                                ],
                                onChanged: (value) {
                                  if (value == null) return;
                                  setState(() => selectedStatus = value);
                                  _fetchOrders();
                                },
                                decoration: InputDecoration(
                                  labelText: 'Status',
                                  filled: true,
                                  fillColor: const Color.fromARGB(255, 229, 237, 229),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : _orders.isEmpty
                            ? const Center(child: Text('No confirmed orders found.'))
                            : ListView.builder(
                                padding: const EdgeInsets.all(16),
                                itemCount: _orders.length,
                                itemBuilder: (context, index) {
                                  final doc = _orders[index];
                                  final data = doc.data() as Map<String, dynamic>;

                                  final name = (data['name'] ?? 'No Name').toString();
                                  if (searchQuery.isNotEmpty &&
                                      !name.toLowerCase().contains(searchQuery)) {
                                    return const SizedBox.shrink();
                                  }

                                  final createdBy = _creatorUsernameCache[(data['created_by'] ?? '').toString()] ?? '';

                                  return OrderCard(
                                    name: name,
                                    status: (data['status'] ?? 'In Progress').toString(),
                                    createdAt: data['date'] ?? data['created_at'],
                                    docId: doc.id,
                                    createdBy: createdBy,
                                    priority: (data['priority'] ?? 'High').toString(),
                                    deliveryDate: data['delivery_datetime'] ?? data['delivery_date'],
                                    onStatusChanged: _fetchOrders,
                                    onDelete: () async {
                                      await FirebaseFirestore.instance
                                          .collection('follow_ups')
                                          .doc(doc.id)
                                          .delete();
                                      await _fetchOrders();
                                    },
                                  );
                                },
                              ),
                  ),
                ],
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            backgroundColor: const Color(0xFF8CC63F),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const OrderFormPage()),
              ).then((_) => _fetchOrders());
            },
            child: const Icon(Icons.add),
          ),
        );
      },
    );
  }
}
