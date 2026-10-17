import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../expo_service.dart';
import 'expo_pdf_service.dart';

const Color primaryBlue = Color(0xFF005BAC);
const Color primaryGreen = Color(0xFF8CC63F);

/// Full detailed review page for an Expo order viewed by an Accounts/Verification user.
/// Displays complete customer details, item breakdown, payment mode,
/// full payment receipt image viewer, and action buttons to Verify or Print/Export PDF.
class ExpoOrderDetailPage extends StatefulWidget {
  final ExpoOrder order;

  const ExpoOrderDetailPage({super.key, required this.order});

  @override
  State<ExpoOrderDetailPage> createState() => _ExpoOrderDetailPageState();
}

class _ExpoOrderDetailPageState extends State<ExpoOrderDetailPage> {
  late ExpoOrder _currentOrder;
  bool _isVerifying = false;
  bool _isExportingPdf = false;

  @override
  void initState() {
    super.initState();
    _currentOrder = widget.order;
  }

  String _formatDate(DateTime dt) {
    return DateFormat('dd MMM yyyy, hh:mm a').format(dt);
  }

  Color _getOrderTypeColor(String type) {
    switch (type) {
      case 'Spot Delivery':
        return const Color(0xFF10B981);
      case 'Booking':
        return primaryBlue;
      case 'Stall Delivery':
        return const Color(0xFFF59E0B);
      default:
        return primaryBlue;
    }
  }

