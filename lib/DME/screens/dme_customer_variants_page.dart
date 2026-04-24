import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/dme_user.dart';
import '../services/dme_supabase_service.dart';
import '../services/dme_customer_variants_service.dart';

const Color _primaryBlue = Color(0xFF005BAC);

class DmeCustomerVariantsPage extends StatefulWidget {
  const DmeCustomerVariantsPage({super.key});

  @override
  State<DmeCustomerVariantsPage> createState() =>
      _DmeCustomerVariantsPageState();
}

class _DmeCustomerVariantsPageState extends State<DmeCustomerVariantsPage> {
  final _svc = DmeCustomerVariantsService.instance;
  final _dmeSvc = DmeSupabaseService.instance;

  // ── User state ───────────────────────────────────────────────────────────
  DmeUser? _dmeUser;
  bool _userLoading = true;

  // ── Branch state ─────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _availableBranches = [];
  int? _selectedBranchId;
  bool _branchesLoaded = false;

  // ── Date range state ─────────────────────────────────────────────────────
  static const _presets = ['This Month', 'This Week', 'Today', 'Custom'];
  String _selectedPreset = 'This Month';
  late DateTime _fromDate;
  late DateTime _toDate;

  // ── Data state ───────────────────────────────────────────────────────────
  List<CustomerVariant> _customers = [];
  bool _loading = true;
  String? _error;

  // ── All branch ids this user is assigned to ───────────────────────────────
  List<int> _userBranchIds = [];

  @override
  void initState() {
    super.initState();
    _setDateRangeForPreset('This Month');
    _loadCurrentUser();
  }

