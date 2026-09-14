import 'package:flutter/material.dart';
import '../../../dme_constants.dart';

class CategoryDistributionCard extends StatelessWidget {
  final Map<int, int> salesByCategory;

  const CategoryDistributionCard({
    super.key,
    required this.salesByCategory,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = salesByCategory.values.fold<int>(0, (acc, v) => acc + v);

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Category Distribution',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            if (salesByCategory.isEmpty)
              const Center(
                child: Text(
                  'No category data in this period',
                  style: TextStyle(color: Colors.grey),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: salesByCategory.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, idx) {
                  final entry = salesByCategory.entries.toList()[idx];
                  final catName = DmeConstants.getCategoryName(entry.key);
                  final count = entry.value;
                  final percent = total > 0 ? (count / total) : 0.0;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            catName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            '$count (${(percent * 100).toStringAsFixed(0)}%)',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: percent,
                          minHeight: 8,
                          backgroundColor: Colors.grey[200],
                          valueColor: AlwaysStoppedAnimation<Color>(
                            idx % 2 == 0
                                ? const Color(0xFF005BAC)
                                : const Color(0xFF8CC63F),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
