import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/material.dart';
import 'package:showcaseview/showcaseview.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart'; // Import to use clearNotificationOpened
class PresentFollowUp extends StatefulWidget {
  final String docId;
  final bool editMode; // <-- Add this

  const PresentFollowUp({super.key, required this.docId, this.editMode = false}); // <-- Default false

  @override
  State<PresentFollowUp> createState() => _PresentFollowUpState();
}

class _PresentFollowUpState extends State<PresentFollowUp> {
  bool _isEditing = false;
  bool _isSaving = false;
  Map<String, dynamic>? _data;
  final _formKey = GlobalKey<FormState>();

  // Controllers for editable fields
  late TextEditingController _nameController;
  late TextEditingController _companyController;
  late TextEditingController _addressController;
  late TextEditingController _phoneController;
  late TextEditingController _reminderController;
  late TextEditingController _commentsController;

  String? _status;
  String? _branch;

  DateTime? _selectedDate;

  final GlobalKey _phoneShowcaseKey = GlobalKey();

  @override
  void dispose() {
    _nameController.dispose();
    _companyController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _reminderController.dispose();
    _commentsController.dispose();
    super.dispose();
  }

  void _initControllers(Map<String, dynamic> data) {
    _nameController = TextEditingController(text: data['name'] ?? '');
    _companyController = TextEditingController(text: data['company'] ?? '');
    _addressController = TextEditingController(text: data['address'] ?? '');
    _phoneController = TextEditingController(text: data['phone'] ?? '');
    _commentsController = TextEditingController(text: data['comments'] ?? '');
    _status = data['status'];
    _branch = data['branch'];

    // Handle reminder
    final dynamic reminderValue = data['reminder'];
    String reminderText = '';

    if (reminderValue is String && reminderValue.isNotEmpty) {
      reminderText = reminderValue;
      try {
        // Try to parse it to set the initial date for the picker
        _selectedDate = DateFormat('dd-MM-yyyy hh:mm a').parse(reminderValue);
      } catch (e) {
        // If it fails, it's probably an old format (e.g., just time).
        // Let's try to get the date from the 'date' field.
        final dynamic dateValue = data['date'];
        if (dateValue is Timestamp) {
          _selectedDate = dateValue.toDate();
        } else if (dateValue is String) {
          try {
            _selectedDate = DateTime.parse(dateValue);
          } catch (_) {}
        }
      }
    } else if (reminderValue is Timestamp) {
      _selectedDate = reminderValue.toDate();
      reminderText = DateFormat('dd-MM-yyyy hh:mm a').format(_selectedDate!);
    } else {
      // No reminder, but maybe a date?
      final dynamic dateValue = data['date'];
      if (dateValue is Timestamp) {
        _selectedDate = dateValue.toDate();
      } else if (dateValue is String) {
        try {
          _selectedDate = DateTime.parse(dateValue);
        } catch (_) {}
      }
    }
    _reminderController = TextEditingController(text: reminderText);
  }

  Future<void> _pickDateTime(BuildContext context) async {
    final now = DateTime.now();
    final initialDate = _selectedDate ?? now;

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: now.subtract(const Duration(days: 365)), // Allow past dates
      lastDate: now.add(const Duration(days: 365)),
    );
    if (pickedDate == null) return;

