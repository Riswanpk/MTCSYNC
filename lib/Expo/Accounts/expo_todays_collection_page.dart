import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../expo_service.dart';
import 'expo_order_detail_page.dart';

const Color _kPrimaryBlue = Color(0xFF005BAC);
const Color _kPrimaryGreen = Color(0xFF8CC63F);

class ExpoTodaysCollectionPage extends StatefulWidget {
  const ExpoTodaysCollectionPage({super.key});

  @override
  State<ExpoTodaysCollectionPage> createState() =>
      _ExpoTodaysCollectionPageState();
}

class _ExpoTodaysCollectionPageState extends State<ExpoTodaysCollectionPage> {
  String? _selectedExhibitionId;
  String? _selectedAccUserId;
  String? _selectedAccUserName;
  bool _filterExpanded = false;
  final Set<String> _selectedOrderIds = {};
  List<Map<String, String>> _accUsers = [];
  late final Stream<List<Exhibition>> _exhibitionsStream;
  String? _ordersStreamExId;
  Stream<List<ExpoOrder>>? _ordersStream;

  @override
  void initState() {
    super.initState();
    _exhibitionsStream = ExpoService.instance.streamExhibitions();
    _loadAccUsers();
  }

  Future<void> _loadAccUsers() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('role', whereIn: ['expo_acc', 'expo_acc_main'])
          .get();
      final list = snap.docs.map((d) {
        final data = d.data();
        final name = (data['username'] ?? data['name'] ?? data['email'] ?? 'User')
            .toString();
        return {'id': d.id, 'name': name};
      }).toList()
        ..sort((a, b) => a['name']!.compareTo(b['name']!));
      if (mounted) {
        setState(() => _accUsers = list);
      }
    } catch (e) {
      debugPrint('Error loading expo_acc users: $e');
    }
  }

  bool _isToday(DateTime dt) {
    final now = DateTime.now();
    return dt.year == now.year && dt.month == now.month && dt.day == now.day;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0A192F) : const Color(0xFFF4F7FA);

    return StreamBuilder<List<Exhibition>>(
      stream: _exhibitionsStream,
      builder: (context, exSnap) {
        final exhibitions = exSnap.data ?? [];
        if (exhibitions.isEmpty) {
          return Scaffold(
            backgroundColor: bgColor,
            appBar: AppBar(
              title: const Text("Today's Collection"),
              backgroundColor: _kPrimaryBlue,
              foregroundColor: Colors.white,
            ),
            body: const Center(child: Text('No exhibitions found.')),
          );
        }

        final activeEx = exhibitions.firstWhere(
          (e) => e.id == _selectedExhibitionId,
          orElse: () => exhibitions.firstWhere(
            (e) => e.isActive,
            orElse: () => exhibitions.first,
          ),
        );

        if (_ordersStreamExId != activeEx.id || _ordersStream == null) {
          _ordersStreamExId = activeEx.id;
          _ordersStream =
              ExpoService.instance.streamOrders(exhibitionId: activeEx.id);
        }

        return Scaffold(
          backgroundColor: bgColor,
          appBar: AppBar(
            title: const Text(
              "Today's Collection",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            backgroundColor: _kPrimaryBlue,
            foregroundColor: Colors.white,
            elevation: 0,
            actions: [
              if (exhibitions.length > 1)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.event_rounded),
                  tooltip: 'Select Exhibition',
                  onSelected: (id) => setState(() => _selectedExhibitionId = id),
                  itemBuilder: (_) => exhibitions
                      .map((e) => PopupMenuItem(
                            value: e.id,
                            child: Text(e.name),
                          ))
                      .toList(),
                ),
            ],
          ),
          body: StreamBuilder<List<ExpoOrder>>(
            stream: _ordersStream,
            builder: (context, orderSnap) {
              if (orderSnap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final todayOrders = (orderSnap.data ?? [])
                  .where((o) =>
                      o.status == 'Completed' &&
                      _isToday(o.completedAt ?? o.orderDate))
                  .toList();

              final collectedOrders = todayOrders.where((o) {
                if (_selectedAccUserId != null) {
                  if (o.verifiedById != null && o.verifiedById!.isNotEmpty) {
                    return o.verifiedById == _selectedAccUserId ||
                        o.verifiedByName == _selectedAccUserName;
                  }
                  return o.wasHandledByUser(_selectedAccUserId!) ||
                      o.claimedByName == _selectedAccUserName;
                }
                return true;
              }).toList();

              final double totalAdvance = collectedOrders.fold(
                  0.0, (acc, o) => acc + o.advanceAmount);

              return Column(
                children: [
                  // Animated Expo Acc User Filter
                  Container(
                    width: double.infinity,
                    color: isDark ? const Color(0xFF0F243E) : Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        InkWell(
                          onTap: () => setState(
                              () => _filterExpanded = !_filterExpanded),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.06)
                                  : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: _kPrimaryBlue.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.person_search_rounded,
                                    size: 18, color: _kPrimaryBlue),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _selectedAccUserName == null
                                        ? 'Filter by Expo Acc User: All'
                                        : 'Expo Acc User: $_selectedAccUserName',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: isDark
                                          ? Colors.white
                                          : Colors.black87,
                                    ),
                                  ),
                                ),
                                AnimatedRotation(
                                  turns: _filterExpanded ? 0.5 : 0.0,
                                  duration: const Duration(milliseconds: 200),
                                  child: const Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    color: _kPrimaryBlue,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeInOut,
                          child: _filterExpanded
                              ? Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Wrap(
                                    spacing: 8,
                                    runSpacing: 6,
                                    children: [
                                      _buildUserChip(
                                        label: 'All',
                                        selected: _selectedAccUserId == null,
                                        isDark: isDark,
                                        onTap: () => setState(() {
                                          _selectedAccUserId = null;
                                          _selectedAccUserName = null;
                                          _filterExpanded = false;
                                        }),
                                      ),
                                      ..._accUsers.map((u) => _buildUserChip(
                                            label: u['name']!,
                                            selected:
                                                _selectedAccUserId == u['id'],
                                            isDark: isDark,
                                            onTap: () => setState(() {
                                              _selectedAccUserId = u['id'];
                                              _selectedAccUserName = u['name'];
                                              _filterExpanded = false;
                                            }),
                                          )),
                                    ],
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),

                  // Top Advance Total Banner
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [_kPrimaryBlue, Color(0xFF0077CC)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: _kPrimaryBlue.withValues(alpha: 0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Collected Advance Total',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${collectedOrders.length} ${collectedOrders.length == 1 ? 'bill' : 'bills'} today',
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '₹${totalAdvance.toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Collected Bills List
                  Expanded(
                    child: RefreshIndicator(
                      color: _kPrimaryBlue,
                      onRefresh: () async {
                        await _loadAccUsers();
                        if (mounted) {
                          setState(() {
                            _ordersStream = ExpoService.instance
                                .streamOrders(exhibitionId: activeEx.id);
                          });
                        }
                      },
                      child: _buildBillsList(collectedOrders, isDark,
                          isPending: false),
                    ),
                  ),

                  // Bottom Selected Total Bar
                  if (_selectedOrderIds.isNotEmpty)
                    _buildSelectedBottomBar(collectedOrders, isDark),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildUserChip({
    required String label,
    required bool selected,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? _kPrimaryGreen
              : (isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : const Color(0xFFE2E8F0)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected
                ? Colors.white
                : (isDark ? Colors.white70 : Colors.black87),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedBottomBar(List<ExpoOrder> orders, bool isDark) {
    final selectedOrders =
        orders.where((o) => _selectedOrderIds.contains(o.id)).toList();
    final double selectedTotal =
        selectedOrders.fold(0.0, (acc, o) => acc + o.advanceAmount);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F243E) : Colors.white,
        border: Border(
          top: BorderSide(
            color: _kPrimaryGreen.withValues(alpha: 0.4),
            width: 1.5,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(
                  'Selected (${selectedOrders.length})',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => setState(() => _selectedOrderIds.clear()),
                  style: TextButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Clear',
                      style: TextStyle(fontSize: 12, color: Colors.redAccent)),
                ),
              ],
            ),
            Text(
              '₹${selectedTotal.toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: _kPrimaryGreen,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBillsList(
    List<ExpoOrder> orders,
    bool isDark, {
    required bool isPending,
  }) {
    if (orders.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: 240,
            child: Center(
              child: Text(
                isPending
                    ? 'No pending bills for today.'
                    : 'No collected bills for today.',
                style: TextStyle(
                  color: isDark ? Colors.white54 : Colors.black54,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 20),
      itemCount: orders.length,
      itemBuilder: (context, index) {
        final order = orders[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          color: isDark ? const Color(0xFF0F243E) : Colors.white,
          elevation: 1.5,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isDark
                  ? Colors.white12
                  : Colors.black.withValues(alpha: 0.06),
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ExpoOrderDetailPage(order: order),
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
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: Checkbox(
                          value: _selectedOrderIds.contains(order.id),
                          activeColor: _kPrimaryGreen,
                          onChanged: (val) {
                            setState(() {
                              if (val == true) {
                                _selectedOrderIds.add(order.id);
                              } else {
                                _selectedOrderIds.remove(order.id);
                              }
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (order.billNumber != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: _kPrimaryBlue.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '#${order.billNumber}',
                            style: const TextStyle(
                              color: _kPrimaryBlue,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      Expanded(
                        child: Text(
                          order.shopName.isNotEmpty
                              ? order.shopName
                              : order.customerName,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        DateFormat('hh:mm a').format(order.orderDate),
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white54 : Colors.black45,
                        ),
                      ),
                    ],
                  ),
                  if (order.customerName.isNotEmpty &&
                      order.shopName.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      order.customerName,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${order.orderType} • ${ExpoOrder.normalizePaymentMode(order.paymentMode)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                      Text(
                        'Advance: ₹${order.advanceAmount.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: _kPrimaryGreen,
                        ),
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
