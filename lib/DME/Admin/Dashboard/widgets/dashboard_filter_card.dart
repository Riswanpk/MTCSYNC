import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../dme_constants.dart';

class DashboardFilterCard extends StatelessWidget {
  final DateTime startDate;
  final DateTime endDate;
  final int? selectedBranchId;
  final List<int> assignedBranches;
  final VoidCallback onPickDateRange;
  final ValueChanged<int?> onBranchChanged;

  const DashboardFilterCard({
    super.key,
    required this.startDate,
    required this.endDate,
    required this.selectedBranchId,
    required this.assignedBranches,
    required this.onPickDateRange,
    required this.onBranchChanged,
  });

  String _formatDate(DateTime date) {
    return DateFormat('dd-MM-yyyy').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.tune_rounded,
                      color: Color(0xFF005BAC),
                      size: 20,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Dashboard Filters',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
                InkWell(
                  onTap: onPickDateRange,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF005BAC).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFF005BAC).withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.calendar_month_rounded,
                          size: 16,
                          color: Color(0xFF005BAC),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${_formatDate(startDate)} - ${_formatDate(endDate)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: Color(0xFF005BAC),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Branch Selector
            Row(
              children: [
                const Icon(Icons.storefront_rounded, size: 20, color: Colors.grey),
                const SizedBox(width: 8),
                const Text(
                  'Branch:',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[850] : Colors.grey[100],
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int?>(
                        value: selectedBranchId,
                        isExpanded: true,
                        items: [
                          DropdownMenuItem<int?>(
                            value: null,
                            child: Text(
                              assignedBranches.isNotEmpty
                                  ? 'All Assigned Branches'
                                  : 'All Branches',
                            ),
                          ),
                          ...(assignedBranches.isNotEmpty
                                  ? DmeConstants.branches.where(
                                      (b) => assignedBranches.contains(b.id),
                                    )
                                  : DmeConstants.branches)
                              .map((b) {
                            return DropdownMenuItem<int?>(
                              value: b.id,
                              child: Text(b.name),
                            );
                          }),
                        ],
                        onChanged: onBranchChanged,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
