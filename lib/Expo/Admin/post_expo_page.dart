import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../expo_service.dart';

class PostExpoPage extends StatefulWidget {
  const PostExpoPage({super.key});

  @override
  State<PostExpoPage> createState() => _PostExpoPageState();
}

class _PostExpoPageState extends State<PostExpoPage>
    with SingleTickerProviderStateMixin {
  static const Color _primaryBlue = Color(0xFF005BAC);
  static const Color _primaryGreen = Color(0xFF8CC63F);

  late final TabController _tabController;
  String? _selectedExhibitionId;
  String? _selectedPrefSalesmanBranch;
  String? _selectedDeliveryBranch;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _fmtMoney(double v) =>
      '₹${NumberFormat('#,##,##0.00', 'en_IN').format(v)}';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor =
        isDark ? const Color(0xFF0A192F) : const Color(0xFFF4F7FA);

    return StreamBuilder<List<Exhibition>>(
      stream: ExpoService.instance.streamExhibitions(),
      builder: (context, exSnap) {
        final exhibitions = exSnap.data ?? [];
        if (exhibitions.isEmpty) {
          return Scaffold(
            backgroundColor: bgColor,
            appBar: AppBar(
              title: const Text('Post Expo'),
              backgroundColor: _primaryBlue,
              foregroundColor: Colors.white,
            ),
            body: const Center(child: Text('No exhibitions found.')),
          );
        }

        final selectedEx = exhibitions.firstWhere(
          (e) => e.id == _selectedExhibitionId,
          orElse: () {
            final ended = exhibitions.where((e) => e.isEnded).toList()
              ..sort((a, b) => b.endDate.compareTo(a.endDate));
            return ended.isNotEmpty ? ended.first : exhibitions.first;
          },
        );

        return Scaffold(
          backgroundColor: bgColor,
          appBar: AppBar(
            title: const Text('Post Expo',
                style: TextStyle(fontWeight: FontWeight.bold)),
            backgroundColor: _primaryBlue,
            foregroundColor: Colors.white,
            actions: [
              if (exhibitions.length > 1)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.event_rounded),
                  tooltip: 'Select Exhibition',
                  onSelected: (id) =>
                      setState(() => _selectedExhibitionId = id),
                  itemBuilder: (_) => exhibitions
                      .map((e) => PopupMenuItem(
                            value: e.id,
                            child: Text(e.name),
                          ))
                      .toList(),
                ),
            ],
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: _primaryGreen,
              indicatorWeight: 3,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              tabs: const [
                Tab(text: 'Pref. Salesman'),
                Tab(text: 'Delivery Status'),
                Tab(text: 'Itemwise Sales'),
              ],
            ),
          ),
          body: StreamBuilder<List<ExpoOrder>>(
            stream:
                ExpoService.instance.streamOrders(exhibitionId: selectedEx.id),
            builder: (context, orderSnap) {
              if (orderSnap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final orders = orderSnap.data ?? [];
              final prefBranches = orders
                  .map((o) => o.preferredBranch.trim())
                  .where((b) => b.isNotEmpty && b != 'N/A')
                  .toSet()
                  .toList()
                ..sort();
              final bookingBranches = orders
                  .where((o) => o.orderType == 'Booking')
                  .map((o) => o.preferredBranch.trim())
                  .where((b) => b.isNotEmpty && b != 'N/A')
                  .toSet()
                  .toList()
                ..sort();
              return TabBarView(
                controller: _tabController,
                children: [
                  _buildPreferredSalesmanTab(orders, prefBranches, isDark),
                  _buildDeliveryByBranchTab(orders, bookingBranches, isDark),
                  _buildItemwiseSalesTab(orders, isDark),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildBranchFilterBar(
    List<String> branches,
    String? selectedBranch,
    ValueChanged<String?> onSelect,
    bool isDark,
  ) {
    if (branches.isEmpty) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      child: Row(
        children: [
          ChoiceChip(
            label: const Text('All Branches'),
            selected: selectedBranch == null,
            selectedColor: _primaryBlue,
            labelStyle: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selectedBranch == null
                  ? Colors.white
                  : (isDark ? Colors.white70 : Colors.black87),
            ),
            onSelected: (_) => onSelect(null),
          ),
          const SizedBox(width: 8),
          ...branches.map((b) {
            final selected = selectedBranch == b;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(b),
                selected: selected,
                selectedColor: _primaryGreen,
                labelStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? Colors.white
                      : (isDark ? Colors.white70 : Colors.black87),
                ),
                onSelected: (_) => onSelect(b),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildPreferredSalesmanTab(
      List<ExpoOrder> orders, List<String> branches, bool isDark) {
    final filtered = _selectedPrefSalesmanBranch == null
        ? orders
        : orders
            .where((o) =>
                o.preferredBranch.trim() == _selectedPrefSalesmanBranch)
            .toList();
    final Map<String, ({int count, double total})> map = {};
    for (final o in filtered) {
      final key = o.preferredSalesman.trim().isNotEmpty
          ? o.preferredSalesman.trim()
          : 'Unassigned';
      final prev = map[key] ?? (count: 0, total: 0.0);
      map[key] = (count: prev.count + 1, total: prev.total + o.totalAmount);
    }
    final list = map.entries.toList()
      ..sort((a, b) => b.value.total.compareTo(a.value.total));
    return Column(
      children: [
        _buildBranchFilterBar(
          branches,
          _selectedPrefSalesmanBranch,
          (val) => setState(() => _selectedPrefSalesmanBranch = val),
          isDark,
        ),
        Expanded(
          child: list.isEmpty
              ? const Center(child: Text('No orders found.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(14),
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final e = list[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      color: isDark ? const Color(0xFF0F243E) : Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: _primaryBlue.withValues(alpha: 0.12),
                          child: const Icon(Icons.person_pin_rounded,
                              color: _primaryBlue),
                        ),
                        title: Text(e.key,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('${e.value.count} orders'),
                        trailing: Text(
                          _fmtMoney(e.value.total),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: _primaryGreen),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildDeliveryByBranchTab(
      List<ExpoOrder> orders, List<String> branches, bool isDark) {
    final bookingOrders = orders
        .where((o) =>
            o.orderType == 'Booking' &&
            (_selectedDeliveryBranch == null ||
                o.preferredBranch.trim() == _selectedDeliveryBranch))
        .toList();
    if (bookingOrders.isEmpty) {
      return const Center(child: Text('No booking/assigned orders.'));
    }
    final Map<String, ({int delivered, int pending, double total})> map = {};
    for (final o in bookingOrders) {
      final key = o.preferredBranch.trim().isNotEmpty
          ? o.preferredBranch.trim()
          : 'N/A';
      final prev = map[key] ?? (delivered: 0, pending: 0, total: 0.0);
      final done = o.isBranchDelivered;
      map[key] = (
        delivered: prev.delivered + (done ? 1 : 0),
        pending: prev.pending + (done ? 0 : 1),
        total: prev.total + o.totalAmount,
      );
    }
    final list = map.entries.toList()
      ..sort((a, b) => b.value.total.compareTo(a.value.total));
    return Column(
      children: [
        _buildBranchFilterBar(
          branches,
          _selectedPrefSalesmanBranch,
          (val) => setState(() => _selectedPrefSalesmanBranch = val),
          isDark,
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(14),
            itemCount: list.length,
            itemBuilder: (context, i) {
              final e = list[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                color: isDark ? const Color(0xFF0F243E) : Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: _primaryGreen.withValues(alpha: 0.15),
                    child: const Icon(Icons.local_shipping_rounded,
                        color: _primaryGreen),
                  ),
                  title: Text(e.key,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                      'Delivered: ${e.value.delivered} • Pending: ${e.value.pending}'),
                  trailing: Text(
                    _fmtMoney(e.value.total),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                        color: _primaryBlue),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildItemwiseSalesTab(List<ExpoOrder> orders, bool isDark) {
    final Map<String, ({int qty, double total})> map = {};
    for (final o in orders) {
      for (final it in o.items) {
        final key = it.itemName.trim().isNotEmpty ? it.itemName.trim() : it.mtcCode;
        final prev = map[key] ?? (qty: 0, total: 0.0);
        map[key] = (qty: prev.qty + it.qty, total: prev.total + it.total);
      }
    }
    final list = map.entries.toList()
      ..sort((a, b) => b.value.total.compareTo(a.value.total));
    if (list.isEmpty) {
      return const Center(child: Text('No items sold.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(14),
      itemCount: list.length,
      itemBuilder: (context, i) {
        final e = list[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          color: isDark ? const Color(0xFF0F243E) : Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: _primaryBlue.withValues(alpha: 0.12),
              child: const Icon(Icons.inventory_2_rounded, color: _primaryBlue),
            ),
            title: Text(e.key,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
            subtitle: Text('Qty Sold: ${e.value.qty}'),
            trailing: Text(
              _fmtMoney(e.value.total),
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13.5,
                  color: _primaryGreen),
            ),
          ),
        );
      },
    );
  }
}
