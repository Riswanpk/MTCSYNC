import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/dme_user.dart';
import '../services/dme_user_dashboard_service.dart';
import '../widgets/dme_user_dashboard_widgets.dart';

const Color _primaryBlue = Color(0xFF005BAC);

class DmeUserDashboardPage extends StatefulWidget {
  final DmeUser dmeUser;

  const DmeUserDashboardPage({super.key, required this.dmeUser});

  @override
  State<DmeUserDashboardPage> createState() => _DmeUserDashboardPageState();
}

class _DmeUserDashboardPageState extends State<DmeUserDashboardPage> {
  final _dashSvc = DmeUserDashboardService.instance;

  // ── Branch state ─────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _availableBranches = [];
  // null means "All assigned branches"
  int? _selectedBranchId;
  bool _branchesLoaded = false;

  // ── Date range state ─────────────────────────────────────────────────────
  static const _presets = ['This Month', 'Last Month', 'This Week', 'Custom'];
  String _selectedPreset = 'This Month';
  late DateTime _fromDate;
  late DateTime _toDate;

  // ── Data state ───────────────────────────────────────────────────────────
  DmeUserDashboardData _data = DmeUserDashboardData.empty();
  bool _loading = true;
  String? _error;

  // ── All branch ids this user is assigned to ───────────────────────────────
  List<int> _userBranchIds = [];

  @override
  void initState() {
    super.initState();
    _setDateRangeForPreset('This Month');
    _init();
  }

