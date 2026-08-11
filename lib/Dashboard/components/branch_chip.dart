import 'package:flutter/material.dart';

const Color primaryBlue = Color(0xFF005BAC);

class BranchChip extends StatelessWidget {
  final List<String> branches;
  final String? selectedBranch;
  final bool isDark;
  final ValueChanged<String?> onChanged;

  const BranchChip({
    super.key,
    required this.branches,
    required this.selectedBranch,
    required this.isDark,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      offset: const Offset(0, 40),
      itemBuilder: (context) => branches
          .map((b) => PopupMenuItem<String>(
                value: b,
                child: Text(b),
              ))
          .toList(),
      onSelected: onChanged,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: (isDark ? Colors.white : primaryBlue).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: (isDark ? Colors.white : primaryBlue).withValues(alpha: 0.15),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              selectedBranch ?? 'Branch',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : primaryBlue,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 16,
              color: isDark ? Colors.white54 : primaryBlue,
            ),
          ],
        ),
      ),
    );
  }
}
