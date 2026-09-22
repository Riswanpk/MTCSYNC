import 'package:flutter/material.dart';

class CallRemarksCard extends StatelessWidget {
  final TextEditingController remarksController;
  final bool callMade;
  final int? callDuration;
  final bool isCompleted;
  final bool hasPendingRequest;
  final String? pendingRequestType;
  final bool isSaving;
  final VoidCallback onSaveAndComplete;

  const CallRemarksCard({
    super.key,
    required this.remarksController,
    required this.callMade,
    required this.callDuration,
    required this.isCompleted,
    required this.hasPendingRequest,
    required this.pendingRequestType,
    required this.isSaving,
    required this.onSaveAndComplete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  callMade ? Icons.check_circle : Icons.lock_outline_rounded,
                  size: 20,
                  color: callMade ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  'Call Remarks',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: callMade ? null : Colors.grey,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (hasPendingRequest) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.amber.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.pending_actions_rounded,
                      color: Colors.amber,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        pendingRequestType == 'phone_number_change'
                            ? 'A phone number change request is pending Admin approval. Completion and remarks are locked.'
                            : (pendingRequestType == 'call_completion'
                                ? 'A call completion request is pending Admin approval. Completion and remarks are locked.'
                                : (pendingRequestType == 'preference_change'
                                    ? 'A preference change request is pending Admin approval. Completion and remarks are locked.'
                                    : (pendingRequestType == 'edit_customer_details'
                                        ? 'A customer details change request is pending Admin approval. Completion and remarks are locked.'
                                        : 'A change request is pending Admin approval. Completion and remarks are locked until approved or rejected.'))),
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.amber[200] : Colors.amber[900],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ] else if (!callMade) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (callDuration != null && callDuration! <= 10)
                      ? Colors.orange.withValues(alpha: 0.12)
                      : Colors.grey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: (callDuration != null && callDuration! <= 10)
                        ? Colors.orange.withValues(alpha: 0.3)
                        : Colors.grey.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      (callDuration != null && callDuration! <= 10)
                          ? Icons.phone_missed_rounded
                          : Icons.info_outline,
                      color: (callDuration != null && callDuration! <= 10)
                          ? Colors.orange[800]
                          : Colors.grey[700],
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        (callDuration != null && callDuration! <= 10)
                            ? (callDuration == 0
                                ? 'Call was not answered (0s). Remarks are only allowed for calls lasting more than 10 seconds. Please try calling again.'
                                : 'Call was under 10 seconds (${callDuration}s). Remarks are only allowed for calls lasting more than 10 seconds. Please try calling again.')
                            : 'Please make a call to the customer first. Remarks are enabled once an attended call lasting more than 10 seconds is verified.',
                        style: TextStyle(
                          fontSize: 12,
                          color: (callDuration != null && callDuration! <= 10)
                              ? Colors.orange[900]
                              : Colors.grey[800],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
            TextField(
              controller: remarksController,
              enabled: callMade && !isCompleted && !hasPendingRequest,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: isCompleted
                    ? 'Reminder is completed. Remarks are locked.'
                    : (hasPendingRequest
                        ? 'Remarks are locked while a request is pending Admin approval.'
                        : (callMade
                            ? 'Enter discussion summary, customer feedback, etc...'
                            : 'Remarks disabled (call must exceed 10s)...')),
                filled: true,
                fillColor: (!callMade || isCompleted || hasPendingRequest)
                    ? (isDark ? Colors.grey[850] : Colors.grey[200])
                    : (isDark ? Colors.grey[900] : Colors.grey[100]),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (isSaving || !callMade || isCompleted || hasPendingRequest)
                    ? null
                    : onSaveAndComplete,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF005BAC),
                  disabledBackgroundColor: Colors.grey[400],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : Text(
                        hasPendingRequest
                            ? 'Request Pending Approval'
                            : (isCompleted ? 'Reminder Completed' : 'Save Remarks & Mark Completed'),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
