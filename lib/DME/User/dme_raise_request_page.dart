import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../dme_config.dart';
import '../dme_constants.dart';

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

  // 'phone', 'preference', or 'completion'
  String _selectedRequestType = 'phone';

  // Phone number form controllers
  late TextEditingController _newPhoneController;
  late TextEditingController _phoneReasonController;

  // Preference form controllers
  String _selectedPreference = 'Whatsapp';
  late TextEditingController _preferenceReasonController;

  // Call completion form controllers
  late TextEditingController _callDurationController;
  late TextEditingController _completionRemarksController;
  late TextEditingController _completionReasonController;

  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _newPhoneController = TextEditingController();
    _phoneReasonController = TextEditingController();

    final currentPref = (widget.reminder['customer_preference'] ?? 'Call').toString().trim();
    // Default to the alternate preference option
    _selectedPreference = currentPref.toLowerCase() == 'whatsapp' ? 'Call' : 'Whatsapp';
    _preferenceReasonController = TextEditingController();

    _callDurationController = TextEditingController();
    _completionRemarksController = TextEditingController();
    _completionReasonController = TextEditingController();
  }

  @override
  void dispose() {
    _newPhoneController.dispose();
    _phoneReasonController.dispose();
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

    setState(() => _isSubmitting = true);

    try {
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
        newValue = _newPhoneController.text.trim();
        reason = _phoneReasonController.text.trim();
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
        newValue = jsonEncode({
          'duration': duration,
          'remarks': remarks,
          'reason': note,
          'user_uid': user?.uid ?? '',
          'user_email': userEmail,
        });
        reason = 'Call Duration: ${duration}s | Remarks: $remarks${note.isNotEmpty ? " | Note: $note" : ""}';
      }

      final payload = {
        'customer_id': customerId,
        'customer_name': customerName,
        'customer_phone': currentPhone,
        'request_type': requestType,
        'current_value': currentValue,
        'new_value': newValue,
        'reason': reason,
        'status': 'pending',
        'requested_by': userEmail,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (reminderId != null) {
        payload['reminder_id'] = reminderId;
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
                subtitle: 'Customer phone number is invalid, unreachable, or needs update. Reminders will be locked until approved.',
                icon: Icons.phonelink_erase_rounded,
                accentColor: Colors.orange.shade800,
              ),

              const SizedBox(height: 10),

              // Option 2: Change preference
              _buildTypeCard(
                type: 'preference',
                title: 'Change Preference (Call / WhatsApp)',
                subtitle: 'Update customer communication preference between Call and WhatsApp.',
                icon: Icons.swap_horiz_rounded,
                accentColor: const Color(0xFF005BAC),
              ),

              const SizedBox(height: 10),

              // Option 3: Mark Call Completed
              _buildTypeCard(
                type: 'completion',
                title: 'Mark Call as Completed',
                subtitle: 'Request admin approval to mark this reminder call as completed with duration and remarks.',
                icon: Icons.check_circle_outline_rounded,
                accentColor: Colors.purple.shade700,
              ),

              const SizedBox(height: 24),

              // Dynamic Input Fields
              if (_selectedRequestType == 'phone') ...[
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
                          'Note: Once submitted, this reminder will be greyed out and cannot be called until Admin approves or rejects the request.',
                          style: TextStyle(fontSize: 12.5, height: 1.35, color: Colors.deepOrange),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // New Phone field
                TextFormField(
                  controller: _newPhoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Correct / New Phone Number *',
                    hintText: 'e.g. 9876543210 or +971501234567',
                    prefixIcon: const Icon(Icons.phone_iphone_rounded),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Please enter the new phone number';
                    }
                    final clean = val.replaceAll(RegExp(r'[\s\-\(\)]'), '');
                    if (clean.length < 6) {
                      return 'Please enter a valid phone number (at least 6 digits)';
                    }
                    if (clean == customerPhone.replaceAll(RegExp(r'[\s\-\(\)]'), '')) {
                      return 'New number cannot be the same as current number';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Reason field
                TextFormField(
                  controller: _phoneReasonController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Reason for Change *',
                    hintText: 'e.g. Wrong number, customer shared updated number, invalid digits',
                    prefixIcon: const Icon(Icons.edit_note_rounded),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Please enter reason for number change';
                    }
                    return null;
                  },
                ),
              ] else if (_selectedRequestType == 'preference') ...[
                // Preference Selection
                const Text(
                  'Select New Preference *',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _buildPreferenceChoiceCard(
                        value: 'Call',
                        label: 'Call',
                        icon: Icons.phone_in_talk_rounded,
                        color: const Color(0xFF005BAC),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildPreferenceChoiceCard(
                        value: 'Whatsapp',
                        label: 'WhatsApp',
                        icon: Icons.chat_bubble_rounded,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Reason field
                TextFormField(
                  controller: _preferenceReasonController,
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
                    return null;
                  },
                ),
              ] else ...[
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
                          'Enter call duration and remarks. Upon Admin approval, this reminder will be marked as Completed with the current timestamp and attributed to you.',
                          style: TextStyle(fontSize: 12.5, height: 1.35, color: Colors.purple.shade900),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Call Duration field
                TextFormField(
                  controller: _callDurationController,
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
                  controller: _completionRemarksController,
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
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Reason / Note field
                TextFormField(
                  controller: _completionReasonController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Reason for Approval Request (Optional)',
                    hintText: 'e.g. Called from alternate device / landline, or call log not detected',
                    prefixIcon: const Icon(Icons.notes_rounded),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],

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

  Widget _buildPreferenceChoiceCard({
    required String value,
    required String label,
    required IconData icon,
    required Color color,
  }) {
    final isSelected = _selectedPreference.toLowerCase() == value.toLowerCase();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => setState(() => _selectedPreference = value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
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
