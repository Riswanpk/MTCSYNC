import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../expo_service.dart';

class ExpoCouponsPage extends StatefulWidget {
  const ExpoCouponsPage({super.key});

  @override
  State<ExpoCouponsPage> createState() => _ExpoCouponsPageState();
}

class _CustomerCouponGroup {
  final String customerKey;
  final String phone;
  final String customerName;
  final String shopName;
  final String place;
  final List<ExpoOrder> orders;
  final double totalAdvance;
  final int totalEligibleCoupons;
  final int couponsTaken;
  final DateTime latestOrderDate;

  const _CustomerCouponGroup({
    required this.customerKey,
    required this.phone,
    required this.customerName,
    required this.shopName,
    required this.place,
    required this.orders,
    required this.totalAdvance,
    required this.totalEligibleCoupons,
    required this.couponsTaken,
    required this.latestOrderDate,
  });

  int get remainingCoupons {
    final diff = totalEligibleCoupons - couponsTaken;
    return diff > 0 ? diff : 0;
  }

  bool get isEligible => totalEligibleCoupons > 0;
  bool get hasPending => remainingCoupons > 0;
  bool get isFullyTaken => isEligible && remainingCoupons == 0;
}

class _ExpoCouponsPageState extends State<ExpoCouponsPage> {
  static const Color _primaryBlue = Color(0xFF005BAC);
  static const Color _primaryGreen = Color(0xFF00897B);

  final ExpoService _expoService = ExpoService.instance;
  final TextEditingController _searchController = TextEditingController();

  String? _selectedExhibitionId;
  String _selectedFilter = 'Eligible';
  String _searchQuery = '';
  bool _isLoading = false;
  bool _isDropdownOpen = false;
  bool _isFilterExpanded = false;
  String? _error;
  List<ExpoOrder> _orders = [];
  Map<String, int> _couponsTakenByKey = {};

