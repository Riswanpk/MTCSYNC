import 'package:flutter/material.dart';
import '../models/transfer_constants.dart';

/// A modern, styled selector button that replaces the default Flutter DropdownButton.
class StyledSelectorPill extends StatelessWidget {
  final String label;
  final String? value;
  final String placeholder;
  final IconData leadingIcon;
  final Color accentColor;
  final VoidCallback onTap;
  final bool isDark;
  final bool enabled;

  const StyledSelectorPill({
    super.key,
    required this.label,
    required this.value,
    required this.placeholder,
    required this.leadingIcon,
    required this.accentColor,
    required this.onTap,
    required this.isDark,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null && value!.isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: enabled ? 1.0 : 0.5,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: !enabled
                  ? (isDark ? const Color(0xFF181C24) : const Color(0xFFF5F6F8))
                  : (isDark ? const Color(0xFF242A36) : Colors.white),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: !enabled
                    ? Colors.grey.withValues(alpha: 0.15)
                    : (hasValue
                        ? accentColor.withValues(alpha: 0.7)
                        : Colors.grey.withValues(alpha: 0.25)),
                width: hasValue && enabled ? 1.4 : 1.0,
              ),
              boxShadow: enabled
                  ? [
                      BoxShadow(
                        color: hasValue
                            ? accentColor.withValues(alpha: 0.1)
                            : Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                Icon(
                  leadingIcon,
                  size: 15,
                  color: !enabled
                      ? Colors.grey.shade400
                      : (hasValue ? accentColor : Colors.grey.shade500),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    hasValue ? value! : placeholder,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: hasValue && enabled ? FontWeight.w600 : FontWeight.normal,
                      color: !enabled
                          ? Colors.grey.shade400
                          : (hasValue
                              ? (isDark ? Colors.white : Colors.black87)
                              : Colors.grey.shade500),
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  enabled ? Icons.keyboard_arrow_down_rounded : Icons.lock_outline_rounded,
                  size: enabled ? 18 : 13,
                  color: !enabled
                      ? Colors.grey.shade400
                      : (hasValue ? accentColor : Colors.grey.shade500),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Styled modal bottom sheet pickers for Month, Branch, and User.
class StyledPickerModal {
  /// Shows a custom styled Month picker bottom sheet.
  static Future<String?> showMonthPicker({
    required BuildContext context,
    required List<String> monthYears,
    required String selectedMonthYear,
  }) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E222A) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.65,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [kTransferPrimaryBlue, Color(0xFF0288D1)],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.calendar_month_rounded, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Select Target Month',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: monthYears.length,
                  itemBuilder: (context, index) {
                    final month = monthYears[index];
                    final isSelected = month == selectedMonthYear;

                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? kTransferPrimaryBlue.withValues(alpha: isDark ? 0.25 : 0.08)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? kTransferPrimaryBlue.withValues(alpha: 0.6)
                              : Colors.grey.withValues(alpha: 0.12),
                        ),
                      ),
                      child: ListTile(
                        dense: true,
                        leading: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? kTransferPrimaryBlue
                                : Colors.grey.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.calendar_today_rounded,
                            size: 14,
                            color: isSelected ? Colors.white : Colors.grey.shade600,
                          ),
                        ),
                        title: Text(
                          month,
                          style: TextStyle(
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            color: isSelected
                                ? kTransferPrimaryBlue
                                : (isDark ? Colors.white : Colors.black87),
                            fontSize: 14,
                          ),
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check_circle_rounded, color: kTransferPrimaryBlue, size: 20)
                            : null,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        onTap: () => Navigator.pop(ctx, month),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Shows a custom styled Branch picker bottom sheet.
  static Future<String?> showBranchPicker({
    required BuildContext context,
    required List<String> branches,
    required String? selectedBranch,
    required Color accentColor,
  }) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final allBranchOptions = branches;

    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E222A) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.6,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.storefront_rounded, color: accentColor, size: 20),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Select Branch',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Expanded(
                child: allBranchOptions.isEmpty
                    ? const Center(
                        child: Text(
                          'No branches found',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: allBranchOptions.length,
                        itemBuilder: (context, index) {
                          final branch = allBranchOptions[index];
                          final isSelected = branch == selectedBranch;

                          return Container(
                            margin: const EdgeInsets.symmetric(vertical: 3),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? accentColor.withValues(alpha: isDark ? 0.25 : 0.08)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected
                                    ? accentColor.withValues(alpha: 0.6)
                                    : Colors.grey.withValues(alpha: 0.12),
                              ),
                            ),
                            child: ListTile(
                              dense: true,
                              leading: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? accentColor
                                      : Colors.grey.withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.location_city_rounded,
                                  size: 14,
                                  color: isSelected ? Colors.white : Colors.grey.shade600,
                                ),
                              ),
                              title: Text(
                                branch,
                                style: TextStyle(
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                  color: isSelected
                                      ? accentColor
                                      : (isDark ? Colors.white : Colors.black87),
                                  fontSize: 13,
                                ),
                              ),
                              trailing: isSelected
                                  ? Icon(Icons.check_circle_rounded, color: accentColor, size: 20)
                                  : null,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              onTap: () => Navigator.pop(ctx, branch),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Shows a custom styled User picker bottom sheet with search and avatar icons.
  static Future<Map<String, dynamic>?> showUserPicker({
    required BuildContext context,
    required String title,
    required List<Map<String, dynamic>> users,
    required Map<String, dynamic>? selectedUser,
    required Color accentColor,
  }) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        String searchQuery = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filteredUsers = users.where((u) {
              if (searchQuery.trim().isEmpty) return true;
              final query = searchQuery.toLowerCase().trim();
              final name = (u['username'] ?? '').toString().toLowerCase();
              final email = (u['email'] ?? '').toString().toLowerCase();
              final branch = (u['branch'] ?? '').toString().toLowerCase();
              return name.contains(query) || email.contains(query) || branch.contains(query);
            }).toList();

            return Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E222A) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.75,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.person_search_rounded, color: accentColor, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${filteredUsers.length} users',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: accentColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Search input
                  TextField(
                    autofocus: false,
                    onChanged: (val) {
                      setModalState(() {
                        searchQuery = val;
                      });
                    },
                    decoration: InputDecoration(
                      hintText: 'Search by name, email or branch...',
                      hintStyle: const TextStyle(fontSize: 12, color: Colors.grey),
                      prefixIcon: Icon(Icons.search_rounded, size: 20, color: accentColor),
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
                  const SizedBox(height: 10),
                  const Divider(height: 1),
                  const SizedBox(height: 6),

                  // Users List
                  Expanded(
                    child: filteredUsers.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.search_off_rounded, size: 40, color: Colors.grey.shade400),
                                  const SizedBox(height: 8),
                                  const Text('No users found', style: TextStyle(color: Colors.grey)),
                                ],
                              ),
                            ),
                          )
                        : ListView.builder(
                            itemCount: filteredUsers.length,
                            itemBuilder: (context, index) {
                              final user = filteredUsers[index];
                              final name = (user['username'] ?? user['email'] ?? 'User').toString();
                              final email = (user['email'] ?? '').toString();
                              final branch = (user['branch'] ?? '').toString();
                              final isSelected = selectedUser != null &&
                                  (selectedUser['email'] ?? '').toString().toLowerCase() ==
                                      email.toLowerCase();

                              return Container(
                                margin: const EdgeInsets.symmetric(vertical: 3),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? accentColor.withValues(alpha: isDark ? 0.25 : 0.08)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isSelected
                                        ? accentColor.withValues(alpha: 0.6)
                                        : Colors.grey.withValues(alpha: 0.12),
                                  ),
                                ),
                                child: ListTile(
                                  dense: true,
                                  leading: Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [accentColor, accentColor.withValues(alpha: 0.7)],
                                      ),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: Text(
                                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                  ),
                                  title: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          name,
                                          style: TextStyle(
                                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                            fontSize: 13,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (branch.isNotEmpty)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: accentColor.withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            branch,
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: accentColor,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  subtitle: email.isNotEmpty
                                      ? Text(
                                          email,
                                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                                          overflow: TextOverflow.ellipsis,
                                        )
                                      : null,
                                  trailing: isSelected
                                      ? Icon(Icons.check_circle_rounded, color: accentColor, size: 20)
                                      : null,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  onTap: () => Navigator.pop(ctx, user),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
