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
  final ExpoService _expoService = ExpoService.instance;

  /// In-memory cache keyed by `<exhibitionId>|<branch>` so orders aren't
  /// re-fetched on every navigation. Only `entryDone` is updated in-place.
  static final Map<String, List<ExpoOrder>> _ordersCache = {};

  String? _selectedExhibitionId;
  String _selectedOrderType = 'All';
  bool _isLoadingOrders = false;
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Expo Orders'),
            if (_userBranch.isNotEmpty)
              Text(
                'Branch: $_userBranch',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
              ),
          ],
        ),
        actions: [
          if (_selectedExhibitionId != null)
            IconButton(
              tooltip: 'Refresh orders',
              icon: const Icon(Icons.refresh),
              onPressed: () => _loadOrdersForExhibition(
                _selectedExhibitionId!,
                forceRefresh: true,
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Exhibition selector
          StreamBuilder<List<Exhibition>>(
            stream: _expoService.streamExhibitions(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: LinearProgressIndicator(),
                );
              }
              final exhibitions = snapshot.data ?? [];
              if (exhibitions.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No exhibitions found.'),
                );
              }

              // Auto-select first exhibition if none selected
              if (_selectedExhibitionId == null) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted || _selectedExhibitionId != null) return;
                  setState(() {
                    _selectedExhibitionId = exhibitions.first.id;
                  });
                  _loadOrdersForExhibition(exhibitions.first.id);
                });
              }

              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: DropdownButtonFormField<String>(
                  value: exhibitions.any((e) => e.id == _selectedExhibitionId)
                      ? _selectedExhibitionId
                      : null,
                  decoration: InputDecoration(
                    labelText: 'Select Exhibition',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                  items: exhibitions
                      .map(
                        (e) => DropdownMenuItem<String>(
                          value: e.id,
                          child: Text(
                            e.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (val) {
                    if (val == null || val == _selectedExhibitionId) return;
                    setState(() {
                      _selectedExhibitionId = val;
                    });
                    _loadOrdersForExhibition(val);
                  },
                ),
              );
            },
          ),

          // Order type filter chips
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _orderTypes.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final type = _orderTypes[index];
                final selected = _selectedOrderType == type;
                return ChoiceChip(
                  label: Text(type),
                  selected: selected,
                  onSelected: (_) {
                    setState(() => _selectedOrderType = type);
                  },
                );
              },
            ),
          ),

          // Summary bar
          if (_selectedExhibitionId != null && !_isLoadingOrders && _error == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Showing ${filtered.length} orders',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.grey[400] : Colors.grey[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    'Entry Done: $doneCount / ${filtered.length}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.green,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

          const Divider(height: 1),

          // Orders list
          Expanded(
            child: _isLoadingOrders
                ? const Center(child: CircularProgressIndicator())
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
          ? Colors.green.withValues(alpha: isDark ? 0.22 : 0.12)
          : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDone
              ? Colors.green
              : (isDark ? Colors.grey[800]! : Colors.grey[300]!),
          width: isDone ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
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
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      order.orderType,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.blue,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (isDone)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.green,
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
