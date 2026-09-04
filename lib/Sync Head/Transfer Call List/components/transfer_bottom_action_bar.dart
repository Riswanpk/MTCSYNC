import 'package:flutter/material.dart';
import '../models/transfer_constants.dart';

class TransferBottomActionBar extends StatelessWidget {
  final int selectedCount;
  final Map<String, dynamic>? selectedDestUser;
  final bool isReady;
  final VoidCallback onTransferPressed;
  final bool isDark;

  const TransferBottomActionBar({
    super.key,
    required this.selectedCount,
    required this.selectedDestUser,
    required this.isReady,
    required this.onTransferPressed,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final cardBg = isDark ? const Color(0xFF1E222A) : Colors.white;
    final destName = selectedDestUser != null
        ? (selectedDestUser!['username'] ?? selectedDestUser!['email'] ?? 'User B').toString()
        : null;
    final destBranch = selectedDestUser?['branch']?.toString() ?? '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black54 : Colors.black.withValues(alpha: 0.1),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [kTransferPrimaryBlue, Color(0xFF0288D1)],
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$selectedCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text('Selected', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  destName != null
                      ? '➔ $destName${destBranch.isNotEmpty ? ' ($destBranch)' : ''}'
                      : 'Select Destination User',
                  style: TextStyle(
                    fontSize: 12,
                    color: destName != null ? kTransferDestAccent : Colors.grey,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: isReady ? onTransferPressed : null,
              icon: const Icon(Icons.send_rounded, size: 16),
              label: const Text(
                'Transfer Now',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: kTransferPrimaryBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                disabledBackgroundColor: Colors.grey.withValues(alpha: 0.3),
                elevation: isReady ? 3 : 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
