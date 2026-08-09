import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../Leads/presentfollowup.dart';
import '../Navigation/user_cache_service.dart';

const Color _primaryBlue = Color(0xFF005BAC);
const Color _primaryGreen = Color(0xFF8CC63F);

class SyncHeadAllLeadsPage extends StatefulWidget {
  const SyncHeadAllLeadsPage({super.key});

  @override
  State<SyncHeadAllLeadsPage> createState() => _SyncHeadAllLeadsPageState();
}

class _SyncHeadAllLeadsPageState extends State<SyncHeadAllLeadsPage> {
  DateTimeRange? _selectedDateRange;
  String? _selectedBranch;

  List<String> _branches = [];
  bool _loadingBranches = true;

  bool _loadingLeads = false;
  bool _hasFetched = false;
  List<Map<String, dynamic>> _allLeads = [];

  // Source filter for lead list view below breakdown: 'ALL', 'CC', 'DME', 'SME', 'SALES'
  String _activeSourceFilter = 'ALL';

  @override
  void initState() {
    super.initState();
    _fetchBranches();
  }

  Future<void> _fetchBranches() async {
    try {
      final branches = await UserCacheService.instance.getBranches();
      if (!mounted) return;
      setState(() {
        _branches = ['All Branches', ...branches];
        _loadingBranches = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingBranches = false);
    }
  }

  Future<void> _fetchLeads() async {
    if (_selectedDateRange == null || _selectedBranch == null) return;

    setState(() {
      _loadingLeads = true;
      _hasFetched = true;
    });

    try {
      final rangeStart = DateTime(
        _selectedDateRange!.start.year,
        _selectedDateRange!.start.month,
        _selectedDateRange!.start.day,
        0,
        0,
        0,
      );
      final rangeEnd = DateTime(
        _selectedDateRange!.end.year,
        _selectedDateRange!.end.month,
        _selectedDateRange!.end.day,
        23,
        59,
        59,
      );

      Query query = FirebaseFirestore.instance.collection('follow_ups');

      if (_selectedBranch != 'All Branches') {
        query = query.where('branch', isEqualTo: _selectedBranch);
      }

      query = query
          .where('created_at',
              isGreaterThanOrEqualTo: Timestamp.fromDate(rangeStart))
          .where('created_at',
              isLessThanOrEqualTo: Timestamp.fromDate(rangeEnd));

      final snap = await query.get();

      final leads = snap.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        data['docId'] = doc.id;
        return data;
      }).toList();

      // Sort by created_at descending
      leads.sort((a, b) {
        final tA = a['created_at'] is Timestamp
            ? (a['created_at'] as Timestamp).toDate()
            : DateTime(1970);
        final tB = b['created_at'] is Timestamp
            ? (b['created_at'] as Timestamp).toDate()
            : DateTime(1970);
        return tB.compareTo(tA);
      });

      if (!mounted) return;
      setState(() {
        _allLeads = leads;
        _loadingLeads = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingLeads = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading leads: $e')),
      );
    }
  }

  String _normalizeSource(dynamic src) {
    if (src == null) return 'SALES';
    final str = src.toString().trim().toUpperCase();
    if (str == 'CC' || str == 'CUSTOMER CALLING' || str == 'CUSTOMER_CALLING') {
      return 'CC';
    }
    if (str == 'DME') return 'DME';
    if (str == 'SME') return 'SME';
    return 'SALES';
  }

  int get _ccCount =>
      _allLeads.where((l) => _normalizeSource(l['source']) == 'CC').length;
  int get _dmeCount =>
      _allLeads.where((l) => _normalizeSource(l['source']) == 'DME').length;
  int get _smeCount =>
      _allLeads.where((l) => _normalizeSource(l['source']) == 'SME').length;
  int get _salesCount =>
      _allLeads.where((l) => _normalizeSource(l['source']) == 'SALES').length;

