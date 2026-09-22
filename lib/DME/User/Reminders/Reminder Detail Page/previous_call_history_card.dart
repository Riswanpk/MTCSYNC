import 'package:flutter/material.dart';
import '../../../Misc/dme_constants.dart';

class PreviousCallHistoryCard extends StatelessWidget {
  final List<Map<String, dynamic>> callHistory;
  final bool isLoadingCallHistory;
  final String Function(dynamic) formatDate;
  final String Function(dynamic) getUserDisplayName;

  const PreviousCallHistoryCard({
    super.key,
    required this.callHistory,
    required this.isLoadingCallHistory,
    required this.formatDate,
    required this.getUserDisplayName,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (isLoadingCallHistory) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(8.0),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (callHistory.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.history_edu_rounded, size: 20, color: Color(0xFF005BAC)),
                const SizedBox(width: 8),
                Text(
                  'Previous Call History (${callHistory.length})',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: callHistory.length,
              separatorBuilder: (_, __) => const Divider(height: 16),
              itemBuilder: (context, idx) {
                final h = callHistory[idx];
                final calledTs = h['called_timestamp'] ?? h['updated_at'];
                final dur = h['call_duration'] as int?;
                final remRemarks = h['remarks']?.toString() ?? '';
                final bId = h['last_purchase_branch'] as int?;
                final bName = DmeConstants.getBranchName(bId);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          formatDate(calledTs),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        Row(
                          children: [
                            if (dur != null && dur > 0) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.green.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '${dur}s',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF005BAC).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                bName,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF005BAC),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (remRemarks.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        remRemarks,
                        style: TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: isDark ? Colors.white70 : Colors.grey[800],
                        ),
                      ),
                    ],
                    if (h['called_by'] != null && h['called_by'].toString().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.person_outline_rounded, size: 12, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(
                            'Called by: ${getUserDisplayName(h['called_by'])}',
                            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ],
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
