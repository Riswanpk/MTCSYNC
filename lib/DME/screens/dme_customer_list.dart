import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/dme_supabase_service.dart';
import '../models/dme_user.dart';
import '../models/dme_customer.dart';
import 'dme_customer_detail.dart';

class DmeCustomerListPage extends StatefulWidget {
  final DmeUser dmeUser;
  const DmeCustomerListPage({super.key, required this.dmeUser});

  @override
  State<DmeCustomerListPage> createState() => _DmeCustomerListPageState();
}

class _DmeCustomerListPageState extends State<DmeCustomerListPage> {
  final _svc = DmeSupabaseService.instance;
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  List<DmeCustomer> _customers = [];
  List<int> _branchIds = [];
  bool _loading = true;
  bool _loadingMore = false;
  String? _selectedCategory;
  String? _selectedType;
  int _offset = 0;
  static const _pageSize = 50;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _init();
  }

  Future<void> _init() async {
    _branchIds = await _svc.getUserBranchIds(widget.dmeUser.id);
    await _loadCustomers();
  }

  Future<void> _loadCustomers({bool append = false}) async {
    if (!append) {
      setState(() { _loading = true; _offset = 0; });
    }
    final results = await _svc.getCustomers(
      branchIds: widget.dmeUser.isAdmin ? null : _branchIds,
      search: _searchCtrl.text.isEmpty ? null : _searchCtrl.text,
      category: _selectedCategory,
      customerType: _selectedType,
      limit: _pageSize,
      offset: _offset,
    );
    setState(() {
      if (append) {
        _customers.addAll(results);
      } else {
        _customers = results;
      }
      _loading = false;
      _loadingMore = false;
    });
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 200 &&
        !_loadingMore &&
        _customers.length >= _offset + _pageSize) {
      _loadingMore = true;
      _offset += _pageSize;
      _loadCustomers(append: true);
    }
  }

  void _search() {
    _offset = 0;
    _loadCustomers();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Customers'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search by name or phone...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          _search();
                        },
                      )
                    : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              onSubmitted: (_) => _search(),
            ),
          ),
          // Filters
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButton<String?>(
                    isExpanded: true,
                    hint: const Text('Category'),
                    value: _selectedCategory,
                    items: [
                      const DropdownMenuItem(value: null, child: Text('All Categories')),
                      ...['Event', 'Catering', 'Restaurant', 'Panthal',
                        'Stage Decoration', 'Auditorium', 'Trust', 'Institution',
                        'Rental', 'Hiring', 'Others']
                          .map((c) => DropdownMenuItem(value: c, child: Text(c))),
                    ],
                    onChanged: (v) {
                      _selectedCategory = v;
                      _search();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<String?>(
                    isExpanded: true,
                    hint: const Text('Type'),
                    value: _selectedType,
                    items: [
                      const DropdownMenuItem(value: null, child: Text('All Types')),
                      ...['Premium', 'Regular', 'Random', 'Bargain', 'Seasonal']
                          .map((t) => DropdownMenuItem(value: t, child: Text(t))),
                    ],
                    onChanged: (v) {
                      _selectedType = v;
                      _search();
                    },
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // List
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _customers.isEmpty
                    ? const Center(child: Text('No customers found'))
                    : ListView.builder(
                        controller: _scrollCtrl,
                        itemCount: _customers.length + (_loadingMore ? 1 : 0),
                        itemBuilder: (_, i) {
                          if (i == _customers.length) {
                            return const Center(
                                child: Padding(
                              padding: EdgeInsets.all(16),
                              child: CircularProgressIndicator(),
                            ));
                          }
                          final c = _customers[i];
                          return _CustomerTile(customer: c, dmeUser: widget.dmeUser);
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _CustomerTile extends StatelessWidget {
  final DmeCustomer customer;
  final DmeUser dmeUser;
  const _CustomerTile({required this.customer, required this.dmeUser});

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd-MMM-yy');
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: const Color(0xFF005BAC).withOpacity(0.1),
        child: Text(
          customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '?',
          style: const TextStyle(
              fontWeight: FontWeight.bold, color: Color(0xFF005BAC)),
        ),
      ),
      title: Text(customer.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        [
          customer.phone,
          if (customer.category != null) customer.category,
          if (customer.lastPurchaseDate != null)
            'Last: ${dateFmt.format(customer.lastPurchaseDate!)}',
        ].join(' • '),
        style: const TextStyle(fontSize: 12),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DmeCustomerDetailPage(
              customer: customer,
              dmeUser: dmeUser,
            ),
          ),
        );
      },
    );
  }
}
