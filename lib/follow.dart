import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:permission_handler/permission_handler.dart';

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
  TimeOfDay? _reminderTime;

  String _status = 'In Progress';

  late FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin;

  @override
  void initState() {
    super.initState();
    _initializeNotifications();
  }

  void _initializeNotifications() async {
    flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initializationSettings = InitializationSettings(android: androidSettings);

    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
    tz.initializeTimeZones();

    if (await Permission.notification.isDenied || await Permission.notification.isRestricted) {
      await Permission.notification.request();
    }
  }

  Future<void> _scheduleReminderNotification(DateTime reminderDate) async {
    if (_reminderTime == null) return;

    final tz.TZDateTime scheduledDate = tz.TZDateTime(
      tz.local,
      reminderDate.year,
      reminderDate.month,
      reminderDate.day,
      _reminderTime!.hour,
      _reminderTime!.minute,
    );

    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'follow_up_alarm_channel',
      'Follow Up Alarms',
      channelDescription: 'Channel for follow-up alarm notifications',
      importance: Importance.max,
      priority: Priority.high,
      fullScreenIntent: true,
      visibility: NotificationVisibility.public,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('alarm'), // Add your sound under android/app/src/main/res/raw/alarm.mp3
      category: AndroidNotificationCategory.alarm,
    );

    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
    );

    await flutterLocalNotificationsPlugin.zonedSchedule(
      0,
      '🔔 Follow-Up Alarm',
      'You have a follow-up scheduled now!',
      scheduledDate,
      platformChannelSpecifics,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.dateAndTime,
     
    );
  }


  String _formatDate(DateTime date) {
    return DateFormat('yyyy-MM-dd').format(date);
  }

  Future<void> _saveFollowUp() async {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User not logged in')),
      );
      return;
    }

    if (_reminderController.text.isNotEmpty && _reminderTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a reminder time')),
      );
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
      'reminder_time': _reminderTime?.format(context) ?? '',
      'branch': branch,
      'created_by': user.uid,
      'created_at': FieldValue.serverTimestamp(),
    });

    if (_reminderController.text.isNotEmpty) {
      final reminderDate = DateTime.parse(_reminderController.text.trim());
      await _scheduleReminderNotification(reminderDate);
    }

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Follow Up'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              _buildDateField(
                _dateController,
                'Date',
                Icons.calendar_today,
                firstDate: DateTime.now(),
                lastDate: DateTime(2100),
                isRequired: true,
              ),
              const SizedBox(height: 16),
              _buildTextField(_nameController, 'Customer Name', Icons.person, isRequired: true),
              const SizedBox(height: 16),
              _buildTextField(_companyController, 'Company', Icons.business),
              const SizedBox(height: 16),
              _buildTextField(_addressController, 'Address', Icons.location_on),
              const SizedBox(height: 16),
              _buildTextField(_phoneController, 'Phone No.', Icons.phone, inputType: TextInputType.phone),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _status,
                decoration: const InputDecoration(
                  labelText: 'Status',
                  prefixIcon: Icon(Icons.assignment_turned_in),
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'In Progress', child: Text('In Progress')),
                  DropdownMenuItem(value: 'Completed', child: Text('Completed')),
                ],
                onChanged: (value) => setState(() => _status = value!),
              ),
              const SizedBox(height: 16),
              _buildMultilineField(_commentsController, 'Comments', Icons.comment),
              const SizedBox(height: 16),
              _buildDateField(
                _reminderController,
                'Reminder Date (max 15 days)',
                Icons.alarm,
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 15)),
              ),
              const SizedBox(height: 16),
              TextFormField(
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'Reminder Time',
                  prefixIcon: Icon(Icons.access_time),
                  border: OutlineInputBorder(),
                ),
                controller: TextEditingController(
                  text: _reminderTime != null ? _reminderTime!.format(context) : '',
                ),
                onTap: () async {
                  final pickedTime = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.now(),
                  );
                  if (pickedTime != null) {
                    setState(() {
                      _reminderTime = pickedTime;
                    });
                  }
                },
                validator: (value) {
                  if (_reminderController.text.isNotEmpty && _reminderTime == null) {
                    return 'Select reminder time';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: _saveFollowUp,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF005BAC),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool isRequired = false,
    TextInputType inputType = TextInputType.text,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: inputType,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: const OutlineInputBorder(),
      ),
      validator: isRequired ? (value) => value!.isEmpty ? 'Enter $label' : null : null,
    );
  }

  Widget _buildMultilineField(TextEditingController controller, String label, IconData icon) {
    return TextFormField(
      controller: controller,
      maxLines: 4,
      decoration: InputDecoration(
        labelText: label,
        alignLabelWithHint: true,
        prefixIcon: Icon(icon),
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _buildDateField(
    TextEditingController controller,
    String label,
    IconData icon, {
    required DateTime firstDate,
    required DateTime lastDate,
    bool isRequired = false,
  }) {
    return TextFormField(
      controller: controller,
      readOnly: true,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: const OutlineInputBorder(),
      ),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: DateTime.now(),
          firstDate: firstDate,
          lastDate: lastDate,
        );
        if (picked != null) {
          controller.text = _formatDate(picked);
        }
      },
      validator: isRequired ? (value) => value!.isEmpty ? 'Select $label' : null : null,
    );
  }
}
