import 'package:flutter/material.dart';

class DmeComplaintTypeSelector extends StatelessWidget {
  final String? selectedType; // 'Product' or 'Service'
  final ValueChanged<String> onTypeSelected;
  final bool showError;

  const DmeComplaintTypeSelector({
    super.key,
    required this.selectedType,
    required this.onTypeSelected,
    this.showError = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isProduct = selectedType == 'Product';
    final isService = selectedType == 'Service';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.category_rounded, color: Color(0xFF005BAC), size: 20),
            const SizedBox(width: 8),
            Text(
              'Complaint Type *',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: showError ? Colors.red : (isDark ? Colors.white : Colors.black87),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildTypeCard(
                context: context,
                type: 'Product',
                title: 'Product',
                subtitle: 'Goods, hardware, material defects or issues',
                icon: Icons.inventory_2_rounded,
                isSelected: isProduct,
                activeColor: const Color(0xFF005BAC),
                isDark: isDark,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _buildTypeCard(
                context: context,
                type: 'Service',
                title: 'Service',
                subtitle: 'Installation, staff, delivery or support issues',
                icon: Icons.miscellaneous_services_rounded,
                isSelected: isService,
                activeColor: const Color(0xFF8CC63F),
                isDark: isDark,
              ),
            ),
          ],
        ),
        if (showError) ...[
          const SizedBox(height: 6),
          const Padding(
            padding: EdgeInsets.only(left: 4),
            child: Text(
              'Please select a complaint type (Product or Service)',
              style: TextStyle(color: Colors.red, fontSize: 12),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTypeCard({
    required BuildContext context,
    required String type,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required Color activeColor,
    required bool isDark,
  }) {
    final bgColor = isSelected
        ? activeColor.withValues(alpha: isDark ? 0.25 : 0.12)
        : (isDark ? const Color(0xFF16253B) : Colors.grey.shade50);

    final borderColor = isSelected
        ? activeColor
        : (isDark ? Colors.white12 : Colors.grey.shade300);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onTypeSelected(type),
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: borderColor,
              width: isSelected ? 2 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: activeColor.withValues(alpha: 0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isSelected
                      ? activeColor
                      : (isDark ? Colors.white10 : Colors.grey.shade200),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 28,
                  color: isSelected
                      ? Colors.white
                      : (isDark ? Colors.white70 : Colors.grey.shade700),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isSelected
                      ? (isDark ? Colors.white : activeColor)
                      : (isDark ? Colors.white70 : Colors.black87),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.25,
                  color: isDark ? Colors.white54 : Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 8),
              Icon(
                isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                size: 20,
                color: isSelected ? activeColor : Colors.grey,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
