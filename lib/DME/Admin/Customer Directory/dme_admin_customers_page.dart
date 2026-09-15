import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../dme_constants.dart';
import '../../dme_config.dart';
import 'dme_admin_customer_detail_page.dart';

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
  bool _isLoading = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebouncer;

  final ScrollController _scrollController = ScrollController();
  List<Map<String, dynamic>> _customers = [];

  // Pagination state
  int _currentOffset = 0;
  static const int _pageSize = 30;
  bool _hasMore = false;
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoading && !_isLoadingMore && _hasMore && _searchQuery.isNotEmpty) {
        _fetchMoreCustomers();
      }
    }
  }

  @override
  void dispose() {
    _searchDebouncer?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String val) {
    _searchDebouncer?.cancel();
    final newQuery = val.trim();
    if (newQuery.isEmpty) {
      setState(() {
        _searchQuery = '';
        _customers = [];
        _isLoading = false;
        _hasMore = false;
        _isLoadingMore = false;
      });
      return;
    }

    _searchDebouncer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) {
        _searchQuery = newQuery;
        _fetchCustomersDirectory(reset: true);
      }
    });
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
    final q = _searchQuery.trim();
    if (q.isEmpty) {
      if (mounted) {
        setState(() {
          _customers = [];
          _isLoading = false;
          _hasMore = false;
          _isLoadingMore = false;
        });
      }
      return;
    }

    final client = await DmeConfig.getClient();
    if (!mounted) return;
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
      final response = await client
          .from('dme_customers')
          .select(
              'id, name, phone, address, salesman, last_purchase_date, created_at, primary_branch, dme_customer_branches(branch_id, category_id, customer_type_id)')
          .or('name.ilike.%$q%,phone.ilike.%$q%,salesman.ilike.%$q%,address.ilike.%$q%')
          .order('last_purchase_date', ascending: false, nullsFirst: false)
          .range(0, _pageSize - 1);

      if (!mounted) return;

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
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading customers: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _fetchMoreCustomers() async {
    final q = _searchQuery.trim();
    if (q.isEmpty) return;

    final client = await DmeConfig.getClient();
    if (!mounted || client == null || _isLoadingMore || !_hasMore) return;

    setState(() => _isLoadingMore = true);

    try {
      final response = await client
          .from('dme_customers')
          .select(
              'id, name, phone, address, salesman, last_purchase_date, created_at, primary_branch, dme_customer_branches(branch_id, category_id, customer_type_id)')
          .or('name.ilike.%$q%,phone.ilike.%$q%,salesman.ilike.%$q%,address.ilike.%$q%')
          .order('last_purchase_date', ascending: false, nullsFirst: false)
          .range(_currentOffset, _currentOffset + _pageSize - 1);

      if (!mounted) return;

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
      if (!mounted) return;
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

      cust['branch_ids'] = branchIds;
      cust['category_ids'] = categoryIds;
      cust['type_ids'] = typeIds;
      result.add(cust);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer Directory'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
        actions: [
          if (_searchQuery.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Reload',
              onPressed: () => _fetchCustomersDirectory(reset: true),
            ),
        ],
      ),
      body: Column(
        children: [
          // Search Box
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[900] : Colors.grey[100],
              border: Border(bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.2))),
            ),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by customer name, phone, address, salesman...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: (_searchController.text.isNotEmpty || _searchQuery.isNotEmpty)
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchDebouncer?.cancel();
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                            _customers = [];
                            _isLoading = false;
                            _hasMore = false;
                            _isLoadingMore = false;
                          });
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
              onChanged: _onSearchChanged,
            ),
          ),

          // Header Stats (Only when search query is active)
          if (_searchQuery.isNotEmpty && !_isLoading && _customers.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${_customers.length} Result(s) for "$_searchQuery"',
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

          // Search Results / Prompts
          Expanded(
            child: _searchQuery.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search_rounded, size: 64, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text(
                            'Search Customer Directory',
                            style: TextStyle(color: Colors.grey[700], fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Type a customer name, phone number, address, or salesman above to search.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey[500], fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  )
                : _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _customers.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32.0),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.person_search_rounded, size: 56, color: Colors.grey[400]),
                                  const SizedBox(height: 12),
                                  Text(
                                    'No customers found for "$_searchQuery"',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.grey[600], fontSize: 15, fontWeight: FontWeight.w500),
                                  ),
                                ],
                              ),
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
                                                    if (c['primary_branch'] != null)
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                        decoration: BoxDecoration(
                                                          color: Colors.green.withValues(alpha: 0.15),
                                                          borderRadius: BorderRadius.circular(4),
                                                          border: Border.all(color: Colors.green.shade700, width: 0.8),
                                                        ),
                                                        child: Row(
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: [
                                                            Icon(Icons.star_rounded, size: 12, color: Colors.green.shade800),
                                                            const SizedBox(width: 2),
                                                            Text(
                                                              'Primary: ${DmeConstants.getBranchName(int.tryParse(c['primary_branch'].toString()))}',
                                                              style: TextStyle(
                                                                  fontSize: 10,
                                                                  fontWeight: FontWeight.bold,
                                                                  color: Colors.green.shade900),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ...branchIds.map((bId) {
                                                      return Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                        decoration: BoxDecoration(
                                                          color: const Color(0xFF005BAC).withValues(alpha: 0.1),
                                                          borderRadius: BorderRadius.circular(4),
                                                        ),
                                                        child: Text(
                                                          DmeConstants.getBranchName(bId),
                                                          style: const TextStyle(
                                                              fontSize: 10,
                                                              fontWeight: FontWeight.bold,
                                                              color: Color(0xFF005BAC)),
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
                                                          style: TextStyle(
                                                              fontSize: 10,
                                                              fontWeight: FontWeight.w500,
                                                              color: Colors.grey[800]),
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
