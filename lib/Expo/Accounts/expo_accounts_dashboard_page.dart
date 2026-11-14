import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../expo_service.dart';

const Color primaryBlue = Color(0xFF005BAC);
const Color primaryGreen = Color(0xFF8CC63F);

///Report view modes for the bottom report selector
enum ExpoReportType {
  branchwise('Branchwise Amounts', Icons.account_tree_rounded),
  paymentMode('Payment Mode Breakdown', Icons.account_balance_wallet_rounded),
  salesRep('Sales Rep Performance', Icons.badge_rounded),
  orderType('Order Type Summary', Icons.category_rounded),
  topItems('Top Selling Items', Icons.inventory_2_rounded),
  dailyTrend('Daily Trend', Icons.calendar_today_rounded),
  districtState('District & State Reach', Icons.location_on_rounded);

  final String title;
  final IconData icon;
  const ExpoReportType(this.title, this.icon);
}

/// Modern, sleek, and high-performance Dashboard for Expo Accounts (`expo_acc`).
/// Displays data only after the user explicitly selects an exhibition at the top.
class ExpoAccountsDashboardPage extends StatefulWidget {
  const ExpoAccountsDashboardPage({super.key});

  @override
  State<ExpoAccountsDashboardPage> createState() =>
      _ExpoAccountsDashboardPageState();
}

class _ExpoAccountsDashboardPageState extends State<ExpoAccountsDashboardPage> {
  Exhibition? _selectedExhibition;
  ExpoReportType _selectedReportType = ExpoReportType.branchwise;

  // Filter toggle: whether to show All Orders or Verified/Completed Only
  bool _verifiedOnly = false;