  static const List<String> _filters = [
    'Eligible',
    'Pending',
    'Taken',
    'All',
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _customerKeyForOrder(ExpoOrder order) {
    final cleanPhone = ExpoService.normalizeCustomerPhone(order.phone);
    if (cleanPhone.isNotEmpty) return cleanPhone;
    return 'name:${order.customerName.trim().toLowerCase()}|${order.shopName.trim().toLowerCase()}';
  }

  int _couponsForAmount(double amount) {
    if (amount < 10000) return 0;
    return amount ~/ 10000;
  }

  Future<void> _loadOrders(String exhibitionId) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _expoService.fetchOrdersForExhibition(exhibitionId),
        _expoService.fetchCustomerCouponsForExhibition(exhibitionId),
      ]);
      if (!mounted) return;
      setState(() {
        _orders = results[0] as List<ExpoOrder>;
        _couponsTakenByKey = results[1] as Map<String, int>;
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

  List<_CustomerCouponGroup> get _customerGroups {
    final grouped = <String, List<ExpoOrder>>{};
    for (final order in _orders) {
      final key = _customerKeyForOrder(order);
      grouped.putIfAbsent(key, () => []).add(order);
    }

    final groups = <_CustomerCouponGroup>[];
    for (final entry in grouped.entries) {
      final key = entry.key;
      final groupOrders = List<ExpoOrder>.from(entry.value)
        ..sort((a, b) {
          if (a.billNumber != null && b.billNumber != null) {
            return a.billNumber!.compareTo(b.billNumber!);
          }
          if (a.billNumber != null) return -1;
          if (b.billNumber != null) return 1;
          return a.orderDate.compareTo(b.orderDate);
        });

      double totalAdvance = 0.0;
      String phone = '';
      String customerName = '';
      String shopName = '';
      String place = '';
      DateTime latestDate = groupOrders.first.orderDate;
      int legacyTaken = 0;

      for (final o in groupOrders) {
        totalAdvance += o.advanceAmount;
        if (o.phone.trim().isNotEmpty) phone = o.phone.trim();
        if (o.customerName.trim().isNotEmpty) {
          customerName = o.customerName.trim();
        }
        if (o.shopName.trim().isNotEmpty) shopName = o.shopName.trim();
        if (o.place.trim().isNotEmpty) place = o.place.trim();
        if (o.orderDate.isAfter(latestDate)) latestDate = o.orderDate;
        if (o.couponTaken) {
          legacyTaken += _couponsForAmount(o.advanceAmount);
        }
      }

      final totalEligible = _couponsForAmount(totalAdvance);
      final taken = _couponsTakenByKey.containsKey(key)
          ? _couponsTakenByKey[key]!
          : legacyTaken;

      groups.add(_CustomerCouponGroup(
        customerKey: key,
        phone: phone,
        customerName: customerName,
        shopName: shopName,
        place: place,
        orders: groupOrders,
        totalAdvance: totalAdvance,
        totalEligibleCoupons: totalEligible,
        couponsTaken: taken,
        latestOrderDate: latestDate,
      ));
    }

    groups.sort((a, b) {
      final aPending = a.hasPending ? 1 : 0;
      final bPending = b.hasPending ? 1 : 0;
      if (aPending != bPending) return bPending.compareTo(aPending);
      return b.latestOrderDate.compareTo(a.latestOrderDate);
    });

    return groups;
  }

  bool _matchesSearch(_CustomerCouponGroup group) {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return true;
    final qBill = q.startsWith('#') ? q.substring(1).trim() : q;

    if (group.customerName.toLowerCase().contains(q) ||
        group.shopName.toLowerCase().contains(q) ||
        group.phone.toLowerCase().contains(q)) {
      return true;
    }

    for (final order in group.orders) {
      if (qBill.isNotEmpty &&
          order.billNumber != null &&
          order.billNumber.toString().contains(qBill)) {
        return true;
      }
      if (order.id.toLowerCase().contains(q)) {
        return true;
      }
    }
    return false;
  }

  List<_CustomerCouponGroup> _applyFilter(List<_CustomerCouponGroup> groups) {
    Iterable<_CustomerCouponGroup> result;
    switch (_selectedFilter) {
      case 'Eligible':
        result = groups.where((g) => g.isEligible);
        break;
      case 'Pending':
        result = groups.where((g) => g.hasPending);
        break;
      case 'Taken':
        result = groups.where((g) => g.isEligible && g.couponsTaken > 0);
        break;
      default:
        result = groups;
    }
    if (_searchQuery.trim().isNotEmpty) {
      result = result.where(_matchesSearch);
    }
    return result.toList();
  }

  Future<void> _setCouponsTaken(
    _CustomerCouponGroup group,
    int newTakenCount,
  ) async {
    final exId = _selectedExhibitionId;
    if (exId == null) return;
    final clamped = newTakenCount < 0 ? 0 : newTakenCount;
    try {
      await _expoService.upsertCustomerCouponsTaken(
        exhibitionId: exId,
        customerPhone: group.customerKey,
        couponsTaken: clamped,
      );
      if (!mounted) return;
      setState(() {
        _couponsTakenByKey[group.customerKey] = clamped;
      });
      final delta = clamped - group.couponsTaken;
      final message = delta > 0
          ? 'Issued $delta coupon(s) (Total taken: $clamped / ${group.totalEligibleCoupons})'
          : 'Updated coupons taken to $clamped / ${group.totalEligibleCoupons}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: clamped >= group.totalEligibleCoupons
              ? _primaryGreen
              : _primaryBlue,
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

  Future<void> _showAdjustCouponsDialog(_CustomerCouponGroup group) async {
    int tempTaken = group.couponsTaken;
    final maxCoupons = group.totalEligibleCoupons > group.couponsTaken
        ? group.totalEligibleCoupons
        : group.couponsTaken;

    final confirmed = await showDialog<int>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final remaining = (group.totalEligibleCoupons - tempTaken) > 0
                ? group.totalEligibleCoupons - tempTaken
                : 0;
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Text(
                group.shopName.isNotEmpty ? group.shopName : group.customerName,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _primaryBlue,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Total Eligible: ${group.totalEligibleCoupons} coupon(s)',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        onPressed: tempTaken > 0
                            ? () => setDialogState(() => tempTaken--)
                            : null,
                        icon: const Icon(Icons.remove_circle_outline),
                        color: _primaryBlue,
                        iconSize: 30,
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 8),
                        decoration: BoxDecoration(
                          color: _primaryBlue.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _primaryBlue.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          '$tempTaken',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: _primaryBlue,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: tempTaken < maxCoupons
                            ? () => setDialogState(() => tempTaken++)
                            : null,
                        icon: const Icon(Icons.add_circle_outline),
                        color: _primaryGreen,
                        iconSize: 30,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Remaining Pending: $remaining',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: remaining > 0 ? _primaryBlue : _primaryGreen,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(tempTaken),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryGreen,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != null && confirmed != group.couponsTaken) {
      await _setCouponsTaken(group, confirmed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final allGroups = _customerGroups;
    final filtered = _applyFilter(allGroups);

    final totalEligibleCoupons = allGroups.fold<int>(
        0, (sum, g) => sum + g.totalEligibleCoupons);
    final totalTakenCoupons = allGroups.fold<int>(
        0, (sum, g) => sum + g.couponsTaken);
    final totalPendingCoupons = allGroups.fold<int>(
        0, (sum, g) => sum + g.remainingCoupons);

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

          // Bill No / Customer Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _searchQuery = val),
              decoration: InputDecoration(
                hintText: 'Search Bill No, Customer, Shop or Phone',
                hintStyle: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: _primaryBlue,
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: isDark
                    ? const Color(0xFF1E293B)
                    : _primaryBlue.withValues(alpha: 0.05),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: _primaryBlue.withValues(alpha: 0.3),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: _primaryBlue.withValues(alpha: 0.3),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: _primaryBlue,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),

          // Animated Filter Panel
          AnimatedSize(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeInOut,
            child: _isFilterExpanded
                ? Container(
                    width: double.infinity,
                    margin: const EdgeInsets.fromLTRB(16, 2, 16, 6),
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
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${filtered.length} Customer${filtered.length == 1 ? '' : 's'} ($_selectedFilter)',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.grey[400] : _primaryBlue,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Row(
                    children: [
                      if (totalPendingCoupons > 0)
                        Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _primaryBlue.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Pending: $totalPendingCoupons',
                            style: const TextStyle(
                              fontSize: 11,
                              color: _primaryBlue,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: _primaryGreen.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Taken: $totalTakenCoupons / $totalEligibleCoupons',
                          style: const TextStyle(
                            fontSize: 12,
                            color: _primaryGreen,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

          const Divider(height: 1),

          // Customer Coupon Groups List
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
                              _searchQuery.trim().isNotEmpty
                                  ? 'No customers or bills matching "$_searchQuery".'
                                  : 'No customers found for "$_selectedFilter".',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final group = filtered[index];
                              return _buildCustomerCouponCard(group, isDark);
                            },
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerCouponCard(_CustomerCouponGroup group, bool isDark) {
    final isEligible = group.isEligible;
    final hasPending = group.hasPending;
    final isFullyTaken = group.isFullyTaken;
    final q = _searchQuery.trim().toLowerCase();
    final qBill = q.startsWith('#') ? q.substring(1).trim() : q;

    final titleText = group.shopName.isNotEmpty && group.customerName.isNotEmpty
        ? '${group.shopName} (${group.customerName})'
        : (group.shopName.isNotEmpty ? group.shopName : group.customerName);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: isFullyTaken
          ? _primaryGreen.withValues(alpha: isDark ? 0.20 : 0.10)
          : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isFullyTaken
              ? _primaryGreen
              : (hasPending
                  ? _primaryBlue.withValues(alpha: 0.65)
                  : Colors.grey.withValues(alpha: 0.3)),
          width: (isFullyTaken || hasPending) ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Customer name & Total Advance
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    titleText,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: isFullyTaken ? _primaryGreen : _primaryBlue,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Total Adv: ₹${group.totalAdvance.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${group.phone}${group.place.isNotEmpty ? ' • ${group.place}' : ''} • ${group.orders.length} Bill${group.orders.length > 1 ? 's' : ''}',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),

            // Coupon breakdown badges
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
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
                        ? 'Total: ${group.totalEligibleCoupons} Coupon${group.totalEligibleCoupons > 1 ? 's' : ''}'
                        : 'Not Eligible',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isEligible ? _primaryBlue : Colors.grey[600],
                    ),
                  ),
                ),
                if (group.couponsTaken > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _primaryGreen.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Taken: ${group.couponsTaken}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _primaryGreen,
                      ),
                    ),
                  ),
                if (hasPending)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _primaryBlue,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      group.couponsTaken > 0
                          ? '+${group.remainingCoupons} More Pending'
                          : '${group.remainingCoupons} Pending',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // Grouped bills list
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: group.orders.map((order) {
                final billLabel = order.billNumber != null
                    ? 'Bill #${order.billNumber}'
                    : 'Order ${order.id.substring(0, order.id.length > 6 ? 6 : order.id.length)}';
                final dateStr =
                    DateFormat('dd MMM').format(order.orderDate.toLocal());
                final isMatchedBill = qBill.isNotEmpty &&
                    order.billNumber != null &&
                    order.billNumber.toString().contains(qBill);

                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isMatchedBill
                        ? _primaryBlue.withValues(alpha: 0.16)
                        : (isDark
                            ? Colors.grey[850]
                            : Colors.grey.withValues(alpha: 0.10)),
                    borderRadius: BorderRadius.circular(8),
                    border: isMatchedBill
                        ? Border.all(color: _primaryBlue, width: 1.2)
                        : null,
                  ),
                  child: Text(
                    '$billLabel • ₹${order.advanceAmount.toStringAsFixed(0)} ($dateStr)',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight:
                          isMatchedBill ? FontWeight.w700 : FontWeight.w500,
                      color: isMatchedBill
                          ? _primaryBlue
                          : (isDark ? Colors.grey[300] : Colors.grey[800]),
                    ),
                  ),
                );
              }).toList(),
            ),

            if (isEligible) ...[
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: 'Adjust Coupons',
                    onPressed: () => _showAdjustCouponsDialog(group),
                    icon: const Icon(Icons.tune_rounded, size: 20),
                    color: _primaryBlue,
                  ),
                  const SizedBox(width: 4),
                  if (hasPending)
                    ElevatedButton.icon(
                      onPressed: () => _setCouponsTaken(
                        group,
                        group.totalEligibleCoupons,
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(
                        Icons.confirmation_number_outlined,
                        size: 16,
                      ),
                      label: Text(
                        'Issue ${group.remainingCoupons} Coupon${group.remainingCoupons > 1 ? 's' : ''}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  else
                    ElevatedButton.icon(
                      onPressed: () => _showAdjustCouponsDialog(group),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(
                        Icons.check_circle_rounded,
                        size: 16,
                      ),
                      label: Text(
                        'All ${group.totalEligibleCoupons} Taken ✓',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
