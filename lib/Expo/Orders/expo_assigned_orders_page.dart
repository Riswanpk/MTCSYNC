import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../Navigation/user_cache_service.dart';
import '../Accounts/expo_pdf_service.dart';
import '../Manager/expo_manager_assign_page.dart';
import '../expo_service.dart';

const Color primaryBlue = Color(0xFF005BAC);
const Color primaryGreen = Color(0xFF8CC63F);

/// Displays branch-assigned exhibition orders after Admin has clicked "End Exhibition".
/// Supports Sales, Asst Manager, Manager, and Admin roles with Pending/Delivered tracking.
class ExpoAssignedOrdersPage extends StatefulWidget {
  const ExpoAssignedOrdersPage({super.key});

  @override
  State<ExpoAssignedOrdersPage> createState() => _ExpoAssignedOrdersPageState();
}

class _ExpoAssignedOrdersPageState extends State<ExpoAssignedOrdersPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  String _role = 'sales';
  String _userBranch = '';
  String _username = '';
  bool _isLoadingUser = true;

  String? _selectedExhibitionId; // null = All Ended Expos
  String _selectedSalesmanFilter = 'All'; // Manager: 'All' | 'Me' | salesman name
  String? _selectedBranchFilter; // Admin: null = All Branches
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _updatingOrderIds = <String>{};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initUser();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initUser() async {
    try {
      final cache = UserCacheService.instance;
      await cache.ensureLoaded();
      if (mounted) {
        setState(() {
          _role = (cache.role ?? 'sales').trim().toLowerCase();
          _userBranch = (cache.branch ?? '').trim();
          _username = (cache.username ?? '').trim();
          _isLoadingUser = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingUser = false);
    }
  }

  bool get _isAdmin => _role == 'admin';
  bool get _isManager => _role == 'manager';

  bool _hasAssignedSalesman(ExpoOrder o) {
    final s = o.preferredSalesman.trim();
    return s.isNotEmpty && s.toUpperCase() != 'N/A';
  }

  bool _matchesSearch(ExpoOrder o) {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return true;
    final billStr = o.billNumber != null ? '#${o.billNumber}' : '';
    return o.shopName.toLowerCase().contains(q) ||
        o.customerName.toLowerCase().contains(q) ||
        o.phone.toLowerCase().contains(q) ||
        o.place.toLowerCase().contains(q) ||
        o.district.toLowerCase().contains(q) ||
        o.preferredSalesman.toLowerCase().contains(q) ||
        o.preferredBranch.toLowerCase().contains(q) ||
        billStr.toLowerCase().contains(q);
  }

  Future<void> _callCustomer(String phone) async {
    final cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (cleaned.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No valid phone number available.')),
        );
      }
      return;
    }
    final uri = Uri(scheme: 'tel', path: cleaned);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(uri);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to launch dialer: $e')),
        );
      }
    }
  }

  Future<void> _confirmAndToggleDelivery(
    ExpoOrder order, {
    required bool markDelivered,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          markDelivered ? 'Mark as Delivered?' : 'Move Back to Pending?',
        ),
        content: Text(
          markDelivered
              ? 'Confirm that order for "${order.shopName.isNotEmpty ? order.shopName : order.customerName}" has been delivered.'
              : 'Move order for "${order.shopName.isNotEmpty ? order.shopName : order.customerName}" back to Pending?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: markDelivered ? primaryGreen : Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: Text(markDelivered ? 'Mark Delivered' : 'Mark Pending'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _updatingOrderIds.add(order.id));
    try {
      await ExpoService.instance.updateBranchDeliveryStatus(
        order: order,
        delivered: markDelivered,
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                markDelivered
                    ? 'Order marked as Delivered'
                    : 'Order moved back to Pending',
              ),
              backgroundColor: markDelivered ? primaryGreen : Colors.orange,
            ),
          );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update status: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _updatingOrderIds.remove(order.id));
      }
    }
  }

  void _showOrderDetailSheet(ExpoOrder order, bool isDark) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F243E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            order.shopName.isNotEmpty
                                ? order.shopName
                                : order.customerName,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          if (order.customerName.isNotEmpty &&
                              order.shopName.isNotEmpty)
                            Text(
                              order.customerName,
                              style: TextStyle(
                                fontSize: 13,
                                color:
                                    isDark ? Colors.white70 : Colors.black54,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (order.billNumber != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: primaryBlue.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Bill #${order.billNumber}',
                          style: const TextStyle(
                            color: primaryBlue,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _detailRow('Exhibition', order.exhibitionName, isDark),
                      _detailRow(
                        'Order Date',
                        DateFormat('dd MMM yyyy, hh:mm a')
                            .format(order.orderDate.toLocal()),
                        isDark,
                      ),
                      _detailRow('Order Type', order.orderType, isDark),
                      if (order.isConvertedToBooking)
                        _detailRow(
                          'Origin',
                          'Converted from Stall Delivery',
                          isDark,
                        ),
                      if (order.deliveryDate != null)
                        _detailRow(
                          'Delivery Date',
                          DateFormat('dd MMM yyyy')
                              .format(order.deliveryDate!.toLocal()),
                          isDark,
                        ),
                      _detailRow(
                          'Branch', order.preferredBranch, isDark),
                      _detailRow(
                          'Salesman', order.preferredSalesman, isDark),
                      if (order.phone.isNotEmpty)
                        _detailRow('Phone', order.phone, isDark),
                      if (order.place.isNotEmpty ||
                          order.district.isNotEmpty ||
                          order.state.isNotEmpty)
                        _detailRow(
                          'Address',
                          [order.place, order.district, order.state]
                              .where((s) => s.trim().isNotEmpty)
                              .join(', '),
                          isDark,
                        ),
                      _detailRow(
                        'Booked By',
                        '${order.createdUserName} (${order.createdUserBranch})',
                        isDark,
                      ),
                      _detailRow(
                        'Payment Mode',
                        ExpoOrder.normalizePaymentMode(order.paymentMode),
                        isDark,
                      ),
                      if (order.notes.isNotEmpty)
                        _detailRow('Notes', order.notes, isDark),
                      if (order.paymentProofUrl != null &&
                          order.paymentProofUrl!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () => _showImagePreview(
                            order.paymentProofUrl!,
                            'Payment Receipt',
                          ),
                          icon: const Icon(Icons.receipt_long_rounded,
                              size: 18),
                          label: const Text('View Payment Receipt'),
                        ),
                      ],
                      if (order.pickupPaymentProofUrl != null &&
                          order.pickupPaymentProofUrl!.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        OutlinedButton.icon(
                          onPressed: () => _showImagePreview(
                            order.pickupPaymentProofUrl!,
                            'Pickup Receipt',
                          ),
                          icon: const Icon(Icons.receipt_long_rounded,
                              size: 18),
                          label: const Text('View Pickup Receipt'),
                        ),
                      ],
                      const SizedBox(height: 14),
                      const Text(
                        'Items Breakdown',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold),
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
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      it.itemName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13.5,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '₹${it.total.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: primaryGreen,
                                    ),
                                  ),
                                ],
                              ),
                              if (it.mtcCode.isNotEmpty)
                                Text(
                                  'MTC: ${it.mtcCode}',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: isDark
                                        ? Colors.white60
                                        : Colors.black54,
                                  ),
                                ),
                              if (it.description.isNotEmpty)
                                Text(
                                  it.description,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: isDark
                                        ? Colors.white60
                                        : Colors.black54,
                                  ),
                                ),
                              const SizedBox(height: 4),
                              Text(
                                'Qty: ${it.qty} × ₹${it.rate.toStringAsFixed(2)} (${it.gst.toStringAsFixed(0)}% GST ${it.gstType == 1 ? 'Incl.' : 'Excl.'})',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: isDark
                                      ? Colors.white70
                                      : Colors.black87,
                                ),
                              ),
                              if (it.photoUrl != null &&
                                  it.photoUrl!.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                InkWell(
                                  onTap: () => _showImagePreview(
                                      it.photoUrl!, it.itemName),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.photo_camera_rounded,
                                          size: 14, color: primaryBlue),
                                      SizedBox(width: 4),
                                      Text(
                                        'View Item Photo',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.bold,
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
                      const Divider(height: 20),
                      _amountRow('Grand Total', order.totalAmount, isDark),
                      _amountRow(
                        'Advance Paid',
                        order.advanceAmount,
                        isDark,
                        valueColor: primaryGreen,
                      ),
                      _amountRow(
                        'Balance Due',
                        order.balanceAmount,
                        isDark,
                        valueColor: order.balanceAmount > 0
                            ? const Color(0xFFE65100)
                            : primaryGreen,
                        bold: true,
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  children: [
                    if (order.phone.isNotEmpty) ...[
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _callCustomer(order.phone),
                          icon: const Icon(Icons.call_rounded, size: 17),
                          label: const Text('Call'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: primaryBlue,
                            side: const BorderSide(color: primaryBlue),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            ExpoPdfService.instance.exportOrderPdf(order),
                        icon: const Icon(Icons.picture_as_pdf_rounded,
                            size: 17),
                        label: const Text('PDF'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.deepPurple,
                          side: const BorderSide(color: Colors.deepPurple),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _confirmAndToggleDelivery(
                            order,
                            markDelivered: !order.isBranchDelivered,
                          );
                        },
                        icon: Icon(
                          order.isBranchDelivered
                              ? Icons.undo_rounded
                              : Icons.check_circle_rounded,
                          size: 17,
                        ),
                        label: Text(
                          order.isBranchDelivered
                              ? 'Mark Pending'
                              : 'Mark Delivered',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: order.isBranchDelivered
                              ? Colors.orange
                              : primaryGreen,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showImagePreview(String url, String title) {
    showDialog<void>(
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
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ],
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: InteractiveViewer(
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const SizedBox(
                    height: 180,
                    child: Center(child: Text('Failed to load image')),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              '$label:',
              style: TextStyle(
                fontSize: 12.5,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _amountRow(
    String label,
    double amount,
    bool isDark, {
    Color? valueColor,
    bool bold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.w500,
              fontSize: bold ? 14 : 13,
            ),
          ),
          Text(
            '₹${amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: bold ? 15 : 13.5,
              color: valueColor ?? (isDark ? Colors.white : Colors.black87),
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

    return StreamBuilder<List<Exhibition>>(
      stream: ExpoService.instance.streamExhibitions(),
      builder: (context, exSnapshot) {
        if (exSnapshot.connectionState == ConnectionState.waiting &&
            !exSnapshot.hasData) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('EXPO Orders'),
              backgroundColor: primaryBlue,
              foregroundColor: Colors.white,
            ),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final endedExhibitions =
            (exSnapshot.data ?? []).where((e) => e.isEnded).toList();
        final endedIds = endedExhibitions.map((e) => e.id).toSet();

        if (_selectedExhibitionId != null &&
            !endedIds.contains(_selectedExhibitionId)) {
          _selectedExhibitionId = null;
        }

        return StreamBuilder<List<ExpoOrder>>(
          stream: ExpoService.instance.streamAllOrders(),
          builder: (context, orderSnap) {
            final allOrders = orderSnap.data ?? [];

            final normalizedUserBranch = _userBranch.trim().toUpperCase();
            final normalizedUsername = _username.trim().toLowerCase();

            // Unassigned count for manager's quick action badge
            final int unassignedBranchCount = _isManager
                ? allOrders.where((o) {
                    if (!endedIds.contains(o.exhibitionId)) return false;
                    if (o.orderType == 'Spot Delivery') return false;
                    if (o.preferredBranch.trim().toUpperCase() !=
                        normalizedUserBranch) {
                      return false;
                    }
                    return !_hasAssignedSalesman(o);
                  }).length
                : 0;

            // Role-scoped assigned orders from ended exhibitions
            final roleOrders = allOrders.where((o) {
              if (!endedIds.contains(o.exhibitionId)) return false;
              if (o.orderType == 'Spot Delivery') return false;
              if (!_hasAssignedSalesman(o)) return false;

              if (_isAdmin) {
                return true;
              }
              if (o.preferredBranch.trim().toUpperCase() !=
                  normalizedUserBranch) {
                return false;
              }
              if (_isManager) {
                return true;
              }
              // Sales / Asst Manager: orders assigned to current user
              return o.preferredSalesman.trim().toLowerCase() ==
                  normalizedUsername;
            }).toList();

            // Collect branch options for Admin & salesmen options for Manager
            final distinctBranches = roleOrders
                .map((o) => o.preferredBranch.trim())
                .where((b) => b.isNotEmpty && b != 'N/A')
                .toSet()
                .toList()
              ..sort();

            if (_selectedBranchFilter != null &&
                !distinctBranches.contains(_selectedBranchFilter)) {
              _selectedBranchFilter = null;
            }

            final distinctBranchSalesmen = _isManager
                ? (roleOrders
                    .map((o) => o.preferredSalesman.trim())
                    .where((s) =>
                        s.isNotEmpty &&
                        s.toLowerCase() != normalizedUsername)
                    .toSet()
                    .toList()
                  ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())))
                : <String>[];

            if (_isManager &&
                _selectedSalesmanFilter != 'All' &&
                _selectedSalesmanFilter != 'Me' &&
                !distinctBranchSalesmen.contains(_selectedSalesmanFilter)) {
              _selectedSalesmanFilter = 'All';
            }

            // Apply UI filters
            final filtered = roleOrders.where((o) {
              if (_selectedExhibitionId != null &&
                  o.exhibitionId != _selectedExhibitionId) {
                return false;
              }
              if (_isAdmin &&
                  _selectedBranchFilter != null &&
                  o.preferredBranch.trim() != _selectedBranchFilter) {
                return false;
              }
              if (_isManager) {
                if (_selectedSalesmanFilter == 'Me' &&
                    o.preferredSalesman.trim().toLowerCase() !=
                        normalizedUsername) {
                  return false;
                } else if (_selectedSalesmanFilter != 'All' &&
                    _selectedSalesmanFilter != 'Me' &&
                    o.preferredSalesman.trim() != _selectedSalesmanFilter) {
                  return false;
                }
              }
              return _matchesSearch(o);
            }).toList();

            final pendingOrders =
                filtered.where((o) => !o.isBranchDelivered).toList();
            final deliveredOrders =
                filtered.where((o) => o.isBranchDelivered).toList();

            final double pendingBalanceTotal = pendingOrders.fold(
              0.0,
              (sum, o) => sum + o.balanceAmount,
            );

            return Scaffold(
              backgroundColor:
                  isDark ? const Color(0xFF0A1628) : const Color(0xFFF4F7FB),
              appBar: AppBar(
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'EXPO Orders',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    Text(
                      _isAdmin
                          ? 'All Branches'
                          : (_isManager
                              ? 'Branch: $_userBranch'
                              : '$_username • $_userBranch'),
                      style:
                          const TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                  ],
                ),
                backgroundColor: primaryBlue,
                foregroundColor: Colors.white,
                elevation: 0,
                actions: [
                  if (_isManager)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: [
                          IconButton(
                            tooltip: 'Assign Unassigned Orders',
                            icon: const Icon(Icons.person_add_alt_1_rounded),
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const ExpoManagerAssignPage(),
                                ),
                              );
                            },
                          ),
                          if (unassignedBranchCount > 0)
                            Positioned(
                              right: 6,
                              top: 6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE65100),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  unassignedBranchCount > 99
                                      ? '99+'
                                      : '$unassignedBranchCount',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
                bottom: TabBar(
                  controller: _tabController,
                  indicatorColor: primaryGreen,
                  indicatorWeight: 3,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white70,
                  tabs: [
                    Tab(text: 'Pending (${pendingOrders.length})'),
                    Tab(text: 'Delivered (${deliveredOrders.length})'),
                  ],
                ),
              ),
              body: endedExhibitions.isEmpty
                  ? _buildNoEndedExposState(isDark)
                  : (orderSnap.connectionState == ConnectionState.waiting &&
                          !orderSnap.hasData)
                      ? const Center(child: CircularProgressIndicator())
                      : Column(
                          children: [
                            _buildFiltersAndSummary(
                              endedExhibitions: endedExhibitions,
                              distinctBranches: distinctBranches,
                              distinctBranchSalesmen: distinctBranchSalesmen,
                              pendingCount: pendingOrders.length,
                              deliveredCount: deliveredOrders.length,
                              pendingBalance: pendingBalanceTotal,
                              isDark: isDark,
                            ),
                            Expanded(
                              child: TabBarView(
                                controller: _tabController,
                                children: [
                                  _buildOrdersList(
                                    orders: pendingOrders,
                                    isDark: isDark,
                                    isDeliveredTab: false,
                                  ),
                                  _buildOrdersList(
                                    orders: deliveredOrders,
                                    isDark: isDark,
                                    isDeliveredTab: true,
                                  ),
                                ],
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

  Widget _buildNoEndedExposState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.local_shipping_outlined,
              size: 64,
              color: primaryBlue.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 16),
            Text(
              'No Exhibition Orders Available Yet',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Assigned EXPO orders will appear here after Admin clicks "End Exhibition".',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.4,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFiltersAndSummary({
    required List<Exhibition> endedExhibitions,
    required List<String> distinctBranches,
    required List<String> distinctBranchSalesmen,
    required int pendingCount,
    required int deliveredCount,
    required double pendingBalance,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F243E) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color:
                isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.06),
          ),
        ),
      ),
      child: Column(
        children: [
          // Summary KPI strip
          Row(
            children: [
              _summaryChip(
                label: 'Pending',
                value: '$pendingCount',
                color: const Color(0xFFE65100),
              ),
              const SizedBox(width: 8),
              _summaryChip(
                label: 'Delivered',
                value: '$deliveredCount',
                color: primaryGreen,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _summaryChip(
                  label: 'Bal Due',
                  value: '₹${pendingBalance.toStringAsFixed(0)}',
                  color: primaryBlue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Exhibition filter + Admin branch dropdown
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      value: _selectedExhibitionId,
                      isExpanded: true,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      dropdownColor:
                          isDark ? const Color(0xFF132238) : Colors.white,
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('All Ended Exhibitions'),
                        ),
                        ...endedExhibitions.map((ex) {
                          return DropdownMenuItem<String?>(
                            value: ex.id,
                            child: Text(
                              ex.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }),
                      ],
                      onChanged: (v) =>
                          setState(() => _selectedExhibitionId = v),
                    ),
                  ),
                ),
              ),
              if (_isAdmin && distinctBranches.isNotEmpty) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.05)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String?>(
                        value: _selectedBranchFilter,
                        isExpanded: true,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        dropdownColor:
                            isDark ? const Color(0xFF132238) : Colors.white,
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('All Branches'),
                          ),
                          ...distinctBranches.map((b) {
                            return DropdownMenuItem<String?>(
                              value: b,
                              child: Text(b),
                            );
                          }),
                        ],
                        onChanged: (v) =>
                            setState(() => _selectedBranchFilter = v),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),

          // Manager salesman filter chips
          if (_isManager) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 32,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _managerFilterChip('All Branch', 'All', isDark),
                  _managerFilterChip('Assigned to Me', 'Me', isDark),
                  ...distinctBranchSalesmen.map(
                    (s) => _managerFilterChip(s, s, isDark),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 8),
          // Search Bar
          TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _searchQuery = v),
            decoration: InputDecoration(
              hintText: 'Search shop, customer, phone, place or bill...',
              hintStyle: const TextStyle(fontSize: 13),
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              filled: true,
              fillColor: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : const Color(0xFFF1F5F9),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _managerFilterChip(String label, String value, bool isDark) {
    final selected = _selectedSalesmanFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: selected
                ? Colors.white
                : (isDark ? Colors.white70 : Colors.black87),
          ),
        ),
        selected: selected,
        selectedColor: primaryBlue,
        backgroundColor: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : const Color(0xFFF1F5F9),
        onSelected: (_) => setState(() => _selectedSalesmanFilter = value),
      ),
    );
  }

  Widget _summaryChip({
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrdersList({
    required List<ExpoOrder> orders,
    required bool isDark,
    required bool isDeliveredTab,
  }) {
    if (orders.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isDeliveredTab
                    ? Icons.task_alt_rounded
                    : Icons.inventory_2_outlined,
                size: 58,
                color: primaryBlue.withValues(alpha: 0.35),
              ),
              const SizedBox(height: 12),
              Text(
                isDeliveredTab ? 'No Delivered Orders' : 'No Pending Orders',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                isDeliveredTab
                    ? 'Orders marked as delivered will appear here.'
                    : 'Assigned exhibition orders awaiting delivery will appear here.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white54 : Colors.black54,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 30),
      itemCount: orders.length,
      itemBuilder: (context, index) {
        final order = orders[index];
        return _buildOrderCard(order, isDark, isDeliveredTab: isDeliveredTab);
      },
    );
  }

  Widget _buildOrderCard(
    ExpoOrder order,
    bool isDark, {
    required bool isDeliveredTab,
  }) {
    final isUpdating = _updatingOrderIds.contains(order.id);
    final locationStr = [order.place, order.district, order.state]
        .where((s) => s.trim().isNotEmpty)
        .join(', ');
    final itemPreview = order.items
        .take(2)
        .map((it) => '${it.itemName} (×${it.qty})')
        .join(', ');
    final extraItemCount = order.items.length > 2 ? order.items.length - 2 : 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1.5,
      color: isDark ? const Color(0xFF0F243E) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _showOrderDetailSheet(order, isDark),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row: Bill #, Exhibition Name, Order Type / Converted badge
              Row(
                children: [
                  if (order.billNumber != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: primaryBlue.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '#${order.billNumber}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: primaryBlue,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      order.exhibitionName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                  ),
                  if (order.isConvertedToBooking)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: Colors.amber.shade700, width: 0.8),
                      ),
                      child: Text(
                        'Converted from Stall',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber.shade800,
                        ),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: primaryBlue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        order.orderType,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: primaryBlue,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),

              // Shop & Customer Name
              Text(
                order.shopName.isNotEmpty
                    ? order.shopName
                    : order.customerName,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              if (order.customerName.isNotEmpty && order.shopName.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    order.customerName,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                ),
              const SizedBox(height: 8),

              // Phone, Location, Delivery Date
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  if (order.phone.isNotEmpty)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.phone_rounded,
                            size: 13,
                            color: isDark ? Colors.white54 : Colors.black45),
                        const SizedBox(width: 4),
                        Text(
                          order.phone,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  if (locationStr.isNotEmpty)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.place_rounded,
                            size: 13,
                            color: isDark ? Colors.white54 : Colors.black45),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            locationStr,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                        ),
                      ],
                    ),
                  if (order.deliveryDate != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.event_rounded,
                            size: 13, color: primaryBlue),
                        const SizedBox(width: 4),
                        Text(
                          'Del: ${DateFormat('dd MMM yyyy').format(order.deliveryDate!.toLocal())}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: primaryBlue,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 8),

              // Assigned Salesman & Branch pill
              Row(
                children: [
                  Icon(Icons.badge_rounded,
                      size: 14,
                      color: isDark ? primaryGreen : Colors.green.shade700),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      '${order.preferredSalesman} (${order.preferredBranch})',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark ? primaryGreen : Colors.green.shade800,
                      ),
                    ),
                  ),
                ],
              ),

              if (itemPreview.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  extraItemCount > 0
                      ? 'Items: $itemPreview +$extraItemCount more'
                      : 'Items: $itemPreview',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
              ],

              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 10),

              // Financial summary
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total: ₹${order.totalAmount.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      Text(
                        'Advance Paid: ₹${order.advanceAmount.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: primaryGreen,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Balance Due',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white54 : Colors.black54,
                        ),
                      ),
                      Text(
                        '₹${order.balanceAmount.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: order.balanceAmount > 0
                              ? const Color(0xFFE65100)
                              : primaryGreen,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Action row: Call | PDF | Mark Delivered / Mark Pending
              Row(
                children: [
                  if (order.phone.isNotEmpty) ...[
                    OutlinedButton.icon(
                      onPressed: () => _callCustomer(order.phone),
                      icon: const Icon(Icons.call_rounded, size: 16),
                      label: const Text('Call', style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: primaryBlue,
                        side: const BorderSide(color: primaryBlue),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(9),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  OutlinedButton.icon(
                    onPressed: () =>
                        ExpoPdfService.instance.exportOrderPdf(order),
                    icon: const Icon(Icons.picture_as_pdf_rounded, size: 16),
                    label: const Text('PDF', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.deepPurple,
                      side: const BorderSide(color: Colors.deepPurple),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: isUpdating
                        ? null
                        : () => _confirmAndToggleDelivery(
                              order,
                              markDelivered: !isDeliveredTab,
                            ),
                    icon: isUpdating
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Icon(
                            isDeliveredTab
                                ? Icons.undo_rounded
                                : Icons.check_circle_rounded,
                            size: 16,
                          ),
                    label: Text(
                      isDeliveredTab ? 'Mark Pending' : 'Mark Delivered',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          isDeliveredTab ? Colors.orange : primaryGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
