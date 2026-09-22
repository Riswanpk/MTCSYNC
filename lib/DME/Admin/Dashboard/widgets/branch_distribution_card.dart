import 'package:flutter/material.dart';
import '../../../Misc/dme_constants.dart';

class BranchDistributionCard extends StatelessWidget {
  final Map<int, int> salesByBranch;

  const BranchDistributionCard({
    super.key,
    required this.salesByBranch,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (salesByBranch.isEmpty) {
      return const SizedBox.shrink();
    }

    final total = salesByBranch.values.fold<int>(0, (acc, v) => acc + v);

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Branch Distribution',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: salesByBranch.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, idx) {
                final entry = salesByBranch.entries.toList()[idx];
                final branchName = DmeConstants.getBranchName(entry.key);
                final count = entry.value;
                final percent = total > 0 ? (count / total) : 0.0;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          branchName,
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
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF005BAC),
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
