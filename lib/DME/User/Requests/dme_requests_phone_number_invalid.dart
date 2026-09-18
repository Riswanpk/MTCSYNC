import 'package:flutter/material.dart';

/// Form component for reporting an invalid/unreachable phone number
/// and requesting an update from Admin.
///
/// Note: As per requirement, user is NOT asked for the new phone number;
/// only the reason is collected here. Admin will enter the new number upon approval.
class DmeRequestsPhoneNumberInvalidForm extends StatelessWidget {
  final Map<String, dynamic> reminder;
  final TextEditingController reasonController;

  const DmeRequestsPhoneNumberInvalidForm({
    super.key,
    required this.reminder,
    required this.reasonController,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final currentPhone = (reminder['customer_phone'] ?? 'N/A').toString().trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Notice banner
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lock_clock_rounded, color: Colors.orange, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Note: Once submitted, this reminder will be greyed out and locked until Admin verifies and updates the customer phone number.',
                  style: TextStyle(fontSize: 12.5, height: 1.35, color: Colors.deepOrange),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Current Phone Display
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isDark ? Colors.grey[850] : Colors.grey[100],
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.phone_locked_rounded, size: 20, color: Colors.orange.shade800),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Current Phone Number',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    currentPhone.isEmpty ? 'N/A' : currentPhone,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Reason field
        TextFormField(
          controller: reasonController,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: 'Reason for Number Change / Issue *',
            hintText: 'e.g. Wrong number, customer unreachable, switched SIM, invalid digits...',
            prefixIcon: const Icon(Icons.edit_note_rounded),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            helperText: 'Admin will enter and confirm the new number upon approving this request.',
            helperMaxLines: 2,
          ),
          validator: (val) {
            if (val == null || val.trim().isEmpty) {
              return 'Please enter reason for number change';
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
}
