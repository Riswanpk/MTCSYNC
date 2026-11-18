import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../expo_service.dart';

class ExpoCouponsPage extends StatefulWidget {
  const ExpoCouponsPage({super.key});

  @override
  State<ExpoCouponsPage> createState() => _ExpoCouponsPageState();
}

class _ExpoCouponsPageState extends State<ExpoCouponsPage> {
  static const Color _primaryBlue = Color(0xFF005BAC);
  static const Color _primaryGreen = Color(0xFF00897B);

  final ExpoService _expoService = ExpoService.instance;

  String? _selectedExhibitionId;
  String _selectedFilter = 'Eligible';
  bool _isLoading = false;
  bool _isDropdownOpen = false;
  bool _isFilterExpanded = false;
  String? _error;
  List<ExpoOrder> _orders = [];

  static const List<String> _filters = [
    'Eligible',
    'Taken',
    'Pending',
    'All',
  ];

  int _eligibleCoupons(ExpoOrder order) {
    if (order.advanceAmount < 10000) return 0;
    return order.advanceAmount ~/ 10000;
  }

  Future<void> _loadOrders(String exhibitionId) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final orders = await _expoService.fetchOrdersForExhibition(exhibitionId);
      if (!mounted) return;
      setState(() {
        _orders = orders;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleCouponTaken(ExpoOrder order) async {
    final eligible = _eligibleCoupons(order);
    if (eligible <= 0) return;

    final newValue = !order.couponTaken;
    try {
      await _expoService.updateOrderCouponTaken(order.id, newValue);
      if (!mounted) return;
      setState(() {
        final idx = _orders.indexWhere((o) => o.id == order.id);
        if (idx != -1) {
          _orders[idx] = order.copyWith(couponTaken: newValue);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newValue
                ? 'Marked $eligible coupon(s) as Taken'
                : 'Marked coupon as Not Taken',
          ),
          backgroundColor: newValue ? _primaryGreen : Colors.orange,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update coupon status: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  List<ExpoOrder> get _filteredOrders {
    switch (_selectedFilter) {
      case 'Eligible':
        return _orders.where((o) => _eligibleCoupons(o) > 0).toList();
      case 'Taken':
        return _orders
            .where((o) => _eligibleCoupons(o) > 0 && o.couponTaken)
            .toList();
      case 'Pending':
        return _orders
            .where((o) => _eligibleCoupons(o) > 0 && !o.couponTaken)
            .toList();
      default:
        return _orders;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filtered = _filteredOrders;
    final eligibleList = _orders.where((o) => _eligibleCoupons(o) > 0).toList();
    final takenCount = eligibleList.where((o) => o.couponTaken).length;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: _primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Expo Coupons',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: 'Filter',
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.filter_list_rounded),
                if (_selectedFilter != 'All')
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFF4ADE80),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            onPressed: () {
              setState(() => _isFilterExpanded = !_isFilterExpanded);
            },
          ),
          if (_selectedExhibitionId != null)
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () => _loadOrders(_selectedExhibitionId!),
            ),
        ],
      ),
      body: Column(
        children: [
          // Custom animated Exhibition selector
          StreamBuilder<List<Exhibition>>(
            stream: _expoService.streamExhibitions(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
                return const LinearProgressIndicator(color: _primaryGreen);
              }
              final exhibitions = snapshot.data ?? [];
              if (exhibitions.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No exhibitions found.'),
                );
              }

              if (_selectedExhibitionId == null) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted || _selectedExhibitionId != null) return;
                  setState(() {
                    _selectedExhibitionId = exhibitions.first.id;
                  });
                  _loadOrders(exhibitions.first.id);
                });
              }

