import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _commentsController = TextEditingController();
  final TextEditingController _reminderController = TextEditingController();

  String _status = 'In Progress';
  TimeOfDay? _selectedReminderTime;


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
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User not logged in')));
      return;
    }

    final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final branch = userDoc.data()?['branch'] ?? 'Unknown';

    await FirebaseFirestore.instance.collection('follow_ups').add({
      'date': _dateController.text.trim(),
      'name': _nameController.text.trim(),
      'company': _companyController.text.trim(),
      'address': _addressController.text.trim(),
      'phone': _phoneController.text.trim(),
      'status': _status,
      'comments': _commentsController.text.trim(),
      'reminder': _reminderController.text.trim(),
      'branch': branch,
      'created_by': user.uid,
      'created_at': FieldValue.serverTimestamp(),
    });

    // ✅ Trigger immediate notification
    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: DateTime.now().millisecondsSinceEpoch.remainder(100000), // unique ID
        channelKey: 'reminder_channel',
        title: 'Follow-Up Saved',
        body: 'Reminder for ${_nameController.text.trim()} saved successfully.',
        notificationLayout: NotificationLayout.Default,
      ),
    );
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

      // Schedule notification
      await AwesomeNotifications().createNotification(
        content: NotificationContent(
          id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
          channelKey: 'reminder_channel',
          title: 'Follow-Up Reminder',
          body: 'Reminder for ${_nameController.text.trim()} - ${_companyController.text.trim()}',
          notificationLayout: NotificationLayout.Default,
        ),
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
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime.now(),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) {
                    _dateController.text = "${picked.year}-${picked.month}-${picked.day}";
                  }
                },
                validator: (value) => value!.isEmpty ? 'Select a date' : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Customer Name',
                  prefixIcon: Icon(Icons.person),
                ),
                validator: (value) => value!.isEmpty ? 'Enter name' : null,
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

              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone No.',
                  prefixIcon: Icon(Icons.phone),
                ),
                validator: (value) => value!.isEmpty ? 'Enter phone number' : null,
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
    );
  }
}
