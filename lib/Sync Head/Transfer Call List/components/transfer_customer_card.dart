import 'package:flutter/material.dart';
import '../models/transfer_constants.dart';

class TransferCustomerCard extends StatelessWidget {
  final Map<String, dynamic> customer;
  final bool isSelected;
  final ValueChanged<bool?> onToggle;
  final bool isDark;

  const TransferCustomerCard({
    super.key,
    required this.customer,
    required this.isSelected,
    required this.onToggle,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final cardBg = isDark ? const Color(0xFF1E222A) : Colors.white;
    final name = (customer['name'] ?? 'Unnamed Customer').toString();
    final contact1 = (customer['contact1'] ?? customer['contact'] ?? '').toString();
    final contact2 = (customer['contact2'] ?? '').toString();
    final address = (customer['address'] ?? '').toString();
    final avatarColor = getCustomerAvatarColor(name);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: isSelected
            ? kTransferPrimaryBlue.withValues(alpha: isDark ? 0.25 : 0.08)
            : cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? kTransferPrimaryBlue : Colors.grey.withValues(alpha: 0.18),
          width: isSelected ? 2.0 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: isSelected
                ? kTransferPrimaryBlue.withValues(alpha: 0.15)
                : (isDark ? Colors.black26 : const Color(0xFF90A4AE).withValues(alpha: 0.08)),
            blurRadius: isSelected ? 8 : 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => onToggle(!isSelected),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Checkbox
              Checkbox(
                value: isSelected,
                activeColor: kTransferPrimaryBlue,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                onChanged: onToggle,
              ),

              // Avatar Circle
              Container(
                margin: const EdgeInsets.only(right: 12),
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [avatarColor, avatarColor.withValues(alpha: 0.7)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),

              // Customer Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),

                    // Phone numbers styled as mini tags
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (contact1.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF1E2D42) : const Color(0xFFE3F2FD),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.phone_rounded, size: 11, color: kTransferPrimaryBlue),
                                const SizedBox(width: 4),
                                Text(
                                  contact1,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: kTransferPrimaryBlue,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (contact2.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF2C2438) : const Color(0xFFF3E5F5),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.phone_iphone_rounded, size: 11, color: Colors.purple),
                                const SizedBox(width: 4),
                                Text(
                                  contact2,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.purple,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),

                    if (address.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.location_on_outlined, size: 13, color: Colors.grey),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              address,
                              style: const TextStyle(fontSize: 11, color: Colors.grey),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
