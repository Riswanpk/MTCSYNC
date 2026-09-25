import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../Misc/dme_constants.dart';

class DashboardFilterCard extends StatelessWidget {
  final DateTime? startDate;
  final DateTime? endDate;
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

    final hasDateSelected = startDate != null && endDate != null;

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
                      color: hasDateSelected
                          ? const Color(0xFF005BAC).withValues(alpha: 0.08)
                          : Colors.grey.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: hasDateSelected
                            ? const Color(0xFF005BAC).withValues(alpha: 0.3)
                            : Colors.grey.shade400,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.calendar_month_rounded,
                          size: 16,
                          color: hasDateSelected
                              ? const Color(0xFF005BAC)
                              : (isDark ? Colors.grey[300] : Colors.grey[700]),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          hasDateSelected
                              ? '${_formatDate(startDate!)} - ${_formatDate(endDate!)}'
                              : 'Select Date Range',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: hasDateSelected
                                ? const Color(0xFF005BAC)
                                : (isDark ? Colors.grey[300] : Colors.grey[700]),
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
                        hint: const Text('Select Branch', style: TextStyle(fontSize: 13)),
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
