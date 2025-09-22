import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'dart:async';

const Color primaryBlue = Color(0xFF005BAC);
const Color primaryGreen = Color(0xFF8CC63F);

class TodoFormPage extends StatefulWidget {
  final String? docId; // <-- Add this
  const TodoFormPage({Key? key, this.docId}) : super(key: key);

  @override
  State<TodoFormPage> createState() => _TodoFormPageState();
}

class _TodoFormPageState extends State<TodoFormPage> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  final TextEditingController _reminderController = TextEditingController();
  String _priority = 'High';
  bool _isSaving = false;

  // For manager assignment
  String? _currentUserRole;
  String? _currentUserBranch;
  List<Map<String, dynamic>> _salesUsers = [];
  String? _selectedSalesUserId;
  TimeOfDay? _selectedReminderTime;
  DateTime? _selectedReminderDate;

  @override
  void initState() {
    super.initState();
    _fetchCurrentUserRoleAndBranch();
    if (widget.docId != null) {
      _loadTodoForEdit(widget.docId!);
    }
  }

  Future<void> _fetchCurrentUserRoleAndBranch() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    setState(() {
      _currentUserRole = userDoc.data()?['role'];
      _currentUserBranch = userDoc.data()?['branch'];
    });
    if (_currentUserRole == 'manager') {
      _fetchSalesUsers();
    }
  }

  Future<void> _fetchSalesUsers() async {
    if (_currentUserBranch == null) return;
    final query = await FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'sales')
        .where('branch', isEqualTo: _currentUserBranch)
        .get();
    setState(() {
      _salesUsers = query.docs.map((doc) {
        final data = doc.data();
        return {
          'uid': doc.id,
          'username': data['username'] ?? data['email'] ?? 'Unknown',
          'email': data['email'] ?? 'unknown@example.com',
        };
      }).toList();
    });
  }

  Future<void> _scheduleNotification(DateTime dateTime, String title, String docId) async {
    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
        channelKey: 'reminder_channel',
        title: 'Task Reminder',
        body: 'Reminder for: $title',
        notificationLayout: NotificationLayout.Default,
        payload: {'docId': docId, 'type': 'todo'},
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

  Future<void> _loadTodoForEdit(String docId) async {
    final doc = await FirebaseFirestore.instance.collection('todo').doc(docId).get();
    if (!doc.exists) return;
    final data = doc.data();
    if (data == null) return;
    setState(() {
      _titleController.text = data['title'] ?? '';
      _descController.text = data['description'] ?? '';
      _priority = data['priority'] ?? 'High';
      if (data['reminder'] != null) {
        final reminderDate = DateTime.tryParse(data['reminder']);
        if (reminderDate != null) {
          _selectedReminderDate = DateTime(reminderDate.year, reminderDate.month, reminderDate.day);
          _selectedReminderTime = TimeOfDay(hour: reminderDate.hour, minute: reminderDate.minute);
          _reminderController.text =
              "${reminderDate.year}-${reminderDate.month.toString().padLeft(2, '0')}-${reminderDate.day.toString().padLeft(2, '0')} ${_selectedReminderTime!.format(context)}";
        }
      }
    });
  }

  Future<void> _saveTodo() async {
    final title = _titleController.text.trim();
    final desc = _descController.text.trim();

    if (title.isEmpty || desc.isEmpty || _priority.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all required fields')),
      );
      return;
    }

    // 🔴 Make reminder mandatory
    if (_selectedReminderDate == null || _selectedReminderTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a reminder date & time')),
      );
      return;
    }

    setState(() => _isSaving = true);

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User not logged in')),
      );
      return;
    }

    String email = '';
    String createdBy = user.uid;
    String? assignedBy;
    String? assignedTo;
    String? assignedToName;
    String? assignedByName;

    if (_currentUserRole == 'manager' && _selectedSalesUserId != null) {
      final salesUser = _salesUsers.firstWhere(
        (u) => u['uid'] == _selectedSalesUserId,
        orElse: () => {},
      );
      email = salesUser['email'] ?? '';
      createdBy = user.uid;
      assignedBy = user.uid;
      assignedByName = (await FirebaseFirestore.instance.collection('users').doc(user.uid).get()).data()?['username'] ?? '';
      assignedTo = salesUser['uid'];
      assignedToName = salesUser['username'];
    } else {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      email = userDoc.data()?['email'] ?? user.email ?? 'unknown@example.com';
      createdBy = user.uid;
    }

    // ✅ Reminder is always required now
    final scheduledDate = DateTime(
      _selectedReminderDate!.year,
      _selectedReminderDate!.month,
      _selectedReminderDate!.day,
      _selectedReminderTime!.hour,
      _selectedReminderTime!.minute,
    );

    if (widget.docId != null) {
      // Update existing todo
      await FirebaseFirestore.instance.collection('todo').doc(widget.docId).update({
        'title': title,
        'description': desc,
        'priority': _priority,
        'reminder': scheduledDate.toIso8601String(),
        // Optionally update other fields as needed
      });
      if (mounted) Navigator.pop(context);
      return;
    }

    final todoRef = await FirebaseFirestore.instance.collection('todo').add({
      'title': title,
      'description': desc,
      'priority': _priority,
      'status': 'pending',
      'timestamp': FieldValue.serverTimestamp(),
      'email': email,
      'created_by': createdBy,
      if (assignedBy != null) 'assigned_by': assignedBy,
      if (assignedByName != null) 'assigned_by_name': assignedByName,
      if (assignedTo != null) 'assigned_to': assignedTo,
      if (assignedToName != null) 'assigned_to_name': assignedToName,
      'reminder': scheduledDate.toIso8601String(), // 🔒 Always saved
      if (assignedBy != null) 'assignment_seen': false,
    });

    // Daily report logic
    final now = DateTime.now();
    final hour = now.hour;
    if ((hour >= 13 && hour <= 23) || (hour >= 0 && hour < 12)) {
      await FirebaseFirestore.instance.collection('daily_report').add({
        'timestamp': now,
        'userId': createdBy,
        'documentId': todoRef.id,
        'type': 'todo',
      });
    }

    // 🔔 Only schedule notification if assigned to self
    if (_currentUserRole != 'manager' || (_currentUserRole == 'manager' && (_selectedSalesUserId == null || _selectedSalesUserId == user.uid))) {
      await _scheduleNotification(scheduledDate, title, todoRef.id);
    }

    if (mounted) {
      Navigator.pop(context);
    }
    // Don't call setState after pop, as the widget is disposed
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _reminderController.dispose();
    super.dispose();
  }

  Widget _priorityDot(String priority) {
    Color color;
    switch (priority) {
      case 'High':
        color = Colors.red;
        break;
      case 'Medium':
        color = Colors.amber;
        break;
      case 'Low':
        color = Colors.green;
        break;
      default:
        color = Colors.grey;
    }
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inputFillColor = isDark ? const Color(0xFF23262F) : Colors.white;
    final inputTextColor = isDark ? Colors.white : Colors.black;
    final labelColor = isDark ? Colors.white70 : Colors.black87;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF181A20) : const Color(0xFFF6F7FB),
      appBar: AppBar(
        title: const Text('Add Task'),
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: AbsorbPointer(
          absorbing: _isSaving,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Title', style: TextStyle(color: labelColor, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              TextField(
                controller: _titleController,
                style: TextStyle(color: inputTextColor),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: inputFillColor,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  hintText: 'Enter task title',
                  hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey),
                ),
              ),
              const SizedBox(height: 18),
              Text('Description', style: TextStyle(color: labelColor, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              TextField(
                controller: _descController,
                style: TextStyle(color: inputTextColor),
                maxLines: 3,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: inputFillColor,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  hintText: 'Enter task description',
                  hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey),
                ),
              ),
              if (_currentUserRole == 'manager')
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 18),
                    const Text('Assign To', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: _selectedSalesUserId,
                      items: [
                        DropdownMenuItem<String>(
                          value: null,
                          child: const Text('None (Assign to Myself)'),
                        ),
                        ..._salesUsers.map<DropdownMenuItem<String>>((user) => DropdownMenuItem<String>(
                              value: user['uid'] as String,
                              child: Text(user['username'] as String),
                            )),
                      ],
                      onChanged: (val) => setState(() => _selectedSalesUserId = val),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Select Sales User',
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 18),
              Text('Priority', style: TextStyle(color: labelColor, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _priority,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: inputFillColor,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                dropdownColor: inputFillColor,
                style: TextStyle(color: inputTextColor),
                items: [
                  DropdownMenuItem(
                    value: 'High',
                    child: Row(
                      children: [
                        _priorityDot('High'),
                        const SizedBox(width: 6),
                        const Text('High'),
                      ],
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'Medium',
                    child: Row(
                      children: [
                        _priorityDot('Medium'),
                        const SizedBox(width: 6),
                        const Text('Medium'),
                      ],
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'Low',
                    child: Row(
                      children: [
                        _priorityDot('Low'),
                        const SizedBox(width: 6),
                        const Text('Low'),
                      ],
                    ),
                  ),
                ],
                onChanged: (val) => setState(() => _priority = val!),
              ),
              const SizedBox(height: 18),
              Text('Reminder (required)', style: TextStyle(color: labelColor, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              TextField(
                controller: _reminderController,
                readOnly: true,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: inputFillColor,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  hintText: 'Pick reminder date & time',
                  hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey),
                  prefixIcon: const Icon(Icons.alarm),
                ),
                onTap: () async {
                  final pickedDate = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 30)),
                  );
                  if (pickedDate != null) {
                    final pickedTime = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.now(),
                    );
                    if (pickedTime != null) {
                      _selectedReminderDate = pickedDate;
                      _selectedReminderTime = pickedTime;
                      final formatted = DateTime(
                        pickedDate.year,
                        pickedDate.month,
                        pickedDate.day,
                        pickedTime.hour,
                        pickedTime.minute,
                      );
                      _reminderController.text =
                          "${formatted.year}-${formatted.month.toString().padLeft(2, '0')}-${formatted.day.toString().padLeft(2, '0')} ${pickedTime.format(context)}";
                      setState(() {});
                    }
                  }
                },
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (_isSaving || _selectedReminderDate == null || _selectedReminderTime == null)
                      ? null
                      : _saveTodo,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Save Task', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
