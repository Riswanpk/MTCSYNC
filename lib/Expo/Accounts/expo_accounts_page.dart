import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../expo_service.dart';
import 'expo_pdf_service.dart';

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
  final Set<String> _verifyingOrderIds = {};
  final Set<String> _exportingPdfOrderIds = {};

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

  Future<void> _verifyOrder(ExpoOrder order) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Verify Order?'),
        content: Text(
          'Are you sure you want to verify order for "${order.shopName}" (${order.paymentMode})? This will move the order to Completed.',
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
            child: const Text('Verify'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _verifyingOrderIds.add(order.id));
    try {
      await ExpoService.instance.updateOrderStatus(order.id, 'Completed');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Order "${order.shopName}" verified successfully!'),
            backgroundColor: primaryGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to verify order: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _verifyingOrderIds.remove(order.id));
      }
    }
  }

  Future<void> _exportPdf(ExpoOrder order) async {
    setState(() => _exportingPdfOrderIds.add(order.id));
    try {
      await ExpoPdfService.instance.exportOrderPdf(order);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error exporting PDF: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _exportingPdfOrderIds.remove(order.id));
      }
    }
  }

  void _showImagePreviewDialog(
      BuildContext context, String imageUrl, String title) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppBar(
              title: Text(title, style: const TextStyle(fontSize: 16)),
              backgroundColor: primaryBlue,
              foregroundColor: Colors.white,
              elevation: 0,
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ],
            ),
            Container(
              constraints: const BoxConstraints(maxHeight: 450),
              color: Colors.black,
              child: InteractiveViewer(
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return const SizedBox(
                      height: 250,
                      child: Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return const SizedBox(
                      height: 200,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.broken_image_rounded,
                                size: 48, color: Colors.grey),
                            SizedBox(height: 8),
                            Text('Failed to load image',
                                style: TextStyle(color: Colors.white)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showOrderDetailsDialog(ExpoOrder order, bool isDark) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 650),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      order.shopName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _getOrderTypeColor(order.orderType)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: _getOrderTypeColor(order.orderType),
                      ),
                    ),
                    child: Text(
                      order.orderType,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _getOrderTypeColor(order.orderType),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: (order.status == 'Completed'
                              ? primaryGreen
                              : const Color(0xFFF59E0B))
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      order.status,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: order.status == 'Completed'
                            ? primaryGreen
                            : const Color(0xFFF59E0B),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(),

              // Scrollable content
              Expanded(
                child: ListView(
                  children: [
                    _buildDetailRow('Exhibition', order.exhibitionName, isDark),
                    _buildDetailRow('Date', _formatDate(order.orderDate), isDark),
                    if (order.customerName.isNotEmpty)
                      _buildDetailRow(
                          'Customer Name', order.customerName, isDark),
                    if (order.phone.isNotEmpty)
                      _buildDetailRow('Phone', order.phone, isDark),
                    if (order.place.isNotEmpty)
                      _buildDetailRow('Place', order.place, isDark),
                    if (order.district.isNotEmpty)
                      _buildDetailRow('District', order.district, isDark),
                    if (order.state.isNotEmpty)
                      _buildDetailRow('State', order.state, isDark),
                    _buildDetailRow(
                        'Preferred Branch', order.preferredBranch, isDark),
                    _buildDetailRow(
                        'Salesman', order.preferredSalesman, isDark),
                    _buildDetailRow('Payment Mode', order.paymentMode, isDark),
                    _buildDetailRow('Created By',
                        '${order.createdUserName} (${order.createdUserBranch})', isDark),

                    // Payment image section: Only displayed if payment mode is Bank Transfer or UPI
                    if (order.paymentMode != 'Cash' &&
                        order.paymentProofUrl != null &&
                        order.paymentProofUrl!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'Payment Proof',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: () => _showImagePreviewDialog(
                          context,
                          order.paymentProofUrl!,
                          'Payment Proof - ${order.shopName}',
                        ),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: primaryBlue.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: primaryBlue.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Image.network(
                                  order.paymentProofUrl!,
                                  width: 46,
                                  height: 46,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(
                                    Icons.receipt_long_rounded,
                                    size: 32,
                                    color: primaryBlue,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'View Payment Receipt',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: primaryBlue,
                                      ),
                                    ),
                                    Text(
                                      'Tap to view image full screen',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.black54,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.open_in_new_rounded,
                                color: primaryBlue,
                                size: 18,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 14),
                    const Divider(),
                    const SizedBox(height: 8),

                    const Text(
                      'Items Breakdown',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),

                    ...order.items.map((it) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.05)
                              : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    it.itemName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                Text(
                                  '₹${it.total.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: primaryGreen,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                            if (it.mtcCode.isNotEmpty)
                              Text(
                                'MTC: ${it.mtcCode}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color:
                                      isDark ? Colors.white60 : Colors.black54,
                                ),
                              ),
                            if (it.description.isNotEmpty)
                              Text(
                                it.description,
                                style: TextStyle(
                                  fontSize: 11,
                                  color:
                                      isDark ? Colors.white54 : Colors.black45,
                                ),
                              ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Qty: ${it.qty} × ₹${it.rate.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color:
                                        isDark ? Colors.white70 : Colors.black87,
                                  ),
                                ),
                                Text(
                                  'GST: ${it.gst.toStringAsFixed(0)}%',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color:
                                        isDark ? Colors.white60 : Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                            if (it.photoUrl != null &&
                                it.photoUrl!.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              InkWell(
                                onTap: () => _showImagePreviewDialog(
                                  context,
                                  it.photoUrl!,
                                  'Item: ${it.itemName}',
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.photo_outlined,
                                        size: 14, color: primaryBlue),
                                    const SizedBox(width: 4),
                                    Text(
                                      'View Item Photo',
                                      style: TextStyle(
                                        fontSize: 11,
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
                      );
                    }),

                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: primaryGreen.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Subtotal:',
                                  style: TextStyle(fontSize: 12)),
                              Text('₹${order.subtotal.toStringAsFixed(2)}',
                                  style: const TextStyle(fontSize: 12)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Total GST:',
                                  style: TextStyle(fontSize: 12)),
                              Text('₹${order.totalGst.toStringAsFixed(2)}',
                                  style: const TextStyle(fontSize: 12)),
                            ],
                          ),
                          const Divider(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Grand Total:',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '₹${order.totalAmount.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: primaryGreen,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),
              // Footer Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: const BorderSide(color: primaryBlue),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _exportPdf(order);
                      },
                      icon: const Icon(Icons.picture_as_pdf_rounded,
                          color: primaryBlue, size: 18),
                      label: const Text(
                        'Print / PDF',
                        style: TextStyle(
                          color: primaryBlue,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  if (order.status != 'Completed') ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryGreen,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _verifyOrder(order);
                        },
                        icon: const Icon(Icons.verified_rounded, size: 18),
                        label: const Text(
                          'Verify Order',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
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
        final isVerifying = _verifyingOrderIds.contains(order.id);
        final isExporting = _exportingPdfOrderIds.contains(order.id);

        return Card(
          margin: const EdgeInsets.only(bottom: 14),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: isDark
                  ? Colors.white12
                  : Colors.black.withValues(alpha: 0.08),
            ),
          ),
          color: isDark ? const Color(0xFF0F243E) : Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row: Shop name & Order type
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
                                color: isDark ? Colors.white70 : Colors.black54,
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

                // Payment info & Proof review banner
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.04)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDark
                          ? Colors.white10
                          : Colors.black.withValues(alpha: 0.05),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        order.paymentMode == 'Cash'
                            ? Icons.payments_rounded
                            : Icons.account_balance_rounded,
                        size: 18,
                        color: order.paymentMode == 'Cash'
                            ? primaryGreen
                            : primaryBlue,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Payment: ${order.paymentMode}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const Spacer(),

                      // If Bank Transfer or UPI, show photo badge / thumbnail
                      // If Cash, no image displayed as requested
                      if (order.paymentMode != 'Cash') ...[
                        if (order.paymentProofUrl != null &&
                            order.paymentProofUrl!.isNotEmpty)
                          InkWell(
                            onTap: () => _showImagePreviewDialog(
                              context,
                              order.paymentProofUrl!,
                              'Payment Proof - ${order.shopName}',
                            ),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: Image.network(
                                    order.paymentProofUrl!,
                                    width: 24,
                                    height: 24,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Icon(
                                      Icons.receipt_rounded,
                                      size: 16,
                                      color: primaryBlue,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Text(
                                  'View Receipt',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: primaryBlue,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          const Text(
                            'No Image',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.redAccent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                // Amount and Action Buttons
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
                      children: [
                        // Details Button
                        IconButton(
                          icon: const Icon(Icons.info_outline_rounded,
                              size: 22, color: primaryBlue),
                          tooltip: 'Order Details',
                          onPressed: () =>
                              _showOrderDetailsDialog(order, isDark),
                        ),

                        // PDF Export Button
                        IconButton(
                          icon: isExporting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.picture_as_pdf_rounded,
                                  size: 22, color: primaryBlue),
                          tooltip: 'Export / Print PDF',
                          onPressed:
                              isExporting ? null : () => _exportPdf(order),
                        ),

                        // Verify Button
                        if (isPendingTab) ...[
                          const SizedBox(width: 4),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryGreen,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: isVerifying
                                ? null
                                : () => _verifyOrder(order),
                            icon: isVerifying
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.check_circle_outline_rounded,
                                    size: 16),
                            label: const Text(
                              'Verify',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
