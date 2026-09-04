import 'package:flutter/material.dart';
import '../models/transfer_constants.dart';

class TransferCustomerHeader extends StatelessWidget {
  final TextEditingController searchController;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;

  final int totalCount;
  final int selectedCount;

  final bool allFilteredSelected;
  final int filteredCount;
  final ValueChanged<bool?> onSelectAllToggle;

  final bool isDark;

  const TransferCustomerHeader({
    super.key,
    required this.searchController,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.totalCount,
    required this.selectedCount,
    required this.allFilteredSelected,
    required this.filteredCount,
    required this.onSelectAllToggle,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final cardBg = isDark ? const Color(0xFF1E222A) : Colors.white;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black38 : const Color(0xFF90A4AE).withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Search input
          TextField(
            controller: searchController,
            onChanged: onSearchChanged,
            decoration: InputDecoration(
              hintText: 'Search customer name or contact...',
              hintStyle: const TextStyle(fontSize: 12, color: Colors.grey),
              prefixIcon: const Icon(Icons.search_rounded, size: 20, color: kTransferPrimaryBlue),
              suffixIcon: searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      onPressed: onClearSearch,
                    )
                  : null,
              isDense: true,
              filled: true,
              fillColor: isDark ? const Color(0xFF262C38) : const Color(0xFFF1F5F9),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Divider(height: 12),

          // Master Checkbox & Selection Counter
          Row(
            children: [
              Checkbox(
                value: allFilteredSelected,
                activeColor: kTransferPrimaryBlue,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                onChanged: onSelectAllToggle,
              ),
              GestureDetector(
                onTap: () => onSelectAllToggle(!allFilteredSelected),
                child: Text(
                  allFilteredSelected ? 'Deselect All' : 'Select All ($filteredCount)',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      kTransferPrimaryBlue.withValues(alpha: 0.15),
                      kTransferPrimaryGreen.withValues(alpha: 0.15),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kTransferPrimaryBlue.withValues(alpha: 0.3)),
                ),
                child: Text(
                  '$selectedCount / $totalCount selected',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: kTransferPrimaryBlue,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
