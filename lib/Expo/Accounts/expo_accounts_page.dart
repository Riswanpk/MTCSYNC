import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../expo_service.dart';
import 'expo_order_detail_page.dart';

const Color primaryBlue = Color(0xFF005BAC);
const Color primaryGreen = Color(0xFF8CC63F);

/// Verification & Accounts Management page for the `expo_acc` user role.
/// Displays orders created by users in 'Pending Verification' status, allows
/// reviewing details and payment proof image (for Bank Transfer / UPI; no image for Cash),
/// verifying orders into 'Completed', and exporting order summary to PDF.
class ExpoAccountsPage extends StatefulWidget {
  const ExpoAccountsPage({super.key});

  @override
  State<ExpoAccountsPage> createState() => _ExpoAccountsPageState();
}

class _ExpoAccountsPageState extends State<ExpoAccountsPage>
    with SingleTickerProviderStateMixin {
  Exhibition? _selectedExhibition;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime dt) {
    return DateFormat('dd MMM yyyy, hh:mm a').format(dt);
  }

  Color _getOrderTypeColor(String type) {
    switch (type) {
      case 'Spot Delivery':
        return const Color(0xFF10B981); // Emerald Green
      case 'Booking':
        return primaryBlue; // Deep Blue
      case 'Stall Delivery':
        return const Color(0xFFF59E0B); // Amber / Orange
      default:
        return primaryBlue;
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
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Exhibitions created by admin will appear here.',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
          );
        }

        final currentEx = _selectedExhibition ??
            (exhibitions.isNotEmpty ? exhibitions.first : null);

        if (currentEx == null) {
          return const Scaffold(
            body: Center(child: Text('No Exhibition Selected')),
          );
        }

        return Scaffold(
          backgroundColor:
              isDark ? const Color(0xFF0A1628) : const Color(0xFFF7F9FC),
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Expo Accounts Verification',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  currentEx.name,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            backgroundColor: primaryBlue,
            foregroundColor: Colors.white,
            elevation: 0,
            actions: [
              if (exhibitions.length > 1)
                PopupMenuButton<Exhibition>(
                  icon: const Icon(Icons.swap_horiz_rounded,
                      color: Colors.white),
                  tooltip: 'Switch Exhibition',
                  onSelected: (ex) {
                    setState(() => _selectedExhibition = ex);
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
              indicatorColor: primaryGreen,
              indicatorWeight: 3,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              tabs: const [
                Tab(
                  icon: Icon(Icons.pending_actions_rounded, size: 20),
                  text: 'Pending Verification',
                ),
                Tab(
                  icon: Icon(Icons.check_circle_rounded, size: 20),
                  text: 'Completed',
                ),
              ],
            ),
          ),
          body: Column(
            children: [
              // Info banner
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                child: Row(
                  children: [
                    const Icon(Icons.location_on_rounded,
                        size: 16, color: primaryBlue),
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
              ),

              // Stream of orders for selected exhibition
              Expanded(
                child: StreamBuilder<List<ExpoOrder>>(
                  stream: ExpoService.instance
                      .streamOrders(exhibitionId: currentEx.id),
                  builder: (context, ordersSnapshot) {
                    if (ordersSnapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final allOrders = ordersSnapshot.data ?? [];
                    final pendingVerificationOrders = allOrders
                        .where((o) =>
                            o.status == 'Pending Verification' ||
                            o.status == 'Pending')
                        .toList();
                    final completedOrders = allOrders
                        .where((o) => o.status == 'Completed')
                        .toList();

                    return TabBarView(
                      controller: _tabController,
                      children: [
                        _buildOrdersList(
                          orders: pendingVerificationOrders,
                          isDark: isDark,
                          isPendingTab: true,
                        ),
                        _buildOrdersList(
                          orders: completedOrders,
                          isDark: isDark,
                          isPendingTab: false,
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOrdersList({
    required List<ExpoOrder> orders,
    required bool isDark,
    required bool isPendingTab,
  }) {
    if (orders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isPendingTab
                  ? Icons.verified_user_outlined
                  : Icons.task_alt_rounded,
              size: 56,
              color: primaryBlue.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 12),
            Text(
              isPendingTab
                  ? 'No Orders Pending Verification'
                  : 'No Completed Orders',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              isPendingTab
                  ? 'Submitted orders from users will show here for accounts check.'
                  : 'Orders verified by accounts will appear here.',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white38 : Colors.black45,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      itemCount: orders.length,
      itemBuilder: (context, index) {
        final order = orders[index];
        final typeColor = _getOrderTypeColor(order.orderType);

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 1.5,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: isDark
                  ? Colors.white12
                  : Colors.black.withValues(alpha: 0.08),
            ),
          ),
          color: isDark ? const Color(0xFF0F243E) : Colors.white,
          child: InkWell(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ExpoOrderDetailPage(order: order),
                ),
              );
            },
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top row: Shop name & Order type badge
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              order.shopName,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            if (order.customerName.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                order.customerName,
                                style: TextStyle(
                                  fontSize: 13,
                                  color:
                                      isDark ? Colors.white70 : Colors.black54,
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
                            color: isDark ? Colors.white54 : Colors.black45),
                        const SizedBox(width: 4),
                        Text(
                          order.place,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      if (order.phone.isNotEmpty) ...[
                        Icon(Icons.phone_rounded,
                            size: 14,
                            color: isDark ? Colors.white54 : Colors.black45),
                        const SizedBox(width: 4),
                        Text(
                          order.phone,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white60 : Colors.black54,
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
                          color: isDark ? Colors.white54 : Colors.black45),
                      const SizedBox(width: 4),
                      Text(
                        'By: ${order.createdUserName} (${order.preferredBranch})',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white54 : Colors.black54,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _formatDate(order.orderDate).split(',').first,
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white38 : Colors.black45,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),
                  const Divider(height: 1),
                  const SizedBox(height: 10),

                  // Payment mode & Receipt indicator
                  Row(
                    children: [
                      Icon(
                        order.paymentMode == 'Cash'
                            ? Icons.payments_rounded
                            : Icons.account_balance_rounded,
                        size: 16,
                        color: order.paymentMode == 'Cash'
                            ? primaryGreen
                            : primaryBlue,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Payment: ${order.paymentMode}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                      if (order.paymentMode != 'Cash' &&
                          order.paymentProofUrl != null &&
                          order.paymentProofUrl!.isNotEmpty) ...[
                        const SizedBox(width: 8),
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
                              color: isDark ? Colors.white54 : Colors.black54,
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
                            isPendingTab ? 'Tap to verify' : 'Tap to view',
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
