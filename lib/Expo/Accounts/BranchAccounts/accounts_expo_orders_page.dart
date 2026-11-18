import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../Navigation/user_cache_service.dart';
import '../../expo_service.dart';
import 'accounts_order_detail_page.dart';

class AccountsExpoOrdersPage extends StatefulWidget {
  const AccountsExpoOrdersPage({super.key});

  @override
  State<AccountsExpoOrdersPage> createState() => _AccountsExpoOrdersPageState();
}

class _AccountsExpoOrdersPageState extends State<AccountsExpoOrdersPage> {
  static const Color _primaryBlue = Color(0xFF005BAC);
  static const Color _primaryGreen = Color(0xFF00897B);

  final ExpoService _expoService = ExpoService.instance;

  /// In-memory cache keyed by `<exhibitionId>|<branch>` so orders aren't
  /// re-fetched on every navigation. Only `entryDone` is updated in-place.
  static final Map<String, List<ExpoOrder>> _ordersCache = {};

  String? _selectedExhibitionId;
  String _selectedOrderType = 'All';
  bool _isLoadingOrders = false;
  bool _isExhibitionDropdownOpen = false;
  bool _isFilterExpanded = false;
  String? _error;
  List<ExpoOrder> _orders = [];

  static const List<String> _orderTypes = [
    'All',
    'Spot Delivery',
    'Booking',
    'Stall Delivery',
  ];

  String get _userBranch =>
      (UserCacheService.instance.branch ?? '').trim();

  String _cacheKey(String exhibitionId) =>
      '$exhibitionId|${_userBranch.toLowerCase()}';

  Future<void> _loadOrdersForExhibition(
    String exhibitionId, {
    bool forceRefresh = false,
  }) async {
    final key = _cacheKey(exhibitionId);
    if (!forceRefresh && _ordersCache.containsKey(key)) {
      setState(() {
        _orders = List<ExpoOrder>.from(_ordersCache[key]!);
        _error = null;
        _isLoadingOrders = false;
      });
      return;
    }

    setState(() {
      _isLoadingOrders = true;
      _error = null;
    });

    try {
      final allOrders =
          await _expoService.fetchOrdersForExhibition(exhibitionId);
      final branchLower = _userBranch.toLowerCase();
      final filtered = allOrders
          .where((o) => o.preferredBranch.trim().toLowerCase() == branchLower)
          .toList();

      _ordersCache[key] = filtered;
      if (!mounted) return;
      setState(() {
        _orders = List<ExpoOrder>.from(filtered);
        _isLoadingOrders = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoadingOrders = false;
      });
    }
  }

  void _updateCachedOrder(ExpoOrder updated) {
    final exId = _selectedExhibitionId;
    if (exId == null) return;
    final key = _cacheKey(exId);

    final idx = _orders.indexWhere((o) => o.id == updated.id);
    if (idx != -1) {
      setState(() {
        _orders[idx] = updated;
      });
    }
    final cached = _ordersCache[key];
    if (cached != null) {
      final cIdx = cached.indexWhere((o) => o.id == updated.id);
      if (cIdx != -1) {
        cached[cIdx] = updated;
      }
    }
  }

  List<ExpoOrder> get _filteredOrders {
    if (_selectedOrderType == 'All') return _orders;
    return _orders
        .where((o) =>
            o.orderType.trim().toLowerCase() ==
            _selectedOrderType.toLowerCase())
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filtered = _filteredOrders;
    final doneCount = filtered.where((o) => o.entryDone).length;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: _primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Expo Orders',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            if (_userBranch.isNotEmpty)
              Text(
                'Branch: $_userBranch',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: Colors.white70,
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Filter Order Type',
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.filter_list_rounded),
                if (_selectedOrderType != 'All')
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
              setState(() {
                _isFilterExpanded = !_isFilterExpanded;
              });
            },
          ),
          if (_selectedExhibitionId != null)
            IconButton(
              tooltip: 'Refresh orders',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () => _loadOrdersForExhibition(
                _selectedExhibitionId!,
                forceRefresh: true,
              ),
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
                  _loadOrdersForExhibition(exhibitions.first.id);
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
                        setState(() {
                          _isExhibitionDropdownOpen = !_isExhibitionDropdownOpen;
                        });
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
                                Icons.event_available_rounded,
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
                              turns: _isExhibitionDropdownOpen ? 0.5 : 0.0,
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
                      child: _isExhibitionDropdownOpen
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
                                          _isExhibitionDropdownOpen = false;
                                          _selectedExhibitionId = ex.id;
                                        });
                                        _loadOrdersForExhibition(ex.id);
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

          // Animated Order Type Filter Panel
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
                      children: _orderTypes.map((type) {
                        final selected = _selectedOrderType == type;
                        return GestureDetector(
                          onTap: () {
                            setState(() => _selectedOrderType = type);
                          },
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
                              type,
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
          if (_selectedExhibitionId != null && !_isLoadingOrders && _error == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Showing ${filtered.length} orders ($_selectedOrderType)',
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
                      'Entry Done: $doneCount / ${filtered.length}',
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
            child: _isLoadingOrders
                ? const Center(
                    child: CircularProgressIndicator(color: _primaryBlue),
                  )
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Failed to load orders:\n$_error',
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _primaryBlue,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: _selectedExhibitionId == null
                                    ? null
                                    : () => _loadOrdersForExhibition(
                                          _selectedExhibitionId!,
                                          forceRefresh: true,
                                        ),
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : filtered.isEmpty
                        ? Center(
                            child: Text(
                              _userBranch.isEmpty
                                  ? 'No branch assigned to your account.'
                                  : 'No orders found for $_userBranch.',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final order = filtered[index];
                              return _buildOrderCard(order, isDark);
                            },
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderCard(ExpoOrder order, bool isDark) {
    final isDone = order.entryDone;
    final billLabel = order.billNumber != null
        ? 'Bill #${order.billNumber}'
        : 'Order ${order.id.substring(0, order.id.length > 8 ? 8 : order.id.length)}';
    final dateStr =
        DateFormat('dd MMM yyyy, hh:mm a').format(order.orderDate.toLocal());

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: isDone
          ? _primaryGreen.withValues(alpha: isDark ? 0.22 : 0.12)
          : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isDone
              ? _primaryGreen
              : _primaryBlue.withValues(alpha: isDark ? 0.35 : 0.25),
          width: isDone ? 1.6 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AccountsOrderDetailPage(
                order: order,
                onEntryDoneChanged: _updateCachedOrder,
              ),
            ),
          );
        },
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
                      color: isDone ? _primaryGreen : _primaryBlue,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _primaryBlue.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      order.orderType,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _primaryBlue,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (isDone)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _primaryGreen,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check, color: Colors.white, size: 13),
                          SizedBox(width: 3),
                          Text(
                            'Entry Done',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
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
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${order.place} • $dateStr',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                  Text(
                    '₹${order.totalAmount.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
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