    final initialTime = TimeOfDay.fromDateTime(initialDate);
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );

    if (pickedTime != null) {
      setState(() {
        _selectedDate = DateTime(
          pickedDate.year,
          pickedDate.month,
          pickedDate.day,
          pickedTime.hour,
          pickedTime.minute,
        );
        _reminderController.text = DateFormat('dd-MM-yyyy hh:mm a').format(_selectedDate!);
      });
    }
  }

  Future<void> _launchDialer(String phoneNumber) async {
    final Uri launchUri = Uri(
      scheme: 'tel',
      path: phoneNumber,
    );
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not launch dialer for $phoneNumber')),
        );
      }
    }
  }

  Future<void> _saveEdits() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final updatedData = {
      'name': _nameController.text.trim(),
      'company': _companyController.text.trim(),
      'address': _addressController.text.trim(),
      'phone': _phoneController.text.trim(),
      'reminder': _reminderController.text.trim(),
      'comments': _commentsController.text.trim(),
      'status': _status,
      'branch': _branch,
      'date': _selectedDate != null ? Timestamp.fromDate(_selectedDate!) : FieldValue.serverTimestamp(),
    };

    try {
      // Update follow_ups
      await FirebaseFirestore.instance
          .collection('follow_ups')
          .doc(widget.docId)
          .update(updatedData);

      // Also update in customer collection if phone exists
      final phone = updatedData['phone'];
      if (phone != null && phone is String && phone.isNotEmpty) {
        final customerQuery = await FirebaseFirestore.instance
            .collection('customer')
            .where('phone', isEqualTo: phone)
            .get();
        for (final doc in customerQuery.docs) {
          await doc.reference.update({
            'name': updatedData['name'],
            'company': updatedData['company'],
            'address': updatedData['address'],
            'phone': updatedData['phone'],
            'branch': updatedData['branch'],
          });
        }
      }

      // --- Schedule or reschedule local notification for reminder ---
      if (_reminderController.text.isNotEmpty && _selectedDate != null) {
        final scheduledDateTime = _selectedDate!;

        // Clear the 'opened' flag so it can be rescheduled if dismissed
        await clearNotificationOpened(widget.docId);

        // Cancel previous notification for this follow-up (if any)
        await AwesomeNotifications().cancelSchedule(int.tryParse(widget.docId.hashCode.toString().substring(0, 7)) ?? 0);

        // Schedule new notification with action button
        await AwesomeNotifications().createNotification(
          content: NotificationContent(
            id: int.tryParse(widget.docId.hashCode.toString().substring(0, 7)) ?? 0,
            channelKey: 'basic_channel',
            title: 'Follow-up Reminder',
            body: 'Reminder for ${_nameController.text}',
            notificationLayout: NotificationLayout.Default,
            payload: {
              'docId': widget.docId, // This is a lead
              'type': 'lead',
              'action': 'edit_followup'
            },
          ),
          actionButtons: [
            NotificationActionButton(
              key: 'EDIT_FOLLOWUP',
              label: 'Edit',
              autoDismissible: true,
            ),
          ],
          schedule: NotificationCalendar(
            year: scheduledDateTime.year,
            month: scheduledDateTime.month,
            day: scheduledDateTime.day,
            hour: scheduledDateTime.hour,
            minute: scheduledDateTime.minute,
            second: 0,
            millisecond: 0,
            repeats: false,
            preciseAlarm: true,
          ),
        );
      }

      setState(() {
        _isEditing = false;
        _data = updatedData;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lead updated successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update: $e')),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  // Temporarily reset the flag in initState for testing
  @override
  void initState() {
    super.initState();
    _isEditing = widget.editMode;
    WidgetsBinding.instance.addPostFrameCallback((_) => _showPhoneShowcaseIfNeeded());
  }

  Future<void> _showPhoneShowcaseIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool('seen_phone_showcase') ?? false;
    print('Showcase seen value: $seen');
    if (!seen && mounted) {
      await Future.delayed(const Duration(seconds: 1));
      print('Showing showcase for phone card');
      ShowCaseWidget.of(context).startShowCase([_phoneShowcaseKey]);
      await prefs.setBool('seen_phone_showcase', true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF181A20) : const Color(0xFFF6F7FB),
      appBar: AppBar(
        title: const Text('Follow-Up Details'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          !_isEditing
              ? IconButton(
                  icon: const Icon(Icons.edit, color: Colors.white),
                  onPressed: () => setState(() => _isEditing = true),
                )
              : IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => setState(() => _isEditing = false),
                ),
        ],
      ),
      body: FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance.collection('follow_ups').doc(widget.docId).get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text('Follow-up not found.'));
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;
          if (_data == null) {
            _data = data;
            _initControllers(data);
          }

          if (_isEditing) {
            return Stack(
              children: [
                SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Edit Lead', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black)),
                        const SizedBox(height: 20),
                        _editField('Name', _nameController, Theme.of(context).brightness == Brightness.dark),
                        _editField('Company', _companyController, Theme.of(context).brightness == Brightness.dark),
                        _editField('Address', _addressController, Theme.of(context).brightness == Brightness.dark),
                        _editField('Phone', _phoneController, Theme.of(context).brightness == Brightness.dark, keyboardType: TextInputType.phone),
                        _editField('Comments', _commentsController, Theme.of(context).brightness == Brightness.dark, maxLines: 2),
                        const SizedBox(height: 12),
                        _editDropdown('Status', ['In Progress', 'Completed'], _status, (val) => setState(() => _status = val), Theme.of(context).brightness == Brightness.dark),
                        const SizedBox(height: 12),
                        _editField(
                          'Reminder',
                          _reminderController,
                          Theme.of(context).brightness == Brightness.dark,
                          readOnly: true,
                          onTap: () => _pickDateTime(context),
                          suffixIcon: const Icon(Icons.calendar_today),
                        ),
                        _editField('Branch', TextEditingController(text: _branch ?? ''), Theme.of(context).brightness == Brightness.dark, enabled: false),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.save),
                            label: const Text('Save Changes'),
                            onPressed: _isSaving ? null : _saveEdits,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF005BAC),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_isSaving)
                  Container(
                    color: Colors.black.withOpacity(0.3),
                    child: const Center(child: CircularProgressIndicator()),
                  ),
              ],
            );
          }

          // --- View Mode ---
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Account Details',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(height: 20),
                GridView.count(
                  crossAxisCount: 2,
                  childAspectRatio: 1.2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _buildInfoCard(Icons.person, 'Name', _data?['name'], isDark),
                    _buildInfoCard(Icons.apartment, 'Company', _data?['company'], isDark),
                    _buildInfoCard(Icons.location_on, 'Address', _data?['address'], isDark),
                    Showcase(
                      key: _phoneShowcaseKey,
                      description: 'Tap here to quickly call this lead!',
                      child: GestureDetector(
                        onTap: () {
                          final phoneNumber = _data?['phone'];
                          if (phoneNumber != null && phoneNumber.isNotEmpty) {
                            _launchDialer(phoneNumber);
                          }
                        },
                        child: _buildInfoCard(Icons.phone, 'Phone', _data?['phone'], isDark),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                Text(
                  'Follow-Up Info',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _buildInfoTile(
                        Icons.flag,
                        'Status',
                        DropdownButton<String>(
                          value: _data?['status'],
                          dropdownColor: isDark ? const Color(0xFF23262F) : Colors.white,
                          style: TextStyle(color: isDark ? Colors.white : Colors.black),
                          items: ['In Progress', 'Completed'].map((status) {
                            return DropdownMenuItem<String>(
                              value: status,
                              child: Text(status),
                            );
                          }).toList(),
                          onChanged: (newStatus) async {
                            if (newStatus != null && newStatus != _data?['status']) {
                              await FirebaseFirestore.instance
                                  .collection('follow_ups')
                                  .doc(widget.docId)
                                  .update({'status': newStatus});
                              setState(() {
                                _data?['status'] = newStatus;
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Status updated to $newStatus')),
                              );
                            }
                          },
                        ),
                        isDark,
                      ),
                    ),
                  ],
                ),
                _buildInfoTile(Icons.calendar_today, 'Date', Text(_formatDisplayDate(_data?['date']), style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)), isDark),
                _buildInfoTile(Icons.alarm, 'Reminder', Text(_formatDisplayDate(_data?['reminder'], isReminder: true), style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)), isDark),
                _buildInfoTile(Icons.comment, 'Comments', Text(_data?['comments'] ?? 'N/A', style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)), isDark),
                _buildInfoTile(Icons.location_city, 'Branch', Text(_data?['branch'] ?? 'N/A', style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)), isDark),
              ],
            ),
          );
        },
      ),
    );
  }

  String _formatDisplayDate(dynamic value, {bool isReminder = false}) {
    if (value == null) return 'N/A';
    if (value is Timestamp) {
      final format = isReminder ? 'yyyy-MM-dd hh:mm a' : 'yyyy-MM-dd';
      return DateFormat(format).format(value.toDate());
    }
    return value.toString();
  }

  Widget _editField(
    String label,
    TextEditingController controller,
    bool isDark, {
    bool enabled = true,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
    bool readOnly = false,
    VoidCallback? onTap,
    Widget? suffixIcon,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        enabled: enabled,
        maxLines: maxLines,
        keyboardType: keyboardType,
        readOnly: readOnly,
        onTap: onTap,
        style: TextStyle(color: isDark ? Colors.white : Colors.black),
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: suffixIcon,
          filled: true,
          fillColor: isDark ? const Color(0xFF23262F) : Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
        validator: (val) {
          if ((label == 'Name' || label == 'Phone') && (val == null || val.trim().isEmpty)) {
            return '$label is required';
          }
          return null;
        },
      ),
    );
  }

  Widget _editDropdown(
    String label,
    List<String> options,
    String? value,
    ValueChanged<String?> onChanged,
    bool isDark,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: isDark ? const Color(0xFF23262F) : Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value,
            isExpanded: true,
            dropdownColor: isDark ? const Color(0xFF23262F) : Colors.white,
            style: TextStyle(color: isDark ? Colors.white : Colors.black),
            items: options.map((opt) => DropdownMenuItem(value: opt, child: Text(opt))).toList(),
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard(IconData icon, String label, String? value, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF23262F) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          if (!isDark) BoxShadow(color: Colors.black12, blurRadius: 6),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 28, color: const Color(0xFF005BAC)),
          const SizedBox(height: 12),
          Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
          const SizedBox(height: 4),
          Text(value ?? 'N/A', textAlign: TextAlign.center, style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)),
        ],
      ),
    );
  }

  Widget _buildInfoTile(IconData icon, String title, Widget valueWidget, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF23262F) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          if (!isDark) BoxShadow(color: Colors.black12, blurRadius: 4),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF005BAC)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                const SizedBox(height: 4),
                valueWidget,
              ],
            ),
          ),
        ],
      ),
    );
  }
}
