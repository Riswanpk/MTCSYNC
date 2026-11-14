import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../Navigation/user_cache_service.dart';
import '../expo_service.dart';
import 'expo_order_detail_page.dart';

const Color primaryBlue = Color(0xFF005BAC);
const Color primaryGreen = Color(0xFF8CC63F);

/// Verification & Accounts Management page for the `expo_acc` user role.
/// Displays orders created by users categorized into:
/// - 'Spot Delivery' (pending verification)
/// - 'Stall Delivery' (pending verification)
/// - 'Booking' (pending verification)
/// - 'Completed' (all completed orders)
///
/// Features:
/// 1. Filter orders by creator / sales user.
/// 2. Multi-selection of cash-only orders of the same sales user to calculate
///    the total cash/advance amount to collect and verify them together.
class ExpoAccountsPage extends StatefulWidget {
  const ExpoAccountsPage({super.key});

  @override
  State<ExpoAccountsPage> createState() => _ExpoAccountsPageState();
}

class _ExpoAccountsPageState extends State<ExpoAccountsPage>
    with SingleTickerProviderStateMixin {
  Exhibition? _selectedExhibition;
  late TabController _tabController;

  // Filter by sales user (createdUserId). null means 'All Users'.
  String? _selectedFilterUserId;

  // Multi-selection of Cash orders for batch cash collection & verification
  final Set<String> _selectedCashOrderIds = <String>{};
  String? _batchClaimedUserId; // UID of user whose cash orders are currently selected
  String? _batchClaimedUserName;
  bool _isBatchVerifying = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime dt) {
    return DateFormat('dd MMM yyyy, hh:mm a').format(dt);
  }

  void _clearBatchSelection() {
    setState(() {
      _selectedCashOrderIds.clear();
      _batchClaimedUserId = null;
      _batchClaimedUserName = null;
    });
  }

  void _toggleCashOrderSelection(ExpoOrder order) {
    if (!order.hasCashComponent) return;
    if (order.status == 'Completed') return;

    setState(() {
      if (_selectedCashOrderIds.contains(order.id)) {
        _selectedCashOrderIds.remove(order.id);
        if (_selectedCashOrderIds.isEmpty) {
          _batchClaimedUserId = null;
          _batchClaimedUserName = null;
        }
      } else {
        // Enforce: only orders of the SAME sales user can be batch collected together
        if (_selectedCashOrderIds.isNotEmpty &&
            _batchClaimedUserId != null &&
            _batchClaimedUserId != order.createdUserId) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Only Cash orders of the same sales user ($_batchClaimedUserName) can be selected together.',
              ),
              backgroundColor: Colors.orange.shade800,
            ),
          );
          return;
        }
        _batchClaimedUserId = order.createdUserId;
        _batchClaimedUserName = order.createdUserName.isNotEmpty
            ? order.createdUserName
            : 'Sales User';
        _selectedCashOrderIds.add(order.id);
      }
    });
  }

  Future<void> _verifyBatchCashOrders(List<ExpoOrder> allOrders) async {
    final selectedList = allOrders
        .where((o) => _selectedCashOrderIds.contains(o.id))
        .toList();

    if (selectedList.isEmpty) return;

    final double totalCashToCollect = selectedList.fold(
      0.0,
      (sum, o) => sum + o.totalCashCollected,
    );

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Verify Batch Cash Orders?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sales User: $_batchClaimedUserName',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text('Selected Orders: ${selectedList.length}'),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: primaryGreen.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: primaryGreen.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Total Cash to Collect:',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  Text(
                    '₹${totalCashToCollect.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: primaryGreen,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Confirm that you have received this total cash amount from the sales user. All selected orders will be marked as Completed.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryGreen,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Collect Cash & Verify All'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isBatchVerifying = true);
    try {
      final ids = selectedList.map((o) => o.id).toList();
      await ExpoService.instance.updateMultipleOrdersStatus(ids, 'Completed');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Successfully verified ${ids.length} orders for $_batchClaimedUserName!',
            ),
            backgroundColor: primaryGreen,
          ),
        );
      }
      _clearBatchSelection();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to verify batch orders: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isBatchVerifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return StreamBuilder<List<Exhibition>>(
      stream: ExpoService.instance.streamExhibitions(),
      builder: (context, exSnapshot) {
        if (exSnapshot.connectionState == ConnectionState.waiting &&
            _selectedExhibition == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final exhibitions = exSnapshot.data ?? [];

        if (exhibitions.isEmpty && _selectedExhibition == null) {
          return Scaffold(
            backgroundColor:
                isDark ? const Color(0xFF0A1628) : const Color(0xFFF7F9FC),
            appBar: AppBar(
              title: const Text(
                'Expo Verification',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              backgroundColor: primaryBlue,
              elevation: 0,
            ),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.event_busy_rounded,
                    size: 64,
                    color: primaryBlue.withValues(alpha: 0.4),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No Active Exhibitions',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Exhibitions created by admin will appear here.',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ],
              ),
            ),
          );
        }

        if (_selectedExhibition == null && exhibitions.isNotEmpty) {
          _selectedExhibition = exhibitions.first;
        } else if (_selectedExhibition != null &&
            exhibitions.any((e) => e.id == _selectedExhibition!.id)) {
          _selectedExhibition =
              exhibitions.firstWhere((e) => e.id == _selectedExhibition!.id);
        }

        final currentEx = _selectedExhibition!;
        if (currentEx.isEnded) {
          ExpoService.instance.autoConvertExpiredStallDeliveries(currentEx);
        }

        return Scaffold(
          backgroundColor:
              isDark ? const Color(0xFF0A1628) : const Color(0xFFF7F9FC),
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Expo Verification',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  ),
                ),
                Text(
                  currentEx.name,
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ],
            ),
            backgroundColor: primaryBlue,
            foregroundColor: Colors.white,
            elevation: 0,
            actions: [
              if (exhibitions.length > 1)
                PopupMenuButton<Exhibition>(
                  tooltip: 'Switch Exhibition',
                  icon: const Icon(Icons.swap_horiz_rounded),
                  onSelected: (ex) {
                    setState(() {
                      _selectedExhibition = ex;
                      _clearBatchSelection();
                    });
                  },
                  itemBuilder: (ctx) => exhibitions.map((e) {
                    return PopupMenuItem<Exhibition>(
                      value: e,
                      child: Text(
                        e.name,
                        style: TextStyle(
                          fontWeight: e.id == currentEx.id
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    );
                  }).toList(),
                ),
            ],
            bottom: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorColor: primaryGreen,
              indicatorWeight: 3,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              tabs: const [
                Tab(
                  icon: Icon(Icons.flash_on_rounded, size: 18),
                  text: 'Spot',
                ),
                Tab(
                  icon: Icon(Icons.storefront_rounded, size: 18),
                  text: 'Stall',
                ),
                Tab(
                  icon: Icon(Icons.local_shipping_rounded, size: 18),
                  text: 'Booking',
                ),
                Tab(
                  icon: Icon(Icons.check_circle_rounded, size: 18),
                  text: 'Completed',
                ),
              ],
            ),
          ),
          body: StreamBuilder<List<ExpoOrder>>(
            stream: ExpoService.instance
                .streamOrders(exhibitionId: currentEx.id),
            builder: (context, ordersSnapshot) {
              if (ordersSnapshot.connectionState ==
                  ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final allOrders = ordersSnapshot.data ?? [];

              // Extract distinct users who created orders for the filter
              final Map<String, String> distinctUsers = {};
              for (final o in allOrders) {
                if (o.createdUserId.isNotEmpty) {
                  final name = o.createdUserName.isNotEmpty
                      ? o.createdUserName
                      : 'User';
                  distinctUsers[o.createdUserId] = name;
                }
              }

              // Apply user filter if active
              final filteredOrders = _selectedFilterUserId == null
                  ? allOrders
                  : allOrders
                      .where((o) => o.createdUserId == _selectedFilterUserId)
                      .toList();

              // Categorize into tabs
              final spotOrders = filteredOrders
                  .where((o) =>
                      o.orderType == 'Spot Delivery' &&
                      o.status != 'Completed')
                  .toList();
              final stallOrders = filteredOrders
                  .where((o) =>
                      o.orderType == 'Stall Delivery' &&
                      o.status != 'Completed')
                  .toList();
              final bookingOrders = filteredOrders
                  .where((o) =>
                      o.orderType == 'Booking' &&
                      o.status != 'Completed')
                  .toList();
              final completedOrders = filteredOrders
                  .where((o) => o.status == 'Completed')
                  .toList();

              // Calculate batch selection metrics for the bottom sheet
              final selectedOrdersList = allOrders
                  .where((o) => _selectedCashOrderIds.contains(o.id))
                  .toList();
              final double batchTotalCash = selectedOrdersList.fold(
                0.0,
                (sum, o) => sum + o.totalCashCollected,
              );

              return Column(
                children: [
                  // Exhibition Info & User Filter Bar
                  _buildHeaderAndFilterBar(
                    currentEx: currentEx,
                    distinctUsers: distinctUsers,
                    isDark: isDark,
                  ),

                  // TabBarView for the 4 tabs
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      physics: const ClampingScrollPhysics(),
                      children: [
                        _ExpoOrdersTabKeepAlive(
                          orders: spotOrders,
                          isDark: isDark,
                          tabTitle: 'Spot Delivery',
                          isPendingTab: true,
                          selectedCashOrderIds: _selectedCashOrderIds,
                          onToggleSelect: _toggleCashOrderSelection,
                        ),
                        _ExpoOrdersTabKeepAlive(
                          orders: stallOrders,
                          isDark: isDark,
                          tabTitle: 'Stall Delivery',
                          isPendingTab: true,
                          selectedCashOrderIds: _selectedCashOrderIds,
                          onToggleSelect: _toggleCashOrderSelection,
                        ),
                        _ExpoOrdersTabKeepAlive(
                          orders: bookingOrders,
                          isDark: isDark,
                          tabTitle: 'Booking',
                          isPendingTab: true,
                          selectedCashOrderIds: _selectedCashOrderIds,
                          onToggleSelect: _toggleCashOrderSelection,
                        ),
                        _ExpoOrdersTabKeepAlive(
                          orders: completedOrders,
                          isDark: isDark,
                          tabTitle: 'Completed',
                          isPendingTab: false,
                          selectedCashOrderIds: _selectedCashOrderIds,
                          onToggleSelect: _toggleCashOrderSelection,
                        ),
                      ],
                    ),
                  ),

                  // Bottom Cash Batch Collection & Verification Bar
                  if (_selectedCashOrderIds.isNotEmpty)
                    _buildBatchVerificationBottomBar(
                      selectedCount: _selectedCashOrderIds.length,
                      totalCash: batchTotalCash,
                      allOrders: allOrders,
                      isDark: isDark,
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  /// Banner with exhibition location, dates, and sales user filter dropdown
  Widget _buildHeaderAndFilterBar({
    required Exhibition currentEx,
    required Map<String, String> distinctUsers,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF0D2137)
            : primaryBlue.withValues(alpha: 0.06),
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? Colors.white10
                : Colors.black.withValues(alpha: 0.05),
          ),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.location_on_rounded, size: 15, color: primaryBlue),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  currentEx.location,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${_formatDate(currentEx.startDate).split(',').first} - ${_formatDate(currentEx.endDate).split(',').first}',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white54 : Colors.black54,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // User Filter Row
          Row(
            children: [
              const Icon(Icons.filter_alt_rounded, size: 16, color: primaryBlue),
              const SizedBox(width: 6),
              const Text(
                'Filter by User:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF132847) : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _selectedFilterUserId != null
                          ? primaryBlue
                          : (isDark ? Colors.white24 : Colors.black12),
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      value: _selectedFilterUserId,
                      isExpanded: true,
                      icon: const Icon(Icons.arrow_drop_down, size: 20),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      dropdownColor:
                          isDark ? const Color(0xFF132847) : Colors.white,
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('All Users'),
                        ),
                        ...distinctUsers.entries.map((entry) {
                          return DropdownMenuItem<String?>(
                            value: entry.key,
                            child: Text(
                              entry.value,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }),
                      ],
                      onChanged: (val) {
                        setState(() {
                          _selectedFilterUserId = val;
                          _clearBatchSelection();
                        });
                      },
                    ),
                  ),
                ),
              ),
              if (_selectedFilterUserId != null) ...[
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Clear Filter',
                  onPressed: () {
                    setState(() {
                      _selectedFilterUserId = null;
                      _clearBatchSelection();
                    });
                  },
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// Sticky bottom card showing total cash to collect and bulk verify button
  Widget _buildBatchVerificationBottomBar({
    required int selectedCount,
    required double totalCash,
    required List<ExpoOrder> allOrders,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F243E) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: primaryBlue.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '$selectedCount selected',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: primaryBlue,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'User: $_batchClaimedUserName',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white70 : Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Text(
                            'Collect Cash: ',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '₹${totalCash.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: primaryGreen,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _clearBatchSelection,
                  child: const Text('Clear', style: TextStyle(color: Colors.grey)),
                ),
                const SizedBox(width: 4),
                ElevatedButton.icon(
                  onPressed: _isBatchVerifying
                      ? null
                      : () => _verifyBatchCashOrders(allOrders),
                  icon: _isBatchVerifying
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_circle_outline_rounded, size: 18),
                  label: Text(
                    _isBatchVerifying ? 'Verifying...' : 'Verify All',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Lightweight stateful wrapper using AutomaticKeepAliveClientMixin.
/// Keeps list state in memory when switching tabs so low-end budget devices
/// don't stutter, lag, or reconstruct widgets during tab transitions.
class _ExpoOrdersTabKeepAlive extends StatefulWidget {
  final List<ExpoOrder> orders;
  final bool isDark;
  final String tabTitle;
  final bool isPendingTab;
  final Set<String> selectedCashOrderIds;
  final ValueChanged<ExpoOrder> onToggleSelect;

  const _ExpoOrdersTabKeepAlive({
    required this.orders,
    required this.isDark,
    required this.tabTitle,
    required this.isPendingTab,
    required this.selectedCashOrderIds,
    required this.onToggleSelect,
  });

  @override
  State<_ExpoOrdersTabKeepAlive> createState() =>
      _ExpoOrdersTabKeepAliveState();
}

class _ExpoOrdersTabKeepAliveState extends State<_ExpoOrdersTabKeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  Color _getOrderTypeColor(String type) {
    switch (type) {
      case 'Spot Delivery':
        return const Color(0xFF10B981);
      case 'Booking':
        return primaryBlue;
      case 'Stall Delivery':
        return const Color(0xFFFF6F00);
      default:
        return primaryBlue;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (widget.orders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              widget.isPendingTab
                  ? Icons.verified_user_outlined
                  : Icons.task_alt_rounded,
              size: 56,
              color: primaryBlue.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 12),
            Text(
              'No ${widget.tabTitle} Orders',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: widget.isDark ? Colors.white70 : Colors.black87,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              widget.isPendingTab
                  ? 'Orders waiting for accounts verification will appear here.'
                  : 'Completed and delivered orders will appear here.',
              style: TextStyle(
                fontSize: 12,
                color: widget.isDark ? Colors.white38 : Colors.black45,
              ),
            ),
          ],
        ),
      );
    }

    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    final now = DateTime.now();

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(
        16,
        14,
        16,
        widget.selectedCashOrderIds.isNotEmpty ? 100 : 24,
      ),
      itemCount: widget.orders.length,
      itemBuilder: (context, index) {
        final order = widget.orders[index];
        final typeColor = _getOrderTypeColor(order.orderType);
        final bool isCash = order.hasCashComponent;
        final bool isSelected = widget.selectedCashOrderIds.contains(order.id);

        final bool isClaimedByOther = order.claimedById != null &&
            order.claimedById != currentUserId &&
            order.claimedAt != null &&
            now.difference(order.claimedAt!).inMinutes < 5;

        final double cashAmount = order.totalCashCollected;

        return Card(
          key: ValueKey(order.id),
          margin: const EdgeInsets.only(bottom: 12),
          elevation: isSelected ? 3 : 1.5,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: isSelected
                  ? primaryGreen
                  : (isClaimedByOther
                      ? Colors.amber.shade700
                      : (widget.isDark
                          ? Colors.white12
                          : Colors.black.withValues(alpha: 0.08))),
              width: isSelected ? 2 : (isClaimedByOther ? 1.5 : 1),
            ),
          ),
          color: isSelected
              ? (widget.isDark
                  ? primaryGreen.withValues(alpha: 0.12)
                  : primaryGreen.withValues(alpha: 0.08))
              : (widget.isDark ? const Color(0xFF0F243E) : Colors.white),
          child: InkWell(
            onTap: () async {
              final currentUserName =
                  UserCacheService.instance.username ?? 'Accounts User';

              // Only perform queue claim lock on pending verification orders
              if (order.status != 'Completed') {
                final claimResult = await ExpoService.instance
                    .claimOrderForVerification(
                  orderId: order.id,
                  userId: currentUserId,
                  userName: currentUserName,
                );

                if (claimResult['success'] != true) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          claimResult['message'] ??
                              'Order is currently being verified by another accounts user.',
                        ),
                        backgroundColor: Colors.amber.shade800,
                      ),
                    );
                  }
                  return;
                }
              }

              if (!context.mounted) return;
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ExpoOrderDetailPage(
                    order: order,
                    currentUserId: currentUserId,
                  ),
                ),
              );
            },
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isClaimedByOther) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade100,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.lock_clock_rounded,
                              size: 14, color: Colors.amber.shade900),
                          const SizedBox(width: 4),
                          Text(
                            'In review by ${order.claimedByName ?? "another user"}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.amber.shade900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Top row: Checkbox (for Cash orders), Shop name & Order type badge
                  Row(
                    children: [
                      if (widget.isPendingTab && isCash) ...[
                        InkWell(
                          onTap: () => widget.onToggleSelect(order),
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Icon(
                              isSelected
                                  ? Icons.check_box_rounded
                                  : Icons.check_box_outline_blank_rounded,
                              color: isSelected ? primaryGreen : Colors.grey,
                              size: 24,
                            ),
                          ),
                        ),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                if (order.billNumber != null) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    margin: const EdgeInsets.only(right: 6),
                                    decoration: BoxDecoration(
                                      color: primaryBlue.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '#${order.billNumber}',
                                      style: const TextStyle(
                                        color: primaryBlue,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                                Expanded(
                                  child: Text(
                                    order.shopName,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: widget.isDark ? Colors.white : Colors.black87,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (order.customerName.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                order.customerName,
                                style: TextStyle(
                                  fontSize: 13,
                                  color:
                                      widget.isDark ? Colors.white70 : Colors.black54,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: typeColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: typeColor),
                        ),
                        child: Text(
                          order.orderType,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: typeColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Location & Phone
                  Row(
                    children: [
                      if (order.place.isNotEmpty) ...[
                        Icon(Icons.place_rounded,
                            size: 14,
                            color: widget.isDark ? Colors.white54 : Colors.black45),
                        const SizedBox(width: 4),
                        Text(
                          order.place,
                          style: TextStyle(
                            fontSize: 12,
                            color: widget.isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      if (order.phone.isNotEmpty) ...[
                        Icon(Icons.phone_rounded,
                            size: 14,
                            color: widget.isDark ? Colors.white54 : Colors.black45),
                        const SizedBox(width: 4),
                        Text(
                          order.phone,
                          style: TextStyle(
                            fontSize: 12,
                            color: widget.isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),

                  // User who created the order & Branch
                  Row(
                    children: [
                      Icon(Icons.person_outline_rounded,
                          size: 14,
                          color: widget.isDark ? Colors.white54 : Colors.black45),
                      const SizedBox(width: 4),
                      Text(
                        'By: ${order.createdUserName} (${order.preferredBranch})',
                        style: TextStyle(
                          fontSize: 11,
                          color: widget.isDark ? Colors.white54 : Colors.black54,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        DateFormat('dd MMM yyyy').format(order.orderDate),
                        style: TextStyle(
                          fontSize: 11,
                          color: widget.isDark ? Colors.white38 : Colors.black45,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),
                  const Divider(height: 1),
                  const SizedBox(height: 10),

                  // Payment mode & Cash amount to collect tag
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isCash
                                ? Icons.payments_rounded
                                : Icons.account_balance_rounded,
                            size: 16,
                            color: isCash ? primaryGreen : primaryBlue,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Payment: ${ExpoOrder.normalizePaymentMode(order.paymentMode)}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: widget.isDark
                                  ? Colors.white70
                                  : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                      if (isCash && cashAmount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: primaryGreen.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Cash: ₹${cashAmount.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: primaryGreen,
                            ),
                          ),
                        ),
                      if ((order.paymentProofUrl != null &&
                              order.paymentProofUrl!.isNotEmpty) ||
                          (order.pickupPaymentProofUrl != null &&
                              order.pickupPaymentProofUrl!.isNotEmpty))
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: primaryBlue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.receipt_rounded,
                                  size: 12, color: primaryBlue),
                              SizedBox(width: 3),
                              Text(
                                'Receipt attached',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: primaryBlue,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: 10),
                  const Divider(height: 1),
                  const SizedBox(height: 10),

                  // Bottom info: Item count, Grand total, and Tap indicator
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${order.items.length} items (${order.totalQty} pcs)',
                            style: TextStyle(
                              fontSize: 11,
                              color: widget.isDark ? Colors.white54 : Colors.black54,
                            ),
                          ),
                          Text(
                            '₹${order.totalAmount.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: primaryGreen,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.isPendingTab ? 'Tap to verify' : 'Tap to view',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: primaryBlue.withValues(alpha: 0.8),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 13,
                            color: primaryBlue,
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
