import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'leads.dart'; // Make sure this import exists

// Update fetchCustomerSuggestions to search by name OR phone:
Future<List<Map<String, dynamic>>> fetchCustomerSuggestions(String query, String branch) async {
  final snap = await FirebaseFirestore.instance
      .collection('customer')
      .where('branch', isEqualTo: branch)
      .get();
  return snap.docs
      .map((doc) => doc.data())
      .where((data) =>
          (data['name'] ?? '').toString().toLowerCase().contains(query.toLowerCase()) ||
          (data['phone'] ?? '').toString().toLowerCase().contains(query.toLowerCase()))
      .toList();
}

class FollowUpForm extends StatefulWidget {
  const FollowUpForm({super.key});

  @override
  State<FollowUpForm> createState() => _FollowUpFormState();
}

class _FollowUpFormState extends State<FollowUpForm> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _companyController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController(text: '+91 ');
  final TextEditingController _commentsController = TextEditingController();
  final TextEditingController _reminderController = TextEditingController();

  String _status = 'In Progress';
  String _priority = 'High'; // <-- Add this
  TimeOfDay? _selectedReminderTime;
  bool _isSaving = false; // <-- Add this


  Future<void> _scheduleNotification(DateTime dateTime) async {
    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: DateTime.now().millisecondsSinceEpoch.remainder(100000), // unique ID
        channelKey: 'reminder_channel',
        title: 'Follow-up Reminder',
        body: 'You have a follow-up scheduled.',
        notificationLayout: NotificationLayout.Default,
      ),
      schedule: NotificationCalendar(
        year: dateTime.year,
        month: dateTime.month,
        day: dateTime.day,
        hour: dateTime.hour,
        minute: dateTime.minute,
        second: 0,
        millisecond: 0,
        timeZone: await AwesomeNotifications().getLocalTimeZoneIdentifier(),
        repeats: false,
      ),
    );
  }


  Future<void> _saveFollowUp() async {
    setState(() => _isSaving = true);
    try {
      if (!_formKey.currentState!.validate()) return;

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User not logged in')));
        return;
      }

      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final branch = userDoc.data()?['branch'] ?? 'Unknown';

      // Save follow up and get document reference
      final followUpRef = await FirebaseFirestore.instance.collection('follow_ups').add({
        'date': _dateController.text.trim(),
        'name': _nameController.text.trim(),
        'company': _companyController.text.trim(),
        'address': _addressController.text.trim(),
        'phone': _phoneController.text.trim(),
        'status': _status,
        'priority': _priority, // <-- Save priority
        'comments': _commentsController.text.trim(),
        'reminder': _reminderController.text.trim(),
        'branch': branch,
        'created_by': user.uid,
        'created_at': FieldValue.serverTimestamp(),
      });

      // Upsert customer profile
      await FirebaseFirestore.instance
          .collection('customer')
          .doc(_phoneController.text)
          .set({
        'name': _nameController.text,
        'company': _companyController.text,
        'address': _addressController.text,
        'phone': _phoneController.text,
        'branch': branch,
      }, SetOptions(merge: true));

      // ✅ Trigger immediate notification
      // REMOVE THIS BLOCK:
      // await AwesomeNotifications().createNotification(
      //   content: NotificationContent(
      //     id: DateTime.now().millisecondsSinceEpoch.remainder(100000), // unique ID
      //     channelKey: 'reminder_channel',
      //     title: 'Follow-Up Saved',
      //     body: 'Reminder for ${_nameController.text.trim()} saved successfully.',
      //     notificationLayout: NotificationLayout.Default,
      //   ),
      // );
      if (_selectedReminderTime != null && _reminderController.text.isNotEmpty) {
        final reminderParts = _reminderController.text.split(' ');
        final datePart = reminderParts[0].split('-');

        final scheduledDate = DateTime(
          int.parse(datePart[0]),
          int.parse(datePart[1]),
          int.parse(datePart[2]),
          _selectedReminderTime!.hour,
          _selectedReminderTime!.minute,
        );

        // Schedule notification with Edit button and docId payload
        await AwesomeNotifications().createNotification(
          content: NotificationContent(
            id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
            channelKey: 'basic_channel', // Use basic_channel for consistency
            title: 'Follow-Up Reminder',
            body: 'Reminder for ${_nameController.text.trim()} - ${_companyController.text.trim()}',
            notificationLayout: NotificationLayout.Default,
            payload: {
              'docId': followUpRef.id,
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
            year: scheduledDate.year,
            month: scheduledDate.month,
            day: scheduledDate.day,
            hour: scheduledDate.hour,
            minute: scheduledDate.minute,
            second: 0,
            millisecond: 0,
            timeZone: await AwesomeNotifications().getLocalTimeZoneIdentifier(),
            preciseAlarm: true,
          ),
        );
      }


      Navigator.pop(context);

      // Store only timestamp, userId, documentId, and type in daily_report
      await FirebaseFirestore.instance.collection('daily_report').add({
        'timestamp': FieldValue.serverTimestamp(),
        'userId': user.uid,
        'documentId': followUpRef.id,
        'type': 'leads',
      });

      // After saving, navigate to LeadsPage
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => LeadsPage(branch: branch),
          ),
        );
      }
    } catch (e) {
      // Handle error, show snackbar, etc.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _autoFillFromCustomer(String phone) async {
    final snap = await FirebaseFirestore.instance
        .collection('customer')
        .where('phone', isEqualTo: phone)
        .limit(1)
        .get();
    if (snap.docs.isNotEmpty) {
      final data = snap.docs.first.data();
      setState(() {
        _nameController.text = data['name'] ?? '';
        _companyController.text = data['company'] ?? '';
        _addressController.text = data['address'] ?? '';
        // You can add more fields if needed
      });
    }
  }

  @override
  void initState() {
    super.initState();
    // Set the date field to today's date in yyyy-mm-dd format
    final now = DateTime.now();
    final dateStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    _dateController.text = dateStr;
    // Ensure "+91 " is present at the start of the phone field
    if (!_phoneController.text.startsWith('+91 ')) {
      _phoneController.text = '+91 ';
    }
  }


  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: const Text('New Follow Up'),
            backgroundColor: Color(0xFF005BAC),
            foregroundColor: Colors.white,
          ),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: ListView(
                children: [
                  TextFormField(
                    controller: _dateController,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'Date',
                      prefixIcon: Icon(Icons.calendar_today),
                    ),
                    // Remove the onTap and validator for date selection
                  ),
                  const SizedBox(height: 16),

                  FutureBuilder<DocumentSnapshot>(
                    future: FirebaseFirestore.instance.collection('users').doc(FirebaseAuth.instance.currentUser!.uid).get(),
                    builder: (context, userSnap) {
                      if (!userSnap.hasData) return const SizedBox();
                      final branch = userSnap.data!.get('branch') ?? '';
                      return RawAutocomplete<Map<String, dynamic>>(
                        textEditingController: _nameController,
                        focusNode: FocusNode(),
                        optionsBuilder: (TextEditingValue textEditingValue) async {
                          if (textEditingValue.text.isEmpty) return const Iterable<Map<String, dynamic>>.empty();
                          return await fetchCustomerSuggestions(textEditingValue.text, branch);
                        },
                        displayStringForOption: (option) => option['name'] ?? '',
                        fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                          return TextFormField(
                            controller: controller,
                            focusNode: focusNode,
                            decoration: const InputDecoration(
                              labelText: 'Customer Name',
                              prefixIcon: Icon(Icons.person),
                            ),
                            validator: (value) => value!.isEmpty ? 'Enter name' : null,
                          );
                        },
                        optionsViewBuilder: (context, onSelected, options) {
                          return Align(
                            alignment: Alignment.topLeft,
                            child: Material(
                              elevation: 4.0,
                              child: SizedBox(
                                height: 200,
                                child: ListView.builder(
                                  padding: EdgeInsets.zero,
                                  itemCount: options.length,
                                  itemBuilder: (context, index) {
                                    final option = options.elementAt(index);
                                    return ListTile(
                                      title: Text(option['name'] ?? ''),
                                      subtitle: Text(option['phone'] ?? ''),
                                      onTap: () {
                                        onSelected(option);
                                      },
                                    );
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                        onSelected: (selectedCustomer) {
                          setState(() {
                            _nameController.text = selectedCustomer['name'] ?? '';
                            _companyController.text = selectedCustomer['company'] ?? '';
                            _addressController.text = selectedCustomer['address'] ?? '';
                            _phoneController.text = selectedCustomer['phone'] ?? '';
                          });
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _companyController,
                    decoration: const InputDecoration(
                      labelText: 'Company',
                      prefixIcon: Icon(Icons.business),
                    ),
                    validator: (value) => value!.isEmpty ? 'Enter company' : null,
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _addressController,
                    decoration: const InputDecoration(
                      labelText: 'Address',
                      prefixIcon: Icon(Icons.location_on),
                    ),
                    validator: (value) => value!.isEmpty ? 'Enter address' : null,
                  ),
                  const SizedBox(height: 16),

                  RawAutocomplete<Map<String, dynamic>>(
                    textEditingController: _phoneController,
                    focusNode: FocusNode(),
                    optionsBuilder: (TextEditingValue textEditingValue) async {
                      if (textEditingValue.text.isEmpty) return const Iterable<Map<String, dynamic>>.empty();
                      // Use the same branch logic as before
                      final user = FirebaseAuth.instance.currentUser;
                      if (user == null) return const Iterable<Map<String, dynamic>>.empty();
                      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
                      final branch = userDoc.data()?['branch'] ?? '';
                      return await fetchCustomerSuggestions(textEditingValue.text, branch);
                    },
                    displayStringForOption: (option) => option['phone'] ?? '',
                    fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                      return TextFormField(
                        controller: controller,
                        focusNode: focusNode,
                        decoration: const InputDecoration(
                          labelText: 'Phone',
                          prefixIcon: Icon(Icons.phone),
                        ),
                        keyboardType: TextInputType.phone,
                        validator: (value) {
                          if (value == null || value.isEmpty || !value.startsWith('+91 ')) {
                            return 'Phone must start with +91 ';
                          }
                          if (value.trim() == '+91') {
                            return 'Enter phone number';
                          }
                          // Check for 10 digits after +91 (excluding spaces)
                          final digits = value.replaceAll(RegExp(r'\D'), '');
                          if (digits.length != 12) {
                            return 'Enter a valid 10-digit number after +91';
                          }
                          return null;
                        },
                        onChanged: (val) {
                          // Always start with "+91 "
                          if (!val.startsWith('+91 ')) {
                            controller.text = '+91 ';
                            controller.selection = TextSelection.fromPosition(
                              TextPosition(offset: controller.text.length),
                            );
                            return;
                          }
                          // Remove "+91 " and spaces to get only digits
                          String raw = val.replaceAll('+91 ', '').replaceAll(' ', '');
                          // Limit to 10 digits max
                          if (raw.length > 10) {
                            raw = raw.substring(0, 10);
                          }
                          // Add space after first 5 digits if applicable
                          String formatted = raw.length > 5
                              ? '+91 ${raw.substring(0, 5)} ${raw.substring(5)}'
                              : '+91 $raw';
                          if (controller.text != formatted) {
                            controller.text = formatted;
                            controller.selection = TextSelection.fromPosition(
                              TextPosition(offset: formatted.length),
                            );
                          }
                        },
                      );
                    },
                    optionsViewBuilder: (context, onSelected, options) {
                      return Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          elevation: 4.0,
                          child: SizedBox(
                            height: 200,
                            child: ListView.builder(
                              padding: EdgeInsets.zero,
                              itemCount: options.length,
                              itemBuilder: (context, index) {
                                final option = options.elementAt(index);
                                return ListTile(
                                  title: Text(option['phone'] ?? ''),
                                  subtitle: Text(option['name'] ?? ''),
                                  onTap: () {
                                    onSelected(option);
                                  },
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
                    onSelected: (selectedCustomer) {
                      setState(() {
                        _nameController.text = selectedCustomer['name'] ?? '';
                        _companyController.text = selectedCustomer['company'] ?? '';
                        _addressController.text = selectedCustomer['address'] ?? '';
                        _phoneController.text = selectedCustomer['phone'] ?? '';
                      });
                    },
                  ),
                  const SizedBox(height: 16),

                  DropdownButtonFormField<String>(
                    value: _status,
                    decoration: const InputDecoration(
                      labelText: 'Status',
                      prefixIcon: Icon(Icons.assignment_turned_in),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'In Progress', child: Text('In Progress')),
                      DropdownMenuItem(value: 'Completed', child: Text('Completed')),
                    ],
                    onChanged: (value) => setState(() => _status = value!),
                    validator: (value) => value == null || value.isEmpty ? 'Select status' : null,
                  ),
                  const SizedBox(height: 16),

                  DropdownButtonFormField<String>(
                    value: _priority,
                    decoration: const InputDecoration(
                      labelText: 'Priority',
                      prefixIcon: Icon(Icons.flag),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'High', child: Text('High')),
                      DropdownMenuItem(value: 'Medium', child: Text('Medium')),
                      DropdownMenuItem(value: 'Low', child: Text('Low')),
                    ],
                    onChanged: (value) => setState(() => _priority = value!),
                    validator: (value) => value == null || value.isEmpty ? 'Select priority' : null,
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _commentsController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Comments',
                      alignLabelWithHint: true,
                      prefixIcon: Icon(Icons.comment),
                    ),
                    validator: (value) => value!.isEmpty ? 'Enter comments' : null,
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _reminderController,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'Reminder (max 15 days)',
                      prefixIcon: Icon(Icons.alarm),
                    ),
                    onTap: () async {
                      final pickedDate = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 15)),
                      );
                      if (pickedDate != null) {
                        final pickedTime = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.now(),
                        );
                        if (pickedTime != null) {
                          _selectedReminderTime = pickedTime;
                          final formatted = DateTime(
                            pickedDate.year,
                            pickedDate.month,
                            pickedDate.day,
                            pickedTime.hour,
                            pickedTime.minute,
                          );
                          _reminderController.text = "${formatted.year}-${formatted.month.toString().padLeft(2, '0')}-${formatted.day.toString().padLeft(2, '0')} ${pickedTime.format(context)}";
                        }
                      }
                    },
                    validator: (value) => value!.isEmpty ? 'Select a reminder date & time' : null,
                  ),
                  const SizedBox(height: 30),

                  ElevatedButton(
                    onPressed: _saveFollowUp,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFF005BAC),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Save Follow Up',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_isSaving)
          Container(
            color: Colors.black.withOpacity(0.3),
            child: const Center(
              child: CircularProgressIndicator(),
            ),
          ),
      ],
    );
  }
}
