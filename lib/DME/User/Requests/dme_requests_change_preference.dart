import 'package:flutter/material.dart';

/// Form component for requesting a communication preference change (Call / WhatsApp).
class DmeRequestsChangePreferenceForm extends StatelessWidget {
  final String selectedPreference;
  final ValueChanged<String> onPreferenceChanged;
  final TextEditingController reasonController;

  const DmeRequestsChangePreferenceForm({
    super.key,
    required this.selectedPreference,
    required this.onPreferenceChanged,
    required this.reasonController,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Select New Preference *',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildChoiceCard(
                context: context,
                value: 'Call',
                label: 'Call',
                icon: Icons.phone_in_talk_rounded,
                color: const Color(0xFF005BAC),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildChoiceCard(
                context: context,
                value: 'Whatsapp',
                label: 'WhatsApp',
                icon: Icons.chat_bubble_rounded,
                color: Colors.green,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),

        // Reason field
        TextFormField(
          controller: reasonController,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: 'Reason for Preference Change *',
            hintText: 'e.g. Customer requested contact only via WhatsApp during office hours',
            prefixIcon: const Icon(Icons.comment_outlined),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
          validator: (val) {
            if (val == null || val.trim().isEmpty) {
              return 'Please enter the reason for changing preference';
            }
            if (val.trim().length < 3) {
              return 'Please provide a more descriptive reason';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildChoiceCard({
    required BuildContext context,
    required String value,
    required String label,
    required IconData icon,
    required Color color,
  }) {
    final isSelected = selectedPreference.toLowerCase() == value.toLowerCase();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => onPreferenceChanged(value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: isDark ? 0.25 : 0.1)
              : (isDark ? Colors.grey[850] : Colors.grey[100]),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? color : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: isSelected ? color : Colors.grey),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? color : (isDark ? Colors.white70 : Colors.black87),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
