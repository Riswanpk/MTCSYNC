import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Form component for requesting Admin approval to mark a reminder call as completed.
class DmeRequestsMarkCallAsCompletedForm extends StatelessWidget {
  final TextEditingController callDurationController;
  final TextEditingController completionRemarksController;
  final TextEditingController completionReasonController;

  const DmeRequestsMarkCallAsCompletedForm({
    super.key,
    required this.callDurationController,
    required this.completionRemarksController,
    required this.completionReasonController,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Notice banner
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.purple.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.purple.withValues(alpha: 0.3)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, color: Colors.purple.shade700, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Enter call duration and remarks. This request submission time is recorded as the call timestamp. Upon Admin approval, this reminder will be marked as Completed and attributed to your user stats.',
                  style: TextStyle(fontSize: 12.5, height: 1.35, color: Colors.purple.shade900),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Call Duration field
        TextFormField(
          controller: callDurationController,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: 'Call Duration (in seconds) *',
            hintText: 'e.g. 45',
            prefixIcon: const Icon(Icons.timer_outlined),
            suffixText: 'sec',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
          validator: (val) {
            if (val == null || val.trim().isEmpty) {
              return 'Please enter the call duration in seconds';
            }
            final dur = int.tryParse(val.trim());
            if (dur == null || dur <= 0) {
              return 'Call duration must be greater than 0 seconds';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),

        // Remarks field
        TextFormField(
          controller: completionRemarksController,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: 'Call Remarks *',
            hintText: 'Enter discussion points, customer feedback, next purchase plan...',
            prefixIcon: const Icon(Icons.rate_review_outlined),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
          validator: (val) {
            if (val == null || val.trim().isEmpty) {
              return 'Please enter the call remarks';
            }
            if (val.trim().length < 3) {
              return 'Please provide more details in remarks';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),

        // Reason / Note field (Optional)
        TextFormField(
          controller: completionReasonController,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: 'Reason for Approval Request (Optional)',
            hintText: 'e.g. Called from alternate device / landline, or call log was not detected',
            prefixIcon: const Icon(Icons.notes_rounded),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ],
    );
  }
}
