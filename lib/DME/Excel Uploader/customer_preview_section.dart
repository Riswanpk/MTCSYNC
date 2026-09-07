import 'package:flutter/material.dart';
import 'excel_uploader_models.dart';

class CustomerPreviewSection extends StatelessWidget {
  final List<ParsedCustomerItem> customerList;
  final List<CustomerConflict> conflicts;
  final String customerFilter;
  final String customerSearch;
  final ValueChanged<String> onFilterChanged;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onResolveConflictsPressed;

  const CustomerPreviewSection({
    super.key,
    required this.customerList,
    required this.conflicts,
    required this.customerFilter,
    required this.customerSearch,
    required this.onFilterChanged,
    required this.onSearchChanged,
    required this.onResolveConflictsPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final filteredCustomers = customerList.where((c) {
      if (customerFilter == 'new' && c.isExisting) return false;
      if (customerFilter == 'existing' && !c.isExisting) return false;
      if (customerFilter == 'conflict' && !c.hasNameConflict) return false;

      if (customerSearch.isNotEmpty) {
        final q = customerSearch.toLowerCase();
        final name = c.partyName.toLowerCase();
        final phone = c.phone.toLowerCase();
        return name.contains(q) || phone.contains(q);
      }
      return true;
    }).toList();

    final newCount = customerList.where((c) => !c.isExisting).length;
    final existingCount = customerList.where((c) => c.isExisting).length;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Transactions (${customerList.length})',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                if (conflicts.isNotEmpty)
                  TextButton.icon(
                    onPressed: onResolveConflictsPressed,
                    icon: const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
                    label: Text(
                      'Resolve Conflicts (${conflicts.length})',
                      style: const TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // Filter chips & Search with Color Theme
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                ChoiceChip(
                  label: Text('All (${customerList.length})', style: const TextStyle(fontSize: 12)),
                  selected: customerFilter == 'all',
                  onSelected: (_) => onFilterChanged('all'),
                ),
                ChoiceChip(
                  avatar: const Icon(Icons.table_chart_rounded, size: 14, color: Colors.green),
                  label: Text(
                    'New Excel ($newCount)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: customerFilter == 'new' ? FontWeight.bold : FontWeight.normal,
                      color: customerFilter == 'new' ? Colors.green[800] : null,
                    ),
                  ),
                  selected: customerFilter == 'new',
                  selectedColor: Colors.green.withValues(alpha: 0.2),
                  side: BorderSide(
                    color: customerFilter == 'new' ? Colors.green : Colors.grey.withValues(alpha: 0.3),
                  ),
                  onSelected: (_) => onFilterChanged('new'),
                ),
                ChoiceChip(
                  avatar: const Icon(Icons.storage_rounded, size: 14, color: Colors.red),
                  label: Text(
                    'Database Existing ($existingCount)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: customerFilter == 'existing' ? FontWeight.bold : FontWeight.normal,
                      color: customerFilter == 'existing' ? Colors.red[800] : null,
                    ),
                  ),
                  selected: customerFilter == 'existing',
                  selectedColor: Colors.red.withValues(alpha: 0.2),
                  side: BorderSide(
                    color: customerFilter == 'existing' ? Colors.red : Colors.grey.withValues(alpha: 0.3),
                  ),
                  onSelected: (_) => onFilterChanged('existing'),
                ),
                if (conflicts.isNotEmpty)
                  ChoiceChip(
                    avatar: const Icon(Icons.warning_amber_rounded, size: 14, color: Colors.orange),
                    label: Text(
                      'Conflicts (${conflicts.length})',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: customerFilter == 'conflict' ? FontWeight.bold : FontWeight.normal,
                        color: customerFilter == 'conflict' ? Colors.orange[800] : null,
                      ),
                    ),
                    selected: customerFilter == 'conflict',
                    selectedColor: Colors.orange.withValues(alpha: 0.2),
                    side: BorderSide(
                      color: customerFilter == 'conflict' ? Colors.orange : Colors.grey.withValues(alpha: 0.3),
                    ),
                    onSelected: (_) => onFilterChanged('conflict'),
                  ),
              ],
            ),
            const SizedBox(height: 10),

            TextField(
              decoration: InputDecoration(
                hintText: 'Search customer name or mobile...',
                prefixIcon: const Icon(Icons.search, size: 20),
                filled: true,
                fillColor: isDark ? Colors.grey[900] : Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              onChanged: onSearchChanged,
            ),
            const SizedBox(height: 12),

            // Customer List View
            Container(
              constraints: const BoxConstraints(maxHeight: 380),
              child: filteredCustomers.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Center(child: Text('No transactions match the filter')),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: filteredCustomers.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, idx) {
                        final cust = filteredCustomers[idx];
                        final isDb = cust.isExisting;
                        final hasConflict = cust.hasNameConflict;

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: isDb
                                    ? (hasConflict ? Colors.orange[700] : Colors.red[700])
                                    : Colors.green[700],
                                foregroundColor: Colors.white,
                                child: Icon(
                                  isDb
                                      ? (hasConflict ? Icons.warning_amber : Icons.storage_rounded)
                                      : Icons.table_chart_rounded,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            cust.partyName,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: isDb
                                                ? (hasConflict
                                                    ? Colors.orange.withValues(alpha: 0.15)
                                                    : Colors.red.withValues(alpha: 0.12))
                                                : Colors.green.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(
                                              color: isDb
                                                  ? (hasConflict ? Colors.orange : Colors.red.withValues(alpha: 0.5))
                                                  : Colors.green.withValues(alpha: 0.5),
                                              width: 0.8,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                isDb ? Icons.storage_rounded : Icons.table_chart_rounded,
                                                size: 11,
                                                color: isDb
                                                    ? (hasConflict ? Colors.orange[800] : Colors.red[800])
                                                    : Colors.green[800],
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                isDb
                                                    ? (hasConflict ? 'DB Conflict' : 'Database Record')
                                                    : 'Excel (New)',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: isDb
                                                      ? (hasConflict ? Colors.orange[800] : Colors.red[800])
                                                      : Colors.green[800],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Mobile: ${cust.phone}  •  Branch: ${cust.branchName}',
                                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                                    ),
                                    if (cust.address.isNotEmpty)
                                      Text(
                                        cust.address,
                                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    if (hasConflict) ...[
                                      const SizedBox(height: 6),
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.withValues(alpha: isDark ? 0.2 : 0.08),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                                  decoration: BoxDecoration(
                                                    color: Colors.red.withValues(alpha: 0.2),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(Icons.storage_rounded, size: 10, color: Colors.red[800]),
                                                      const SizedBox(width: 3),
                                                      Text(
                                                        'Database:',
                                                        style: TextStyle(
                                                          fontSize: 10,
                                                          fontWeight: FontWeight.bold,
                                                          color: Colors.red[800],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(width: 4),
                                                Expanded(
                                                  child: Text(
                                                    '"${cust.existingDbName}"',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.bold,
                                                      color: isDark ? Colors.red[200] : Colors.red[900],
                                                    ),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                                  decoration: BoxDecoration(
                                                    color: Colors.green.withValues(alpha: 0.2),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(Icons.table_chart_rounded, size: 10, color: Colors.green[800]),
                                                      const SizedBox(width: 3),
                                                      Text(
                                                        'Excel File:',
                                                        style: TextStyle(
                                                          fontSize: 10,
                                                          fontWeight: FontWeight.bold,
                                                          color: Colors.green[800],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(width: 4),
                                                Expanded(
                                                  child: Text(
                                                    '"${cust.partyName}"',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.bold,
                                                      color: isDark ? Colors.green[200] : Colors.green[900],
                                                    ),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
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

