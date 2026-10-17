import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../Navigation/user_cache_service.dart';
import '../expo_service.dart';
import 'expo_order_form.dart';

const Color primaryBlue = Color(0xFF005BAC);
const Color primaryGreen = Color(0xFF8CC63F);

class ExpoUserMainPage extends StatefulWidget {
  final Exhibition? initialExhibition;
  final bool isAdminView;

  const ExpoUserMainPage({
    super.key,
    this.initialExhibition,
    this.isAdminView = false,
  });

  @override
  State<ExpoUserMainPage> createState() => _ExpoUserMainPageState();
}

class _ExpoUserMainPageState extends State<ExpoUserMainPage> {
  Exhibition? _selectedExhibition;
  String? _currentUserId;
  String? _userRole;
  bool _isLoadingUser = true;

  @override
  void initState() {
    super.initState();
    _selectedExhibition = widget.initialExhibition;
    _initUser();
  }

  Future<void> _initUser() async {
    try {
      final cache = UserCacheService.instance;
      await cache.ensureLoaded();
      final user = FirebaseAuth.instance.currentUser;
      if (mounted) {
        setState(() {
          _currentUserId = user?.uid;
          _userRole = cache.role;
          _isLoadingUser = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingUser = false);
    }
  }

  String _formatDate(DateTime dt) {
    return DateFormat('dd MMM yyyy, hh:mm a').format(dt.toLocal());
  }

  Color _getOrderTypeColor(String type) {
    switch (type) {
      case 'Spot Delivery':
        return const Color(0xFF00897B);
      case 'Booking':
        return primaryBlue;
      case 'Stall Delivery':
        return const Color(0xFFFF6F00);
      default:
        return primaryBlue;
    }
  }

  void _showOrderDetailsDialog(ExpoOrder order, bool isDark) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF0F243E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    order.shopName,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getOrderTypeColor(order.orderType)
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _getOrderTypeColor(order.orderType),
                    ),
                  ),
                  child: Text(
                    order.orderType,
                    style: TextStyle(
                      color: _getOrderTypeColor(order.orderType),
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            if (order.customerName.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Customer: ${order.customerName}',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
            ],
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Info block
                _buildDialogInfoRow(
                  'Date',
                  _formatDate(order.orderDate),
                  isDark,
                ),
                if (order.deliveryDate != null)
                  _buildDialogInfoRow(
                    'Delivery Date',
                    DateFormat('dd MMM yyyy').format(order.deliveryDate!),
                    isDark,
                  ),
                if (order.stallPickupDate != null)
                  _buildDialogInfoRow(
                    'Pickup Date',
                    DateFormat('dd MMM yyyy').format(order.stallPickupDate!),
                    isDark,
                  ),
                if (order.stallPickupStatus != null &&
                    order.stallPickupStatus!.isNotEmpty)
                  _buildDialogInfoRow(
                    'Stall Status',
                    order.stallPickupStatus!,
                    isDark,
                  ),
                if (order.isConvertedToBooking)
                  _buildDialogInfoRow(
                    'Notice',
                    'Converted from Stall Delivery to Normal Booking',
                    isDark,
                  ),
                if (order.phone.isNotEmpty)
                  _buildDialogInfoRow('Phone', order.phone, isDark),
                if (order.place.isNotEmpty || order.district.isNotEmpty)
                  _buildDialogInfoRow(
                    'Location',
                    [order.place, order.district, order.state]
                        .where((s) => s.isNotEmpty)
                        .join(', '),
                    isDark,
                  ),
                if (order.orderType != 'Spot Delivery')
                  _buildDialogInfoRow(
                    'Branch / Salesman',
                    '${order.preferredBranch} (${order.preferredSalesman})',
                    isDark,
                  ),
                _buildDialogInfoRow(
                  'Booked By',
                  '${order.createdUserName} (${order.createdUserBranch})',
                  isDark,
                ),
                _buildDialogInfoRow(
                  'Payment Mode',
                  order.paymentMode,
                  isDark,
                ),
                if (order.paymentProofUrl != null &&
                    order.paymentProofUrl!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () {
                      _showImagePreviewDialog(
                        context,
                        order.paymentProofUrl!,
                        '${order.paymentMode} Proof',
                      );
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: primaryBlue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: primaryBlue.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.receipt_long_rounded,
                              color: primaryBlue, size: 20),
                          const SizedBox(width: 8),
                          const Text(
                            'View Payment Receipt',
                            style: TextStyle(
                              color: primaryBlue,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          const Spacer(),
                          const Icon(Icons.open_in_new_rounded,
                              color: primaryBlue, size: 16),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 8),

                const Text(
                  'Item Breakdown',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),

                // Items list
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
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                          ),
                        if (it.description.isNotEmpty)
                          Text(
                            it.description,
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                          ),
                        const SizedBox(height: 4),
                        Text(
                          'Qty: ${it.qty}  ×  Rate: ₹${it.rate.toStringAsFixed(2)}  (+${it.gst}% GST)',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                        if (it.photoUrl != null && it.photoUrl!.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          InkWell(
                            onTap: () {
                              _showImagePreviewDialog(
                                context,
                                it.photoUrl!,
                                it.itemName,
                              );
                            },
                            child: Row(
                              children: [
                                const Icon(Icons.photo_camera_rounded,
                                    size: 14, color: primaryBlue),
                                const SizedBox(width: 4),
                                const Text(
                                  'View Item Photo',
                                  style: TextStyle(
                                    color: primaryBlue,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
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

                const SizedBox(height: 8),
                const Divider(),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total Qty:'),
                    Text('${order.totalQty}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Subtotal:'),
                    Text('₹${order.subtotal.toStringAsFixed(2)}'),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total GST:'),
                    Text('+ ₹${order.totalGst.toStringAsFixed(2)}',
                        style: const TextStyle(color: Colors.orange)),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Grand Total:',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(
                      '₹${order.totalAmount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: primaryGreen,
                      ),
                    ),
                  ],
                ),
                if (order.orderType != 'Spot Delivery') ...[
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Advance Paid:'),
                      Text(
                        '₹${order.advanceAmount.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: primaryGreen,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Balance Due:'),
                      Text(
                        '₹${order.balanceAmount.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: order.balanceAmount > 0
                              ? const Color(0xFFE65100)
                              : primaryGreen,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
          if (order.orderType == 'Stall Delivery' &&
              order.stallPickupStatus != 'Picked Up' &&
              !order.isConvertedToBooking)
            ElevatedButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                await ExpoService.instance.markStallDeliveryPickedUp(order.id);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                          'Order marked as Picked Up at Stall (Spot Delivery)!'),
                      backgroundColor: primaryGreen,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6F00),
              ),
              child: const Text('Picked Up at Stall',
                  style: TextStyle(color: Colors.white)),
            ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              final newStatus =
                  order.status == 'Pending' ? 'Completed' : 'Pending';
              await ExpoService.instance
                  .updateOrderStatus(order.id, newStatus);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Order marked as $newStatus'),
                    backgroundColor: primaryGreen,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  order.status == 'Pending' ? primaryGreen : Colors.orange,
            ),
            child: Text(
              order.status == 'Pending'
                  ? 'Mark Completed'
                  : 'Move to Pending',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDialogInfoRow(String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
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

    if (_isLoadingUser) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final bool isAdmin = widget.isAdminView || _userRole == 'admin';
    final stream = isAdmin
        ? ExpoService.instance.streamExhibitions()
        : ExpoService.instance
            .streamExhibitionsForUser(_currentUserId ?? '');

    return StreamBuilder<List<Exhibition>>(
      stream: stream,
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
                'Expo Orders',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              backgroundColor: primaryBlue,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.storefront_outlined,
                      size: 68,
                      color: primaryBlue.withValues(alpha: 0.35),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No Exhibition Assigned',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isAdmin
                          ? 'No exhibitions exist yet. Create one from the admin page.'
                          : 'You have not been selected for any active exhibitions yet. When an admin adds you to an exhibition, it will appear here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        // Auto-select first exhibition if not set
        if (_selectedExhibition == null && exhibitions.isNotEmpty) {
          _selectedExhibition = exhibitions.first;
        } else if (_selectedExhibition != null &&
            exhibitions.any((e) => e.id == _selectedExhibition!.id)) {
          // Refresh data of currently selected exhibition
          _selectedExhibition =
              exhibitions.firstWhere((e) => e.id == _selectedExhibition!.id);
        }

        final currentEx = _selectedExhibition!;
        if (currentEx.isEnded) {
          ExpoService.instance.autoConvertExpiredStallDeliveries(currentEx);
        }

        return DefaultTabController(
          length: 2,
          child: Scaffold(
            backgroundColor:
                isDark ? const Color(0xFF0A1628) : const Color(0xFFF7F9FC),
            appBar: AppBar(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Expo Orders',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
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
              bottom: const TabBar(
                indicatorColor: primaryGreen,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                tabs: [
                  Tab(text: 'Pending'),
                  Tab(text: 'Completed'),
                ],
              ),
            ),
            body: Column(
              children: [
                // Exhibition Info Header Banner
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

                // Orders Tabs
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
                      final pendingOrders = allOrders
                          .where((o) =>
                              o.status == 'Pending' ||
                              o.status == 'Pending Verification')
                          .toList();
                      final completedOrders = allOrders
                          .where((o) => o.status == 'Completed')
                          .toList();

                      return TabBarView(
                        children: [
                          _buildOrdersList(
                            pendingOrders,
                            isDark,
                            tabName: 'Pending',
                          ),
                          _buildOrdersList(
                            completedOrders,
                            isDark,
                            tabName: 'Completed',
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
            // Middle bottom + button to add order
            floatingActionButtonLocation:
                FloatingActionButtonLocation.centerFloat,
            floatingActionButton: FloatingActionButton.extended(
              onPressed: () async {
                final chosenType = await _showOrderTypeDialog(context);
                if (chosenType != null && context.mounted) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ExpoOrderFormPage(
                        exhibition: currentEx,
                        initialOrderType: chosenType,
                      ),
                    ),
                  );
                }
              },
              backgroundColor: primaryBlue,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded, size: 24),
              label: const Text(
                'Add Order',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
          ),
        );
      },
    );
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
              constraints: const BoxConstraints(maxHeight: 400),
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return const SizedBox(
                    height: 200,
                    child: Center(child: CircularProgressIndicator()),
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
                          Text('Failed to load image'),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _showOrderTypeDialog(BuildContext context) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF0F243E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Select Order Type',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 17,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Expanded(
                child: _buildOrderTypeActionTile(
                  context: ctx,
                  type: 'Spot Delivery',
                  icon: Icons.flash_on_rounded,
                  color: const Color(0xFF00897B),
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildOrderTypeActionTile(
                  context: ctx,
                  type: 'Booking',
                  icon: Icons.bookmark_add_rounded,
                  color: primaryBlue,
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildOrderTypeActionTile(
                  context: ctx,
                  type: 'Stall Delivery',
                  icon: Icons.storefront_rounded,
                  color: const Color(0xFFFF6F00),
                  isDark: isDark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOrderTypeActionTile({
    required BuildContext context,
    required String type,
    required IconData icon,
    required Color color,
    required bool isDark,
  }) {
    return InkWell(
      onTap: () => Navigator.of(context).pop(type),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: isDark ? 0.15 : 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: color.withValues(alpha: 0.35),
            width: 1.2,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: color.withValues(alpha: 0.2),
              child: Icon(icon, size: 22, color: color),
            ),
            const SizedBox(height: 8),
            Text(
              type,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrdersList(
    List<ExpoOrder> orders,
    bool isDark, {
    required String tabName,
  }) {
    if (orders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              tabName == 'Pending'
                  ? Icons.hourglass_empty_rounded
                  : Icons.task_alt_rounded,
              size: 58,
              color: primaryBlue.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 12),
            Text(
              'No $tabName Orders',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              tabName == 'Pending'
                  ? 'Tap the + Add Order button below to submit an order.'
                  : 'Orders marked as completed will appear here.',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white38 : Colors.black45,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 90),
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
              color:
                  isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.06),
            ),
          ),
          color: isDark ? const Color(0xFF0F243E) : Colors.white,
          child: InkWell(
            onTap: () => _showOrderDetailsDialog(order, isDark),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Row 1: Shop Name & Order Type Badge
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          order.shopName,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: typeColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: typeColor, width: 1),
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
                  if (order.customerName.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      order.customerName,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),

                  // Row 2: Location & Phone
                  Row(
                    children: [
                      if (order.place.isNotEmpty) ...[
                        Icon(Icons.place_rounded,
                            size: 14,
                            color: isDark ? Colors.white54 : Colors.black45),
                        const SizedBox(width: 3),
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
                        const SizedBox(width: 3),
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
                  const SizedBox(height: 10),
                  const Divider(height: 1),
                  const SizedBox(height: 10),

                  // Row 3: Items count, Total Amount & Status action
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${order.items.length} Item${order.items.length != 1 ? "s" : ""}  (${order.totalQty} pcs)',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                          ),
                          if (order.orderType != 'Spot Delivery' &&
                              order.preferredBranch.isNotEmpty &&
                              order.preferredBranch != 'N/A')
                            Text(
                              'Branch: ${order.preferredBranch}',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? Colors.white38 : Colors.black45,
                              ),
                            ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '₹${order.totalAmount.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: primaryGreen,
                            ),
                          ),
                          Text(
                            _formatDate(order.orderDate).split(',').first,
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? Colors.white38 : Colors.black45,
                            ),
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
