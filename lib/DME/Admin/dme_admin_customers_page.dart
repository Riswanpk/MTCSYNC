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

  List<Map<String, dynamic>> _allCustomers = [];
  List<int> _assignedBranches = [];

  // Filter selections
  int? _selectedBranchId; // null = All allowed
  int? _selectedCategoryId; // null = All
  int? _selectedTypeId; // null = All
  String _sortBy = 'recent'; // 'recent', 'name_asc', 'name_desc'

  SupabaseClient? get _supabaseClient {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _initBranchAccess();
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
    await _fetchCustomersDirectory();
  }

  @override
  void dispose() {
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

  Future<void> _fetchCustomersDirectory() async {
    final client = _supabaseClient;
    if (client == null || !DmeConfig.isConfigured) {
      setState(() => _isLoading = false);
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Query customers with their branches, categories, types junctions
      final response = await client
          .from('dme_customers')
          .select('id, name, phone, address, salesman, last_purchase_date, created_at, dme_customer_branches(branch_id, category_id, customer_type_id)')
          .order('last_purchase_date', ascending: false);

      final List data = response as List;
      List<Map<String, dynamic>> customers = [];

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

        // If user is restricted to specific assigned branches, ensure customer has activity in at least one assigned branch
        if (_assignedBranches.isNotEmpty && !branchIds.any((bId) => _assignedBranches.contains(bId))) {
          continue;
        }

        cust['branch_ids'] = branchIds;
        cust['category_ids'] = categoryIds;
        cust['type_ids'] = typeIds;
        customers.add(cust);
      }

      setState(() {
        _allCustomers = customers;
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

  List<Map<String, dynamic>> _getFilteredCustomers() {
    return _allCustomers.where((c) {
      // 1. Search Query
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final name = (c['name'] ?? '').toString().toLowerCase();
        final phone = (c['phone'] ?? '').toString().toLowerCase();
        final address = (c['address'] ?? '').toString().toLowerCase();
        final salesman = (c['salesman'] ?? '').toString().toLowerCase();
        if (!name.contains(q) && !phone.contains(q) && !address.contains(q) && !salesman.contains(q)) {
          return false;
        }
      }

      // 2. Branch Filter
      if (_selectedBranchId != null) {
        final List<int> bIds = (c['branch_ids'] as List<int>?) ?? [];
        if (!bIds.contains(_selectedBranchId)) return false;
      }

      // 3. Category Filter
      if (_selectedCategoryId != null) {
        final List<int> catIds = (c['category_ids'] as List<int>?) ?? [];
        if (!catIds.contains(_selectedCategoryId)) return false;
      }

      // 4. Customer Type Filter
      if (_selectedTypeId != null) {
        final List<int> tIds = (c['type_ids'] as List<int>?) ?? [];
        if (!tIds.contains(_selectedTypeId)) return false;
      }

      return true;
    }).toList()
      ..sort((a, b) {
        if (_sortBy == 'name_asc') {
          return (a['name'] ?? '').toString().toLowerCase().compareTo((b['name'] ?? '').toString().toLowerCase());
        } else if (_sortBy == 'name_desc') {
          return (b['name'] ?? '').toString().toLowerCase().compareTo((a['name'] ?? '').toString().toLowerCase());
        } else {
          // recent purchase date
          final dateA = a['last_purchase_date']?.toString() ?? '';
          final dateB = b['last_purchase_date']?.toString() ?? '';
          return dateB.compareTo(dateA);
        }
      });
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
                            setState(() {});
                          },
                          child: const Text('Reset All'),
                        ),
                      ],
                    ),
                    const Divider(),

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
                          setState(() {});
                          Navigator.pop(ctx);
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
    final filtered = _getFilteredCustomers();

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
            onPressed: _fetchCustomersDirectory,
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
                              setState(() => _searchQuery = '');
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
                  onChanged: (val) => setState(() => _searchQuery = val.trim()),
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
                              onDeleted: () => setState(() => _selectedBranchId = null),
                            ),
                          ),
                        if (_selectedCategoryId != null)
                          Padding(
                            padding: const EdgeInsets.only(right: 6.0),
                            child: Chip(
                              label: Text('Category: ${DmeConstants.getCategoryName(_selectedCategoryId)}', style: const TextStyle(fontSize: 11)),
                              deleteIcon: const Icon(Icons.close, size: 14),
                              onDeleted: () => setState(() => _selectedCategoryId = null),
                            ),
                          ),
                        if (_selectedTypeId != null)
                          Padding(
                            padding: const EdgeInsets.only(right: 6.0),
                            child: Chip(
                              label: Text('Type: ${DmeConstants.getCustomerTypeName(_selectedTypeId)}', style: const TextStyle(fontSize: 11)),
                              deleteIcon: const Icon(Icons.close, size: 14),
                              onDeleted: () => setState(() => _selectedTypeId = null),
                            ),
                          ),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _selectedBranchId = null;
                              _selectedCategoryId = null;
                              _selectedTypeId = null;
                              _sortBy = 'recent';
                            });
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
                  '${filtered.length} Customer(s) Found',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey),
                ),
                Text(
                  'Total Directory: ${_allCustomers.length}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),

          // List View
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
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
                        onRefresh: _fetchCustomersDirectory,
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final c = filtered[index];
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
