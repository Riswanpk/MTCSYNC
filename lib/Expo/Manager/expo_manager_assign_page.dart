import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../Navigation/user_cache_service.dart';
import '../expo_service.dart';

const Color primaryBlue = Color(0xFF005BAC);
const Color primaryGreen = Color(0xFF8CC63F);

/// Manager-only assignment workspace opened by long-pressing the "Expo" button.
/// Displays branch orders from exhibitions ended by Admin so the Manager can
/// assign `N/A` preferred salesman orders to Sales, Asst Manager, or himself.
class ExpoManagerAssignPage extends StatefulWidget {
  const ExpoManagerAssignPage({super.key});

  @override
  State<ExpoManagerAssignPage> createState() => _ExpoManagerAssignPageState();
}

class _ExpoManagerAssignPageState extends State<ExpoManagerAssignPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  String _managerBranch = '';
  String _managerName = '';
  String _managerUid = '';
  bool _isLoadingUser = true;
  bool _isAssigning = false;

  List<Map<String, dynamic>> _branchUsers = [];
  String? _selectedExhibitionId; // null = All Ended Expos
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedOrderIds = <String>{};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      if (_tabController.index != 0 && _selectedOrderIds.isNotEmpty) {
        setState(() => _selectedOrderIds.clear());
      } else {
        setState(() {});
      }
    });
    _initUserAndTeam();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initUserAndTeam() async {
    try {
      final cache = UserCacheService.instance;
      await cache.ensureLoaded();
      final branch = (cache.branch ?? '').trim();
      final name = (cache.username ?? 'Manager').trim();
      final uid = (cache.uid ?? '').trim();
      final users = branch.isNotEmpty
          ? await ExpoService.instance.getBranchAssignableUsers(branch)
          : <Map<String, dynamic>>[];

      if (mounted) {
        setState(() {
          _managerBranch = branch;
          _managerName = name;
          _managerUid = uid;
          _branchUsers = users;
          _isLoadingUser = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingUser = false);
    }
  }

  bool _isUnassignedSalesman(ExpoOrder o) {
    final s = o.preferredSalesman.trim();
    return s.isEmpty || s.toUpperCase() == 'N/A';
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
        billStr.toLowerCase().contains(q);
  }

  Future<void> _openAssigneePickerSheet({
    required List<ExpoOrder> targetOrders,
    required List<ExpoOrder> allBranchOrders,
  }) async {
    if (targetOrders.isEmpty) return;

    // Count active (assigned) orders per user in this branch for balanced distribution
    final Map<String, int> orderCounts = {};
    for (final o in allBranchOrders) {
      if (!_isUnassignedSalesman(o) && !o.isBranchDelivered) {
        final key = o.preferredSalesman.trim().toLowerCase();
        orderCounts[key] = (orderCounts[key] ?? 0) + 1;
      }
    }

    final teamMembers = _branchUsers.where((u) {
      final uid = (u['uid'] ?? '').toString().trim();
      final uname = (u['username'] ?? '').toString().trim();
      if (_managerUid.isNotEmpty && uid == _managerUid) return false;
      if (uname.toLowerCase() == _managerName.toLowerCase()) return false;
      return true;
    }).toList();

    final String? chosenSalesman = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AssigneePickerSheet(
        managerName: _managerName,
        managerBranch: _managerBranch,
        orderCount: targetOrders.length,
        teamMembers: teamMembers,
        activeOrderCounts: orderCounts,
      ),
    );

    if (chosenSalesman == null || chosenSalesman.isEmpty || !mounted) return;

    setState(() => _isAssigning = true);
    try {
      final ids = targetOrders.map((o) => o.id).toList();
      await ExpoService.instance.assignOrdersToSalesman(
        orderIds: ids,
        salesmanName: chosenSalesman,
      );
      if (mounted) {
        setState(() {
          _selectedOrderIds.removeAll(ids);
        });
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                ids.length == 1
                    ? 'Order assigned to $chosenSalesman'
                    : '${ids.length} orders assigned to $chosenSalesman',
              ),
              backgroundColor: primaryGreen,
            ),
          );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to assign orders: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isAssigning = false);
    }
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
              title: const Text('Assign Expo Orders'),
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

        return Scaffold(
          backgroundColor:
              isDark ? const Color(0xFF0A1628) : const Color(0xFFF4F7FB),
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Assign Expo Orders',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                ),
                Text(
                  'Branch: ${_managerBranch.isEmpty ? 'N/A' : _managerBranch}',
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ],
            ),
            backgroundColor: primaryBlue,
            foregroundColor: Colors.white,
            elevation: 0,
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: primaryGreen,
              indicatorWeight: 3,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              tabs: const [
                Tab(text: 'Unassigned (N/A)'),
                Tab(text: 'Assigned'),
              ],
            ),
          ),
          body: endedExhibitions.isEmpty
              ? _buildNoEndedExposState(isDark)
              : StreamBuilder<List<ExpoOrder>>(
                  stream: ExpoService.instance.streamAllOrders(),
                  builder: (context, orderSnap) {
                    if (orderSnap.connectionState == ConnectionState.waiting &&
                        !orderSnap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final normalizedBranch =
                        _managerBranch.trim().toUpperCase();
                    final branchOrders = (orderSnap.data ?? []).where((o) {
                      if (!endedIds.contains(o.exhibitionId)) return false;
                      if (o.orderType == 'Spot Delivery') return false;
                      return o.preferredBranch.trim().toUpperCase() ==
                          normalizedBranch;
                    }).toList();

                    final expoFiltered = _selectedExhibitionId == null
                        ? branchOrders
                        : branchOrders
                            .where(
                                (o) => o.exhibitionId == _selectedExhibitionId)
                            .toList();

                    final searched =
                        expoFiltered.where(_matchesSearch).toList();

                    final unassignedOrders =
                        searched.where(_isUnassignedSalesman).toList();
                    final assignedOrders = searched
                        .where((o) => !_isUnassignedSalesman(o))
                        .toList();

                    // Remove any stale selected IDs no longer in unassigned list
                    final unassignedIdSet =
                        unassignedOrders.map((e) => e.id).toSet();
                    _selectedOrderIds
                        .removeWhere((id) => !unassignedIdSet.contains(id));

                    return Column(
                      children: [
                        _buildFilterHeader(
                          endedExhibitions: endedExhibitions,
                          unassignedCount: unassignedOrders.length,
                          assignedCount: assignedOrders.length,
                          isDark: isDark,
                        ),
                        Expanded(
                          child: TabBarView(
                            controller: _tabController,
                            children: [
                              _buildUnassignedTab(
                                orders: unassignedOrders,
                                allBranchOrders: branchOrders,
                                isDark: isDark,
                              ),
                              _buildAssignedTab(
                                orders: assignedOrders,
                                allBranchOrders: branchOrders,
                                isDark: isDark,
                              ),
                            ],
                          ),
                        ),
                        if (_tabController.index == 0 &&
                            _selectedOrderIds.isNotEmpty)
                          _buildBulkAssignBar(
                            unassignedOrders: unassignedOrders,
                            allBranchOrders: branchOrders,
                            isDark: isDark,
                          ),
                      ],
                    );
                  },
                ),
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
              Icons.event_available_rounded,
              size: 64,
              color: primaryBlue.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 16),
            Text(
              'No Ended Exhibitions Yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Branch orders with unassigned salesmen will appear here once Admin clicks "End Exhibition".',
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

  Widget _buildFilterHeader({
    required List<Exhibition> endedExhibitions,
    required int unassignedCount,
    required int assignedCount,
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
          // Ended Exhibition selector chips
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(
                      'All Ended Expos (${unassignedCount + assignedCount})',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _selectedExhibitionId == null
                            ? Colors.white
                            : (isDark ? Colors.white70 : Colors.black87),
                      ),
                    ),
                    selected: _selectedExhibitionId == null,
                    selectedColor: primaryBlue,
                    backgroundColor: isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : const Color(0xFFF1F5F9),
                    onSelected: (_) =>
                        setState(() => _selectedExhibitionId = null),
                  ),
                ),
                ...endedExhibitions.map((ex) {
                  final selected = _selectedExhibitionId == ex.id;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(
                        ex.name,
                        style: TextStyle(
                          fontSize: 12,
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
                      onSelected: (_) =>
                          setState(() => _selectedExhibitionId = ex.id),
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 10),
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
          const SizedBox(height: 8),
          Row(
            children: [
              _summaryBadge(
                label: 'Pending Assign',
                count: unassignedCount,
                color: const Color(0xFFE65100),
              ),
              const SizedBox(width: 8),
              _summaryBadge(
                label: 'Assigned',
                count: assignedCount,
                color: primaryGreen,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryBadge({
    required String label,
    required int count,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        '$label: $count',
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Widget _buildUnassignedTab({
    required List<ExpoOrder> orders,
    required List<ExpoOrder> allBranchOrders,
    required bool isDark,
  }) {
    if (orders.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.assignment_turned_in_rounded,
                size: 58,
                color: primaryGreen.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 12),
              Text(
                'No Unassigned Orders',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'All $_managerBranch orders for ended exhibitions have a salesman assigned.',
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

    final bool allSelected =
        orders.isNotEmpty && _selectedOrderIds.length == orders.length;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          color: isDark
              ? Colors.white.withValues(alpha: 0.03)
              : primaryBlue.withValues(alpha: 0.04),
          child: Row(
            children: [
              Checkbox(
                value: allSelected,
                activeColor: primaryBlue,
                onChanged: (_) {
                  setState(() {
                    if (allSelected) {
                      _selectedOrderIds.clear();
                    } else {
                      _selectedOrderIds.addAll(orders.map((o) => o.id));
                    }
                  });
                },
              ),
              Text(
                allSelected ? 'Deselect All' : 'Select All (${orders.length})',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
              const Spacer(),
              if (_selectedOrderIds.isNotEmpty)
                Text(
                  '${_selectedOrderIds.length} selected',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: primaryBlue,
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 90),
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final order = orders[index];
              final isSelected = _selectedOrderIds.contains(order.id);
              return _buildOrderCard(
                order: order,
                allBranchOrders: allBranchOrders,
                isDark: isDark,
                isUnassigned: true,
                isSelected: isSelected,
                onToggleSelect: () {
                  setState(() {
                    if (isSelected) {
                      _selectedOrderIds.remove(order.id);
                    } else {
                      _selectedOrderIds.add(order.id);
                    }
                  });
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAssignedTab({
    required List<ExpoOrder> orders,
    required List<ExpoOrder> allBranchOrders,
    required bool isDark,
  }) {
    if (orders.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.group_outlined,
                size: 58,
                color: primaryBlue.withValues(alpha: 0.35),
              ),
              const SizedBox(height: 12),
              Text(
                'No Assigned Orders',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Orders assigned to your branch team will appear here.',
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
        return _buildOrderCard(
          order: orders[index],
          allBranchOrders: allBranchOrders,
          isDark: isDark,
          isUnassigned: false,
          isSelected: false,
        );
      },
    );
  }

  Widget _buildOrderCard({
    required ExpoOrder order,
    required List<ExpoOrder> allBranchOrders,
    required bool isDark,
    required bool isUnassigned,
    required bool isSelected,
    VoidCallback? onToggleSelect,
  }) {
    final locationParts =
        [order.place, order.district].where((s) => s.trim().isNotEmpty).toList();
    final locationStr = locationParts.join(', ');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: isSelected ? 3 : 1.5,
      color: isDark ? const Color(0xFF0F243E) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isSelected
              ? primaryBlue
              : (isDark
                  ? Colors.white12
                  : Colors.black.withValues(alpha: 0.06)),
          width: isSelected ? 1.8 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: isUnassigned ? onToggleSelect : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Checkbox (if unassigned) + Bill + Expo + Badge
              Row(
                children: [
                  if (isUnassigned) ...[
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: Checkbox(
                        value: isSelected,
                        activeColor: primaryBlue,
                        onChanged: (_) => onToggleSelect?.call(),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
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
                        'From Stall',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber.shade800,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),

              // Shop & Customer
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

              // Phone & Location
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
                        Text(
                          locationStr,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white70 : Colors.black87,
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
                          'Del: ${DateFormat('dd MMM yyyy').format(order.deliveryDate!)}',
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
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 10),

              // Items & Money Summary
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${order.items.length} Item${order.items.length != 1 ? 's' : ''} (${order.totalQty} pcs)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Total: ₹${order.totalAmount.toStringAsFixed(0)}  •  Adv: ₹${order.advanceAmount.toStringAsFixed(0)}  •  Bal: ₹${order.balanceAmount.toStringAsFixed(0)}',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Assignee Status + Assign / Reassign Button
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: (isUnassigned ? Colors.orange : primaryGreen)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isUnassigned
                                ? Icons.person_off_rounded
                                : Icons.person_rounded,
                            size: 15,
                            color:
                                isUnassigned ? Colors.orange : primaryGreen,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              isUnassigned
                                  ? 'Salesman: N/A'
                                  : 'Assigned: ${order.preferredSalesman}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: isUnassigned
                                    ? const Color(0xFFE65100)
                                    : (isDark
                                        ? primaryGreen
                                        : Colors.green.shade800),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: _isAssigning
                        ? null
                        : () => _openAssigneePickerSheet(
                              targetOrders: [order],
                              allBranchOrders: allBranchOrders,
                            ),
                    icon: Icon(
                      isUnassigned
                          ? Icons.person_add_alt_1_rounded
                          : Icons.swap_horiz_rounded,
                      size: 16,
                    ),
                    label: Text(
                      isUnassigned ? 'Assign' : 'Reassign',
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isUnassigned ? primaryBlue : Colors.teal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
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

  Widget _buildBulkAssignBar({
    required List<ExpoOrder> unassignedOrders,
    required List<ExpoOrder> allBranchOrders,
    required bool isDark,
  }) {
    final selectedOrders = unassignedOrders
        .where((o) => _selectedOrderIds.contains(o.id))
        .toList();
    if (selectedOrders.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F243E) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${selectedOrders.length} Order${selectedOrders.length != 1 ? 's' : ''} Selected',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ),
            TextButton(
              onPressed: () => setState(() => _selectedOrderIds.clear()),
              child: const Text('Clear'),
            ),
            const SizedBox(width: 6),
            ElevatedButton.icon(
              onPressed: _isAssigning
                  ? null
                  : () => _openAssigneePickerSheet(
                        targetOrders: selectedOrders,
                        allBranchOrders: allBranchOrders,
                      ),
              icon: _isAssigning
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.person_add_alt_1_rounded, size: 18),
              label: Text(
                'Assign ${selectedOrders.length} Selected Orders',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryGreen,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AssigneePickerSheet extends StatefulWidget {
  final String managerName;
  final String managerBranch;
  final int orderCount;
  final List<Map<String, dynamic>> teamMembers;
  final Map<String, int> activeOrderCounts;

  const _AssigneePickerSheet({
    required this.managerName,
    required this.managerBranch,
    required this.orderCount,
    required this.teamMembers,
    required this.activeOrderCounts,
  });

  @override
  State<_AssigneePickerSheet> createState() => _AssigneePickerSheetState();
}

class _AssigneePickerSheetState extends State<_AssigneePickerSheet> {
  String _query = '';

  String _roleLabel(String rawRole) {
    final r = rawRole.trim().toLowerCase();
    if (r == 'manager') return 'MANAGER';
    if (r == 'asst_manager' || r == 'asst manager' || r == 'assistant manager') {
      return 'ASST MANAGER';
    }
    return 'SALES';
  }

  Color _roleColor(String rawRole) {
    final r = rawRole.trim().toLowerCase();
    if (r == 'manager') return primaryBlue;
    if (r == 'asst_manager' || r == 'asst manager' || r == 'assistant manager') {
      return Colors.teal;
    }
    return primaryGreen;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filtered = _query.trim().isEmpty
        ? widget.teamMembers
        : widget.teamMembers.where((u) {
            final name = (u['username'] ?? '').toString().toLowerCase();
            final role = _roleLabel((u['role'] ?? '').toString()).toLowerCase();
            final q = _query.trim().toLowerCase();
            return name.contains(q) || role.contains(q);
          }).toList();

    final managerActiveCount =
        widget.activeOrderCounts[widget.managerName.trim().toLowerCase()] ?? 0;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.78,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF132238) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            Text(
              widget.orderCount == 1
                  ? 'Assign Order to Salesman'
                  : 'Assign ${widget.orderCount} Orders',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : const Color(0xFF0A1628),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Select a team member from ${widget.managerBranch} branch',
              style: TextStyle(
                fontSize: 12.5,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
            ),
            const SizedBox(height: 14),

            // Prominent Assign to Myself card
            Material(
              color: primaryBlue.withValues(alpha: isDark ? 0.25 : 0.08),
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => Navigator.of(context).pop(widget.managerName),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: primaryBlue, width: 1.4),
                  ),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        backgroundColor: primaryBlue,
                        radius: 20,
                        child: Icon(Icons.person_pin_rounded,
                            color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Assign to Myself (${widget.managerName})',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: isDark ? Colors.white : primaryBlue,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: primaryBlue,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'MANAGER',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '$managerActiveCount active orders',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: isDark
                                        ? Colors.white60
                                        : Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios_rounded,
                          size: 16, color: primaryBlue),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Search team members
            TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Search salesman or assistant manager...',
                hintStyle: const TextStyle(fontSize: 13),
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
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
            const SizedBox(height: 10),

            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        'No matching branch team members found.',
                        style: TextStyle(
                          color: isDark ? Colors.white54 : Colors.black54,
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final user = filtered[index];
                        final uname =
                            (user['username'] ?? 'User').toString().trim();
                        final rawRole = (user['role'] ?? 'sales').toString();
                        final rLabel = _roleLabel(rawRole);
                        final rColor = _roleColor(rawRole);
                        final activeCount =
                            widget.activeOrderCounts[uname.toLowerCase()] ?? 0;

                        return Material(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.04)
                              : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          child: ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            leading: CircleAvatar(
                              backgroundColor: rColor.withValues(alpha: 0.15),
                              child: Text(
                                uname.isNotEmpty
                                    ? uname[0].toUpperCase()
                                    : 'U',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: rColor,
                                ),
                              ),
                            ),
                            title: Text(
                              uname,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: rColor.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      rLabel,
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.bold,
                                        color: rColor,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '$activeCount active orders',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: isDark
                                          ? Colors.white54
                                          : Colors.black54,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            trailing: const Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 14,
                            ),
                            onTap: () => Navigator.of(context).pop(uname),
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
}
