import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'supersale_admin_booking_report.dart';
import 'supersale_admin_delivery_report.dart';
import 'supersale_admin_full_report.dart';
import 'supersale_admin_monthly_report.dart';
import 'supersale_admin_report.dart';
import 'supersale_admin_dashboard_models.dart';
import 'supersale_admin_dashboard_excel.dart';

const Color _primaryBlue = Color(0xFF005BAC);
const Color _primaryGreen = Color(0xFF8CC63F);

class SupersaleAdminDashboardPage extends StatefulWidget {
  const SupersaleAdminDashboardPage({super.key});

  @override
  State<SupersaleAdminDashboardPage> createState() =>
      _SupersaleAdminDashboardPageState();
}

class _SupersaleAdminDashboardPageState
    extends State<SupersaleAdminDashboardPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  bool _isLoading = true;
  bool _isLoadingEntries = false;
  bool _isExporting = false;
  String? _errorMessage;

  SupersaleDashboardBundle? _bundle;
  SupersaleComputedAnalytics? _analytics;

  // Global Filters - initial selection is null so user must choose before data is fetched/displayed
  String? _selectedCampaignId; // null => No campaign selected
  String? _selectedBranch; // null => No branch selected
  DateTimeRange? _selectedDateRange;

  bool get _hasSelection => _selectedCampaignId != null || _selectedBranch != null;

  // Sub-view toggles & filters
  String _branchSubTab = 'booking'; // 'booking' | 'delivery'
  String _staffSubTab = 'performance'; // 'performance' | 'non_participants'
  String _selectedRoleFilter = 'all'; // 'all', 'manager', 'asst_manager', 'sales'
  String _staffSearchQuery = '';
  String _auditSubTab = 'spot_vs_booking'; // 'spot_vs_booking' | 'cancelled' | 'split'
  String _orderStatusFilter = 'all'; // 'all', 'pending', 'delivered', 'spot', 'overdue', 'cancelled'
  String _orderSearchQuery = '';
  Timer? _staffSearchDebounce;
  Timer? _orderSearchDebounce;

  // Monthly Excel Quick Export controls
  int _exportYear = DateTime.now().year;
  int _exportMonth = DateTime.now().month;

  final NumberFormat _currencyFmt =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
  final NumberFormat _qtyFmt = NumberFormat('#,##0.##');
  final DateFormat _shortDateFmt = DateFormat('dd MMM yy');
  final DateFormat _dateTimeFmt = DateFormat('dd MMM yyyy, hh:mm a');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _loadDashboardData();
  }

  @override
  void dispose() {
    _staffSearchDebounce?.cancel();
    _orderSearchDebounce?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadDashboardData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Only fetch lightweight metadata (campaigns and branches) on initial entrance
      final bundle = await SupersaleDashboardService.fetchMetadata();
      if (!mounted) return;
      _bundle = bundle;
      if (_hasSelection) {
        await _fetchEntriesAndRecompute();
      } else {
        setState(() {
          _analytics = null;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to load Supersale dashboard: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchEntriesAndRecompute() async {
    final bundle = _bundle;
    if (bundle == null) return;

    if (!_hasSelection) {
      setState(() {
        _analytics = null;
        _isLoadingEntries = false;
      });
      return;
    }

    setState(() => _isLoadingEntries = true);

    try {
      final entries = await SupersaleDashboardService.fetchEntriesForSelection(
        campaigns: bundle.allCampaigns,
        branches: bundle.allBranches,
        selectedCampaignId: _selectedCampaignId,
        selectedBranch: _selectedBranch,
      );

      final updatedBundle = bundle.copyWith(allEntries: entries);
      _bundle = updatedBundle;

      final computed = SupersaleDashboardService.computeAnalytics(
        bundle: updatedBundle,
        selectedCampaignId: _selectedCampaignId,
        selectedBranch: _selectedBranch,
        dateRange: _selectedDateRange,
      );

      if (mounted) {
        setState(() {
          _analytics = computed;
          _isLoadingEntries = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingEntries = false;
        });
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text('Failed to load report data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _recomputeLocalFilters() {
    final bundle = _bundle;
    if (bundle == null || !_hasSelection) return;

    final computed = SupersaleDashboardService.computeAnalytics(
      bundle: bundle,
      selectedCampaignId: _selectedCampaignId,
      selectedBranch: _selectedBranch,
      dateRange: _selectedDateRange,
    );

    setState(() {
      _analytics = computed;
    });
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _selectedDateRange,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: _primaryBlue,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black87,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && mounted) {
      setState(() {
        _selectedDateRange = picked;
      });
      _recomputeLocalFilters();
    }
  }

  String _buildActiveFilterLabel() {
    final parts = <String>[];
    if (_selectedCampaignId != null && _bundle != null) {
      final match = _bundle!.allCampaigns
          .where((c) => c.id == _selectedCampaignId)
          .toList();
      if (match.isNotEmpty) {
        parts.add(match.first.item);
      }
    }
    if (_selectedBranch != null) {
      parts.add('Branch: $_selectedBranch');
    }
    if (_selectedDateRange != null) {
      parts.add(
        '${_shortDateFmt.format(_selectedDateRange!.start)} - ${_shortDateFmt.format(_selectedDateRange!.end)}',
      );
    }
    return parts.isEmpty ? 'Select a Campaign or Branch' : parts.join(' • ');
  }

  Future<void> _exportMasterExcel() async {
    final analytics = _analytics;
    if (analytics == null || _isExporting) return;

    setState(() => _isExporting = true);
    try {
      await generateSupersaleMasterDashboardExcel(
        analytics: analytics,
        filterLabel: _buildActiveFilterLabel(),
      );
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text('Master Dashboard Excel generated! Opening share sheet...'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text('Failed to export Excel: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _exportCampaignSpecificExcel(
    SupersaleCampaignModel campaign,
    String reportType,
  ) async {
    if (_isExporting) return;
    setState(() => _isExporting = true);
    try {
      final branches = campaign.effectiveBranches;
      if (reportType == 'booking') {
        await generateBookingReport(
          selectedItem: campaign.item,
          activeBranches: branches,
          adminPostingId: campaign.id,
        );
      } else if (reportType == 'delivery') {
        await generateDeliveryReport(
          selectedItem: campaign.item,
          activeBranches: branches,
          adminPostingId: campaign.id,
        );
      } else {
        await generateFullReport(
          selectedItem: campaign.item,
          activeBranches: branches,
          adminPostingId: campaign.id,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text('Report generation failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _exportMonthlyExcel({required bool isSummary}) async {
    if (_isExporting) return;
    setState(() => _isExporting = true);
    try {
      await generateMonthlyReport(
        year: _exportYear,
        month: _exportMonth,
        isSummary: isSummary,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text('Monthly report failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0A1628) : const Color(0xFFF4F7FB);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text(
          'Supersale Dashboard',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19),
        ),
        backgroundColor: _primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.date_range_rounded),
            tooltip: 'Filter by Date Range',
            onPressed: _pickDateRange,
          ),
          IconButton(
            icon: _isExporting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.download_rounded),
            tooltip: 'Export Master Dashboard Excel',
            onPressed: _isExporting ? null : _exportMasterExcel,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Data',
            onPressed: _isLoading ? null : _loadDashboardData,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: _primaryGreen,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard_rounded, size: 18), text: 'Overview & Campaigns'),
            Tab(icon: Icon(Icons.store_rounded, size: 18), text: 'Branch Reports'),
            Tab(icon: Icon(Icons.people_alt_rounded, size: 18), text: 'Staff Performance'),
            Tab(icon: Icon(Icons.warning_amber_rounded, size: 18), text: 'Overdue & Pending'),
            Tab(icon: Icon(Icons.bolt_rounded, size: 18), text: 'Spot Sale & Audit'),
            Tab(icon: Icon(Icons.table_view_rounded, size: 18), text: 'Orders & Exports'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _primaryBlue))
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline_rounded,
                            size: 56, color: Colors.redAccent),
                        const SizedBox(height: 12),
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _loadDashboardData,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Retry'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primaryBlue,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    _buildGlobalFilterBar(isDark),
                    Expanded(
                      child: _isLoadingEntries
                          ? const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  CircularProgressIndicator(
                                      color: _primaryBlue),
                                  SizedBox(height: 14),
                                  Text(
                                    'Loading report data...',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : !_hasSelection || _analytics == null
                              ? _buildSelectPromptState(isDark)
                              : TabBarView(
                                  controller: _tabController,
                                  children: [
                                    _buildOverviewAndCampaignsTab(isDark),
                                    _buildBranchReportsTab(isDark),
                                    _buildStaffPerformanceTab(isDark),
                                    _buildOverdueAndPendingTab(isDark),
                                    _buildSpotSaleAndAuditTab(isDark),
                                    _buildOrdersAndExportsTab(isDark),
                                  ],
                                ),
                    ),
                  ],
                ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GLOBAL FILTER BAR
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildGlobalFilterBar(bool isDark) {
    final campaigns = _bundle?.allCampaigns ?? [];
    final branches = _bundle?.allBranches ?? [];

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF162238) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Campaign Dropdown
              Expanded(
                flex: 3,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : Colors.grey[100],
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isDark ? Colors.white12 : Colors.grey[300]!,
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      value: _selectedCampaignId,
                      isExpanded: true,
                      isDense: true,
                      dropdownColor:
                          isDark ? const Color(0xFF1E293B) : Colors.white,
                      icon: const Icon(Icons.keyboard_arrow_down_rounded,
                          color: _primaryBlue, size: 20),
                      items: [
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Text(
                            'Select Campaign (${campaigns.length})',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white70 : Colors.black54,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        ...campaigns.map((c) {
                          return DropdownMenuItem<String?>(
                            value: c.id,
                            child: Text(
                              '${c.item} (${_shortDateFmt.format(c.bookingStart)})',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }),
                      ],
                      onChanged: (val) {
                        setState(() => _selectedCampaignId = val);
                        _fetchEntriesAndRecompute();
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Branch Dropdown
              Expanded(
                flex: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : Colors.grey[100],
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isDark ? Colors.white12 : Colors.grey[300]!,
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      value: _selectedBranch,
                      isExpanded: true,
                      isDense: true,
                      dropdownColor:
                          isDark ? const Color(0xFF1E293B) : Colors.white,
                      icon: const Icon(Icons.keyboard_arrow_down_rounded,
                          color: _primaryBlue, size: 20),
                      items: [
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Text(
                            'Select Branch (${branches.length})',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white70 : Colors.black54,
                            ),
                          ),
                        ),
                        ...branches.map((b) {
                          return DropdownMenuItem<String?>(
                            value: b,
                            child: Text(
                              b,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                          );
                        }),
                      ],
                      onChanged: (val) {
                        setState(() => _selectedBranch = val);
                        _fetchEntriesAndRecompute();
                      },
                    ),
                  ),
                ),
              ),
              if (_selectedCampaignId != null ||
                  _selectedBranch != null ||
                  _selectedDateRange != null) ...[
                const SizedBox(width: 6),
                InkWell(
                  onTap: () {
                    setState(() {
                      _selectedCampaignId = null;
                      _selectedBranch = null;
                      _selectedDateRange = null;
                      _analytics = null;
                    });
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.filter_alt_off_rounded,
                        size: 18, color: Colors.redAccent),
                  ),
                ),
              ],
            ],
          ),
          if (_selectedDateRange != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.calendar_month_rounded,
                    size: 14, color: _primaryBlue),
                const SizedBox(width: 6),
                Text(
                  'Date Filter: ${_shortDateFmt.format(_selectedDateRange!.start)} – ${_shortDateFmt.format(_selectedDateRange!.end)}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : _primaryBlue,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    setState(() => _selectedDateRange = null);
                    _recomputeLocalFilters();
                  },
                  child: const Text(
                    'Clear Date',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 1: OVERVIEW & CAMPAIGN-WISE REPORT
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildOverviewAndCampaignsTab(bool isDark) {
    final a = _analytics!;
    final now = DateTime.now();

    return RefreshIndicator(
      onRefresh: _loadDashboardData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Executive KPI Grid (8 cards)
          _buildSectionHeader(
            title: 'Executive KPI Summary',
            subtitle: _buildActiveFilterLabel(),
            icon: Icons.speed_rounded,
            isDark: isDark,
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.55,
            children: [
              _buildKpiCard(
                title: 'Total Bookings',
                mainValue: '${a.totalValidOrders} Orders',
                subValue: 'Qty: ${_qtyFmt.format(a.totalBookedQty)} units',
                icon: Icons.shopping_bag_rounded,
                gradient: const [Color(0xFF005BAC), Color(0xFF1976D2)],
                onTap: () => _tabController.animateTo(5),
              ),
              _buildKpiCard(
                title: 'Total Order Value',
                mainValue: _currencyFmt.format(a.totalOrderAmount),
                subValue: 'Advance: ${_currencyFmt.format(a.totalAdvanceAmount)}',
                icon: Icons.currency_rupee_rounded,
                gradient: const [Color(0xFF2E7D32), Color(0xFF66BB6A)],
                onTap: () => _tabController.animateTo(1),
              ),
              _buildKpiCard(
                title: 'Delivered (${a.deliveryFulfillmentPct.toStringAsFixed(1)}%)',
                mainValue: '${_qtyFmt.format(a.deliveredQty)} Qty',
                subValue:
                    '${a.deliveredOrders} orders • ${_currencyFmt.format(a.deliveredAmount)}',
                icon: Icons.check_circle_rounded,
                gradient: const [Color(0xFF00796B), Color(0xFF26A69A)],
                onTap: () {
                  setState(() => _branchSubTab = 'delivery');
                  _tabController.animateTo(1);
                },
              ),
              _buildKpiCard(
                title: 'Pending Delivery',
                mainValue: '${_qtyFmt.format(a.pendingQty)} Qty',
                subValue:
                    '${a.pendingOrders} orders • ${_currencyFmt.format(a.pendingAmount)}',
                icon: Icons.pending_actions_rounded,
                gradient: const [Color(0xFFE65100), Color(0xFFFF9800)],
                onTap: () => _tabController.animateTo(3),
              ),
              _buildKpiCard(
                title: 'Spot Sales (${a.spotSaleQtySharePct.toStringAsFixed(1)}%)',
                mainValue: '${_qtyFmt.format(a.spotSaleQty)} Qty',
                subValue:
                    '${a.spotSaleOrders} orders • ${_currencyFmt.format(a.spotSaleAmount)}',
                icon: Icons.flash_on_rounded,
                gradient: const [Color(0xFF6A1B9A), Color(0xFFAB47BC)],
                onTap: () => _tabController.animateTo(4),
              ),
              _buildKpiCard(
                title: 'Pre-Bookings',
                mainValue: '${_qtyFmt.format(a.normalBookingQty)} Qty',
                subValue:
                    '${a.normalBookingOrders} orders • ${_currencyFmt.format(a.normalBookingAmount)}',
                icon: Icons.bookmark_added_rounded,
                gradient: const [Color(0xFF1565C0), Color(0xFF42A5F5)],
                onTap: () => _tabController.animateTo(4),
              ),
              _buildKpiCard(
                title: 'Overdue Orders',
                mainValue: '${a.overdueOrders} Overdue',
                subValue: 'Past delivery deadline',
                icon: Icons.warning_rounded,
                gradient: const [Color(0xFFC62828), Color(0xFFEF5350)],
                onTap: () => _tabController.animateTo(3),
              ),
              _buildKpiCard(
                title: 'Campaigns & Cancelled',
                mainValue: '${a.totalCampaigns} Campaigns',
                subValue:
                    'Open: ${a.activeBookingCampaigns} • Cancelled: ${a.cancelledOrders}',
                icon: Icons.campaign_rounded,
                gradient: const [Color(0xFF37474F), Color(0xFF607D8B)],
                onTap: () {
                  setState(() => _auditSubTab = 'cancelled');
                  _tabController.animateTo(4);
                },
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Fulfillment Progress Card
          _buildFulfillmentOverviewCard(a, isDark),

          const SizedBox(height: 24),

          // Campaign-Wise Performance Report Section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: _buildSectionHeader(
                  title: 'Campaign-Wise Performance Report',
                  subtitle:
                      'Tap any campaign to filter dashboard or export Excel',
                  icon: Icons.analytics_rounded,
                  isDark: isDark,
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SupersaleAdminReportPage(),
                    ),
                  );
                },
                icon: const Icon(Icons.file_download_outlined, size: 18),
                label: const Text('Report Page'),
              ),
            ],
          ),
          const SizedBox(height: 10),

          if (a.campaignRows.isEmpty)
            _buildEmptyCard('No campaigns match the current filter.', isDark)
          else
            ...a.campaignRows.map((row) => _buildCampaignReportCard(row, now, isDark)),
        ],
      ),
    );
  }

  Widget _buildFulfillmentOverviewCard(
      SupersaleComputedAnalytics a, bool isDark) {
    final double delPct = (a.deliveryFulfillmentPct / 100.0).clamp(0.0, 1.0);
    final double spotPct = (a.spotSaleQtySharePct / 100.0).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.grey[200]!,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Overall Delivery Fulfillment',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              Text(
                '${a.deliveryFulfillmentPct.toStringAsFixed(1)}% Delivered',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: _primaryGreen,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: delPct,
              minHeight: 10,
              backgroundColor: Colors.orange.withValues(alpha: 0.2),
              valueColor: const AlwaysStoppedAnimation<Color>(_primaryGreen),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Delivered: ${_qtyFmt.format(a.deliveredQty)} Qty (${_currencyFmt.format(a.deliveredAmount)})',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
              Text(
                'Pending: ${_qtyFmt.format(a.pendingQty)} Qty (${_currencyFmt.format(a.pendingAmount)})',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.orange[300] : Colors.orange[800],
                ),
              ),
            ],
          ),
          const Divider(height: 22),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Spot Sale vs Pre-Booking Split',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              Text(
                '${a.spotSaleQtySharePct.toStringAsFixed(1)}% Spot Sale',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Colors.purpleAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: spotPct,
              minHeight: 10,
              backgroundColor: _primaryBlue.withValues(alpha: 0.25),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.purple),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Spot Sale: ${_qtyFmt.format(a.spotSaleQty)} Qty (${a.spotSaleOrders} orders)',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
              Text(
                'Pre-Booking: ${_qtyFmt.format(a.normalBookingQty)} Qty (${a.normalBookingOrders} orders)',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCampaignReportCard(
      CampaignReportRow row, DateTime now, bool isDark) {
    final c = row.campaign;
    final status = c.statusLabel(now);
    final Color badgeColor = status == 'Booking Open'
        ? _primaryGreen
        : (status == 'Delivery Active' ? _primaryBlue : Colors.grey);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _selectedCampaignId == c.id
              ? _primaryBlue
              : (isDark ? Colors.white12 : Colors.grey[200]!),
          width: _selectedCampaignId == c.id ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _primaryBlue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.flash_on_rounded,
                      color: _primaryBlue, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.item,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Booking: ${_shortDateFmt.format(c.bookingStart)} - ${_shortDateFmt.format(c.bookingEnd)} • Deliv End: ${_shortDateFmt.format(c.deliveryEnd)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white54 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: badgeColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildMiniStat(
                    'Booked Qty', _qtyFmt.format(row.bookedQty), _primaryBlue, isDark),
                _buildMiniStat('Delivered', _qtyFmt.format(row.deliveredQty),
                    _primaryGreen, isDark),
                _buildMiniStat(
                    'Pending', _qtyFmt.format(row.pendingQty), Colors.orange, isDark),
                _buildMiniStat(
                    'Spot Qty', _qtyFmt.format(row.spotSaleQty), Colors.purple, isDark),
                _buildMiniStat('Value', _currencyFmt.format(row.totalAmount),
                    Colors.teal, isDark),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: (row.deliveryPct / 100.0).clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: Colors.grey.withValues(alpha: 0.2),
                valueColor: const AlwaysStoppedAnimation<Color>(_primaryGreen),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  '${row.totalOrders} orders • ${row.activeBranches.length} branches • ${row.participatingUsers.length} staff • ${row.deliveryPct.toStringAsFixed(0)}% delivered',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
                const Spacer(),
                if (row.overdueOrders > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${row.overdueOrders} Overdue',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.redAccent,
                      ),
                    ),
                  ),
              ],
            ),
            const Divider(height: 18),
            // Quick actions for this campaign
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _buildActionChip(
                  label: _selectedCampaignId == c.id
                      ? 'Clear Filter'
                      : 'Filter Dashboard',
                  icon: Icons.filter_alt_rounded,
                  color: _primaryBlue,
                  onTap: () {
                    setState(() {
                      _selectedCampaignId =
                          _selectedCampaignId == c.id ? null : c.id;
                    });
                    _fetchEntriesAndRecompute();
                  },
                ),
                _buildActionChip(
                  label: 'Booking Excel',
                  icon: Icons.receipt_long_rounded,
                  color: _primaryGreen,
                  onTap: () => _exportCampaignSpecificExcel(c, 'booking'),
                ),
                _buildActionChip(
                  label: 'Delivery Excel',
                  icon: Icons.local_shipping_rounded,
                  color: Colors.teal,
                  onTap: () => _exportCampaignSpecificExcel(c, 'delivery'),
                ),
                _buildActionChip(
                  label: 'Full Excel',
                  icon: Icons.table_chart_rounded,
                  color: Colors.deepOrange,
                  onTap: () => _exportCampaignSpecificExcel(c, 'full'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 2: BRANCH-WISE REPORTS (BOOKING SUMMARY & DELIVERY SUMMARY)
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildBranchReportsTab(bool isDark) {
    final a = _analytics!;

    return Column(
      children: [
        // Toggle bar between Branch Booking & Revenue vs Branch Delivery & Fulfillment
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: isDark ? const Color(0xFF162238) : Colors.white,
          child: Row(
            children: [
              Expanded(
                child: _buildSegmentedButton(
                  title: 'Booking & Revenue (${a.branchBookingRows.length})',
                  icon: Icons.receipt_long_rounded,
                  isSelected: _branchSubTab == 'booking',
                  isDark: isDark,
                  onTap: () => setState(() => _branchSubTab = 'booking'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildSegmentedButton(
                  title: 'Delivery & Pending (${a.branchDeliveryRows.length})',
                  icon: Icons.local_shipping_rounded,
                  isSelected: _branchSubTab == 'delivery',
                  isDark: isDark,
                  onTap: () => setState(() => _branchSubTab = 'delivery'),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _branchSubTab == 'booking'
              ? _buildBranchBookingReportList(a, isDark)
              : _buildBranchDeliveryReportList(a, isDark),
        ),
      ],
    );
  }

  Widget _buildBranchBookingReportList(
      SupersaleComputedAnalytics a, bool isDark) {
    if (a.branchBookingRows.isEmpty) {
      return Center(
        child: _buildEmptyCard(
            'No branch booking entries found for the selected filter.', isDark),
      );
    }

    final double maxQty = a.branchBookingRows
        .map((r) => r.totalQty)
        .fold(0.0, (prev, el) => el > prev ? el : prev);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Grand Total Banner
        Container(
          padding: const EdgeInsets.all(14),
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_primaryBlue, Color(0xFF1976D2)],
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildBannerStat('Branches', '${a.branchBookingRows.length}'),
              _buildBannerStat('Total Qty', _qtyFmt.format(a.totalBookedQty)),
              _buildBannerStat(
                  'Total Amount', _currencyFmt.format(a.totalOrderAmount)),
              _buildBannerStat(
                  'Total Advance', _currencyFmt.format(a.totalAdvanceAmount)),
            ],
          ),
        ),
        ...a.branchBookingRows.asMap().entries.map((entry) {
          final rank = entry.key + 1;
          final row = entry.value;
          final ratio = maxQty > 0 ? (row.totalQty / maxQty).clamp(0.0, 1.0) : 0.0;

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark ? Colors.white12 : Colors.grey[200]!,
              ),
            ),
            child: InkWell(
              onTap: () {
                setState(() {
                  _selectedBranch =
                      _selectedBranch == row.branch ? null : row.branch;
                });
                _fetchEntriesAndRecompute();
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: rank <= 3
                            ? _primaryGreen.withValues(alpha: 0.2)
                            : _primaryBlue.withValues(alpha: 0.12),
                        child: Text(
                          '#$rank',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: rank <= 3 ? _primaryGreen : _primaryBlue,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        row.branch,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '(${row.totalOrders} orders)',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white54 : Colors.black54,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${_qtyFmt.format(row.totalQty)} Qty',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: _primaryBlue,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: 6,
                      backgroundColor: _primaryBlue.withValues(alpha: 0.12),
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(_primaryBlue),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _buildMiniStat(
                        'Total Amount',
                        _currencyFmt.format(row.totalAmount),
                        _primaryBlue,
                        isDark,
                      ),
                      _buildMiniStat(
                        'Advance',
                        _currencyFmt.format(row.totalAdvance),
                        _primaryGreen,
                        isDark,
                      ),
                      _buildMiniStat(
                        'Pre-Book Qty',
                        _qtyFmt.format(row.normalQty),
                        Colors.indigo,
                        isDark,
                      ),
                      _buildMiniStat(
                        'Spot Qty',
                        _qtyFmt.format(row.spotQty),
                        Colors.purple,
                        isDark,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildBranchDeliveryReportList(
      SupersaleComputedAnalytics a, bool isDark) {
    if (a.branchDeliveryRows.isEmpty) {
      return Center(
        child: _buildEmptyCard(
            'No branch delivery data found for the selected filter.', isDark),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF00796B), Color(0xFF26A69A)],
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildBannerStat('Booked Qty', _qtyFmt.format(a.totalBookedQty)),
              _buildBannerStat('Delivered', _qtyFmt.format(a.deliveredQty)),
              _buildBannerStat('Pending', _qtyFmt.format(a.pendingQty)),
              _buildBannerStat(
                  'Fulfillment', '${a.deliveryFulfillmentPct.toStringAsFixed(1)}%'),
            ],
          ),
        ),
        ...a.branchDeliveryRows.map((row) {
          final pct = (row.deliveryPct / 100.0).clamp(0.0, 1.0);
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark ? Colors.white12 : Colors.grey[200]!,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      row.branch,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: _primaryGreen.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${row.deliveryPct.toStringAsFixed(1)}% Delivered',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: _primaryGreen,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (row.overdueOrders > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${row.overdueOrders} Overdue',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.redAccent,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 7,
                    backgroundColor: Colors.orange.withValues(alpha: 0.25),
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(_primaryGreen),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _buildMiniStat(
                      'Total Booked',
                      _qtyFmt.format(row.totalBookingQty),
                      _primaryBlue,
                      isDark,
                    ),
                    _buildMiniStat(
                      'Delivered',
                      _qtyFmt.format(row.deliveredQty),
                      _primaryGreen,
                      isDark,
                    ),
                    _buildMiniStat(
                      'Pending',
                      _qtyFmt.format(row.pendingQty),
                      Colors.orange,
                      isDark,
                    ),
                    _buildMiniStat(
                      'Cancelled',
                      _qtyFmt.format(row.cancelledQty),
                      Colors.redAccent,
                      isDark,
                    ),
                  ],
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 3: STAFF PERFORMANCE & NON-PARTICIPANTS REPORT
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildStaffPerformanceTab(bool isDark) {
    final a = _analytics!;

    final filteredPerformance = a.userPerformanceRows.where((u) {
      if (_selectedRoleFilter != 'all' &&
          u.role.toLowerCase() != _selectedRoleFilter) {
        return false;
      }
      if (_staffSearchQuery.isNotEmpty) {
        final q = _staffSearchQuery.toLowerCase();
        if (!u.username.toLowerCase().contains(q) &&
            !u.branch.toLowerCase().contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();

    final filteredNonParticipants = a.nonParticipantRows.where((u) {
      if (_selectedRoleFilter != 'all' &&
          u.role.toLowerCase() != _selectedRoleFilter) {
        return false;
      }
      if (_staffSearchQuery.isNotEmpty) {
        final q = _staffSearchQuery.toLowerCase();
        if (!u.username.toLowerCase().contains(q) &&
            !u.branch.toLowerCase().contains(q) &&
            !u.campaignItem.toLowerCase().contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          color: isDark ? const Color(0xFF162238) : Colors.white,
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildSegmentedButton(
                      title: 'Staff Leaderboard (${filteredPerformance.length})',
                      icon: Icons.leaderboard_rounded,
                      isSelected: _staffSubTab == 'performance',
                      isDark: isDark,
                      onTap: () => setState(() => _staffSubTab = 'performance'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildSegmentedButton(
                      title:
                          'Zero Orders / Non-Part. (${filteredNonParticipants.length})',
                      icon: Icons.person_off_rounded,
                      isSelected: _staffSubTab == 'non_participants',
                      isDark: isDark,
                      onTap: () =>
                          setState(() => _staffSubTab = 'non_participants'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: SizedBox(
                      height: 38,
                      child: TextField(
                        onChanged: (val) {
                          _staffSearchDebounce?.cancel();
                          _staffSearchDebounce = Timer(const Duration(milliseconds: 250), () {
                            if (mounted) setState(() => _staffSearchQuery = val.trim());
                          });
                        },
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Search staff or branch...',
                          prefixIcon: const Icon(Icons.search_rounded, size: 18),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 0),
                          filled: true,
                          fillColor: isDark
                              ? const Color(0xFF1E293B)
                              : Colors.grey[100],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: Container(
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color:
                            isDark ? const Color(0xFF1E293B) : Colors.grey[100],
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedRoleFilter,
                          isExpanded: true,
                          dropdownColor:
                              isDark ? const Color(0xFF1E293B) : Colors.white,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          items: const [
                            DropdownMenuItem(
                                value: 'all', child: Text('All Roles')),
                            DropdownMenuItem(
                                value: 'manager', child: Text('Manager')),
                            DropdownMenuItem(
                                value: 'asst_manager',
                                child: Text('Asst. Manager')),
                            DropdownMenuItem(
                                value: 'sales', child: Text('Sales')),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _selectedRoleFilter = val);
                            }
                          },
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
          child: _staffSubTab == 'performance'
              ? _buildStaffLeaderboardList(filteredPerformance, isDark)
              : _buildNonParticipantsList(filteredNonParticipants, isDark),
        ),
      ],
    );
  }

  Widget _buildStaffLeaderboardList(
      List<UserPerformanceReportRow> rows, bool isDark) {
    if (rows.isEmpty) {
      return Center(
        child: _buildEmptyCard('No matching staff records found.', isDark),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark ? Colors.white12 : Colors.grey[200]!,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: _primaryBlue.withValues(alpha: 0.12),
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _primaryBlue,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row.username,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        Text(
                          '${row.branch} • ${row.formattedRole} • Campaigns: ${row.participatedCampaigns}/${row.applicableCampaigns}',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white54 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _currencyFmt.format(row.totalAmount),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: _primaryGreen,
                        ),
                      ),
                      Text(
                        '${_qtyFmt.format(row.bookedQty)} Qty (${row.totalOrders} orders)',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _buildMiniStat('Delivered', _qtyFmt.format(row.deliveredQty),
                      _primaryGreen, isDark),
                  _buildMiniStat('Pending', _qtyFmt.format(row.pendingQty),
                      Colors.orange, isDark),
                  _buildMiniStat(
                      'Spot Orders', '${row.spotSaleOrders}', Colors.purple, isDark),
                  _buildMiniStat('Overdue', '${row.overdueOrders}',
                      row.overdueOrders > 0 ? Colors.redAccent : Colors.grey, isDark),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNonParticipantsList(
      List<NonParticipantRow> rows, bool isDark) {
    if (rows.isEmpty) {
      return Center(
        child: _buildEmptyCard(
            'All eligible users have participated in their applicable campaigns!',
            isDark),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final r = rows[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.redAccent.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.person_off_rounded,
                  color: Colors.redAccent, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.username,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    Text(
                      '${r.branch} • ${r.formattedRole}',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white54 : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    r.campaignItem,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: _primaryBlue,
                    ),
                  ),
                  Text(
                    'Deliv End: ${_shortDateFmt.format(r.deliveryEnd)}',
                    style: TextStyle(
                      fontSize: 10,
                      color: isDark ? Colors.white54 : Colors.black54,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 4: OVERDUE & PENDING DELIVERIES REPORT
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildOverdueAndPendingTab(bool isDark) {
    final a = _analytics!;
    final now = DateTime.now();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionHeader(
          title: 'Overdue Pending Deliveries (${a.overdueEntries.length})',
          subtitle:
              'Orders past their delivery reminder or campaign delivery end date',
          icon: Icons.warning_amber_rounded,
          isDark: isDark,
        ),
        const SizedBox(height: 10),
        if (a.overdueEntries.isEmpty)
          _buildEmptyCard('Zero overdue deliveries! All caught up.', isDark)
        else
          ...a.overdueEntries.map(
            (e) => _buildOrderEntryTile(e, isDark, now: now, highlightOverdue: true),
          ),
        const SizedBox(height: 24),
        _buildSectionHeader(
          title: 'All Pending Deliveries (${a.pendingEntries.length})',
          subtitle: 'Active bookings awaiting delivery completion',
          icon: Icons.pending_actions_rounded,
          isDark: isDark,
        ),
        const SizedBox(height: 10),
        if (a.pendingEntries.isEmpty)
          _buildEmptyCard('No pending deliveries for this filter.', isDark)
        else
          ...a.pendingEntries.take(100).map(
                (e) => _buildOrderEntryTile(e, isDark, now: now),
              ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 5: SPOT SALE VS PRE-BOOKING & AUDIT (CANCELLED & SPLIT DELIVERIES)
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildSpotSaleAndAuditTab(bool isDark) {
    final a = _analytics!;
    final now = DateTime.now();

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: isDark ? const Color(0xFF162238) : Colors.white,
          child: Row(
            children: [
              Expanded(
                child: _buildSegmentedButton(
                  title: 'Spot vs Booking',
                  icon: Icons.bolt_rounded,
                  isSelected: _auditSubTab == 'spot_vs_booking',
                  isDark: isDark,
                  onTap: () => setState(() => _auditSubTab = 'spot_vs_booking'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildSegmentedButton(
                  title: 'Cancelled (${a.cancelledOrders})',
                  icon: Icons.cancel_outlined,
                  isSelected: _auditSubTab == 'cancelled',
                  isDark: isDark,
                  onTap: () => setState(() => _auditSubTab = 'cancelled'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildSegmentedButton(
                  title: 'Split (${a.partialSplitOrders})',
                  icon: Icons.call_split_rounded,
                  isSelected: _auditSubTab == 'split',
                  isDark: isDark,
                  onTap: () => setState(() => _auditSubTab = 'split'),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _auditSubTab == 'spot_vs_booking'
              ? _buildSpotVsBookingComparisonView(a, isDark)
              : _auditSubTab == 'cancelled'
                  ? _buildCancelledAuditList(a.cancelledEntries, now, isDark)
                  : _buildSplitAuditList(a.splitEntries, now, isDark),
        ),
      ],
    );
  }

  Widget _buildSpotVsBookingComparisonView(
      SupersaleComputedAnalytics a, bool isDark) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: _buildKpiCard(
                title: 'Spot Sales Total',
                mainValue: '${_qtyFmt.format(a.spotSaleQty)} Qty',
                subValue:
                    '${a.spotSaleOrders} orders • ${_currencyFmt.format(a.spotSaleAmount)}',
                icon: Icons.flash_on_rounded,
                gradient: const [Color(0xFF6A1B9A), Color(0xFFAB47BC)],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildKpiCard(
                title: 'Pre-Bookings Total',
                mainValue: '${_qtyFmt.format(a.normalBookingQty)} Qty',
                subValue:
                    '${a.normalBookingOrders} orders • ${_currencyFmt.format(a.normalBookingAmount)}',
                icon: Icons.bookmark_added_rounded,
                gradient: const [Color(0xFF005BAC), Color(0xFF42A5F5)],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _buildSectionHeader(
          title: 'Branch-Wise Spot Sale vs Pre-Booking Breakdown',
          subtitle: 'Quantity and order count comparison by branch',
          icon: Icons.compare_arrows_rounded,
          isDark: isDark,
        ),
        const SizedBox(height: 10),
        if (a.branchBookingRows.isEmpty)
          _buildEmptyCard('No booking data available.', isDark)
        else
          ...a.branchBookingRows.map((row) {
            final spotPct =
                row.totalQty > 0 ? (row.spotQty / row.totalQty) * 100.0 : 0.0;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark ? Colors.white12 : Colors.grey[200]!,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        row.branch,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      Text(
                        'Spot Share: ${spotPct.toStringAsFixed(1)}%',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: Colors.purple,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildMiniStat(
                        'Spot Sale',
                        '${_qtyFmt.format(row.spotQty)} Qty (${row.spotOrders})',
                        Colors.purple,
                        isDark,
                      ),
                      _buildMiniStat(
                        'Pre-Booking',
                        '${_qtyFmt.format(row.normalQty)} Qty (${row.normalOrders})',
                        _primaryBlue,
                        isDark,
                      ),
                      _buildMiniStat(
                        'Total Qty',
                        _qtyFmt.format(row.totalQty),
                        _primaryGreen,
                        isDark,
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _buildCancelledAuditList(
      List<SupersaleEntryModel> entries, DateTime now, bool isDark) {
    if (entries.isEmpty) {
      return Center(
        child: _buildEmptyCard('No cancelled orders in this view.', isDark),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        return _buildOrderEntryTile(entries[index], isDark,
            now: now, showCancelReason: true);
      },
    );
  }

  Widget _buildSplitAuditList(
      List<SupersaleEntryModel> entries, DateTime now, bool isDark) {
    if (entries.isEmpty) {
      return Center(
        child: _buildEmptyCard(
            'No partial or split delivery entries in this view.', isDark),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        return _buildOrderEntryTile(entries[index], isDark, now: now);
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 6: CUSTOMER ORDER DIRECTORY & EXCEL EXPORT HUB
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildOrdersAndExportsTab(bool isDark) {
    final a = _analytics!;
    final now = DateTime.now();

    final filteredOrders = a.filteredEntries.where((e) {
      switch (_orderStatusFilter) {
        case 'pending':
          if (!e.isPending) return false;
          break;
        case 'delivered':
          if (!e.isDelivered) return false;
          break;
        case 'spot':
          if (!e.isSpotSale || e.isCancelled) return false;
          break;
        case 'overdue':
          if (!e.isOverdue(now)) return false;
          break;
        case 'cancelled':
          if (!e.isCancelled) return false;
          break;
      }
      if (_orderSearchQuery.isNotEmpty) {
        final q = _orderSearchQuery.toLowerCase();
        if (!e.customerName.toLowerCase().contains(q) &&
            !e.phone.toLowerCase().contains(q) &&
            !e.billedPhone.toLowerCase().contains(q) &&
            !e.username.toLowerCase().contains(q) &&
            !e.itemName.toLowerCase().contains(q) &&
            !e.branch.toLowerCase().contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Excel Export Hub Card
        _buildExcelExportHubCard(isDark),
        const SizedBox(height: 20),

        // Customer Order Directory
        _buildSectionHeader(
          title: 'Customer Order Directory (${filteredOrders.length})',
          subtitle: 'Search by customer name, phone, billed phone, staff, or item',
          icon: Icons.manage_search_rounded,
          isDark: isDark,
        ),
        const SizedBox(height: 10),
        TextField(
          onChanged: (val) {
            _orderSearchDebounce?.cancel();
            _orderSearchDebounce = Timer(const Duration(milliseconds: 250), () {
              if (mounted) setState(() => _orderSearchQuery = val.trim());
            });
          },
          style: TextStyle(
            fontSize: 13,
            color: isDark ? Colors.white : Colors.black87,
          ),
          decoration: InputDecoration(
            hintText: 'Search customer, phone, staff, branch, item...',
            prefixIcon: const Icon(Icons.search_rounded),
            filled: true,
            fillColor: isDark ? const Color(0xFF1E293B) : Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: isDark ? Colors.white12 : Colors.grey[300]!,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildFilterChip('All', 'all', isDark),
              _buildFilterChip('Pending', 'pending', isDark),
              _buildFilterChip('Delivered', 'delivered', isDark),
              _buildFilterChip('Spot Sale', 'spot', isDark),
              _buildFilterChip('Overdue', 'overdue', isDark),
              _buildFilterChip('Cancelled', 'cancelled', isDark),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (filteredOrders.isEmpty)
          _buildEmptyCard('No orders match your search criteria.', isDark)
        else
          ...filteredOrders.take(150).map(
                (e) => _buildOrderEntryTile(
                  e,
                  isDark,
                  now: now,
                  showCancelReason: e.isCancelled,
                ),
              ),
      ],
    );
  }

  Widget _buildExcelExportHubCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.grey[200]!,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _primaryGreen.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.table_view_rounded,
                    color: _primaryGreen, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'All-in-One Excel Export Center',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    Text(
                      'Generate Master Workbook, Monthly Performance, or Campaign Reports',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white54 : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isExporting ? null : _exportMasterExcel,
              icon: const Icon(Icons.download_for_offline_rounded),
              label: const Text(
                'Download 7-Sheet Master Dashboard Excel',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const Divider(height: 24),
          Text(
            'Quick Monthly Performance Excel Export',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _exportMonth,
                  isDense: true,
                  decoration: InputDecoration(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  items: List.generate(12, (i) {
                    final m = i + 1;
                    return DropdownMenuItem(
                      value: m,
                      child: Text(
                        DateFormat('MMMM').format(DateTime(2000, m)),
                        style: const TextStyle(fontSize: 12),
                      ),
                    );
                  }),
                  onChanged: (val) {
                    if (val != null) setState(() => _exportMonth = val);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _exportYear,
                  isDense: true,
                  decoration: InputDecoration(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  items: List.generate(5, (i) {
                    final y = DateTime.now().year - 2 + i;
                    return DropdownMenuItem(
                      value: y,
                      child: Text('$y', style: const TextStyle(fontSize: 12)),
                    );
                  }),
                  onChanged: (val) {
                    if (val != null) setState(() => _exportYear = val);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isExporting
                      ? null
                      : () => _exportMonthlyExcel(isSummary: false),
                  icon: const Icon(Icons.list_alt_rounded, size: 18),
                  label: const Text('Monthly Detailed',
                      style: TextStyle(fontSize: 12)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isExporting
                      ? null
                      : () => _exportMonthlyExcel(isSummary: true),
                  icon: const Icon(Icons.summarize_rounded, size: 18),
                  label: const Text('Monthly Summary',
                      style: TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SHARED REUSABLE WIDGETS
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildOrderEntryTile(
    SupersaleEntryModel e,
    bool isDark, {
    required DateTime now,
    bool highlightOverdue = false,
    bool showCancelReason = false,
  }) {
    final isOverdue = e.isOverdue(now);
    final Color statusColor = e.isCancelled
        ? Colors.redAccent
        : (e.isDelivered
            ? _primaryGreen
            : (isOverdue ? Colors.red : Colors.orange));

    final String statusLabel = e.isCancelled
        ? 'Cancelled'
        : (e.isDelivered
            ? 'Delivered'
            : (isOverdue ? 'Overdue (${e.daysOverdue(now)}d)' : 'Pending'));

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: highlightOverdue
              ? Colors.redAccent.withValues(alpha: 0.45)
              : (isDark ? Colors.white12 : Colors.grey[200]!),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _primaryBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  e.branch,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    color: _primaryBlue,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  e.itemName,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (e.isSpotSale)
                Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.purple.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Spot Sale',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.purple,
                    ),
                  ),
                ),
              if (e.isPartialSplit || e.hasPartialDelivery)
                Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    e.isPartialSplit ? 'Part Split' : 'Part Rem.',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.person_outline_rounded,
                  size: 15, color: Colors.grey),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${e.customerName.isNotEmpty ? e.customerName : "Customer"} • ${e.phone}',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
              Text(
                'Staff: ${e.username}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : _primaryBlue,
                ),
              ),
            ],
          ),
          if (e.description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Desc: ${e.description}',
              style: TextStyle(
                fontSize: 11,
                fontStyle: FontStyle.italic,
                color: isDark ? Colors.white54 : Colors.black54,
              ),
            ),
          ],
          if (showCancelReason && e.cancelReason.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Cancel Reason: ${e.cancelReason}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.redAccent,
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              _buildMiniStat(
                  'Qty', _qtyFmt.format(e.quantity), _primaryBlue, isDark),
              _buildMiniStat(
                  'Rate', _currencyFmt.format(e.rate), Colors.indigo, isDark),
              _buildMiniStat('Total', _currencyFmt.format(e.totalAmount),
                  _primaryGreen, isDark),
              _buildMiniStat('Advance', _currencyFmt.format(e.advance),
                  Colors.teal, isDark),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Booked: ${e.createdAt != null ? _dateTimeFmt.format(e.createdAt!) : "N/A"}',
                style: TextStyle(
                  fontSize: 10,
                  color: isDark ? Colors.white38 : Colors.black45,
                ),
              ),
              if (e.effectiveDeadline != null)
                Text(
                  'Deadline: ${_shortDateFmt.format(e.effectiveDeadline!)}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: isOverdue
                        ? Colors.redAccent
                        : (isDark ? Colors.white54 : Colors.black54),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String mainValue,
    required String subValue,
    required IconData icon,
    required List<Color> gradient,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: gradient,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: gradient.first.withValues(alpha: 0.25),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: Colors.white, size: 16),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (onTap != null)
                    Icon(Icons.chevron_right_rounded,
                        color: Colors.white.withValues(alpha: 0.7), size: 16),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mainValue,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subValue,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 10,
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

  Widget _buildSectionHeader({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isDark,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _primaryBlue.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: _primaryBlue, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white54 : Colors.black54,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMiniStat(
      String label, String value, Color color, bool isDark) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: isDark ? 0.15 : 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 11,
                color: color,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 1),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBannerStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.8),
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  Widget _buildSegmentedButton({
    required String title,
    required IconData icon,
    required bool isSelected,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? _primaryBlue
              : (isDark ? const Color(0xFF1E293B) : Colors.grey[100]),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected
                  ? Colors.white
                  : (isDark ? Colors.white60 : Colors.black54),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isSelected
                      ? Colors.white
                      : (isDark ? Colors.white70 : Colors.black87),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionChip({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value, bool isDark) {
    final isSelected = _orderStatusFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        selectedColor: _primaryBlue,
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected
              ? Colors.white
              : (isDark ? Colors.white70 : Colors.black87),
        ),
        onSelected: (_) => setState(() => _orderStatusFilter = value),
      ),
    );
  }

  Widget _buildSelectPromptState(bool isDark) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: _primaryBlue.withValues(alpha: isDark ? 0.2 : 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.touch_app_rounded,
                size: 56,
                color: _primaryBlue,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Select a Campaign or Branch',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'To avoid heavy queries and show precise statistics, choose a Supersale campaign or a specific branch from the dropdown above to load and view all reports.',
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? Colors.white12 : Colors.grey[200]!,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.arrow_upward_rounded,
                      size: 16, color: _primaryBlue),
                  const SizedBox(width: 8),
                  Text(
                    'Use the dropdown filters at the top',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : _primaryBlue,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyCard(String message, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(28),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.grey[200]!,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_rounded,
              size: 42, color: _primaryBlue.withValues(alpha: 0.4)),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white60 : Colors.black54,
            ),
          ),
        ],
      ),
    );
  }
}