  Future<void> _loadCurrentUser() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _userLoading = false);
      return;
    }
    final user = await _dmeSvc.getCurrentUser(uid);
    if (mounted) {
      setState(() {
        _dmeUser = user;
        _userLoading = false;
      });
      if (user != null) _init();
    }
  }

  Future<void> _init() async {
    _userBranchIds = await _svc.getUserBranchIds(_dmeUser!.id);

    final allBranches = await _svc.getAllBranches();

    if (mounted) {
      setState(() {
        _availableBranches = _dmeUser!.isAdmin
            ? allBranches
            : allBranches
                .where((b) => _userBranchIds.contains(b['id'] as int?))
                .toList();
        _branchesLoaded = true;
      });
    }
    await _loadData();
  }

  void _setDateRangeForPreset(String preset) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (preset) {
      case 'This Month':
        _fromDate = DateTime(now.year, now.month, 1);
        _toDate = today;
        break;
      case 'This Week':
        final weekStart = now.subtract(Duration(days: now.weekday - 1));
        _fromDate = DateTime(weekStart.year, weekStart.month, weekStart.day);
        _toDate = today;
        break;
      case 'Today':
        _fromDate = today;
        _toDate = today;
        break;
      default:
        break;
    }
  }

  List<int>? _effectiveBranchIds() {
    if (_dmeUser == null) return null;
    if (_dmeUser!.isAdmin && _selectedBranchId == null) {
      return null;
    }
    if (_selectedBranchId != null) {
      return [_selectedBranchId!];
    }
    return _userBranchIds.isEmpty ? null : _userBranchIds;
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final customers = await _svc.fetchCustomersWithVariants(
        from: _fromDate,
        to: _toDate,
        branchIds: _effectiveBranchIds(),
      );
      if (mounted) setState(() { _customers = customers; _error = null; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _pickCustomRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2022),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _fromDate, end: _toDate),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: _primaryBlue),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _fromDate = picked.start;
        _toDate = picked.end;
        _selectedPreset = 'Custom';
      });
      await _loadData();
    }
  }



  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_userLoading) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF0A1628) : Colors.grey[100],
        appBar: AppBar(
          title: const Text('Customers with Multiple Categories/Types',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          centerTitle: true,
          backgroundColor: _primaryBlue,
          foregroundColor: Colors.white,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_dmeUser == null) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF0A1628) : Colors.grey[100],
        appBar: AppBar(
          title: const Text('Customers with Multiple Categories/Types',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          centerTitle: true,
          backgroundColor: _primaryBlue,
          foregroundColor: Colors.white,
        ),
        body: const Center(child: Text('User not found')),
      );
    }

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A1628) : Colors.grey[100],
      appBar: AppBar(
        title: const Text('Customers with Multiple Categories/Types',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        centerTitle: true,
        backgroundColor: _primaryBlue,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          _buildFiltersBar(isDark),
          _loading ? _buildLoading() : _buildBody(isDark),
        ],
      ),
    );
  }

  Widget _buildFiltersBar(bool isDark) {
    return SizedBox(
      child: Container(
      color: isDark ? const Color(0xFF1C2E42) : Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Branch selector
          if (_branchesLoaded && _availableBranches.isNotEmpty)
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: isDark ? const Color(0xFF172334) : Colors.grey[50],
                border: Border.all(
                  color: isDark ? Colors.white10 : Colors.grey[300]!,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: DropdownButton<int?>(
                isExpanded: true,
                underline: const SizedBox(),
                value: _selectedBranchId,
                items: [
                  DropdownMenuItem(
                    value: null,
                    child: Text(
                      'All${!_dmeUser!.isAdmin ? ' Assigned' : ''}',
                      style:
                          TextStyle(color: isDark ? Colors.white70 : Colors.black87),
                    ),
                  ),
                  ..._availableBranches.map((b) {
                    final bid = b['id'] as int?;
                    final name = b['name'] as String? ?? 'Unknown';
                    return DropdownMenuItem(
                      value: bid,
                      child: Text(name),
                    );
                  }).toList(),
                ]
                    .map((item) => DropdownMenuItem(
                          value: item.value,
                          child: item.child,
                        ))
                    .toList(),
                onChanged: (val) => setState(() {
                  _selectedBranchId = val;
                  _loadData();
                }),
              ),
            ),
          const SizedBox(height: 12),
          // Date range presets
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final preset in _presets) ...[
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedPreset = preset;
                        if (preset != 'Custom') {
                          _setDateRangeForPreset(preset);
                          _loadData();
                        } else {
                          _pickCustomRange();
                        }
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        color: _selectedPreset == preset
                            ? _primaryBlue
                            : (isDark
                                ? Colors.white.withOpacity(0.08)
                                : Colors.grey[300]),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (preset == 'Custom')
                            const Icon(Icons.calendar_today_rounded, size: 14),
                          if (preset == 'Custom') const SizedBox(width: 6),
                          Text(
                            preset,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _selectedPreset == preset
                                  ? Colors.white
                                  : (isDark ? Colors.white70 : Colors.black87),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ]
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Date range display
          Text(
            '${DateFormat('d MMM yy').format(_fromDate)} — ${DateFormat('d MMM yy').format(_toDate)}',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white54 : Colors.black54,
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildLoading() {
    return const Center(child: CircularProgressIndicator());
  }

  Widget _buildBody(bool isDark) {
    if (_error != null) return _buildError();
    if (_customers.isEmpty) {
      return Center(
        child: Text(
          'No customers found with multiple categories or types in this period',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isDark ? Colors.white54 : Colors.black54,
          ),
        ),
      );
    }

    return Expanded(
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _customers.length,
        itemBuilder: (context, index) {
          final customer = _customers[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            color: isDark ? const Color(0xFF1C2E42) : Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name + Phone
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              customer.customerName,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              customer.customerPhone,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.white54 : Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Purchase count badge
                      Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: _primaryBlue.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _primaryBlue.withOpacity(0.3),
                          ),
                        ),
                        child: Text(
                          '${customer.purchaseCount} purchases',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: _primaryBlue,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Categories
                  if (customer.hasMultipleCategories) ...[
                    _buildVariantSection(
                      title: 'Categories (${customer.categories.length})',
                      items: customer.categories.toList(),
                      color: const Color(0xFF2979FF),
                      isDark: isDark,
                    ),
                    const SizedBox(height: 10),
                  ],
                  // Types
                  if (customer.hasMultipleTypes) ...[
                    _buildVariantSection(
                      title: 'Customer Types (${customer.types.length})',
                      items: customer.types.toList(),
                      color: const Color(0xFF7C4DFF),
                      isDark: isDark,
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildVariantSection({
    required String title,
    required List<String> items,
    required Color color,
    required bool isDark,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white70 : Colors.black87,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: items.map((item) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: color.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Text(
                item,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            const Text('Failed to load customers',
                style: TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            Text(_error ?? '',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryBlue,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
