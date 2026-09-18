import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../dme_config.dart';
import '../../dme_constants.dart';

// Export all request components for modular access
export 'dme_requests_phone_number_invalid.dart';
export 'dme_requests_change_preference.dart';
export 'dme_requests_mark_call_as_completed.dart';
export 'dme_requests_edit_customer_details.dart';

import 'dme_requests_phone_number_invalid.dart';
import 'dme_requests_change_preference.dart';
import 'dme_requests_mark_call_as_completed.dart';
import 'dme_requests_edit_customer_details.dart';

class DmeRaiseRequestPage extends StatefulWidget {
  final Map<String, dynamic> reminder;

  const DmeRaiseRequestPage({
    super.key,
    required this.reminder,
  });

  @override
  State<DmeRaiseRequestPage> createState() => _DmeRaiseRequestPageState();
}

class _DmeRaiseRequestPageState extends State<DmeRaiseRequestPage> {
  final _formKey = GlobalKey<FormState>();
  final _editCustomerDetailsKey = GlobalKey<DmeRequestsEditCustomerDetailsFormState>();

  // 'phone', 'edit_customer_details', 'preference', or 'completion'
  String _selectedRequestType = 'phone';

  // 1. Phone number form controller (only reason needed as admin enters new number)
  late TextEditingController _phoneReasonController;

  // 2. Edit Customer Details form controllers
  late TextEditingController _editNameController;
  late TextEditingController _editReasonController;

  // 3. Preference form controllers
  String _selectedPreference = 'Whatsapp';
  late TextEditingController _preferenceReasonController;

  // 4. Call completion form controllers
  late TextEditingController _callDurationController;
  late TextEditingController _completionRemarksController;
  late TextEditingController _completionReasonController;

  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _phoneReasonController = TextEditingController();

    _editNameController = TextEditingController(
      text: (widget.reminder['customer_name'] ?? '').toString().trim(),
    );
    _editReasonController = TextEditingController();

    final currentPref = (widget.reminder['customer_preference'] ?? 'Call').toString().trim();
    _selectedPreference = currentPref.toLowerCase() == 'whatsapp' ? 'Call' : 'Whatsapp';
    _preferenceReasonController = TextEditingController();

