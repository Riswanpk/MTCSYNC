import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

import '../dme_constants.dart';
import '../dme_config.dart';
import 'dme_admin_customer_detail_page.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class DmeAdminCustomersPage extends StatefulWidget {
  final List<int>? userAssignedBranches;

  const DmeAdminCustomersPage({
    super.key,
    this.userAssignedBranches,
  });

  @override
  State<DmeAdminCustomersPage> createState() => _DmeAdminCustomersPageState();
}

class _DmeAdminCustomersPageState extends State<DmeAdminCustomersPage> {
  bool _isLoading = true;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  final ScrollController _scrollController = ScrollController();
  List<Map<String, dynamic>> _customers = [];
  List<int> _assignedBranches = [];

  // Filter selections
  int? _selectedBranchId; // null = All allowed
  int? _selectedCategoryId; // null = All
  int? _selectedTypeId; // null = All
  String _sortBy = 'recent'; // 'recent', 'name_asc', 'name_desc'

  // Pagination state
  int _currentOffset = 0;
  static const int _pageSize = 30;
  bool _hasMore = true;
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _initBranchAccess();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoading && !_isLoadingMore && _hasMore) {
        _fetchMoreCustomers();
      }
    }
  }

  Future<void> _initBranchAccess() async {
    if (widget.userAssignedBranches != null) {
      _assignedBranches = widget.userAssignedBranches!;
    } else {
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
          final data = doc.data();
          final role = data?['role']?.toString();
          if (role == 'dme_user' && data?['assigned_branches'] is List) {
            _assignedBranches = (data!['assigned_branches'] as List)
                .map((e) => int.tryParse(e.toString()) ?? 0)
                .where((e) => e > 0)
                .toList();
          }
        }
      } catch (e) {
        debugPrint('Error loading user assigned branches: $e');
      }
    }
    await _fetchCustomersDirectory(reset: true);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  String _formatDate(dynamic date) {
    if (date == null) return 'N/A';
    if (date is DateTime) {
      return DateFormat('dd-MM-yyyy').format(date);
    }
    final str = date.toString().trim();
    if (str.isEmpty) return 'N/A';
    final parsed = DateTime.tryParse(str);
    if (parsed != null) {
      return DateFormat('dd-MM-yyyy').format(parsed);
    }
    return str;
  }

  Future<void> _fetchCustomersDirectory({bool reset = false}) async {
    final client = await DmeConfig.getClient();
    if (client == null) {
      setState(() => _isLoading = false);
      return;
    }

    if (reset) {
      setState(() {
        _isLoading = true;
        _currentOffset = 0;
        _hasMore = true;
        _customers.clear();
      });
    }

    try {
      // 1. If branch, category, or type filters are active, query customer IDs matching junction criteria
      List<int>? filteredCustomerIds;
      final needsJunctionFilter = _selectedBranchId != null ||
          _selectedCategoryId != null ||
          _selectedTypeId != null ||
          _assignedBranches.isNotEmpty;

      if (needsJunctionFilter) {
        var junctionQuery = client.from('dme_customer_branches').select('customer_id');

        if (_selectedBranchId != null) {
          junctionQuery = junctionQuery.eq('branch_id', _selectedBranchId!);
        } else if (_assignedBranches.isNotEmpty) {
          junctionQuery = junctionQuery.inFilter('branch_id', _assignedBranches);
        }

        if (_selectedCategoryId != null) {
          junctionQuery = junctionQuery.eq('category_id', _selectedCategoryId!);
        }

        if (_selectedTypeId != null) {
          junctionQuery = junctionQuery.eq('customer_type_id', _selectedTypeId!);
        }

        final junctionRes = await junctionQuery;
        final Set<int> matchedCustIds = {};
        for (var row in (junctionRes as List)) {
          final cId = row['customer_id'] as int?;
          if (cId != null) matchedCustIds.add(cId);
        }
        filteredCustomerIds = matchedCustIds.toList();

        if (filteredCustomerIds.isEmpty) {
          setState(() {
            _customers = [];
            _hasMore = false;
            _isLoading = false;
          });
          return;
        }
      }

      // 2. Query dme_customers
      dynamic query = client
          .from('dme_customers')
          .select('id, name, phone, address, salesman, last_purchase_date, created_at, dme_customer_branches(branch_id, category_id, customer_type_id)');

      if (filteredCustomerIds != null) {
        query = query.inFilter('id', filteredCustomerIds);
      }

      // Search Query
      if (_searchQuery.trim().isNotEmpty) {
        final q = _searchQuery.trim();
        query = query.or('name.ilike.%$q%,phone.ilike.%$q%,salesman.ilike.%$q%,address.ilike.%$q%');
      }

      // Order
      if (_sortBy == 'name_asc') {
        query = query.order('name', ascending: true);
      } else if (_sortBy == 'name_desc') {
        query = query.order('name', ascending: false);
      } else {
        query = query.order('last_purchase_date', ascending: false, nullsFirst: false);
      }

      final response = await query.range(0, _pageSize - 1);
      final List data = response as List;

      List<Map<String, dynamic>> parsedList = _parseCustomerRows(data);

      setState(() {
        _customers = parsedList;
        _currentOffset = data.length;
        _hasMore = data.length >= _pageSize;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading customers directory: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading customers: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _fetchMoreCustomers() async {
    final client = await DmeConfig.getClient();
    if (client == null || _isLoadingMore || !_hasMore) return;

    setState(() => _isLoadingMore = true);

    try {
      List<int>? filteredCustomerIds;
      final needsJunctionFilter = _selectedBranchId != null ||
          _selectedCategoryId != null ||
          _selectedTypeId != null ||
          _assignedBranches.isNotEmpty;

      if (needsJunctionFilter) {
        var junctionQuery = client.from('dme_customer_branches').select('customer_id');

        if (_selectedBranchId != null) {
          junctionQuery = junctionQuery.eq('branch_id', _selectedBranchId!);
        } else if (_assignedBranches.isNotEmpty) {
          junctionQuery = junctionQuery.inFilter('branch_id', _assignedBranches);
        }

        if (_selectedCategoryId != null) {
          junctionQuery = junctionQuery.eq('category_id', _selectedCategoryId!);
        }

        if (_selectedTypeId != null) {
          junctionQuery = junctionQuery.eq('customer_type_id', _selectedTypeId!);
        }

        final junctionRes = await junctionQuery;
        final Set<int> matchedCustIds = {};
        for (var row in (junctionRes as List)) {
          final cId = row['customer_id'] as int?;
          if (cId != null) matchedCustIds.add(cId);
        }
        filteredCustomerIds = matchedCustIds.toList();

        if (filteredCustomerIds.isEmpty) {
          setState(() {
            _hasMore = false;
            _isLoadingMore = false;
          });
          return;
        }
      }

      dynamic query = client
          .from('dme_customers')
          .select('id, name, phone, address, salesman, last_purchase_date, created_at, dme_customer_branches(branch_id, category_id, customer_type_id)');

      if (filteredCustomerIds != null) {
        query = query.inFilter('id', filteredCustomerIds);
      }

      if (_searchQuery.trim().isNotEmpty) {
        final q = _searchQuery.trim();
        query = query.or('name.ilike.%$q%,phone.ilike.%$q%,salesman.ilike.%$q%,address.ilike.%$q%');
      }

      if (_sortBy == 'name_asc') {
        query = query.order('name', ascending: true);
      } else if (_sortBy == 'name_desc') {
        query = query.order('name', ascending: false);
      } else {
        query = query.order('last_purchase_date', ascending: false, nullsFirst: false);
      }

      final response = await query.range(_currentOffset, _currentOffset + _pageSize - 1);
      final List data = response as List;

      List<Map<String, dynamic>> parsedList = _parseCustomerRows(data);

      setState(() {
        _customers.addAll(parsedList);
        _currentOffset += data.length;
        _hasMore = data.length >= _pageSize;
        _isLoadingMore = false;
      });
    } catch (e) {
      debugPrint('Error fetching more customers: $e');
      setState(() => _isLoadingMore = false);
    }
  }

  List<Map<String, dynamic>> _parseCustomerRows(List data) {
    List<Map<String, dynamic>> result = [];
    for (var item in data) {
      final cust = Map<String, dynamic>.from(item);
      final branchList = cust['dme_customer_branches'] as List?;

      List<int> branchIds = [];
      List<int> categoryIds = [];
      List<int> typeIds = [];

      if (branchList != null) {
        for (var b in branchList) {
          final bId = b['branch_id'] as int?;
          final catId = b['category_id'] as int?;
          final tId = b['customer_type_id'] as int?;
          if (bId != null && !branchIds.contains(bId)) branchIds.add(bId);
          if (catId != null && !categoryIds.contains(catId)) categoryIds.add(catId);
          if (tId != null && !typeIds.contains(tId)) typeIds.add(tId);
        }
      }

      // If user restricted to assigned branches
      if (_assignedBranches.isNotEmpty && !branchIds.any((bId) => _assignedBranches.contains(bId))) {
        continue;
      }

      // Check category & type filters if selected
      if (_selectedBranchId != null && !branchIds.contains(_selectedBranchId)) continue;
      if (_selectedCategoryId != null && !categoryIds.contains(_selectedCategoryId)) continue;
      if (_selectedTypeId != null && !typeIds.contains(_selectedTypeId)) continue;

      cust['branch_ids'] = branchIds;
      cust['category_ids'] = categoryIds;
      cust['type_ids'] = typeIds;
      result.add(cust);
    }
    return result;
  }

  void _openFilterBottomSheet() {
    final availableBranches = _assignedBranches.isNotEmpty
        ? DmeConstants.branches.where((b) => _assignedBranches.contains(b.id)).toList()
        : DmeConstants.branches;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                top: 20,
                left: 20,
                right: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Filter Directory',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                        TextButton(
                          onPressed: () {
                            setModalState(() {
                              _selectedBranchId = null;
                              _selectedCategoryId = null;
                              _selectedTypeId = null;
                              _sortBy = 'recent';
                            });
                            _fetchCustomersDirectory(reset: true);
                          },
                          child: const Text('Reset All'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Branch Filter (respects assigned branches)
                    const Text('Branch', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.withValues(alpha: 0.4)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int?>(
                          value: _selectedBranchId,
                          isExpanded: true,
                          items: [
                            const DropdownMenuItem<int?>(value: null, child: Text('All Allowed Branches')),
                            ...availableBranches.map((b) {
                              return DropdownMenuItem<int?>(value: b.id, child: Text(b.name));
                            }),
                          ],
                          onChanged: (val) => setModalState(() => _selectedBranchId = val),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Category Filter
                    const Text('Category', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.withValues(alpha: 0.4)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int?>(
                          value: _selectedCategoryId,
                          isExpanded: true,
                          items: [
                            const DropdownMenuItem<int?>(value: null, child: Text('All Categories')),
                            ...DmeConstants.categories.map((c) {
                              return DropdownMenuItem<int?>(value: c.id, child: Text(c.name));
                            }),
                          ],
                          onChanged: (val) => setModalState(() => _selectedCategoryId = val),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Customer Type Filter
                    const Text('Customer Type', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.withValues(alpha: 0.4)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int?>(
                          value: _selectedTypeId,
                          isExpanded: true,
                          items: [
                            const DropdownMenuItem<int?>(value: null, child: Text('All Customer Types')),
                            ...DmeConstants.customerTypes.map((t) {
                              return DropdownMenuItem<int?>(value: t.id, child: Text(t.name));
                            }),
                          ],
                          onChanged: (val) => setModalState(() => _selectedTypeId = val),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Sort By
                    const Text('Sort By', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('Recent Purchase', style: TextStyle(fontSize: 12)),
                          selected: _sortBy == 'recent',
                          onSelected: (_) => setModalState(() => _sortBy = 'recent'),
                        ),
                        ChoiceChip(
                          label: const Text('Name (A-Z)', style: TextStyle(fontSize: 12)),
                          selected: _sortBy == 'name_asc',
                          onSelected: (_) => setModalState(() => _sortBy = 'name_asc'),
                        ),
                        ChoiceChip(
                          label: const Text('Name (Z-A)', style: TextStyle(fontSize: 12)),
                          selected: _sortBy == 'name_desc',
                          onSelected: (_) => setModalState(() => _sortBy = 'name_desc'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Apply Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF005BAC),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _fetchCustomersDirectory(reset: true);
                        },
                        child: const Text('Apply Filters', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final hasActiveFilter = _selectedBranchId != null || _selectedCategoryId != null || _selectedTypeId != null || _sortBy != 'recent';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer Directory'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Badge(
              isLabelVisible: hasActiveFilter,
              child: const Icon(Icons.tune_rounded),
            ),
            tooltip: 'Filter Directory',
            onPressed: _openFilterBottomSheet,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Reload',
            onPressed: () => _fetchCustomersDirectory(reset: true),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Box & Active Filter Chips
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[900] : Colors.grey[100],
              border: Border(bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.2))),
            ),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search by customer name, phone, address, salesman...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              _searchQuery = '';
                              _fetchCustomersDirectory(reset: true);
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: isDark ? Colors.grey[850] : Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  onChanged: (val) {
                    _searchQuery = val.trim();
                    _fetchCustomersDirectory(reset: true);
                  },
                ),
                if (hasActiveFilter) ...[
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        if (_selectedBranchId != null)
                          Padding(
                            padding: const EdgeInsets.only(right: 6.0),
                            child: Chip(
                              label: Text('Branch: ${DmeConstants.getBranchName(_selectedBranchId)}', style: const TextStyle(fontSize: 11)),
                              deleteIcon: const Icon(Icons.close, size: 14),
                              onDeleted: () {
                                _selectedBranchId = null;
                                _fetchCustomersDirectory(reset: true);
                              },
                            ),
                          ),
                        if (_selectedCategoryId != null)
                          Padding(
                            padding: const EdgeInsets.only(right: 6.0),
                            child: Chip(
                              label: Text('Category: ${DmeConstants.getCategoryName(_selectedCategoryId)}', style: const TextStyle(fontSize: 11)),
                              deleteIcon: const Icon(Icons.close, size: 14),
                              onDeleted: () {
                                _selectedCategoryId = null;
                                _fetchCustomersDirectory(reset: true);
                              },
                            ),
                          ),
                        if (_selectedTypeId != null)
                          Padding(
                            padding: const EdgeInsets.only(right: 6.0),
                            child: Chip(
                              label: Text('Type: ${DmeConstants.getCustomerTypeName(_selectedTypeId)}', style: const TextStyle(fontSize: 11)),
                              deleteIcon: const Icon(Icons.close, size: 14),
                              onDeleted: () {
                                _selectedTypeId = null;
                                _fetchCustomersDirectory(reset: true);
                              },
                            ),
                          ),
                        TextButton(
                          onPressed: () {
                            _selectedBranchId = null;
                            _selectedCategoryId = null;
                            _selectedTypeId = null;
                            _sortBy = 'recent';
                            _fetchCustomersDirectory(reset: true);
                          },
                          child: const Text('Clear Filters', style: TextStyle(fontSize: 11)),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Customer List Header Stats
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_customers.length} Customer(s) Loaded',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey),
                ),
                if (_hasMore)
                  const Text(
                    'Scroll down for more...',
                    style: TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic),
                  ),
              ],
            ),
          ),

          // List View
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _customers.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.person_search_rounded, size: 56, color: Colors.grey[400]),
                            const SizedBox(height: 12),
                            Text(
                              'No customers match the criteria',
                              style: TextStyle(color: Colors.grey[600], fontSize: 15, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () => _fetchCustomersDirectory(reset: true),
                        child: ListView.separated(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          itemCount: _customers.length + (_isLoadingMore ? 1 : 0),
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            if (index == _customers.length) {
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(12.0),
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            }
                            final c = _customers[index];
                            final name = c['name'] ?? 'Unnamed Customer';
                            final phone = c['phone'] ?? 'N/A';
                            final address = c['address'] ?? '';
                            final lastDate = c['last_purchase_date'];
                            final branchIds = (c['branch_ids'] as List<int>?) ?? [];
                            final categoryIds = (c['category_ids'] as List<int>?) ?? [];

                            return Card(
                              elevation: 2,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => DmeAdminCustomerDetailPage(customer: c),
                                    ),
                                  );
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(14.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          CircleAvatar(
                                            radius: 22,
                                            backgroundColor: const Color(0xFF005BAC).withValues(alpha: 0.1),
                                            foregroundColor: const Color(0xFF005BAC),
                                            child: const Icon(Icons.business_rounded, size: 22),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  name,
                                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  'Mobile: $phone',
                                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                                                ),
                                                if (address.isNotEmpty) ...[
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    address,
                                                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                          const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey),
                                        ],
                                      ),
                                      const Divider(height: 16),

                                      // Branches & Categories Badges
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Wrap(
                                              spacing: 4,
                                              runSpacing: 4,
                                              children: [
                                                ...branchIds.map((bId) {
                                                  return Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFF005BAC).withValues(alpha: 0.1),
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: Text(
                                                      DmeConstants.getBranchName(bId),
                                                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF005BAC)),
                                                    ),
                                                  );
                                                }),
                                                ...categoryIds.take(2).map((catId) {
                                                  return Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: Colors.grey.withValues(alpha: 0.15),
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: Text(
                                                      DmeConstants.getCategoryName(catId),
                                                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Colors.grey[800]),
                                                    ),
                                                  );
                                                }),
                                              ],
                                            ),
                                          ),
                                          Text(
                                            'Last: ${_formatDate(lastDate)}',
                                            style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w500),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
