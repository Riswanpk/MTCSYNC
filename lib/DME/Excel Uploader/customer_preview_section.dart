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
                    label: Text('Resolve (${conflicts.length})', style: const TextStyle(color: Colors.orange, fontSize: 12)),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // Filter chips & Search
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: Text('All (${customerList.length})', style: const TextStyle(fontSize: 12)),
                  selected: customerFilter == 'all',
                  onSelected: (_) => onFilterChanged('all'),
                ),
                ChoiceChip(
                  label: Text('New (${customerList.where((c) => !c.isExisting).length})', style: const TextStyle(fontSize: 12)),
                  selected: customerFilter == 'new',
                  selectedColor: Colors.green.withValues(alpha: 0.2),
                  onSelected: (_) => onFilterChanged('new'),
                ),
                ChoiceChip(
                  label: Text('Existing (${customerList.where((c) => c.isExisting).length})', style: const TextStyle(fontSize: 12)),
                  selected: customerFilter == 'existing',
                  selectedColor: Colors.blue.withValues(alpha: 0.2),
                  onSelected: (_) => onFilterChanged('existing'),
                ),
                if (conflicts.isNotEmpty)
                  ChoiceChip(
                    label: Text('Conflicts (${conflicts.length})', style: const TextStyle(fontSize: 12)),
                    selected: customerFilter == 'conflict',
                    selectedColor: Colors.orange.withValues(alpha: 0.2),
                    onSelected: (_) => onFilterChanged('conflict'),
                  ),
              ],
            ),
            const SizedBox(height: 8),

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
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: cust.isExisting
                                    ? (cust.hasNameConflict ? Colors.orange : Colors.blue)
                                    : Colors.green,
                                foregroundColor: Colors.white,
                                child: Icon(
                                  cust.isExisting
                                      ? (cust.hasNameConflict ? Icons.warning_amber : Icons.how_to_reg)
                                      : Icons.person_add,
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
                                            color: cust.isExisting
                                                ? (cust.hasNameConflict
                                                    ? Colors.orange.withValues(alpha: 0.15)
                                                    : Colors.blue.withValues(alpha: 0.15))
                                                : Colors.green.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(
                                              color: cust.isExisting
                                                  ? (cust.hasNameConflict ? Colors.orange : Colors.blue)
                                                  : Colors.green,
                                              width: 0.8,
                                            ),
                                          ),
                                          child: Text(
                                            cust.isExisting
                                                ? (cust.hasNameConflict ? 'Duplicate' : 'Existing')
                                                : 'New Customer',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: cust.isExisting
                                                  ? (cust.hasNameConflict ? Colors.orange[800] : Colors.blue[800])
                                                  : Colors.green[800],
                                            ),
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
                                    if (cust.hasNameConflict) ...[
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          'Known Name: "${cust.existingDbName}" vs Excel Name: "${cust.partyName}"',
                                          style: const TextStyle(fontSize: 11, color: Colors.deepOrange),
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
