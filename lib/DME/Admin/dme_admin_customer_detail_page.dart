import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../dme_constants.dart';
import '../dme_config.dart';

class DmeAdminCustomerDetailPage extends StatefulWidget {
  final Map<String, dynamic> customer;

  const DmeAdminCustomerDetailPage({
    super.key,
    required this.customer,
  });

  @override
  State<DmeAdminCustomerDetailPage> createState() => _DmeAdminCustomerDetailPageState();
}

class _DmeAdminCustomerDetailPageState extends State<DmeAdminCustomerDetailPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late Map<String, dynamic> _customer;

  bool _isLoading = true;
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _sales = [];
  Map<String, dynamic>? _reminder;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _customer = Map<String, dynamic>.from(widget.customer);
    _loadFullCustomerProfile();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _formatDate(dynamic date) {
    if (date == null) return 'N/A';
    if (date is DateTime) {
      return DateFormat('dd-MM-yyyy').format(date);
    }
    final str = date.toString().trim();
    if (str.isEmpty) return 'N/A';
    final parsed = DateTime.tryParse(str);
    if (parsed != null) {
      return DateFormat('dd-MM-yyyy').format(parsed);
    }
    return str;
  }

  Future<void> _loadFullCustomerProfile() async {
    final client = await DmeConfig.getClient();
    final customerId = _customer['id'];
    if (client == null || customerId == null) {
      setState(() => _isLoading = false);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final results = await Future.wait([
        // 1. Customer Branches Junction
        client
            .from('dme_customer_branches')
            .select('branch_id, category_id, customer_type_id, created_at')
            .eq('customer_id', customerId),

        // 2. Sales with detail products
        client
            .from('dme_sales')
            .select('id, date, purchased_branch, salesman, category_id, customer_type_id, uploaded_by, dme_sales_detail(products)')
            .eq('customer_id', customerId)
            .order('date', ascending: false),

        // 3. Current reminder
        client
            .from('dme_reminders')
            .select()
            .eq('customer_id', customerId)
            .maybeSingle(),
      ]);

      setState(() {
        _branches = List<Map<String, dynamic>>.from(results[0] as List);
        _sales = List<Map<String, dynamic>>.from(results[1] as List);
        _reminder = results[2] as Map<String, dynamic>?;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading customer profile: $e');
      setState(() => _isLoading = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final customerName = _customer['name'] ?? 'Unnamed Customer';
    final customerPhone = _customer['phone'] ?? 'N/A';
    final customerAddress = _customer['address'] ?? '';
    final salesman = _customer['salesman'] ?? '';
    final lastPurchaseDate = _customer['last_purchase_date'];

    return Scaffold(
      appBar: AppBar(
        title: Text(customerName, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) {
                return [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Customer Header Card
                          Card(
                            elevation: 3,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            child: Padding(
                              padding: const EdgeInsets.all(18.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      CircleAvatar(
                                        radius: 28,
                                        backgroundColor: const Color(0xFF005BAC).withValues(alpha: 0.1),
                                        foregroundColor: const Color(0xFF005BAC),
                                        child: const Icon(Icons.business_rounded, size: 30),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              customerName,
                                              style: theme.textTheme.titleMedium?.copyWith(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 18,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            if (salesman.isNotEmpty)
                                              Text('Salesman: $salesman', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                                            const SizedBox(height: 2),
                                            Text(
                                              'Last Purchase: ${_formatDate(lastPurchaseDate)}',
                                              style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Divider(height: 24),
                                  Row(
                                    children: [
                                      const Icon(Icons.phone_iphone_rounded, size: 18, color: Color(0xFF005BAC)),
                                      const SizedBox(width: 8),
                                      Text(customerPhone, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                    ],
                                  ),
                                  if (customerAddress.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Icon(Icons.location_on_rounded, size: 18, color: Colors.grey),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            customerAddress,
                                            style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.black87),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Quick Summary KPIs
                          Row(
                            children: [
                              Expanded(
                                child: _buildKpiCard(
                                  title: 'Branches',
                                  value: '${_branches.length}',
                                  icon: Icons.storefront_rounded,
                                  color: const Color(0xFF005BAC),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildKpiCard(
                                  title: 'Total Sales',
                                  value: '${_sales.length}',
                                  icon: Icons.receipt_long_rounded,
                                  color: const Color(0xFF8CC63F),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildKpiCard(
                                  title: 'Reminder',
                                  value: _reminder != null ? _formatDate(_reminder!['reminder_date']) : 'None',
                                  icon: Icons.alarm_on_rounded,
                                  color: Colors.orange,
                                  isDate: true,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // Active Reminder Card
                          if (_reminder != null)
                            Card(
                              elevation: 1,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              color: (_reminder!['status'] == 'completed')
                                  ? Colors.green.withValues(alpha: 0.1)
                                  : Colors.orange.withValues(alpha: 0.1),
                              child: Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: Row(
                                  children: [
                                    Icon(
                                      (_reminder!['status'] == 'completed')
                                          ? Icons.check_circle_outline_rounded
                                          : Icons.alarm_rounded,
                                      color: (_reminder!['status'] == 'completed') ? Colors.green[800] : Colors.orange[900],
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Reminder Due: ${_formatDate(_reminder!['reminder_date'])}  •  Status: ${(_reminder!['status'] ?? 'pending').toString().toUpperCase()}',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                              color: (_reminder!['status'] == 'completed') ? Colors.green[900] : Colors.orange[900],
                                            ),
                                          ),
                                          if ((_reminder!['remarks'] ?? '').toString().isNotEmpty)
                                            Text(
                                              'Notes: ${_reminder!['remarks']}',
                                              style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey[800]),
                                            ),
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
                  ),
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _SliverAppBarDelegate(
                      TabBar(
                        controller: _tabController,
                        labelColor: const Color(0xFF005BAC),
                        unselectedLabelColor: Colors.grey,
                        indicatorColor: const Color(0xFF005BAC),
                        indicatorWeight: 3,
                        tabs: [
                          Tab(text: 'Purchases (${_sales.length})', icon: const Icon(Icons.shopping_bag_rounded, size: 18)),
                          Tab(text: 'Branches & Types (${_branches.length})', icon: const Icon(Icons.hub_rounded, size: 18)),
                        ],
                      ),
                      color: isDark ? Colors.grey[900]! : Colors.white,
                    ),
                  ),
                ];
              },
              body: TabBarView(
                controller: _tabController,
                children: [
                  // Tab 1: Sales / Purchases Tab
                  _buildPurchasesTab(),

                  // Tab 2: Branches & Types Tab
                  _buildBranchesTab(),
                ],
              ),
            ),
    );
  }

  Widget _buildKpiCard({required String title, required String value, required IconData icon, required Color color, bool isDate = false}) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: isDate ? 12 : 16,
                color: color,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(title, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildPurchasesTab() {
    if (_sales.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long_outlined, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text('No purchase records found', style: TextStyle(color: Colors.grey[600], fontSize: 14)),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _sales.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final sale = _sales[index];
        final branchName = DmeConstants.getBranchName(sale['purchased_branch'] as int?);
        final categoryName = DmeConstants.getCategoryName(sale['category_id'] as int?);
        final typeName = DmeConstants.getCustomerTypeName(sale['customer_type_id'] as int?);
        final dateStr = sale['date']?.toString();
        final details = sale['dme_sales_detail'] as List?;
        final products = (details != null && details.isNotEmpty) ? details[0]['products'] as List? : null;

        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.event, size: 16, color: Color(0xFF005BAC)),
                        const SizedBox(width: 6),
                        Text(_formatDate(dateStr), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF005BAC).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        branchName,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF005BAC)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text('Category: $categoryName', style: TextStyle(fontSize: 12, color: Colors.grey[800], fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    Text('•  Type: $typeName', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                  ],
                ),
                if (products != null && products.isNotEmpty) ...[
                  const Divider(height: 16),
                  Text('Items Purchased:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey[600])),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: products.map((p) {
                      final item = p['item_name'] ?? '';
                      final qty = p['qty'] ?? '';
                      return Chip(
                        label: Text('$item  ($qty)', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        backgroundColor: const Color(0xFF8CC63F).withValues(alpha: 0.15),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBranchesTab() {
    if (_branches.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.storefront_outlined, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text('No branch connections registered', style: TextStyle(color: Colors.grey[600], fontSize: 14)),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _branches.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final b = _branches[index];
        final branchName = DmeConstants.getBranchName(b['branch_id'] as int?);
        final categoryName = DmeConstants.getCategoryName(b['category_id'] as int?);
        final typeName = DmeConstants.getCustomerTypeName(b['customer_type_id'] as int?);

        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: const Color(0xFF005BAC).withValues(alpha: 0.1),
              foregroundColor: const Color(0xFF005BAC),
              child: const Icon(Icons.store_mall_directory_rounded),
            ),
            title: Text(branchName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 2),
                Text('Category: $categoryName', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                Text('Customer Type: $typeName', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar _tabBar;
  final Color color;

  _SliverAppBarDelegate(this._tabBar, {required this.color});

  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: color,
      child: _tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) {
    return false;
  }
}
