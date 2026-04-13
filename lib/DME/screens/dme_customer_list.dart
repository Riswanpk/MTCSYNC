import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/dme_supabase_service.dart';
import '../models/dme_user.dart';
import '../models/dme_customer.dart';
import 'dme_customer_detail.dart';

// ── Hardcoded lookup tables ───────────────────────────────────────
const Map<String, int> _categoryNameToId = {
  'EVENT': 1,
  'CATERING': 2,
  'RESTAURANT': 3,
  'PANTHAL': 4,
  'STAGE DECORATION': 5,
  'AUDITORIUM': 6,
  'TRUST': 7,
  'INSTITUTION': 8,
  'RENTAL': 9,
  'HIRING': 10,
  'VEHICLE SHOWROOM': 11,
  'RESORT': 12,
  'GENERAL & OTHERS': 13,
};

const Map<String, int> _customerTypeNameToId = {
  'PREMIUM': 1,
  'REGULAR': 2,
  'BARGAIN': 3,
  'INSTITUTIONS': 4,
  'DEALERS': 5,
  'GENERAL': 6,
};

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
  List<int> _filterBranchIds = []; // Selected branches for filtering
  Map<String, int> _branchNameToId = {}; // Map branch names to IDs
  List<String> _availableBranches = [];
  List<String> _availableSalesmen = [];
  String? _selectedBranchName; // Track selected branch
  bool _loading = true;
  bool _loadingMore = false;
  int? _selectedCategoryId; // ← NEW: Use ID instead of name
  int? _selectedTypeId; // ← NEW: Use ID instead of name
  DateTime? _dateFrom;
  DateTime? _dateTo;
  String? _selectedSalesman;
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
    await _loadBranchesAndSalesmen();
    await _loadCustomers();
  }

  Future<void> _loadBranchesAndSalesmen() async {
    try {
      // Load available branches only
      final branches = await _svc.getBranches();
      print('DEBUG: Branches loaded: ${branches.length}');
      
      setState(() {
        _availableBranches = [];
        _branchNameToId = {};
        
        for (var b in branches) {
          try {
            final name = b['name'] as String?;
            final id = b['id'] as int?;
            print('DEBUG: Branch data - name: $name, id: $id');
            if (name != null && id != null) {
              _availableBranches.add(name);
              _branchNameToId[name] = id;
            }
          } catch (e) {
            print('DEBUG: Error parsing branch: $b, error: $e');
          }
        }
        _availableBranches.sort(); // Sort alphabetically
      });
      print('DEBUG: Available branches: $_availableBranches');
      print('DEBUG: Branch ID map: $_branchNameToId');
    } catch (e, st) {
      print('ERROR loading branches: $e');
      print('Stack trace: $st');
    }
  }

  Future<void> _loadSalesmenForBranch(String? branchName) async {
    if (branchName == null) {
      setState(() {
        _availableSalesmen = [];
        _selectedSalesman = null;
      });
      return;
    }

    try {
      final branchId = _branchNameToId[branchName];
      if (branchId == null) {
        print('ERROR: Branch ID not found for: $branchName');
        setState(() {
          _availableSalesmen = [];
          _selectedSalesman = null;
        });
        return;
      }

      print('DEBUG: Loading salesmen for branch: $branchName (ID: $branchId)');

      // Load customers for selected branch only
      final branchCustomers = await _svc.getCustomers(
        branchIds: [branchId],
        limit: 500,
        offset: 0,
      );
      print('DEBUG: Customers in branch loaded: ${branchCustomers.length}');

      final uniqueSalesmen = <String>{};
      for (var customer in branchCustomers) {
        if (customer.salesman != null && customer.salesman!.isNotEmpty) {
          print('DEBUG: Found salesman in branch: ${customer.salesman}');
          uniqueSalesmen.add(customer.salesman!);
        }
      }

      setState(() {
        _availableSalesmen = uniqueSalesmen.toList()..sort();
        _selectedSalesman = null; // Reset salesman selection
      });
      print('DEBUG: Available salesmen for branch: $_availableSalesmen');
    } catch (e, st) {
      print('ERROR loading salesmen for branch: $e');
      print('Stack trace: $st');
      setState(() {
        _availableSalesmen = [];
        _selectedSalesman = null;
      });
    }
  }

  Future<void> _loadCustomers({bool append = false}) async {
    if (!append) {
      setState(() {
        _loading = true;
        _offset = 0;
      });
    }
    final branchFilter = _filterBranchIds.isEmpty ? null : _filterBranchIds;
    
    // Use selected branch filter if set, otherwise use defaults
    final effectiveBranchIds = branchFilter ?? (widget.dmeUser.isAdmin ? null : _branchIds);
    
    print('DEBUG: _loadCustomers - branchFilter: $branchFilter, isAdmin: ${widget.dmeUser.isAdmin}, effectiveBranchIds: $effectiveBranchIds');
    
    final results = await _svc.getCustomers(
      branchIds: effectiveBranchIds,
      search: _searchCtrl.text.isEmpty ? null : _searchCtrl.text,
      categoryId: _selectedCategoryId,
      customerTypeId: _selectedTypeId,
      lastPurchaseDateFrom: _dateFrom,
      lastPurchaseDateTo: _dateTo,
      salesman: _selectedSalesman,
      limit: _pageSize,
      offset: _offset,
    );
    
    print('DEBUG: _loadCustomers returned ${results.length} customers');
    
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
    if (_scrollCtrl.position.pixels >=
            _scrollCtrl.position.maxScrollExtent - 200 &&
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
      backgroundColor: const Color(0xFFF0F4FA),
      appBar: AppBar(
        elevation: 0,
        title: const Text(
          'Customers',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.3),
        ),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // ── Search + filters ─────────────────────────────────────
          Container(
            color: const Color(0xFF005BAC),
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
            child: Column(
              children: [
                // Search bar
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'Search by name or phone...',
                      hintStyle:
                          TextStyle(color: Colors.grey[400], fontSize: 14),
                      prefixIcon: const Icon(Icons.search_rounded,
                          color: Color(0xFF005BAC)),
                      suffixIcon: _searchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded,
                                  color: Colors.grey),
                              onPressed: () {
                                _searchCtrl.clear();
                                _search();
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 13),
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(height: 10),
                // Filter dropdowns - Row 1: Category & Type
                Row(
                  children: [
                    Expanded(
                      child: _FilterDropdown(
                        hint: 'Category',
                        items: [null, ..._categoryNameToId.keys],
                        onChanged: (v) {
                          if (v == null) {
                            _selectedCategoryId = null;
                          } else {
                            _selectedCategoryId = _categoryNameToId[v];
                          }
                          _search();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _FilterDropdown(
                        hint: 'Type',
                        items: [null, ..._customerTypeNameToId.keys],
                        onChanged: (v) {
                          if (v == null) {
                            _selectedTypeId = null;
                          } else {
                            _selectedTypeId = _customerTypeNameToId[v];
                          }
                          _search();
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Filter dropdowns - Row 2: Branch & Salesman
                Row(
                  children: [
                    Expanded(
                      child: _FilterDropdown(
                        hint: 'Branch',
                        items: [null, ..._availableBranches],
                        onChanged: (v) {
                          setState(() {
                            _selectedBranchName = v;
                            if (v == null) {
                              _filterBranchIds = [];
                            } else {
                              final branchId = _branchNameToId[v];
                              _filterBranchIds = branchId != null ? [branchId] : [];
                            }
                          });
                          // Load salesmen for the selected branch
                          _loadSalesmenForBranch(v);
                          _search();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _FilterDropdown(
                        hint: 'Salesman',
                        items: _selectedBranchName == null ? [] : [null, ..._availableSalesmen],
                        onChanged: (v) {
                          if (_selectedBranchName != null) {
                            setState(() => _selectedSalesman = v);
                            _search();
                          }
                        },
                        enabled: _selectedBranchName != null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Date range filter - Row 3
                Row(
                  children: [
                    Expanded(
                      child: _DateFilterButton(
                        label: 'From',
                        date: _dateFrom,
                        onDateChanged: (date) {
                          setState(() => _dateFrom = date);
                          _search();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _DateFilterButton(
                        label: 'To',
                        date: _dateTo,
                        onDateChanged: (date) {
                          setState(() => _dateTo = date);
                          _search();
                        },
                      ),
                    ),
                    if (_dateFrom != null || _dateTo != null)
                      IconButton(
                        icon: const Icon(Icons.clear_rounded,
                            color: Colors.white, size: 18),
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 36, minHeight: 36),
                        onPressed: () {
                          setState(() {
                            _dateFrom = null;
                            _dateTo = null;
                          });
                          _search();
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),

          // ── List ─────────────────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _customers.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: Colors.blue.withValues(alpha: 0.08),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.person_search_rounded,
                                  size: 48, color: Color(0xFF005BAC)),
                            ),
                            const SizedBox(height: 16),
                            const Text('No customers found',
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text('Try a different search or filter',
                                style: TextStyle(color: Colors.grey[500])),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                        itemCount: _customers.length + (_loadingMore ? 1 : 0),
                        itemBuilder: (_, i) {
                          if (i == _customers.length) {
                            return const Center(
                              child: Padding(
                                padding: EdgeInsets.all(16),
                                child: CircularProgressIndicator(),
                              ),
                            );
                          }
                          return _CustomerCard(
                              customer: _customers[i], dmeUser: widget.dmeUser);
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

// ── Date Filter Button ────────────────────────────────────────────────────

class _DateFilterButton extends StatelessWidget {
  final String label;
  final DateTime? date;
  final ValueChanged<DateTime?> onDateChanged;

  const _DateFilterButton({
    required this.label,
    required this.date,
    required this.onDateChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime.now(),
        );
        if (picked != null) {
          onDateChanged(picked);
        }
      },
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: date != null
                ? Colors.white
                : Colors.white.withValues(alpha: 0.3),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                date != null
                    ? DateFormat('MMM dd, yy').format(date!)
                    : label,
                style: TextStyle(
                  color: date != null ? Colors.white : Colors.white70,
                  fontSize: 12,
                  fontWeight: date != null ? FontWeight.w600 : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.calendar_today_rounded,
                color: Colors.white, size: 14),
          ],
        ),
      ),
    );
  }
}

// ── Filter Dropdown ────────────────────────────────────────────────────────

class _FilterDropdown extends StatefulWidget {
  final String hint;
  final List<String?> items;
  final ValueChanged<String?> onChanged;
  final bool enabled;

  const _FilterDropdown({
    required this.hint,
    required this.items,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  State<_FilterDropdown> createState() => _FilterDropdownState();
}

class _FilterDropdownState extends State<_FilterDropdown> {
  String? _value;

  @override
  void didUpdateWidget(_FilterDropdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reset value if widget becomes disabled
    if (!widget.enabled && _value != null) {
      setState(() => _value = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: widget.enabled
            ? Colors.white.withValues(alpha: 0.15)
            : Colors.grey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: widget.enabled
              ? Colors.white.withValues(alpha: 0.3)
              : Colors.grey.withValues(alpha: 0.2),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: DropdownButton<String?>(
        value: _value,
        isExpanded: true,
        underline: const SizedBox(),
        dropdownColor: Colors.white,
        style: TextStyle(
          fontSize: 12,
          color: widget.enabled ? Colors.black87 : Colors.grey[400],
        ),
        hint: Text(
          widget.hint,
          style: TextStyle(
            color: widget.enabled ? Colors.white : Colors.grey[300],
            fontSize: 12,
          ),
        ),
        icon: Icon(
          Icons.expand_more_rounded,
          color: widget.enabled ? Colors.white : Colors.grey[400],
          size: 16,
        ),
        disabledHint: Text(
          widget.hint,
          style: TextStyle(color: Colors.grey[400], fontSize: 12),
        ),
        items: widget.enabled
            ? [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text('All ${widget.hint}s',
                      style: const TextStyle(fontSize: 12)),
                ),
                ...widget.items.where((i) => i != null).map(
                      (i) => DropdownMenuItem<String?>(
                        value: i,
                        child: Text(i!, style: const TextStyle(fontSize: 12)),
                      ),
                    ),
              ]
            : [],
        onChanged: widget.enabled
            ? (v) {
                setState(() => _value = v);
                widget.onChanged(v);
              }
            : null,
      ),
    );
  }
}

// ── Customer Card ──────────────────────────────────────────────────────────

class _CustomerCard extends StatelessWidget {
  final DmeCustomer customer;
  final DmeUser dmeUser;
  const _CustomerCard({required this.customer, required this.dmeUser});

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd MMM yy');
    const primaryBlue = Color(0xFF005BAC);
    final initial =
        customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '?';

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DmeCustomerDetailPage(
            customer: customer,
            dmeUser: dmeUser,
          ),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF1E2A3A)
              : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: [
              // Avatar
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      primaryBlue.withValues(alpha: 0.8),
                      primaryBlue,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    initial,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customer.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(Icons.phone_rounded,
                            size: 12, color: Colors.grey),
                        const SizedBox(width: 3),
                        Text(
                          customer.phone.isNotEmpty ? customer.phone : '–',
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (customer.customerType != null)
                          Text(
                            customer.customerType!,
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[700]),
                          ),
                        if (customer.customerType != null &&
                            customer.category != null)
                          Text(
                            ' • ',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[400]),
                          ),
                        if (customer.category != null)
                          Text(
                            customer.category!,
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[700]),
                          ),
                        const Spacer(),
                        if (customer.lastPurchaseDate != null)
                          Row(
                            children: [
                              Icon(Icons.shopping_bag_rounded,
                                  size: 11, color: Colors.grey[400]),
                              const SizedBox(width: 3),
                              Text(
                                dateFmt.format(customer.lastPurchaseDate!),
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey[500]),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: Colors.grey, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