              final selectedEx = exhibitions.firstWhere(
                (e) => e.id == _selectedExhibitionId,
                orElse: () => exhibitions.first,
              );

              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                child: Column(
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        setState(() => _isDropdownOpen = !_isDropdownOpen);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF1E293B)
                              : _primaryBlue.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _primaryBlue.withValues(alpha: 0.45),
                            width: 1.2,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: _primaryBlue.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.confirmation_number_rounded,
                                color: _primaryBlue,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Selected Exhibition',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: isDark
                                          ? Colors.grey[400]
                                          : _primaryBlue,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    selectedEx.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            AnimatedRotation(
                              turns: _isDropdownOpen ? 0.5 : 0.0,
                              duration: const Duration(milliseconds: 220),
                              child: const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: _primaryBlue,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeInOut,
                      child: _isDropdownOpen
                          ? Container(
                              margin: const EdgeInsets.only(top: 6),
                              constraints: const BoxConstraints(maxHeight: 220),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF1E293B)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: _primaryBlue.withValues(alpha: 0.25),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.08),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Material(
                                type: MaterialType.transparency,
                                child: ListView.separated(
                                  shrinkWrap: true,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 4),
                                  itemCount: exhibitions.length,
                                  separatorBuilder: (_, __) =>
                                      const Divider(height: 1),
                                  itemBuilder: (context, idx) {
                                    final ex = exhibitions[idx];
                                    final isSelected =
                                        ex.id == _selectedExhibitionId;
                                    return ListTile(
                                      dense: true,
                                      title: Text(
                                        ex.name,
                                        style: TextStyle(
                                          fontWeight: isSelected
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                          color: isSelected ? _primaryBlue : null,
                                        ),
                                      ),
                                      trailing: isSelected
                                          ? const Icon(Icons.check_circle,
                                              color: _primaryGreen, size: 18)
                                          : null,
                                      onTap: () {
                                        setState(() {
                                          _isDropdownOpen = false;
                                          _selectedExhibitionId = ex.id;
                                        });
                                        _loadOrders(ex.id);
                                      },
                                    );
                                  },
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              );
            },
          ),

          // Animated Filter Panel
          AnimatedSize(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeInOut,
            child: _isFilterExpanded
                ? Container(
                    width: double.infinity,
                    margin: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF1E293B)
                          : _primaryGreen.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _primaryGreen.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _filters.map((f) {
                        final selected = _selectedFilter == f;
                        return GestureDetector(
                          onTap: () => setState(() => _selectedFilter = f),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: selected
                                  ? _primaryGreen
                                  : (isDark
                                      ? Colors.grey[850]
                                      : Colors.white),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: selected
                                    ? _primaryGreen
                                    : _primaryBlue.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Text(
                              f,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: selected
                                    ? Colors.white
                                    : (isDark ? Colors.white70 : _primaryBlue),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  )
                : const SizedBox.shrink(),
          ),

          // Summary bar
          if (_selectedExhibitionId != null && !_isLoading && _error == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Showing ${filtered.length} ($_selectedFilter)',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.grey[400] : _primaryBlue,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: _primaryGreen.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Taken: $takenCount / ${eligibleList.length} Eligible',
                      style: const TextStyle(
                        fontSize: 12,
                        color: _primaryGreen,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          const Divider(height: 1),

          // Orders list
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: _primaryBlue),
                  )
                : _error != null
                    ? Center(child: Text('Error: $_error'))
                    : filtered.isEmpty
                        ? Center(
                            child: Text(
                              'No orders found for "$_selectedFilter".',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final order = filtered[index];
                              return _buildCouponCard(order, isDark);
                            },
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildCouponCard(ExpoOrder order, bool isDark) {
    final coupons = _eligibleCoupons(order);
    final isEligible = coupons > 0;
    final isTaken = isEligible && order.couponTaken;
    final billLabel = order.billNumber != null
        ? 'Bill #${order.billNumber}'
        : 'Order ${order.id.substring(0, order.id.length > 8 ? 8 : order.id.length)}';
    final dateStr =
        DateFormat('dd MMM yyyy').format(order.orderDate.toLocal());

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: isTaken
          ? _primaryGreen.withValues(alpha: isDark ? 0.22 : 0.12)
          : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isTaken
              ? _primaryGreen
              : (isEligible
                  ? _primaryBlue.withValues(alpha: 0.4)
                  : Colors.grey.withValues(alpha: 0.3)),
          width: isTaken ? 1.6 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  billLabel,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: isTaken ? _primaryGreen : _primaryBlue,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (isEligible ? _primaryBlue : Colors.grey)
                        .withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isEligible
                        ? '$coupons Coupon${coupons > 1 ? 's' : ''}'
                        : 'Not Eligible',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isEligible ? _primaryBlue : Colors.grey[600],
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  'Adv: ₹${order.advanceAmount.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              order.shopName.isNotEmpty
                  ? '${order.shopName} (${order.customerName})'
                  : order.customerName,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${order.phone} • ${order.place} • $dateStr',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ),
                if (isEligible)
                  ElevatedButton.icon(
                    onPressed: () => _toggleCouponTaken(order),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isTaken ? _primaryGreen : _primaryBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: Icon(
                      isTaken
                          ? Icons.check_circle_rounded
                          : Icons.confirmation_number_outlined,
                      size: 16,
                    ),
                    label: Text(
                      isTaken ? 'Taken ✓' : 'Mark Taken',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
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