  Future<void> _init() async {
    _userBranchIds =
        await _dashSvc.getUserBranchIds(widget.dmeUser.id);

    final allBranches = await _dashSvc.getAllBranches();

    if (mounted) {
      setState(() {
        _availableBranches = widget.dmeUser.isAdmin
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
    switch (preset) {
      case 'This Month':
        _fromDate = DateTime(now.year, now.month, 1);
        _toDate = DateTime(now.year, now.month + 1, 0);
        break;
      case 'Last Month':
        final first = DateTime(now.year, now.month - 1, 1);
        _fromDate = first;
        _toDate = DateTime(now.year, now.month, 0);
        break;
      case 'This Week':
        final weekStart = now.subtract(Duration(days: now.weekday - 1));
        _fromDate = DateTime(weekStart.year, weekStart.month, weekStart.day);
        _toDate = _fromDate.add(const Duration(days: 6));
        break;
      default:
        break; // keep current for 'Custom'
    }
  }

  /// Resolve which branch IDs to query
  List<int>? _effectiveBranchIds() {
    if (widget.dmeUser.isAdmin && _selectedBranchId == null) {
      return null; // admin "All" → no filter
    }
    if (_selectedBranchId != null) {
      return [_selectedBranchId!];
    }
    // non-admin "All assigned" → their branch IDs
    return _userBranchIds.isEmpty ? null : _userBranchIds;
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await _dashSvc.fetchDashboardData(
        from: _fromDate,
        to: _toDate,
        branchIds: _effectiveBranchIds(),
      );
      if (mounted) setState(() { _data = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  // ── Date picker helpers ───────────────────────────────────────────────────

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
      _loadData();
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dateFmt = DateFormat('d MMM yy');

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0A1628) : Colors.grey[100],
      appBar: AppBar(
        title: const Text('My Dashboard'),
        backgroundColor: _primaryBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadData,
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Filters bar ───────────────────────────────────────────────────
          _buildFiltersBar(isDark, dateFmt),
          // ── Content ───────────────────────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _buildError()
                    : RefreshIndicator(
                        onRefresh: _loadData,
                        child: _buildBody(isDark),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltersBar(bool isDark, DateFormat dateFmt) {
    final cardColor = isDark ? const Color(0xFF1A2332) : Colors.white;

    return Material(
      color: cardColor,
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Branch selector ───────────────────────────────────────────
            if (_branchesLoaded)
              DropdownButtonFormField<int?>(
                value: _selectedBranchId,
                decoration: InputDecoration(
                  labelText: 'Branch',
                  labelStyle: TextStyle(
                      color: isDark ? Colors.white54 : Colors.black54,
                      fontSize: 12),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                isExpanded: true,
                items: [
                  DropdownMenuItem<int?>(
                    value: null,
                    child: Text(
                      widget.dmeUser.isAdmin
                          ? 'All Branches'
                          : 'All Assigned Branches',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                  ..._availableBranches.map((b) => DropdownMenuItem<int?>(
                        value: b['id'] as int?,
                        child: Text(b['name'] as String? ?? ''),
                      )),
                ],
                onChanged: (v) {
                  setState(() => _selectedBranchId = v);
                  _loadData();
                },
              ),
            const SizedBox(height: 8),
            // ── Date preset chips + custom ────────────────────────────────
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ..._presets.where((p) => p != 'Custom').map((preset) {
                    final selected = _selectedPreset == preset;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(preset),
                        selected: selected,
                        selectedColor: _primaryBlue,
                        labelStyle: TextStyle(
                          color: selected ? Colors.white : null,
                          fontSize: 12,
                        ),
                        onSelected: (_) {
                          setState(() {
                            _selectedPreset = preset;
                            _setDateRangeForPreset(preset);
                          });
                          _loadData();
                        },
                      ),
                    );
                  }),
                  // Custom date range button
                  GestureDetector(
                    onTap: _pickCustomRange,
                    child: Chip(
                      avatar: const Icon(Icons.date_range, size: 14),
                      label: Text(
                        _selectedPreset == 'Custom'
                            ? '${dateFmt.format(_fromDate)} – ${dateFmt.format(_toDate)}'
                            : 'Custom',
                        style: const TextStyle(fontSize: 12),
                      ),
                      backgroundColor: _selectedPreset == 'Custom'
                          ? _primaryBlue.withOpacity(0.15)
                          : null,
                    ),
                  ),
                ],
              ),
            ),
            // ── Active range label ────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${dateFmt.format(_fromDate)}  →  ${dateFmt.format(_toDate)}',
                  style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white38 : Colors.black38),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(bool isDark) {
    final data = _data;
    final returningPct = data.totalUniqueCustomers > 0
        ? (data.returningCustomers / data.totalUniqueCustomers * 100)
            .toStringAsFixed(1)
        : '0.0';

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // ── Top stat cards ────────────────────────────────────────────────
        DashboardStatCard(
          label: 'Total Customers Purchased',
          value: data.totalUniqueCustomers.toString(),
          icon: Icons.people_rounded,
          color: _primaryBlue,
          subtitle: 'Unique customers in selected range',
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: DashboardStatCard(
                label: 'Purchase Records',
                value: data.totalPurchaseRecords.toString(),
                icon: Icons.receipt_long_rounded,
                color: const Color(0xFF8CC63F),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DashboardStatCard(
                label: 'Returning Customers',
                value: data.returningCustomers.toString(),
                icon: Icons.replay_rounded,
                color: const Color(0xFFFFA500),
                subtitle: '$returningPct% of total',
              ),
            ),
          ],
        ),

        // ── Category breakdown ────────────────────────────────────────────
        if (data.byCategory.isNotEmpty) ...[
          const SizedBox(height: 16),
          CategoryPieCard(stats: data.byCategory),
        ],

        // ── Branch breakdown ──────────────────────────────────────────────
        if (data.byBranch.length > 1) ...[
          const SizedBox(height: 16),
          BranchBreakdownCard(stats: data.byBranch),
        ],

        // ── Daily trend ───────────────────────────────────────────────────
        const SizedBox(height: 16),
        DailyTrendCard(dailyTrend: data.dailyTrend),

        const SizedBox(height: 24),
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
            Text('Failed to load dashboard data',
                style: const TextStyle(fontSize: 16)),
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
                  foregroundColor: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