    _callDurationController = TextEditingController();
    _completionRemarksController = TextEditingController();
    _completionReasonController = TextEditingController();
  }

  @override
  void dispose() {
    _phoneReasonController.dispose();
    _editNameController.dispose();
    _editReasonController.dispose();
    _preferenceReasonController.dispose();
    _callDurationController.dispose();
    _completionRemarksController.dispose();
    _completionReasonController.dispose();
    super.dispose();
  }

  Future<void> _submitRequest() async {
    if (!_formKey.currentState!.validate()) return;

    final client = await DmeConfig.getClient();
    if (client == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to connect to database. Please check connection.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    final userEmail = user?.email ?? user?.displayName ?? 'user';
    final customerId = int.tryParse(widget.reminder['customer_id']?.toString() ?? '') ?? 0;
    final reminderId = int.tryParse(widget.reminder['id']?.toString() ?? '');
    final customerName = widget.reminder['customer_name'] ?? 'Unnamed Customer';
    final currentPhone = (widget.reminder['customer_phone'] ?? '').toString().trim();
    final currentPreference = (widget.reminder['customer_preference'] ?? 'Call').toString().trim();

    String requestType;
    String currentValue;
    String newValue;
    String reason;

    if (_selectedRequestType == 'phone') {
      requestType = 'phone_number_change';
      currentValue = currentPhone;
      newValue = ''; // User does not enter number; Admin provides it on approval
      reason = _phoneReasonController.text.trim();
    } else if (_selectedRequestType == 'edit_customer_details') {
      final editState = _editCustomerDetailsKey.currentState;
      final editData = editState?.getData();

      if (editData == null || !editData.hasChanges) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please modify at least one detail (Name, Customer Type, or Category) to submit request.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      requestType = 'edit_customer_details';
      currentValue = editData.toJsonCurrentValue();
      newValue = editData.toJsonNewValue();
      reason = editData.toFormattedSummary();
    } else if (_selectedRequestType == 'preference') {
      requestType = 'preference_change';
      currentValue = currentPreference;
      newValue = _selectedPreference;
      reason = _preferenceReasonController.text.trim();
    } else {
      requestType = 'call_completion';
      currentValue = (widget.reminder['status'] ?? 'pending').toString();
      final duration = int.tryParse(_callDurationController.text.trim()) ?? 0;
      final remarks = _completionRemarksController.text.trim();
      final note = _completionReasonController.text.trim();
      final submissionTime = DateTime.now();
      final submissionTimeIso = submissionTime.toIso8601String();
      newValue = jsonEncode({
        'duration': duration,
        'remarks': remarks,
        'reason': note,
        'user_uid': user?.uid ?? '',
        'user_email': userEmail,
        'called_timestamp': submissionTimeIso,
      });
      reason = 'Call Duration: ${duration}s | Remarks: $remarks${note.isNotEmpty ? " | Note: $note" : ""}';
    }

    setState(() => _isSubmitting = true);

    try {
      final submissionNow = DateTime.now();
      final submissionNowIso = submissionNow.toIso8601String();
      final payload = <String, dynamic>{
        'customer_id': customerId,
        'customer_name': customerName,
        'customer_phone': currentPhone,
        'request_type': requestType,
        'current_value': currentValue,
        'new_value': newValue,
        'reason': reason,
        'status': 'pending',
        'requested_by': userEmail,
        'created_at': submissionNowIso,
        'updated_at': submissionNowIso,
      };
      if (reminderId != null) {
        payload['reminder_id'] = reminderId;

        // If mark call as completed, update dme_reminders called_timestamp with the submission time
        if (requestType == 'call_completion') {
          final duration = int.tryParse(_callDurationController.text.trim()) ?? 0;
          try {
            await client.from('dme_reminders').update({
              'called_timestamp': submissionNowIso,
              'call_duration': duration,
              'called_by': userEmail,
              'updated_at': submissionNowIso,
            }).eq('id', reminderId);
          } catch (remErr) {
            debugPrint('Notice updating reminder called_timestamp on request submission: $remErr');
          }
        }
      }

      await client.from(DmeConstants.tableChangeRequests).insert(payload);

      if (mounted) {
        setState(() => _isSubmitting = false);
        Navigator.pop(context, {
          'type': requestType,
          'success': true,
          'new_value': newValue,
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit request: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final customerName = widget.reminder['customer_name'] ?? 'Unnamed Customer';
    final customerPhone = (widget.reminder['customer_phone'] ?? 'N/A').toString();
    final customerPreference = (widget.reminder['customer_preference'] ?? 'Call').toString();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Raise Request', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Customer Details Summary Card
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                color: isDark ? const Color(0xFF1E2638) : const Color(0xFFEFF6FF),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: const Color(0xFF005BAC).withValues(alpha: 0.15),
                        foregroundColor: const Color(0xFF005BAC),
                        child: const Icon(Icons.person_rounded, size: 28),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              customerName,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.phone_rounded, size: 14, color: Colors.grey),
                                const SizedBox(width: 4),
                                Text(
                                  customerPhone,
                                  style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Icon(
                                  customerPreference.toLowerCase() == 'whatsapp'
                                      ? Icons.chat_bubble_outline_rounded
                                      : Icons.phone_in_talk_rounded,
                                  size: 14,
                                  color: customerPreference.toLowerCase() == 'whatsapp'
                                      ? Colors.green
                                      : const Color(0xFF005BAC),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Current Preference: $customerPreference',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: customerPreference.toLowerCase() == 'whatsapp'
                                        ? Colors.green[800]
                                        : const Color(0xFF005BAC),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              const Text(
                'Select Request Type',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),

              // Option 1: Phone number invalid
              _buildTypeCard(
                type: 'phone',
                title: 'Phone Number Invalid / Change',
                subtitle: 'Number unreachable or invalid. Reminder locks until Admin verifies & enters new number.',
                icon: Icons.phonelink_erase_rounded,
                accentColor: Colors.orange.shade800,
              ),

              const SizedBox(height: 10),

              // Option 2: Edit Customer Details (NEW)
              _buildTypeCard(
                type: 'edit_customer_details',
                title: 'Edit Customer Details',
                subtitle: 'Request to update Customer Name, Category, or Customer Type (change any or all).',
                icon: Icons.manage_accounts_rounded,
                accentColor: const Color(0xFF007A87),
              ),

              const SizedBox(height: 10),

              // Option 3: Change preference
              _buildTypeCard(
                type: 'preference',
                title: 'Change Preference (Call / WhatsApp)',
                subtitle: 'Update customer communication preference between Call and WhatsApp.',
                icon: Icons.swap_horiz_rounded,
                accentColor: const Color(0xFF005BAC),
              ),

              const SizedBox(height: 10),

              // Option 4: Mark Call Completed
              _buildTypeCard(
                type: 'completion',
                title: 'Mark Call as Completed',
                subtitle: 'Request admin approval to mark this reminder call as completed with duration and remarks.',
                icon: Icons.check_circle_outline_rounded,
                accentColor: Colors.purple.shade700,
              ),

              const SizedBox(height: 24),

              // Modular Dynamic Input Fields based on selected type
              if (_selectedRequestType == 'phone')
                DmeRequestsPhoneNumberInvalidForm(
                  reminder: widget.reminder,
                  reasonController: _phoneReasonController,
                )
              else if (_selectedRequestType == 'edit_customer_details')
                DmeRequestsEditCustomerDetailsForm(
                  key: _editCustomerDetailsKey,
                  reminder: widget.reminder,
                  nameController: _editNameController,
                  reasonController: _editReasonController,
                )
              else if (_selectedRequestType == 'preference')
                DmeRequestsChangePreferenceForm(
                  selectedPreference: _selectedPreference,
                  onPreferenceChanged: (newPref) {
                    setState(() => _selectedPreference = newPref);
                  },
                  reasonController: _preferenceReasonController,
                )
              else
                DmeRequestsMarkCallAsCompletedForm(
                  callDurationController: _callDurationController,
                  completionRemarksController: _completionRemarksController,
                  completionReasonController: _completionReasonController,
                ),

              const SizedBox(height: 28),

              // Submit Button
              ElevatedButton.icon(
                onPressed: _isSubmitting ? null : _submitRequest,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send_rounded, size: 20),
                label: Text(
                  _isSubmitting ? 'Submitting...' : 'Submit Request to Admin',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF005BAC),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTypeCard({
    required String type,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
  }) {
    final isSelected = _selectedRequestType == type;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        setState(() => _selectedRequestType = type);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? accentColor.withValues(alpha: isDark ? 0.2 : 0.08)
              : (isDark ? Colors.grey[850] : Colors.white),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? accentColor : Colors.grey.withValues(alpha: 0.3),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: isSelected ? accentColor : Colors.grey.withValues(alpha: 0.15),
              foregroundColor: isSelected ? Colors.white : Colors.grey[700],
              child: Icon(icon, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14.5,
                      color: isSelected ? accentColor : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white60 : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            Radio<String>(
              value: type,
              groupValue: _selectedRequestType,
              activeColor: accentColor,
              onChanged: (val) {
                if (val != null) setState(() => _selectedRequestType = val);
              },
            ),
          ],
        ),
      ),
    );
  }
}
