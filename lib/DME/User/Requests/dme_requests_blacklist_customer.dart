import 'package:flutter/material.dart';

/// Form component for requesting to blacklist a customer so future Excel uploads
/// store sales data without generating call reminders.
///
/// Reason is mandatory.
class DmeRequestsBlacklistCustomerForm extends StatelessWidget {
  final Map<String, dynamic> reminder;
  final TextEditingController reasonController;

  const DmeRequestsBlacklistCustomerForm({
    super.key,
    required this.reminder,
    required this.reasonController,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final customerName = (reminder['customer_name'] ?? 'Customer').toString().trim();
    final customerPhone = (reminder['customer_phone'] ?? 'N/A').toString().trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Info banner
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.block_rounded, color: Colors.red.shade700, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Note: When approved by Admin, this customer will be marked as blacklisted. Future Excel uploads will continue to store their purchase data, but no call reminders will be created.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: isDark ? Colors.red[200] : Colors.red.shade900,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Customer Display
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
              Icon(Icons.person_off_rounded, size: 22, color: Colors.red.shade700),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Customer to Blacklist',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      customerName.isEmpty ? 'Customer' : customerName,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    if (customerPhone.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Phone: $customerPhone',
                        style: TextStyle(fontSize: 12, color: isDark ? Colors.grey[400] : Colors.grey[700]),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Mandatory Reason Field
        TextFormField(
          controller: reasonController,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: 'Reason for Blacklisting Customer *',
            hintText: 'e.g. Customer requested not to receive follow-up calls, closed business, do not disturb...',
            prefixIcon: const Icon(Icons.report_problem_outlined),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            helperText: 'Provide a clear reason for Admin review.',
            helperMaxLines: 2,
          ),
          validator: (val) {
            if (val == null || val.trim().isEmpty) {
              return 'Please enter the reason for blacklisting this customer';
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

