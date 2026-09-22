import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../Misc/dme_constants.dart';

class PurchaseHistoryCard extends StatelessWidget {
  final List<Map<String, dynamic>> salesHistory;
  final bool isLoadingHistory;
  final bool isPurchaseHistoryExpanded;
  final VoidCallback onToggleExpanded;
  final Map<String, dynamic> reminder;
  final String Function(dynamic) formatDate;

  const PurchaseHistoryCard({
    super.key,
    required this.salesHistory,
    required this.isLoadingHistory,
    required this.isPurchaseHistoryExpanded,
    required this.onToggleExpanded,
    required this.reminder,
    required this.formatDate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onToggleExpanded,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.shopping_bag_outlined, size: 20, color: Color(0xFF005BAC)),
                        const SizedBox(width: 8),
                        Text(
                          'Purchase History (${salesHistory.length})',
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    AnimatedRotation(
                      turns: isPurchaseHistoryExpanded ? 0.5 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 24,
                        color: Color(0xFF005BAC),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (isPurchaseHistoryExpanded) ...[
              const SizedBox(height: 12),
              if (isLoadingHistory)
                const Center(child: Padding(padding: EdgeInsets.all(12.0), child: CircularProgressIndicator()))
              else if (salesHistory.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Center(
                    child: Text(
                      'No previous sales found.',
                      style: TextStyle(color: Colors.grey[600], fontSize: 13),
                    ),
                  ),
                )
              else
                Builder(
                  builder: (context) {
                    final remDateStr = reminder['last_purchase_date']?.toString().trim();
                    final remDate = remDateStr != null && remDateStr.isNotEmpty
                        ? DateTime.tryParse(remDateStr)?.toLocal()
                        : null;
                    final remDateFormatted = remDate != null ? DateFormat('yyyy-MM-dd').format(remDate) : remDateStr;

                    int currentSaleIndex = -1;
                    if (remDateFormatted != null && remDateFormatted.isNotEmpty) {
                      currentSaleIndex = salesHistory.indexWhere((s) {
                        final sDateStr = s['date']?.toString().trim();
                        if (sDateStr == null || sDateStr.isEmpty) return false;
                        final sDate = DateTime.tryParse(sDateStr)?.toLocal();
                        final sDateFormatted = sDate != null ? DateFormat('yyyy-MM-dd').format(sDate) : sDateStr;
                        return sDateFormatted == remDateFormatted;
                      });
                    }

                    if (currentSaleIndex == -1 && salesHistory.isNotEmpty) {
                      currentSaleIndex = 0;
                    }

                    final Map<String, dynamic>? currentSale =
                        currentSaleIndex >= 0 ? salesHistory[currentSaleIndex] : null;
                    final List<Map<String, dynamic>> previousSales = [];
                    for (int i = 0; i < salesHistory.length; i++) {
                      if (i != currentSaleIndex) {
                        previousSales.add(salesHistory[i]);
                      }
                    }

                    Widget buildProductsWrap(Map<String, dynamic> s) {
                      final details = s['dme_sales_detail'] as List?;
                      dynamic rawProducts;
                      if (details != null && details.isNotEmpty) {
                        rawProducts = details[0]['products'];
                      } else if (s['dme_sales_detail'] is Map) {
                        rawProducts = (s['dme_sales_detail'] as Map)['products'];
                      }

                      List<dynamic> productsList = [];
                      if (rawProducts is List) {
                        productsList = rawProducts;
                      } else if (rawProducts is Map) {
                        productsList = [rawProducts];
                      }

                      if (productsList.isEmpty) {
                        return Text(
                          'No item details recorded',
                          style: TextStyle(fontSize: 12, color: Colors.grey[500], fontStyle: FontStyle.italic),
                        );
                      }

                      return Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: productsList.map((p) {
                          String itemName = '';
                          String qty = '';
                          if (p is Map) {
                            itemName = p['item_name']?.toString() ?? '';
                            qty = p['qty']?.toString() ?? '';
                          } else {
                            itemName = p.toString();
                          }
                          final label = qty.isNotEmpty ? '$itemName : $qty' : itemName;
                          return Chip(
                            label: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            visualDensity: VisualDensity.compact,
                            backgroundColor:
                                isDark ? Colors.grey[800] : const Color(0xFF8CC63F).withValues(alpha: 0.15),
                            side: BorderSide(
                              color: isDark ? Colors.grey[700]! : Colors.green.withValues(alpha: 0.2),
                            ),
                          );
                        }).toList(),
                      );
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Current Reminder's Purchase
                        if (currentSale != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF005BAC).withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.star_rounded, size: 14, color: Color(0xFF005BAC)),
                                const SizedBox(width: 4),
                                Text(
                                  'Current Purchase (${formatDate(currentSale['date'] ?? reminder['last_purchase_date'])})',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF005BAC),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          buildProductsWrap(currentSale),
                        ],

                        // Previous Purchases
                        if (previousSales.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          const Divider(height: 1),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const Icon(Icons.history_rounded, size: 16, color: Colors.grey),
                              const SizedBox(width: 6),
                              Text(
                                'Previous Purchases (${previousSales.length})',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.grey[300] : Colors.grey[700],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: previousSales.length,
                            separatorBuilder: (_, __) => const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8.0),
                              child: Divider(height: 1),
                            ),
                            itemBuilder: (context, idx) {
                              final s = previousSales[idx];
                              final saleDate = formatDate(s['date']);
                              final catId = int.tryParse(s['category_id']?.toString() ?? '');
                              final typeId = int.tryParse(s['customer_type_id']?.toString() ?? '');
                              final catName = DmeConstants.getCategoryName(catId);
                              final typeName = DmeConstants.getCustomerTypeName(typeId);

                              return Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.grey[900] : Colors.grey[50],
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 4,
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      children: [
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.calendar_today_rounded, size: 13, color: Colors.grey[600]),
                                            const SizedBox(width: 4),
                                            Text(
                                              saleDate,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                        Text('•', style: TextStyle(fontSize: 11, color: Colors.grey[400])),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF005BAC).withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            'Cat: $catName',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF005BAC),
                                            ),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: (typeName == 'PREMIUM')
                                                ? Colors.amber.withValues(alpha: 0.15)
                                                : Colors.grey.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            'Type: $typeName',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: (typeName == 'PREMIUM')
                                                  ? (isDark ? Colors.amber[300] : Colors.amber[900])
                                                  : (isDark ? Colors.grey[300] : Colors.grey[700]),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    buildProductsWrap(s),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                      ],
                    );
                  },
                ),
            ],
          ],
        ),
      ),
    );
  }
}
