import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../expo_service.dart';

class AccountsOrderDetailPage extends StatefulWidget {
  final ExpoOrder order;
  final ValueChanged<ExpoOrder>? onEntryDoneChanged;

  const AccountsOrderDetailPage({
    super.key,
    required this.order,
    this.onEntryDoneChanged,
  });

  @override
  State<AccountsOrderDetailPage> createState() =>
      _AccountsOrderDetailPageState();
}

class _AccountsOrderDetailPageState extends State<AccountsOrderDetailPage> {
  final ExpoService _expoService = ExpoService.instance;
  late ExpoOrder _order;
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _order = widget.order;
  }

  Future<void> _toggleEntryDone() async {
    if (_isUpdating) return;

    final targetValue = !_order.entryDone;
    if (!targetValue) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Undo Entry Done?'),
          content: const Text(
            'Do you want to mark this order as not done?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Yes, Undo'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    setState(() => _isUpdating = true);
    try {
      await _expoService.updateOrderEntryDone(_order.id, targetValue);
      if (!mounted) return;
      setState(() {
        _order = _order.copyWith(entryDone: targetValue);
        _isUpdating = false;
      });
      widget.onEntryDoneChanged?.call(_order);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            targetValue
                ? 'Order marked as Entry Done'
                : 'Order marked as Pending Entry',
          ),
          backgroundColor: targetValue ? Colors.green : Colors.orange,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUpdating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _openPhotoViewer(String url, String title) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Center(
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) => const Center(
                    child: Text(
                      'Failed to load image',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              left: 16,
              right: 48,
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '-';
    return DateFormat('dd MMM yyyy, hh:mm a').format(dt.toLocal());
  }

  String _formatDateOnly(DateTime? dt) {
    if (dt == null) return '-';
    return DateFormat('dd MMM yyyy').format(dt.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final billLabel = _order.billNumber != null
        ? 'Bill #${_order.billNumber}'
        : 'Order ${_order.id.substring(0, _order.id.length > 8 ? 8 : _order.id.length)}';

    return Scaffold(
      appBar: AppBar(
        title: Text(billLabel),
        actions: [
          if (_order.entryDone)
            Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 16),
                  SizedBox(width: 4),
                  Text(
                    'Entry Done',
                    style: TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          _buildSectionCard(
            isDark: isDark,
            title: 'Order Overview',
            children: [
              _buildRow('Exhibition', _order.exhibitionName),
              _buildRow('Order Type', _order.orderType),
              _buildRow('Order Date', _formatDate(_order.orderDate)),
              _buildRow('Status', _order.status),
              if (_order.stallPickupStatus != null &&
                  _order.stallPickupStatus!.isNotEmpty)
                _buildRow('Stall Pickup Status', _order.stallPickupStatus!),
              _buildRow('Branch Delivery', _order.branchDeliveryStatus),
              if (_order.deliveryDate != null)
                _buildRow('Delivery Date', _formatDateOnly(_order.deliveryDate)),
              if (_order.stallPickupDate != null)
                _buildRow(
                    'Stall Pickup Date', _formatDateOnly(_order.stallPickupDate)),
            ],
          ),
          const SizedBox(height: 12),
          _buildSectionCard(
            isDark: isDark,
            title: 'Customer & Branch Details',
            children: [
              _buildRow('Shop Name', _order.shopName),
              _buildRow('Customer Name', _order.customerName),
              _buildRow('Phone', _order.phone),
              _buildRow('Place', _order.place),
              _buildRow('District', _order.district),
              _buildRow('State', _order.state),
              _buildRow('Preferred Branch', _order.preferredBranch),
              _buildRow('Preferred Salesman', _order.preferredSalesman),
              _buildRow('Created By',
                  '${_order.createdUserName} (${_order.createdUserBranch})'),
            ],
          ),
          const SizedBox(height: 12),
          _buildSectionCard(
            isDark: isDark,
            title: 'Items (${_order.items.length})',
            children: [
              if (_order.items.isEmpty)
                const Text('No items listed')
              else
                ..._order.items.map((item) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.itemName,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  'Qty: ${item.qty} × ₹${item.rate.toStringAsFixed(2)} (GST ${item.gst.toStringAsFixed(0)}%)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? Colors.grey[400]
                                        : Colors.grey[700],
                                  ),
                                ),
                                if (item.photoUrl != null &&
                                    item.photoUrl!.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: GestureDetector(
                                      onTap: () => _openPhotoViewer(
                                        item.photoUrl!,
                                        item.itemName,
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.network(
                                          item.photoUrl!,
                                          height: 70,
                                          width: 70,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              const SizedBox.shrink(),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Text(
                            '₹${item.total.toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    )),
            ],
          ),
          const SizedBox(height: 12),
          _buildSectionCard(
            isDark: isDark,
            title: 'Payment Summary',
            children: [
              _buildRow('Total Qty', '${_order.totalQty}'),
              _buildRow('Subtotal', '₹${_order.subtotal.toStringAsFixed(2)}'),
              _buildRow('Total GST', '₹${_order.totalGst.toStringAsFixed(2)}'),
              if (_order.roundOff != 0)
                _buildRow(
                    'Round Off', '₹${_order.roundOff.toStringAsFixed(2)}'),
              _buildRow(
                'Total Amount',
                '₹${_order.totalAmount.toStringAsFixed(2)}',
                isBold: true,
              ),
              _buildRow(
                  'Advance Paid', '₹${_order.advanceAmount.toStringAsFixed(2)}'),
              _buildRow(
                  'Balance Due', '₹${_order.balanceAmount.toStringAsFixed(2)}'),
              const Divider(height: 16),
              _buildRow('Payment Mode', _order.paymentMode),
              if (_order.cashAmount > 0)
                _buildRow(
                    'Cash Amount', '₹${_order.cashAmount.toStringAsFixed(2)}'),
              if (_order.onlineAmount > 0)
                _buildRow('Online Amount',
                    '₹${_order.onlineAmount.toStringAsFixed(2)}'),
              if (_order.pickupAmount > 0) ...[
                const Divider(height: 16),
                _buildRow('Pickup Payment Mode',
                    _order.pickupPaymentMode ?? '-'),
                _buildRow('Pickup Amount',
                    '₹${_order.pickupAmount.toStringAsFixed(2)}'),
                if (_order.pickupCashAmount > 0)
                  _buildRow('Pickup Cash',
                      '₹${_order.pickupCashAmount.toStringAsFixed(2)}'),
                if (_order.pickupOnlineAmount > 0)
                  _buildRow('Pickup Online',
                      '₹${_order.pickupOnlineAmount.toStringAsFixed(2)}'),
                if (_order.pickedUpAt != null)
                  _buildRow('Picked Up At', _formatDate(_order.pickedUpAt)),
              ],
            ],
          ),
          if ((_order.paymentProofUrl != null &&
                  _order.paymentProofUrl!.isNotEmpty) ||
              (_order.pickupPaymentProofUrl != null &&
                  _order.pickupPaymentProofUrl!.isNotEmpty)) ...[
            const SizedBox(height: 12),
            _buildSectionCard(
              isDark: isDark,
              title: 'Payment Photos',
              children: [
                if (_order.paymentProofUrl != null &&
                    _order.paymentProofUrl!.isNotEmpty)
                  _buildPhotoTile(
                    title: 'Payment Receipt',
                    url: _order.paymentProofUrl!,
                  ),
                if (_order.pickupPaymentProofUrl != null &&
                    _order.pickupPaymentProofUrl!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildPhotoTile(
                    title: 'Pickup Payment Receipt',
                    url: _order.pickupPaymentProofUrl!,
                  ),
                ],
              ],
            ),
          ],
          if (_order.notes.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildSectionCard(
              isDark: isDark,
              title: 'Notes',
              children: [
                Text(_order.notes),
              ],
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _isUpdating ? null : _toggleEntryDone,
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _order.entryDone ? Colors.green : const Color(0xFF1E88E5),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: _isUpdating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(_order.entryDone
                      ? Icons.check_circle
                      : Icons.done_all_rounded),
              label: Text(
                _order.entryDone ? 'Entry Done ✓' : 'Entry Done',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoTile({required String title, required String url}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: () => _openPhotoViewer(url, title),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                Image.network(
                  url,
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Container(
                      height: 200,
                      color: Colors.black12,
                      child: const Center(child: CircularProgressIndicator()),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) => Container(
                    height: 120,
                    color: Colors.black12,
                    child: const Center(child: Text('Could not load image')),
                  ),
                ),
                Container(
                  margin: const EdgeInsets.all(8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.zoom_in, color: Colors.white, size: 16),
                      SizedBox(width: 4),
                      Text(
                        'Tap to zoom',
                        style: TextStyle(color: Colors.white, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionCard({
    required bool isDark,
    required String title,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 135,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '-' : value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