  Future<void> _verifyOrder() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Verify Order?'),
        content: Text(
          'Are you sure you want to verify order for "${_currentOrder.shopName}" (${_currentOrder.paymentMode})? This will move the order to Completed.',
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

    setState(() => _isVerifying = true);
    try {
      await ExpoService.instance.updateOrderStatus(_currentOrder.id, 'Completed');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Order "${_currentOrder.shopName}" verified successfully!'),
            backgroundColor: primaryGreen,
          ),
        );
        Navigator.of(context).pop(true);
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
        setState(() => _isVerifying = false);
      }
    }
  }

  Future<void> _markStallPickup() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Stall Pickup'),
        content: Text(
          'Confirm that customer "${_currentOrder.shopName}" has picked up their items at the stall? This completes the order as a spot delivery.',
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
            child: const Text('Confirm Pickup'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await ExpoService.instance.markStallDeliveryPickedUp(_currentOrder.id);
      setState(() {
        _currentOrder = _currentOrder.copyWith(
          status: 'Completed',
          stallPickupStatus: 'Picked Up',
          completedAt: DateTime.now(),
        );
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Order marked as picked up at stall (Spot Delivery)!'),
            backgroundColor: primaryGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _convertToBooking() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Convert to Normal Booking'),
        content: Text(
          'Convert order for "${_currentOrder.shopName}" to a Normal Booking? Preferred branch (${_currentOrder.preferredBranch}) will fulfill delivery.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryBlue,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Convert to Booking'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await ExpoService.instance.convertStallDeliveryToBooking(_currentOrder.id);
      setState(() {
        _currentOrder = _currentOrder.copyWith(
          orderType: 'Booking',
          isConvertedToBooking: true,
          stallPickupStatus: 'Converted to Booking',
        );
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Order converted to Normal Booking!'),
            backgroundColor: primaryBlue,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _exportPdf() async {
    setState(() => _isExportingPdf = true);
    try {
      await ExpoPdfService.instance.exportOrderPdf(_currentOrder);
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
        setState(() => _isExportingPdf = false);
      }
    }
  }

  void _showImagePreviewDialog(String imageUrl, String title) {
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
              constraints: const BoxConstraints(maxHeight: 500),
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

  Widget _buildDetailRow(String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              '$label:',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
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
    final order = _currentOrder;
    final typeColor = _getOrderTypeColor(order.orderType);
    final isCompleted = order.status == 'Completed';

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A1628) : const Color(0xFFF7F9FC),
      appBar: AppBar(
        title: const Text(
          'Order Verification',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 17,
          ),
        ),
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: _isExportingPdf
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.picture_as_pdf_rounded),
            tooltip: 'Print / Export PDF',
            onPressed: _isExportingPdf ? null : _exportPdf,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Order Top Card (Shop & Status)
            Card(
              elevation: 1.5,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.06),
                ),
              ),
              color: isDark ? const Color(0xFF0F243E) : Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            order.shopName,
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: (isCompleted ? primaryGreen : const Color(0xFFF59E0B))
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            order.status,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isCompleted ? primaryGreen : const Color(0xFFF59E0B),
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          _formatDate(order.orderDate),
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white54 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Order & Customer Details Card
            Card(
              elevation: 1.5,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.06),
                ),
              ),
              color: isDark ? const Color(0xFF0F243E) : Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Customer & Booking Info',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    const Divider(height: 1),
                    const SizedBox(height: 10),
                    _buildDetailRow('Exhibition', order.exhibitionName, isDark),
                    if (order.customerName.isNotEmpty)
                      _buildDetailRow('Customer Name', order.customerName, isDark),
                    if (order.phone.isNotEmpty)
                      _buildDetailRow('Phone', order.phone, isDark),
                    if (order.place.isNotEmpty)
                      _buildDetailRow('Place', order.place, isDark),
                    if (order.district.isNotEmpty)
                      _buildDetailRow('District', order.district, isDark),
                    if (order.state.isNotEmpty)
                      _buildDetailRow('State', order.state, isDark),
                    if (order.orderType != 'Spot Delivery') ...[
                      _buildDetailRow('Preferred Branch', order.preferredBranch, isDark),
                      _buildDetailRow('Salesman', order.preferredSalesman, isDark),
                    ],
                    if (order.deliveryDate != null)
                      _buildDetailRow(
                        'Delivery Date',
                        DateFormat('dd MMM yyyy').format(order.deliveryDate!),
                        isDark,
                      ),
                    if (order.stallPickupDate != null)
                      _buildDetailRow(
                        'Pickup Date',
                        DateFormat('dd MMM yyyy').format(order.stallPickupDate!),
                        isDark,
                      ),
                    if (order.stallPickupStatus != null && order.stallPickupStatus!.isNotEmpty)
                      _buildDetailRow('Stall Status', order.stallPickupStatus!, isDark),
                    if (order.isConvertedToBooking)
                      _buildDetailRow('Notice', 'Converted from Stall Delivery to Normal Booking', isDark),
                    _buildDetailRow('Created By',
                        '${order.createdUserName} (${order.createdUserBranch})', isDark),
                    _buildDetailRow('Payment Mode', order.paymentMode, isDark),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Payment Verification Section
            Card(
              elevation: 1.5,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.06),
                ),
              ),
              color: isDark ? const Color(0xFF0F243E) : Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          order.paymentMode == 'Cash'
                              ? Icons.payments_rounded
                              : Icons.account_balance_rounded,
                          color: order.paymentMode == 'Cash' ? primaryGreen : primaryBlue,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Payment Proof (${order.paymentMode})',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Divider(height: 1),
                    const SizedBox(height: 12),

                    // If Cash: No payment image displayed
                    if (order.paymentMode == 'Cash')
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: primaryGreen.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: primaryGreen.withValues(alpha: 0.2)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.check_circle_outline_rounded,
                                color: primaryGreen, size: 20),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Payment by Cash. No receipt image required.',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: primaryGreen,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    // If Bank Transfer or UPI: Show receipt preview
                    else if (order.paymentProofUrl != null &&
                        order.paymentProofUrl!.isNotEmpty)
                      InkWell(
                        onTap: () => _showImagePreviewDialog(
                          order.paymentProofUrl!,
                          'Payment Receipt - ${order.shopName}',
                        ),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: primaryBlue.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: primaryBlue.withValues(alpha: 0.25)),
                          ),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  order.paymentProofUrl!,
                                  width: 64,
                                  height: 64,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(
                                    Icons.receipt_long_rounded,
                                    size: 36,
                                    color: primaryBlue,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'View Payment Receipt',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: primaryBlue,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'Tap to view receipt photo full screen',
                                      style: TextStyle(fontSize: 12, color: Colors.black54),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.open_in_new_rounded,
                                color: primaryBlue,
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.2)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.warning_amber_rounded,
                                color: Colors.redAccent, size: 20),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'No payment proof uploaded for this transfer.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.redAccent,
                                  fontWeight: FontWeight.w600,
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
            const SizedBox(height: 14),

            // Items Breakdown Card
            Card(
              elevation: 1.5,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.06),
                ),
              ),
              color: isDark ? const Color(0xFF0F243E) : Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Items Breakdown',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${order.items.length} items (${order.totalQty} pcs)',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Divider(height: 1),
                    const SizedBox(height: 12),

                    ...order.items.map((it) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.04)
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
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                Text(
                                  '₹${it.total.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: primaryGreen,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                            if (it.mtcCode.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  'MTC: ${it.mtcCode}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark ? Colors.white60 : Colors.black54,
                                  ),
                                ),
                              ),
                            if (it.description.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  it.description,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark ? Colors.white54 : Colors.black45,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Qty: ${it.qty} × ₹${it.rate.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark ? Colors.white70 : Colors.black87,
                                  ),
                                ),
                                Text(
                                  'GST: ${it.gst.toStringAsFixed(0)}%',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark ? Colors.white60 : Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                            if (it.photoUrl != null && it.photoUrl!.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              InkWell(
                                onTap: () => _showImagePreviewDialog(
                                  it.photoUrl!,
                                  'Item: ${it.itemName}',
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.photo_outlined, size: 14, color: primaryBlue),
                                    SizedBox(width: 4),
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

                    const SizedBox(height: 8),
                    // Summary totals box
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: primaryGreen.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Subtotal:', style: TextStyle(fontSize: 13)),
                              Text('₹${order.subtotal.toStringAsFixed(2)}',
                                  style: const TextStyle(fontSize: 13)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Total GST:', style: TextStyle(fontSize: 13)),
                              Text('₹${order.totalGst.toStringAsFixed(2)}',
                                  style: const TextStyle(fontSize: 13)),
                            ],
                          ),
                          const Divider(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Grand Total:',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                '₹${order.totalAmount.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: primaryGreen,
                                ),
                              ),
                            ],
                          ),
                          if (order.orderType != 'Spot Delivery') ...[
                            const Divider(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Advance Paid:',
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                Text(
                                  '₹${order.advanceAmount.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                      fontSize: 13, fontWeight: FontWeight.bold, color: primaryGreen),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Balance Due:',
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                Text(
                                  '₹${order.balanceAmount.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: order.balanceAmount > 0 ? const Color(0xFFE65100) : primaryGreen,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomSheet: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F243E) : Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: SafeArea(
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: primaryBlue, width: 1.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: _isExportingPdf ? null : _exportPdf,
                  icon: _isExportingPdf
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.picture_as_pdf_rounded, color: primaryBlue),
                  label: const Text(
                    'Print / PDF',
                    style: TextStyle(
                      color: primaryBlue,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              if (!isCompleted) ...[
                const SizedBox(width: 14),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 2,
                    ),
                    onPressed: _isVerifying ? null : _verifyOrder,
                    icon: _isVerifying
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_circle_rounded),
                    label: const Text(
                      'Verify Order',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ],
              if (order.orderType == 'Stall Delivery' &&
                  order.stallPickupStatus != 'Picked Up' &&
                  !order.isConvertedToBooking) ...[
                const SizedBox(width: 10),
                IconButton(
                  tooltip: 'Mark Picked Up at Stall',
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6F00).withValues(alpha: 0.15),
                    foregroundColor: const Color(0xFFFF6F00),
                  ),
                  onPressed: _markStallPickup,
                  icon: const Icon(Icons.storefront_rounded),
                ),
                IconButton(
                  tooltip: 'Convert to Normal Booking',
                  style: IconButton.styleFrom(
                    backgroundColor: primaryBlue.withValues(alpha: 0.15),
                    foregroundColor: primaryBlue,
                  ),
                  onPressed: _convertToBooking,
                  icon: const Icon(Icons.transform_rounded),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