  final NumberFormat _currencyFmt = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );

  final NumberFormat _compactFmt = NumberFormat.compactCurrency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 1,
  );

  String _formatMoney(double amount, {bool compact = false}) {
    if (compact && amount >= 100000) {
      return _compactFmt.format(amount);
    }
    return _currencyFmt.format(amount.round());
  }

  bool _isSameDay(DateTime a, DateTime b) {
    final localA = a.toLocal();
    final localB = b.toLocal();
    return localA.year == localB.year &&
        localA.month == localB.month &&
        localA.day == localB.day;
  }

  /// Effective collected total for an order:
  /// Spot Delivery = full totalAmount, Stall / Booking = advanceAmount + pickupAmount.
  double _effectiveAdvance(ExpoOrder o) => o.totalPaidAmount;

  void _showReportTypeSelector(BuildContext context, bool isDark) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF132238) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: primaryBlue.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.analytics_rounded,
                        color: primaryBlue,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Select Report Type',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : const Color(0xFF0A1628),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Flexible(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: ExpoReportType.values.map((type) {
                        final isSelected = _selectedReportType == type;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Material(
                            color: isSelected
                                ? primaryBlue.withValues(
                                    alpha: isDark ? 0.25 : 0.08,
                                  )
                                : (isDark
                                      ? Colors.white.withValues(alpha: 0.03)
                                      : const Color(0xFFF7F9FC)),
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () {
                                setState(() => _selectedReportType = type);
                                Navigator.pop(ctx);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: isSelected
                                        ? primaryGreen
                                        : Colors.transparent,
                                    width: 1.5,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? primaryGreen
                                            : primaryBlue.withValues(
                                                alpha: 0.1,
                                              ),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Icon(
                                        type.icon,
                                        size: 18,
                                        color: isSelected
                                            ? Colors.white
                                            : primaryBlue,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Text(
                                        type.title,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: isSelected
                                              ? FontWeight.bold
                                              : FontWeight.w600,
                                          color: isDark
                                              ? Colors.white
                                              : const Color(0xFF1A2536),
                                        ),
                                      ),
                                    ),
                                    if (isSelected)
                                      const Icon(
                                        Icons.check_circle_rounded,
                                        color: primaryGreen,
                                        size: 20,
                                      )
                                    else
                                      Icon(
                                        Icons.chevron_right_rounded,
                                        color: isDark
                                            ? Colors.white38
                                            : Colors.grey.shade400,
                                        size: 20,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0A1628) : const Color(0xFFF4F7FB);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text(
          'Expo Accounts Dashboard',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_selectedExhibition != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () {
                    setState(() => _verifiedOnly = !_verifiedOnly);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: _verifiedOnly
                          ? primaryGreen
                          : Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _verifiedOnly
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _verifiedOnly
                              ? Icons.verified_rounded
                              : Icons.all_inclusive_rounded,
                          size: 14,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          _verifiedOnly ? 'Verified Only' : 'All Orders',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: StreamBuilder<List<Exhibition>>(
        stream: ExpoService.instance.streamExhibitions(),
        builder: (context, exSnapshot) {
          if (exSnapshot.connectionState == ConnectionState.waiting &&
              !exSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final exhibitions = exSnapshot.data ?? [];

          // Keep _selectedExhibition synced if updated in stream
          if (_selectedExhibition != null) {
            final match = exhibitions.where(
              (e) => e.id == _selectedExhibition!.id,
            );
            if (match.isNotEmpty) {
              _selectedExhibition = match.first;
            } else {
              _selectedExhibition = null;
            }
          }

          return Column(
            children: [
              // Top Exhibition Selector Bar
              _buildExhibitionSelectorHeader(exhibitions, isDark),

              // Main Content Area
              Expanded(
                child: _selectedExhibition == null
                    ? _buildSelectExpoPrompt(exhibitions, isDark)
                    : _buildDashboardBody(_selectedExhibition!, isDark),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: _selectedExhibition == null
          ? null
          : _buildBottomReportSelectorBar(context, isDark),
    );
  }

  /// Header bar allowing the user to select an exhibition from a sleek dropdown
  Widget _buildExhibitionSelectorHeader(
    List<Exhibition> exhibitions,
    bool isDark,
  ) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [primaryBlue, Color(0xFF004482)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        boxShadow: [
          BoxShadow(
            color: primaryBlue.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF132238) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _selectedExhibition != null
                ? primaryGreen
                : Colors.white.withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _selectedExhibition?.id,
            isExpanded: true,
            hint: Row(
              children: [
                const Icon(
                  Icons.festival_rounded,
                  color: primaryBlue,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Text(
                  exhibitions.isEmpty
                      ? 'No Exhibitions Found'
                      : 'Select an Exhibition to view Dashboard...',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : Colors.blueGrey.shade700,
                  ),
                ),
              ],
            ),
            icon: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: primaryGreen.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: primaryGreen,
                size: 20,
              ),
            ),
            dropdownColor: isDark ? const Color(0xFF132238) : Colors.white,
            items: exhibitions.map((ex) {
              final dateRange =
                  '${DateFormat('dd MMM').format(ex.startDate)} - ${DateFormat('dd MMM yyyy').format(ex.endDate)}';
              return DropdownMenuItem<String>(
                value: ex.id,
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: ex.isActive
                            ? primaryGreen
                            : (ex.isUpcoming ? Colors.amber : Colors.grey),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${ex.name} (${ex.location})',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF0A1628),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      dateRange,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white54 : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
            onChanged: (val) {
              if (val == null) return;
              final chosen = exhibitions.firstWhere((e) => e.id == val);
              setState(() {
                _selectedExhibition = chosen;
              });
            },
          ),
        ),
      ),
    );
  }

  /// Displayed before an exhibition is selected
  Widget _buildSelectExpoPrompt(List<Exhibition> exhibitions, bool isDark) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    primaryBlue.withValues(alpha: 0.15),
                    primaryGreen.withValues(alpha: 0.15),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                border: Border.all(
                  color: primaryGreen.withValues(alpha: 0.4),
                  width: 1.5,
                ),
              ),
              child: const Icon(
                Icons.insert_chart_outlined_rounded,
                size: 44,
                color: primaryBlue,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Select an Exhibition',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : const Color(0xFF0A1628),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose an exhibition from the top dropdown or tap one below to view live financial metrics, advance collections, and detailed reports.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.4,
                color: isDark ? Colors.white60 : Colors.blueGrey.shade600,
              ),
            ),
            if (exhibitions.isNotEmpty) ...[
              const SizedBox(height: 24),
               Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'AVAILABLE EXHIBITIONS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                    color: isDark ? Colors.white54 : Colors.blueGrey,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              ...exhibitions.take(5).map((ex) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Material(
                    color: isDark ? const Color(0xFF132238) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    elevation: 1,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        setState(() => _selectedExhibition = ex);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: primaryBlue.withValues(alpha: 0.15),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: primaryBlue.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.storefront_rounded,
                                color: primaryBlue,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    ex.name,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: isDark
                                          ? Colors.white
                                          : const Color(0xFF0A1628),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${ex.location} • ${DateFormat('dd MMM yyyy').format(ex.startDate)}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark
                                          ? Colors.white60
                                          : Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 16,
                              color: primaryGreen,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  /// Main dashboard body once an exhibition is selected
  Widget _buildDashboardBody(Exhibition exhibition, bool isDark) {
    if (exhibition.isEnded) {
      ExpoService.instance.autoConvertExpiredStallDeliveries(exhibition);
    }
    return StreamBuilder<List<ExpoOrder>>(
      stream: ExpoService.instance.streamOrders(exhibitionId: exhibition.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final rawOrders = snapshot.data ?? [];
        final orders = _verifiedOnly
            ? rawOrders.where((o) => o.status == 'Completed').toList()
            : rawOrders;

        final now = DateTime.now();

        // Single-pass O(N) calculation of the 6 primary KPIs + supplementary counts
        double totalAmount = 0.0;
        double totalToday = 0.0;
        double totalAdvance = 0.0;
        double totalAdvanceToday = 0.0;
        int ordersTotal = orders.length;
        int ordersToday = 0;

        int verifiedCount = 0;
        int pendingCount = 0;
        double totalBalance = 0.0;

        for (final o in orders) {
          final isToday = _isSameDay(o.orderDate, now);
          final adv = _effectiveAdvance(o);

          totalAmount += o.totalAmount;
          totalAdvance += adv;
          totalBalance += o.balanceAmount;

          if (isToday) {
            ordersToday++;
            totalToday += o.totalAmount;
            totalAdvanceToday += adv;
          }

          if (o.status == 'Completed') {
            verifiedCount++;
          } else {
            pendingCount++;
          }
        }

        return CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 6 Core KPI Cards in a sleek 2x3 Grid
                    _buildKpiGrid(
                      totalAmount: totalAmount,
                      totalToday: totalToday,
                      totalAdvance: totalAdvance,
                      totalAdvanceToday: totalAdvanceToday,
                      ordersToday: ordersToday,
                      ordersTotal: ordersTotal,
                      isDark: isDark,
                    ),
                    const SizedBox(height: 12),

                    // Quick Verification Status & Balance Strip
                    _buildVerificationStatusBanner(
                      verifiedCount: verifiedCount,
                      pendingCount: pendingCount,
                      totalBalance: totalBalance,
                      isDark: isDark,
                    ),
                    const SizedBox(height: 18),

                    // Quick Horizontal Report Type Switcher Chips
                    _buildReportChipStrip(isDark),
                    const SizedBox(height: 12),

                    // Section Title for Active Report
                    Row(
                      children: [
                        Container(
                          width: 4,
                          height: 18,
                          decoration: BoxDecoration(
                            color: primaryGreen,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          _selectedReportType.icon,
                          size: 18,
                          color: isDark ? primaryGreen : primaryBlue,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _selectedReportType.title,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF0A1628),
                            ),
                          ),
                        ),
                        Text(
                          '${orders.length} bills',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? Colors.white54
                                : Colors.blueGrey.shade600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ),

            // Active Report Content
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
              sliver: _buildSelectedReportSliver(orders, isDark),
            ),
          ],
        );
      },
    );
  }

  /// Builds the 6 required KPI cards:
  /// 1. Total Amount | 2. Total Today
  /// 3. Total Advance | 4. Total Advance Today
  /// 5. No. of Orders Today | 6. No. of Orders Total
  Widget _buildKpiGrid({
    required double totalAmount,
    required double totalToday,
    required double totalAdvance,
    required double totalAdvanceToday,
    required int ordersToday,
    required int ordersTotal,
    required bool isDark,
  }) {
    return Column(
      children: [
        // Row 1: Total Amount (Blue) & Total Today (Green)
        Row(
          children: [
            Expanded(
              child: _KpiMetricCard(
                title: 'Total Amount',
                value: _formatMoney(totalAmount),
                subtitle: 'Overall Order Value',
                icon: Icons.currency_rupee_rounded,
                accentColor: primaryBlue,
                isHighlight: true,
                isDark: isDark,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _KpiMetricCard(
                title: 'Total Today',
                value: _formatMoney(totalToday),
                subtitle: "Today's Order Value",
                icon: Icons.today_rounded,
                accentColor: primaryGreen,
                isHighlight: true,
                isDark: isDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Row 2: Total Advance (Blue) & Total Advance Today (Green)
        Row(
          children: [
            Expanded(
              child: _KpiMetricCard(
                title: 'Total Advance',
                value: _formatMoney(totalAdvance),
                subtitle: 'Spot + Advance Collected',
                icon: Icons.savings_rounded,
                accentColor: primaryBlue,
                isDark: isDark,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _KpiMetricCard(
                title: 'Total Advance Today',
                value: _formatMoney(totalAdvanceToday),
                subtitle: 'Collected Today',
                icon: Icons.payments_rounded,
                accentColor: primaryGreen,
                isDark: isDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Row 3: No of Orders Today (Blue) & No of Orders Total (Green)
        Row(
          children: [
            Expanded(
              child: _KpiMetricCard(
                title: 'No. of Orders Today',
                value: '$ordersToday',
                subtitle: "Today's Bill Count",
                icon: Icons.receipt_rounded,
                accentColor: primaryBlue,
                isDark: isDark,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _KpiMetricCard(
                title: 'No. of Orders Total',
                value: '$ordersTotal',
                subtitle: 'Cumulative Bills',
                icon: Icons.receipt_long_rounded,
                accentColor: primaryGreen,
                isDark: isDark,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Compact summary bar showing Verified vs Pending count and Balance Due
  Widget _buildVerificationStatusBanner({
    required int verifiedCount,
    required int pendingCount,
    required double totalBalance,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF132238) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: primaryBlue.withValues(alpha: isDark ? 0.3 : 0.12),
        ),
      ),
      child: Row(
        children: [
          _buildMiniStatPill(
            icon: Icons.verified_rounded,
            color: primaryGreen,
            label: 'Verified',
            value: '$verifiedCount',
            isDark: isDark,
          ),
          Container(
            height: 22,
            width: 1,
            margin: const EdgeInsets.symmetric(horizontal: 10),
            color: isDark ? Colors.white12 : Colors.grey.shade200,
          ),
          _buildMiniStatPill(
            icon: Icons.pending_actions_rounded,
            color: Colors.orange.shade700,
            label: 'Pending',
            value: '$pendingCount',
            isDark: isDark,
          ),
          Container(
            height: 22,
            width: 1,
            margin: const EdgeInsets.symmetric(horizontal: 10),
            color: isDark ? Colors.white12 : Colors.grey.shade200,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Balance Due',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white54 : Colors.grey.shade600,
                  ),
                ),
                Text(
                  _formatMoney(totalBalance, compact: true),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : primaryBlue,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStatPill({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
    required bool isDark,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 5),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: isDark ? Colors.white54 : Colors.grey.shade600,
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : const Color(0xFF0A1628),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Horizontal quick-scroll chips for switching report types without opening the bottom sheet
  Widget _buildReportChipStrip(bool isDark) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: ExpoReportType.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final type = ExpoReportType.values[index];
          final selected = _selectedReportType == type;
          return Material(
            color: selected
                ? primaryBlue
                : (isDark ? const Color(0xFF132238) : Colors.white),
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => setState(() => _selectedReportType = type),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: selected
                        ? primaryGreen
                        : (isDark ? Colors.white12 : Colors.grey.shade300),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      type.icon,
                      size: 14,
                      color: selected
                          ? primaryGreen
                          : (isDark ? Colors.white70 : primaryBlue),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      type.title,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: selected
                            ? FontWeight.bold
                            : FontWeight.w600,
                        color: selected
                            ? Colors.white
                            : (isDark
                                  ? Colors.white70
                                  : const Color(0xFF1A2536)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Dispatches to the selected report builder
  Widget _buildSelectedReportSliver(List<ExpoOrder> orders, bool isDark) {
    if (orders.isEmpty) {
      return SliverToBoxAdapter(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF132238) : Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Icon(
                Icons.inbox_rounded,
                size: 48,
                color: primaryBlue.withValues(alpha: 0.35),
              ),
              const SizedBox(height: 10),
              Text(
                'No Orders Yet',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white70 : Colors.blueGrey.shade700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Orders placed under this exhibition will populate this report automatically.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white38 : Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    switch (_selectedReportType) {
      case ExpoReportType.branchwise:
        return _buildBranchwiseReport(orders, isDark);
      case ExpoReportType.paymentMode:
        return _buildPaymentModeReport(orders, isDark);
      case ExpoReportType.salesRep:
        return _buildSalesRepReport(orders, isDark);
      case ExpoReportType.orderType:
        return _buildOrderTypeReport(orders, isDark);
      case ExpoReportType.topItems:
        return _buildTopItemsReport(orders, isDark);
      case ExpoReportType.dailyTrend:
        return _buildDailyTrendReport(orders, isDark);
      case ExpoReportType.districtState:
        return _buildDistrictStateReport(orders, isDark);
    }
  }

  // ---------------------------------------------------------------------------
  // 1. BRANCHWISE AMOUNTS REPORT
  // ---------------------------------------------------------------------------
  Widget _buildBranchwiseReport(List<ExpoOrder> orders, bool isDark) {
    final Map<String, _AggRow> map = {};
    double grandTotal = 0.0;

    for (final o in orders) {
      final branch = o.preferredBranch.trim().isNotEmpty
          ? o.preferredBranch.trim().toUpperCase()
          : (o.createdUserBranch.trim().isNotEmpty
                ? o.createdUserBranch.trim().toUpperCase()
                : 'UNASSIGNED');
      final row = map.putIfAbsent(branch, () => _AggRow(title: branch));
      row.bills++;
      row.totalAmount += o.totalAmount;
      row.advanceCollected += _effectiveAdvance(o);
      row.balanceAmount += o.balanceAmount;
      grandTotal += o.totalAmount;
    }

    final list = map.values.toList()
      ..sort((a, b) => b.totalAmount.compareTo(a.totalAmount));

    return SliverList.separated(
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, idx) {
        final item = list[idx];
        final share = grandTotal > 0 ? (item.totalAmount / grandTotal) : 0.0;
        final isEven = idx % 2 == 0;
        return _buildReportRowCard(
          rank: idx + 1,
          title: item.title,
          subtitle:
              '${item.bills} ${item.bills == 1 ? 'Bill' : 'Bills'} • Advance: ${_formatMoney(item.advanceCollected)}',
          trailingTop: _formatMoney(item.totalAmount),
          trailingBottom: '${(share * 100).toStringAsFixed(1)}% of total',
          progress: share,
          barColor: isEven ? primaryBlue : primaryGreen,
          isDark: isDark,
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 2. PAYMENT MODE AMOUNTS REPORT
  // ---------------------------------------------------------------------------
  Widget _buildPaymentModeReport(List<ExpoOrder> orders, bool isDark) {
    final Map<String, _AggRow> map = {
      for (final mode in ExpoOrder.paymentModes) mode: _AggRow(title: mode),
    };
    double grandAdvance = 0.0;
    double grandTotal = 0.0;

    for (final o in orders) {
      final mode = ExpoOrder.normalizePaymentMode(o.paymentMode);
      final row = map.putIfAbsent(mode, () => _AggRow(title: mode));
      final adv = _effectiveAdvance(o);
      row.bills++;
      row.totalAmount += o.totalAmount;
      row.advanceCollected += adv;
      if (o.status == 'Completed') {
        row.verifiedAdvance += adv;
      } else {
        row.pendingAdvance += adv;
      }
      grandAdvance += adv;
      grandTotal += o.totalAmount;
    }

    final list = map.values.where((r) => r.bills > 0).toList()
      ..sort((a, b) => b.advanceCollected.compareTo(a.advanceCollected));

    return SliverList.separated(
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, idx) {
        final item = list[idx];
        final share = grandAdvance > 0
            ? (item.advanceCollected / grandAdvance)
            : (grandTotal > 0 ? item.totalAmount / grandTotal : 0.0);
        IconData modeIcon = Icons.payments_rounded;
        Color modeColor = primaryGreen;
        if (item.title == 'UPI') {
          modeIcon = Icons.qr_code_2_rounded;
          modeColor = primaryBlue;
        } else if (item.title == 'UPI + Cash') {
          modeIcon = Icons.qr_code_scanner_rounded;
          modeColor = const Color(0xFF0288D1);
        } else if (item.title == 'Bank') {
          modeIcon = Icons.account_balance_rounded;
          modeColor = const Color(0xFF00796B);
        } else if (item.title == 'Bank + Cash') {
          modeIcon = Icons.account_balance_wallet_rounded;
          modeColor = const Color(0xFF2E7D32);
        }

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF132238) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: modeColor.withValues(alpha: isDark ? 0.35 : 0.2),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: modeColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(modeIcon, color: modeColor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF0A1628),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${item.bills} ${item.bills == 1 ? 'Bill' : 'Bills'} • Order Value: ${_formatMoney(item.totalAmount)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? Colors.white60
                                : Colors.blueGrey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _formatMoney(item.advanceCollected),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: modeColor,
                        ),
                      ),
                      Text(
                        'Collected (${(share * 100).toStringAsFixed(1)}%)',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white54 : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: share.clamp(0.0, 1.0),
                  minHeight: 6,
                  backgroundColor: isDark
                      ? Colors.white10
                      : Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(modeColor),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Verified: ${_formatMoney(item.verifiedAdvance)}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: primaryGreen,
                    ),
                  ),
                  Text(
                    'Pending Verification: ${_formatMoney(item.pendingAdvance)}',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.orange.shade700,
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

  // ---------------------------------------------------------------------------
  // 3. SALES REP PERFORMANCE (ORDER AMOUNT, BILLS, ADVANCE COLLECTED)
  // ---------------------------------------------------------------------------
  Widget _buildSalesRepReport(List<ExpoOrder> orders, bool isDark) {
    final Map<String, _AggRow> map = {};
    double grandTotal = 0.0;

    for (final o in orders) {
      final key = o.createdUserId.isNotEmpty
          ? o.createdUserId
          : o.createdUserName;
      final name = o.createdUserName.trim().isNotEmpty
          ? o.createdUserName.trim()
          : 'Sales Rep';
      final branch = o.createdUserBranch.trim().isNotEmpty
          ? o.createdUserBranch.trim().toUpperCase()
          : '';

      final row = map.putIfAbsent(
        key,
        () => _AggRow(title: name, tag: branch),
      );
      final adv = _effectiveAdvance(o);
      row.bills++;
      row.totalAmount += o.totalAmount;
      row.advanceCollected += adv;
      if (o.hasCashComponent && o.status != 'Completed') {
        row.pendingAdvance += o.totalCashCollected; // Unverified cash in hand with rep
      }
      grandTotal += o.totalAmount;
    }

    final list = map.values.toList()
      ..sort((a, b) => b.totalAmount.compareTo(a.totalAmount));

    return SliverList.separated(
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, idx) {
        final item = list[idx];
        final share = grandTotal > 0 ? (item.totalAmount / grandTotal) : 0.0;
        final isEven = idx % 2 == 0;
        final accent = isEven ? primaryBlue : primaryGreen;

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF132238) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: accent.withValues(alpha: isDark ? 0.3 : 0.15),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '#${idx + 1}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14.5,
                                  color: isDark
                                      ? Colors.white
                                      : const Color(0xFF0A1628),
                                ),
                              ),
                            ),
                            if (item.tag.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: primaryBlue.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  item.tag,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: primaryBlue,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${item.bills} ${item.bills == 1 ? 'Bill' : 'Bills'} • Advance Collected: ${_formatMoney(item.advanceCollected)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? Colors.white60
                                : Colors.blueGrey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _formatMoney(item.totalAmount),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15.5,
                          color: isDark ? Colors.white : primaryBlue,
                        ),
                      ),
                      Text(
                        '${(share * 100).toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white54 : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (item.pendingAdvance > 0) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.payments_outlined,
                        size: 14,
                        color: Colors.orange.shade800,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Unverified Cash to Collect: ${_formatMoney(item.pendingAdvance)}',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 4. ORDER TYPE SUMMARY (SPOT vs STALL vs BOOKING)
  // ---------------------------------------------------------------------------
  Widget _buildOrderTypeReport(List<ExpoOrder> orders, bool isDark) {
    final Map<String, _AggRow> map = {
      'Spot Delivery': _AggRow(title: 'Spot Delivery'),
      'Stall Delivery': _AggRow(title: 'Stall Delivery'),
      'Booking': _AggRow(title: 'Booking'),
    };
    double grandTotal = 0.0;

    for (final o in orders) {
      final type = o.orderType.isNotEmpty ? o.orderType : 'Booking';
      final row = map.putIfAbsent(type, () => _AggRow(title: type));
      row.bills++;
      row.totalAmount += o.totalAmount;
      row.advanceCollected += _effectiveAdvance(o);
      row.balanceAmount += o.balanceAmount;
      grandTotal += o.totalAmount;
    }

    final list = map.values.toList()
      ..sort((a, b) => b.totalAmount.compareTo(a.totalAmount));

    return SliverList.separated(
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, idx) {
        final item = list[idx];
        final share = grandTotal > 0 ? (item.totalAmount / grandTotal) : 0.0;
        final isEven = idx % 2 == 0;
        return _buildReportRowCard(
          rank: idx + 1,
          title: item.title,
          subtitle:
              '${item.bills} Bills • Collected: ${_formatMoney(item.advanceCollected)} • Bal: ${_formatMoney(item.balanceAmount)}',
          trailingTop: _formatMoney(item.totalAmount),
          trailingBottom: '${(share * 100).toStringAsFixed(1)}% of total',
          progress: share,
          barColor: isEven ? primaryBlue : primaryGreen,
          isDark: isDark,
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 5. TOP SELLING ITEMS REPORT
  // ---------------------------------------------------------------------------
  Widget _buildTopItemsReport(List<ExpoOrder> orders, bool isDark) {
    final Map<String, _AggRow> map = {};
    double grandItemRevenue = 0.0;

    for (final o in orders) {
      for (final item in o.items) {
        final key = item.mtcCode.trim().isNotEmpty
            ? item.mtcCode.trim().toUpperCase()
            : item.itemName.trim().toUpperCase();
        final label = item.itemName.trim().isNotEmpty
            ? item.itemName.trim()
            : item.mtcCode.trim();
        final row = map.putIfAbsent(
          key,
          () => _AggRow(title: label, tag: item.mtcCode.trim()),
        );
        row.bills += item.qty; // Reuse bills counter for Total Qty Sold
        row.totalAmount += item.total;
        grandItemRevenue += item.total;
      }
    }

    final list = map.values.toList()
      ..sort((a, b) => b.totalAmount.compareTo(a.totalAmount));

    return SliverList.separated(
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, idx) {
        final item = list[idx];
        final share = grandItemRevenue > 0
            ? (item.totalAmount / grandItemRevenue)
            : 0.0;
        final isEven = idx % 2 == 0;
        return _buildReportRowCard(
          rank: idx + 1,
          title: item.tag.isNotEmpty && item.tag != item.title
              ? '${item.title} (${item.tag})'
              : item.title,
          subtitle: 'Total Quantity Sold: ${item.bills} units',
          trailingTop: _formatMoney(item.totalAmount),
          trailingBottom: '${(share * 100).toStringAsFixed(1)}% revenue',
          progress: share,
          barColor: isEven ? primaryBlue : primaryGreen,
          isDark: isDark,
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 6. DAILY TREND REPORT (DAY-BY-DAY EXPO BREAKDOWN)
  // ---------------------------------------------------------------------------
  Widget _buildDailyTrendReport(List<ExpoOrder> orders, bool isDark) {
    final Map<String, _AggRow> map = {};
    double grandTotal = 0.0;

    for (final o in orders) {
      final localDate = o.orderDate.toLocal();
      final dayKey = DateFormat('yyyy-MM-dd').format(localDate);
      final prettyDay = DateFormat('EEE, dd MMM yyyy').format(localDate);
      final row = map.putIfAbsent(
        dayKey,
        () => _AggRow(title: prettyDay, tag: dayKey),
      );
      row.bills++;
      row.totalAmount += o.totalAmount;
      row.advanceCollected += _effectiveAdvance(o);
      grandTotal += o.totalAmount;
    }

    final list = map.values.toList()
      ..sort((a, b) => b.tag.compareTo(a.tag)); // newest date first

    return SliverList.separated(
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, idx) {
        final item = list[idx];
        final share = grandTotal > 0 ? (item.totalAmount / grandTotal) : 0.0;
        final isEven = idx % 2 == 0;
        return _buildReportRowCard(
          rank: idx + 1,
          title: item.title,
          subtitle:
              '${item.bills} ${item.bills == 1 ? 'Order' : 'Orders'} • Advance: ${_formatMoney(item.advanceCollected)}',
          trailingTop: _formatMoney(item.totalAmount),
          trailingBottom: '${(share * 100).toStringAsFixed(1)}% of expo',
          progress: share,
          barColor: isEven ? primaryBlue : primaryGreen,
          isDark: isDark,
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 7. DISTRICT & STATE REACH REPORT
  // ---------------------------------------------------------------------------
  Widget _buildDistrictStateReport(List<ExpoOrder> orders, bool isDark) {
    final Map<String, _AggRow> map = {};
    double grandTotal = 0.0;

    for (final o in orders) {
      final dist = o.district.trim().isNotEmpty
          ? o.district.trim().toUpperCase()
          : 'UNSPECIFIED';
      final st = o.state.trim().isNotEmpty ? o.state.trim().toUpperCase() : '';
      final label = st.isNotEmpty ? '$dist, $st' : dist;

      final row = map.putIfAbsent(label, () => _AggRow(title: label));
      row.bills++;
      row.totalAmount += o.totalAmount;
      row.advanceCollected += _effectiveAdvance(o);
      grandTotal += o.totalAmount;
    }

    final list = map.values.toList()
      ..sort((a, b) => b.totalAmount.compareTo(a.totalAmount));

    return SliverList.separated(
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, idx) {
        final item = list[idx];
        final share = grandTotal > 0 ? (item.totalAmount / grandTotal) : 0.0;
        final isEven = idx % 2 == 0;
        return _buildReportRowCard(
          rank: idx + 1,
          title: item.title,
          subtitle:
              '${item.bills} ${item.bills == 1 ? 'Order' : 'Orders'} • Advance: ${_formatMoney(item.advanceCollected)}',
          trailingTop: _formatMoney(item.totalAmount),
          trailingBottom: '${(share * 100).toStringAsFixed(1)}% share',
          progress: share,
          barColor: isEven ? primaryBlue : primaryGreen,
          isDark: isDark,
        );
      },
    );
  }

  /// Reusable sleek row card with rank badge, progress bar, and values
  Widget _buildReportRowCard({
    required int rank,
    required String title,
    required String subtitle,
    required String trailingTop,
    required String trailingBottom,
    required double progress,
    required Color barColor,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF132238) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: barColor.withValues(alpha: isDark ? 0.3 : 0.14),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: barColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  '$rank',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12.5,
                    color: barColor,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: isDark ? Colors.white : const Color(0xFF0A1628),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isDark
                            ? Colors.white60
                            : Colors.blueGrey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    trailingTop,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: isDark ? Colors.white : primaryBlue,
                    ),
                  ),
                  Text(
                    trailingBottom,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: isDark ? Colors.white54 : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: isDark ? Colors.white10 : Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
            ),
          ),
        ],
      ),
    );
  }

  /// Sticky bottom bar with prominent button to select Report Types
  Widget _buildBottomReportSelectorBar(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF101E33) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ACTIVE REPORT VIEW',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: isDark ? Colors.white54 : Colors.blueGrey,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(
                        _selectedReportType.icon,
                        size: 16,
                        color: primaryGreen,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          _selectedReportType.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF0A1628),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryBlue,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () => _showReportTypeSelector(context, isDark),
              icon: const Icon(
                Icons.analytics_rounded,
                size: 18,
                color: primaryGreen,
              ),
              label: const Text(
                'Select Report',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lightweight KPI Metric Card widget (no BackdropFilter for smooth 60fps on budget phones)
class _KpiMetricCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color accentColor;
  final bool isHighlight;
  final bool isDark;

  const _KpiMetricCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    this.isHighlight = false,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    if (isHighlight) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: accentColor == primaryBlue
                ? const [Color(0xFF005BAC), Color(0xFF003F7A)]
                : const [Color(0xFF7CB532), Color(0xFF5D8E1E)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: accentColor.withValues(alpha: 0.28),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white70,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 16, color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10.5, color: Colors.white70),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF132238) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: accentColor.withValues(alpha: isDark ? 0.35 : 0.2),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : Colors.blueGrey.shade700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 15, color: accentColor),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : const Color(0xFF0A1628),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              color: isDark ? Colors.white54 : Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Internal accumulator model for fast O(N) grouping
class _AggRow {
  final String title;
  final String tag;
  int bills = 0;
  double totalAmount = 0.0;
  double advanceCollected = 0.0;
  double balanceAmount = 0.0;
  double verifiedAdvance = 0.0;
  double pendingAdvance = 0.0;

  _AggRow({required this.title, this.tag = ''});
}
