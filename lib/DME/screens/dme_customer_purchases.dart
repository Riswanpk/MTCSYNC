import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/dme_supabase_service.dart';
import '../models/dme_user.dart';
import '../models/dme_customer.dart';
import '../models/dme_sale.dart';

class DmeCustomerPurchasesPage extends StatefulWidget {
  final DmeCustomer customer;
  final DmeUser dmeUser;

  const DmeCustomerPurchasesPage({
    super.key,
    required this.customer,
    required this.dmeUser,
  });

  @override
  State<DmeCustomerPurchasesPage> createState() =>
      _DmeCustomerPurchasesPageState();
}

class _DmeCustomerPurchasesPageState extends State<DmeCustomerPurchasesPage> {
  final _svc = DmeSupabaseService.instance;
  List<DmeSale> _sales = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPurchases();
  }

  Future<void> _loadPurchases() async {
    try {
      setState(() => _loading = true);
      final sales = await _svc.getSalesForCustomer(widget.customer.id!);
      setState(() => _sales = sales);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading purchases: $e')),
        );
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd MMM yyyy');
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.customer.name} - Purchase History'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _sales.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.08),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.shopping_bag_rounded,
                            size: 48, color: Color(0xFF005BAC)),
                      ),
                      const SizedBox(height: 16),
                      const Text('No purchases found',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('This customer has not made any purchases',
                          style: TextStyle(color: Colors.grey[500])),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _sales.length,
                  itemBuilder: (_, i) {
                    final sale = _sales[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.grey[850] : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Date header
                            Row(
                              children: [
                                const Icon(Icons.calendar_today,
                                    size: 16, color: Color(0xFF005BAC)),
                                const SizedBox(width: 6),
                                Text(
                                  dateFmt.format(sale.date),
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF005BAC)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            // Sale details in a grid
                            if (sale.salesman != null)
                              _buildDetailRow('Salesman', sale.salesman!),
                            if (sale.category != null)
                              _buildDetailRow('Category', sale.category!),
                            if (sale.customerType != null)
                              _buildDetailRow(
                                  'Customer Type', sale.customerType!),
                            // Items count
                            _buildDetailRow(
                              'Items',
                              '${sale.items.length} product${sale.items.length != 1 ? 's' : ''}',
                            ),
                            if (sale.items.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              // Expandable items list
                              ExpansionTile(
                                title: const Text('View Items',
                                    style: TextStyle(fontSize: 12)),
                                tilePadding: EdgeInsets.zero,
                                children: [
                                  ...sale.items.map(
                                    (item) => Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 4, horizontal: 8),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.circle,
                                              size: 4, color: Colors.grey),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              item.productName,
                                              style:
                                                  const TextStyle(fontSize: 12),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Qty: ${item.quantity.toStringAsFixed(0)}',
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey[600],
                                                fontWeight: FontWeight.w600),
                                          ),
                                        ],
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
                  },
                ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