  List<Map<String, dynamic>> get _displayedLeads {
    if (_activeSourceFilter == 'ALL') return _allLeads;
    return _allLeads
        .where((l) => _normalizeSource(l['source']) == _activeSourceFilter)
        .toList();
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023, 1, 1),
      lastDate: DateTime(2100),
      initialDateRange: _selectedDateRange ??
          DateTimeRange(
            start: DateTime(now.year, now.month, 1),
            end: now,
          ),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: _primaryBlue,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Color(0xFF1E293B),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() => _selectedDateRange = picked);
      _fetchLeads();
    }
  }

  void _showBranchPickerBottomSheet(bool isDark) {
    String searchQuery = '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filteredBranches = _branches.where((b) {
              return b.toLowerCase().contains(searchQuery.toLowerCase());
            }).toList();

            final sheetBg =
                isDark ? const Color(0xFF1E293B) : Colors.white;
            final textColor =
                isDark ? Colors.white : const Color(0xFF0F172A);

            return Container(
              height: MediaQuery.of(context).size.height * 0.65,
              decoration: BoxDecoration(
                color: sheetBg,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 20,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  // Handle indicator
                  Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        const Icon(Icons.location_city_rounded,
                            color: _primaryBlue, size: 24),
                        const SizedBox(width: 10),
                        Text(
                          'Select Branch',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Search box
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: TextField(
                      onChanged: (val) =>
                          setModalState(() => searchQuery = val),
                      style: TextStyle(color: textColor, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Search branch...',
                        hintStyle: TextStyle(
                          color: isDark ? Colors.white38 : Colors.grey.shade500,
                        ),
                        prefixIcon: Icon(Icons.search_rounded,
                            color: isDark ? Colors.white54 : _primaryBlue),
                        filled: true,
                        fillColor: isDark
                            ? const Color(0xFF0F172A)
                            : const Color(0xFFF1F5F9),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: _loadingBranches
                        ? const Center(
                            child: CircularProgressIndicator(strokeWidth: 2.5))
                        : filteredBranches.isEmpty
                            ? Center(
                                child: Text(
                                  'No branches found',
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.white54
                                        : Colors.grey.shade600,
                                  ),
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                itemCount: filteredBranches.length,
                                itemBuilder: (context, index) {
                                  final branch = filteredBranches[index];
                                  final isSelected =
                                      _selectedBranch == branch;
                                  final isAll = branch == 'All Branches';

                                  return Padding(
                                    padding:
                                        const EdgeInsets.only(bottom: 8.0),
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: () {
                                          Navigator.pop(context);
                                          setState(() =>
                                              _selectedBranch = branch);
                                          _fetchLeads();
                                        },
                                        borderRadius:
                                            BorderRadius.circular(14),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 16, vertical: 14),
                                          decoration: BoxDecoration(
                                            color: isSelected
                                                ? _primaryBlue
                                                    .withValues(alpha: 0.12)
                                                : isDark
                                                    ? const Color(0xFF0F172A)
                                                    : const Color(0xFFF8FAFC),
                                            borderRadius:
                                                BorderRadius.circular(14),
                                            border: Border.all(
                                              color: isSelected
                                                  ? _primaryBlue
                                                  : isDark
                                                      ? const Color(0xFF334155)
                                                      : const Color(0xFFE2E8F0),
                                              width: isSelected ? 1.8 : 1.0,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Container(
                                                padding:
                                                    const EdgeInsets.all(8),
                                                decoration: BoxDecoration(
                                                  color: isSelected
                                                      ? _primaryBlue
                                                      : isAll
                                                          ? _primaryGreen
                                                              .withValues(
                                                                  alpha: 0.2)
                                                          : isDark
                                                              ? Colors.white10
                                                              : Colors.grey
                                                                  .shade200,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: Icon(
                                                  isAll
                                                      ? Icons
                                                          .select_all_rounded
                                                      : Icons
                                                          .storefront_rounded,
                                                  size: 18,
                                                  color: isSelected
                                                      ? Colors.white
                                                      : isAll
                                                          ? _primaryGreen
                                                          : isDark
                                                              ? Colors.white70
                                                              : const Color(
                                                                  0xFF475569),
                                                ),
                                              ),
                                              const SizedBox(width: 14),
                                              Expanded(
                                                child: Text(
                                                  branch,
                                                  style: TextStyle(
                                                    fontSize: 15,
                                                    fontWeight: isSelected
                                                        ? FontWeight.bold
                                                        : FontWeight.w500,
                                                    color: isSelected
                                                        ? _primaryBlue
                                                        : textColor,
                                                  ),
                                                ),
                                              ),
                                              if (isSelected)
                                                const Icon(
                                                  Icons.check_circle_rounded,
                                                  color: _primaryBlue,
                                                  size: 22,
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _formatDate(DateTime d) => DateFormat('dd MMM yyyy').format(d);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subTextColor = isDark ? Colors.white60 : const Color(0xFF64748B);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text(
          'Total Leads Overview',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19),
        ),
        backgroundColor: _primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_selectedDateRange != null && _selectedBranch != null)
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Refresh',
              onPressed: _fetchLeads,
            ),
        ],
      ),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── Filter Section Header ──
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardBg,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Filters',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                      color: subTextColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      // Date Range Custom Selector
                      Expanded(
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: _pickDateRange,
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: _selectedDateRange != null
                                    ? _primaryBlue.withValues(alpha: 0.08)
                                    : isDark
                                        ? const Color(0xFF0F172A)
                                        : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: _selectedDateRange != null
                                      ? _primaryBlue
                                      : isDark
                                          ? const Color(0xFF334155)
                                          : const Color(0xFFE2E8F0),
                                  width: _selectedDateRange != null ? 1.5 : 1.0,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: _selectedDateRange != null
                                          ? _primaryBlue
                                          : isDark
                                              ? Colors.white10
                                              : Colors.grey.shade300,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.calendar_today_rounded,
                                      size: 14,
                                      color: _selectedDateRange != null
                                          ? Colors.white
                                          : subTextColor,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Date Range',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: subTextColor,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          _selectedDateRange == null
                                              ? 'Select Date'
                                              : '${DateFormat('dd/MM').format(_selectedDateRange!.start)} - ${DateFormat('dd/MM').format(_selectedDateRange!.end)}',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: _selectedDateRange == null
                                                ? (isDark
                                                    ? Colors.amber.shade300
                                                    : Colors.amber.shade800)
                                                : textColor,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    Icons.arrow_drop_down_rounded,
                                    color: subTextColor,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Branch Custom Selector (No Flutter Default Dropdown)
                      Expanded(
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => _showBranchPickerBottomSheet(isDark),
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: _selectedBranch != null
                                    ? _primaryBlue.withValues(alpha: 0.08)
                                    : isDark
                                        ? const Color(0xFF0F172A)
                                        : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: _selectedBranch != null
                                      ? _primaryBlue
                                      : isDark
                                          ? const Color(0xFF334155)
                                          : const Color(0xFFE2E8F0),
                                  width: _selectedBranch != null ? 1.5 : 1.0,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: _selectedBranch != null
                                          ? _primaryBlue
                                          : isDark
                                              ? Colors.white10
                                              : Colors.grey.shade300,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.storefront_rounded,
                                      size: 14,
                                      color: _selectedBranch != null
                                          ? Colors.white
                                          : subTextColor,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Branch',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: subTextColor,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          _selectedBranch ?? 'Select Branch',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: _selectedBranch == null
                                                ? (isDark
                                                    ? Colors.amber.shade300
                                                    : Colors.amber.shade800)
                                                : textColor,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    color: subTextColor,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // ── Body Area ──
          if (!_hasFetched) ...[
            // Prompt to select filters
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: _primaryBlue.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.filter_alt_rounded,
                          size: 54,
                          color: _primaryBlue,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Select Date Range & Branch',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Please choose a Date Range and a Branch above to view total leads created by CC, DME, SME, and SALES.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: subTextColor,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ] else if (_loadingLeads) ...[
            const SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(strokeWidth: 3),
                    SizedBox(height: 16),
                    Text(
                      'Calculating leads by source...',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            // Summary Stat Cards & Visual Distribution
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Total Hero Card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF005BAC), Color(0xFF003B73)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: _primaryBlue.withValues(alpha: 0.35),
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'TOTAL LEADS CREATED',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '${_allLeads.length}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 34,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Branch: ${_selectedBranch ?? ''}  •  ${_formatDate(_selectedDateRange!.start)} - ${_formatDate(_selectedDateRange!.end)}',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Icon(
                              Icons.analytics_rounded,
                              color: Colors.white,
                              size: 36,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    Text(
                      'Source Breakdown',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 4 Source Grid Cards: CC, DME, SME, SALES
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 1.35,
                      children: [
                        _buildSourceCard(
                          title: 'CC (Customer Calling)',
                          code: 'CC',
                          count: _ccCount,
                          total: _allLeads.length,
                          color: const Color(0xFFF59E0B), // Amber/Orange
                          icon: Icons.phone_in_talk_rounded,
                          isDark: isDark,
                        ),
                        _buildSourceCard(
                          title: 'DME (Digital)',
                          code: 'DME',
                          count: _dmeCount,
                          total: _allLeads.length,
                          color: const Color(0xFF8B5CF6), // Purple
                          icon: Icons.campaign_rounded,
                          isDark: isDark,
                        ),
                        _buildSourceCard(
                          title: 'SME (Social Media)',
                          code: 'SME',
                          count: _smeCount,
                          total: _allLeads.length,
                          color: const Color(0xFF0EA5E9), // Sky Blue
                          icon: Icons.share_rounded,
                          isDark: isDark,
                        ),
                        _buildSourceCard(
                          title: 'SALES',
                          code: 'SALES',
                          count: _salesCount,
                          total: _allLeads.length,
                          color: const Color(0xFF10B981), // Emerald
                          icon: Icons.trending_up_rounded,
                          isDark: isDark,
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // Distribution Progress Bar
                    if (_allLeads.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF334155)
                                : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Proportional Share',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: textColor,
                              ),
                            ),
                            const SizedBox(height: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: SizedBox(
                                height: 12,
                                child: Row(
                                  children: [
                                    if (_ccCount > 0)
                                      Expanded(
                                        flex: _ccCount,
                                        child: Container(
                                            color: const Color(0xFFF59E0B)),
                                      ),
                                    if (_dmeCount > 0)
                                      Expanded(
                                        flex: _dmeCount,
                                        child: Container(
                                            color: const Color(0xFF8B5CF6)),
                                      ),
                                    if (_smeCount > 0)
                                      Expanded(
                                        flex: _smeCount,
                                        child: Container(
                                            color: const Color(0xFF0EA5E9)),
                                      ),
                                    if (_salesCount > 0)
                                      Expanded(
                                        flex: _salesCount,
                                        child: Container(
                                            color: const Color(0xFF10B981)),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Source Filter Tabs for detailed lead listing
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Lead Details',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                        Text(
                          '${_displayedLeads.length} leads',
                          style: TextStyle(
                            fontSize: 13,
                            color: subTextColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        children: [
                          _buildFilterChip('ALL', 'All (${_allLeads.length})'),
                          _buildFilterChip('CC', 'CC ($_ccCount)'),
                          _buildFilterChip('DME', 'DME ($_dmeCount)'),
                          _buildFilterChip('SME', 'SME ($_smeCount)'),
                          _buildFilterChip('SALES', 'Sales ($_salesCount)'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Lead List
            if (_displayedLeads.isEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: Text(
                      'No leads match the selected source filter.',
                      style: TextStyle(color: subTextColor, fontSize: 14),
                    ),
                  ),
                ),
              ),
            ] else ...[
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final lead = _displayedLeads[index];
                      final name = lead['customer_name'] ??
                          lead['name'] ??
                          'Unknown Lead';
                      final phone = lead['phone'] ?? lead['mobile'] ?? 'N/A';
                      final status = lead['status'] ?? 'In Progress';
                      final source = _normalizeSource(lead['source']);
                      final createdDate = lead['created_at'] is Timestamp
                          ? (lead['created_at'] as Timestamp).toDate()
                          : null;
                      final branchName = lead['branch'] ?? '';

                      Color statusColor;
                      if (status == 'Sale' || status == 'Sold') {
                        statusColor = const Color(0xFF10B981);
                      } else if (status == 'Cancelled') {
                        statusColor = const Color(0xFFEF4444);
                      } else {
                        statusColor = const Color(0xFF3B82F6);
                      }

                      Color sourceBadgeColor;
                      if (source == 'CC') {
                        sourceBadgeColor = const Color(0xFFF59E0B);
                      } else if (source == 'DME') {
                        sourceBadgeColor = const Color(0xFF8B5CF6);
                      } else if (source == 'SME') {
                        sourceBadgeColor = const Color(0xFF0EA5E9);
                      } else {
                        sourceBadgeColor = const Color(0xFF10B981);
                      }

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              final docId = lead['docId'] as String?;
                              if (docId != null && docId.isNotEmpty) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        PresentFollowUp(docId: docId),
                                  ),
                                );
                              }
                            },
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: cardBg,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isDark
                                      ? const Color(0xFF334155)
                                      : const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color:
                                          sourceBadgeColor.withValues(alpha: 0.12),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: Text(
                                        source,
                                        style: TextStyle(
                                          color: sourceBadgeColor,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            color: textColor,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Icon(Icons.phone_rounded,
                                                size: 13, color: subTextColor),
                                            const SizedBox(width: 4),
                                            Text(
                                              phone,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: subTextColor,
                                              ),
                                            ),
                                            if (branchName.isNotEmpty) ...[
                                              const SizedBox(width: 8),
                                              Text('•',
                                                  style: TextStyle(
                                                      color: subTextColor)),
                                              const SizedBox(width: 8),
                                              Text(
                                                branchName,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: subTextColor,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: statusColor.withValues(alpha: 0.12),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          status,
                                          style: TextStyle(
                                            color: statusColor,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      if (createdDate != null) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          DateFormat('dd MMM').format(createdDate),
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: subTextColor,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                    childCount: _displayedLeads.length,
                  ),
                ),
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 30)),
          ],
        ],
      ),
    );
  }

  Widget _buildSourceCard({
    required String title,
    required String code,
    required int count,
    required int total,
    required Color color,
    required IconData icon,
    required bool isDark,
  }) {
    final pct = total > 0 ? (count / total * 100).toStringAsFixed(1) : '0.0';
    final isSelected = _activeSourceFilter == code;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() {
            _activeSourceFilter = _activeSourceFilter == code ? 'ALL' : code;
          });
        },
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isSelected
                ? color.withValues(alpha: 0.15)
                : isDark
                    ? const Color(0xFF1E293B)
                    : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? color
                  : isDark
                      ? const Color(0xFF334155)
                      : const Color(0xFFE2E8F0),
              width: isSelected ? 2.0 : 1.0,
            ),
            boxShadow: [
              if (isSelected)
                BoxShadow(
                  color: color.withValues(alpha: 0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              else
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: color, size: 18),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$pct%',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(String code, String label) {
    final isSelected = _activeSourceFilter == code;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        selected: isSelected,
        label: Text(label),
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          color: isSelected
              ? Colors.white
              : isDark
                  ? Colors.white70
                  : const Color(0xFF475569),
        ),
        selectedColor: _primaryBlue,
        backgroundColor:
            isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
        checkmarkColor: Colors.white,
        onSelected: (val) {
          setState(() {
            _activeSourceFilter = val ? code : 'ALL';
          });
        },
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: isSelected
                ? _primaryBlue
                : isDark
                    ? const Color(0xFF334155)
                    : const Color(0xFFE2E8F0),
          ),
        ),
      ),
    );
  }
}
