import 'package:flutter/material.dart';
import '../models/transfer_constants.dart';
import 'styled_picker_modal.dart';

class TransferUserSelectorCard extends StatelessWidget {
  final String selectedMonthYear;
  final List<String> monthYears;
  final ValueChanged<String> onMonthChanged;

  final List<String> branches;
  final List<Map<String, dynamic>> allUsers;

  // User A (Source)
  final String? selectedSourceBranch;
  final Map<String, dynamic>? selectedSourceUser;
  final ValueChanged<String?> onSourceBranchChanged;
  final ValueChanged<Map<String, dynamic>?> onSourceUserChanged;

  // User B (Destination)
  final String? selectedDestBranch;
  final Map<String, dynamic>? selectedDestUser;
  final ValueChanged<String?> onDestBranchChanged;
  final ValueChanged<Map<String, dynamic>?> onDestUserChanged;

  final bool isDark;

  const TransferUserSelectorCard({
    super.key,
    required this.selectedMonthYear,
    required this.monthYears,
    required this.onMonthChanged,
    required this.branches,
    required this.allUsers,
    required this.selectedSourceBranch,
    required this.selectedSourceUser,
    required this.onSourceBranchChanged,
    required this.onSourceUserChanged,
    required this.selectedDestBranch,
    required this.selectedDestUser,
    required this.onDestBranchChanged,
    required this.onDestUserChanged,
    required this.isDark,
  });

  List<Map<String, dynamic>> _filterUsers(String? branch, {String? excludeEmail}) {
    if (branch == null || branch.isEmpty) return [];
    return allUsers.where((u) {
      final uBranch = (u['branch'] ?? '').toString().trim();
      if (uBranch.toLowerCase() != branch.toLowerCase()) return false;
      if (excludeEmail != null && excludeEmail.isNotEmpty) {
        final uEmail = (u['email'] ?? '').toString().trim();
        if (uEmail.toLowerCase() == excludeEmail.toLowerCase()) return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final cardBg = isDark ? const Color(0xFF1E222A) : Colors.white;

    final isSourceUserEnabled = selectedSourceBranch != null && selectedSourceBranch!.isNotEmpty;
    final isDestUserEnabled = selectedDestBranch != null && selectedDestBranch!.isNotEmpty;

    final sourceAvailableUsers = _filterUsers(selectedSourceBranch);
    final destAvailableUsers = _filterUsers(
      selectedDestBranch,
      excludeEmail: selectedSourceUser?['email'],
    );

    final sourceUserName = selectedSourceUser != null
        ? (selectedSourceUser!['username'] ?? selectedSourceUser!['email'] ?? 'User A').toString()
        : null;
    final destUserName = selectedDestUser != null
        ? (selectedDestUser!['username'] ?? selectedDestUser!['email'] ?? 'User B').toString()
        : null;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black38 : const Color(0xFF90A4AE).withValues(alpha: 0.15),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Month Selector Row with Custom Modal Trigger
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [const Color(0xFF1F2937), const Color(0xFF111827)]
                    : [const Color(0xFFE8F0FE), const Color(0xFFF1F5F9)],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kTransferPrimaryBlue.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: kTransferPrimaryBlue.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.calendar_month_rounded, size: 16, color: kTransferPrimaryBlue),
                ),
                const SizedBox(width: 8),
                const Text('Month:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const Spacer(),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () async {
                    final selected = await StyledPickerModal.showMonthPicker(
                      context: context,
                      monthYears: monthYears,
                      selectedMonthYear: selectedMonthYear,
                    );
                    if (selected != null && selected != selectedMonthYear) {
                      onMonthChanged(selected);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF262C38) : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: kTransferPrimaryBlue.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          selectedMonthYear,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: kTransferPrimaryBlue,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: kTransferPrimaryBlue),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // User A and User B Side by Side with visual Transfer Arrow
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // User A (Source)
              Expanded(
                child: _buildPickerContainer(
                  title: 'User A (From)',
                  titleIcon: Icons.call_made_rounded,
                  accentColor: kTransferSourceAccent,
                  branchValue: selectedSourceBranch,
                  userNameValue: sourceUserName,
                  userPlaceholder: isSourceUserEnabled ? 'Select User A' : 'Select Branch first',
                  isUserEnabled: isSourceUserEnabled,
                  onSelectBranchTap: () async {
                    final b = await StyledPickerModal.showBranchPicker(
                      context: context,
                      branches: branches,
                      selectedBranch: selectedSourceBranch,
                      accentColor: kTransferSourceAccent,
                    );
                    if (b != null) {
                      onSourceBranchChanged(b);
                    }
                  },
                  onSelectUserTap: () async {
                    final u = await StyledPickerModal.showUserPicker(
                      context: context,
                      title: 'Select User A (Source)',
                      users: sourceAvailableUsers,
                      selectedUser: selectedSourceUser,
                      accentColor: kTransferSourceAccent,
                    );
                    if (u != null) {
                      onSourceUserChanged(u);
                    }
                  },
                ),
              ),

              // Visual arrow indicator
              Padding(
                padding: const EdgeInsets.only(top: 28, left: 6, right: 6),
                child: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [kTransferSourceAccent, kTransferDestAccent],
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 14),
                ),
              ),

              // User B (Destination)
              Expanded(
                child: _buildPickerContainer(
                  title: 'User B (To)',
                  titleIcon: Icons.call_received_rounded,
                  accentColor: kTransferDestAccent,
                  branchValue: selectedDestBranch,
                  userNameValue: destUserName,
                  userPlaceholder: isDestUserEnabled ? 'Select User B' : 'Select Branch first',
                  isUserEnabled: isDestUserEnabled,
                  onSelectBranchTap: () async {
                    final b = await StyledPickerModal.showBranchPicker(
                      context: context,
                      branches: branches,
                      selectedBranch: selectedDestBranch,
                      accentColor: kTransferDestAccent,
                    );
                    if (b != null) {
                      onDestBranchChanged(b);
                    }
                  },
                  onSelectUserTap: () async {
                    final u = await StyledPickerModal.showUserPicker(
                      context: context,
                      title: 'Select User B (Destination)',
                      users: destAvailableUsers,
                      selectedUser: selectedDestUser,
                      accentColor: kTransferDestAccent,
                    );
                    if (u != null) {
                      onDestUserChanged(u);
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPickerContainer({
    required String title,
    required IconData titleIcon,
    required Color accentColor,
    required String? branchValue,
    required String? userNameValue,
    required String userPlaceholder,
    required bool isUserEnabled,
    required VoidCallback onSelectBranchTap,
    required VoidCallback onSelectUserTap,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: isDark ? 0.08 : 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: userNameValue != null
              ? accentColor.withValues(alpha: 0.5)
              : Colors.grey.withValues(alpha: 0.2),
          width: userNameValue != null ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(titleIcon, size: 14, color: accentColor),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: accentColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Styled Branch Selector
          StyledSelectorPill(
            label: 'Branch',
            value: branchValue,
            placeholder: 'Select Branch',
            leadingIcon: Icons.storefront_rounded,
            accentColor: accentColor,
            onTap: onSelectBranchTap,
            isDark: isDark,
          ),
          const SizedBox(height: 6),

          // Styled User Selector (Disabled until branch is selected)
          StyledSelectorPill(
            label: 'User',
            value: userNameValue,
            placeholder: userPlaceholder,
            leadingIcon: Icons.person_outline_rounded,
            accentColor: accentColor,
            onTap: onSelectUserTap,
            isDark: isDark,
            enabled: isUserEnabled,
          ),
        ],
      ),
    );
  }
}
