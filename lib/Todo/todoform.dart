import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'todo_widget_updater.dart'; // At the top
import '../Misc/user_cache_service.dart';

/// Returns the current 12 PM–12 PM IST window as [windowStart, windowEnd].
List<DateTime> _getCurrentISTWindow() {
  tz.initializeTimeZones();
  final ist = tz.getLocation('Asia/Kolkata');
  final nowIST = tz.TZDateTime.now(ist);
  DateTime windowStart, windowEnd;
  if (nowIST.hour >= 12) {
    // After 12 PM: window is today 12 PM → tomorrow 12 PM
    windowStart = tz.TZDateTime(ist, nowIST.year, nowIST.month, nowIST.day, 12);
    final tomorrow = nowIST.add(const Duration(days: 1));
    windowEnd = tz.TZDateTime(ist, tomorrow.year, tomorrow.month, tomorrow.day, 12);
  } else {
    // Before 12 PM: window is yesterday 12 PM → today 12 PM
    final yesterday = nowIST.subtract(const Duration(days: 1));
    windowStart = tz.TZDateTime(ist, yesterday.year, yesterday.month, yesterday.day, 12);
    windowEnd = tz.TZDateTime(ist, nowIST.year, nowIST.month, nowIST.day, 12);
  }
  return [windowStart, windowEnd];
}

/// Creates a daily_report document only if one doesn't already exist
/// for this user+type in the current 12 PM–12 PM IST window.
Future<void> _createDailyReportIfNeeded({
  required String userId,
  required String documentId,
  required String type,
}) async {
  final window = _getCurrentISTWindow();
  final existing = await FirebaseFirestore.instance
      .collection('daily_report')
      .where('userId', isEqualTo: userId)
      .where('type', isEqualTo: type)
      .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(window[0]))
      .where('timestamp', isLessThan: Timestamp.fromDate(window[1]))
      .limit(1)
      .get();
  if (existing.docs.isEmpty) {
    await FirebaseFirestore.instance.collection('daily_report').add({
      'timestamp': FieldValue.serverTimestamp(),
      'userId': userId,
      'documentId': documentId,
      'type': type,
    });
  }
}

const Color primaryBlue = Color(0xFF005BAC);
const Color primaryGreen = Color(0xFF8CC63F);

class TodoFormPage extends StatefulWidget {
  final String? docId; // <-- Add this
  const TodoFormPage({Key? key, this.docId}) : super(key: key);

  static const String DRAFT_KEY = 'todo_form_draft';

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
    // Check for a draft when the form loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.docId == null) _loadDraft();
    });
  }

  Future<void> _fetchCurrentUserRoleAndBranch() async {
    final cache = UserCacheService.instance;
    await cache.ensureLoaded();
    setState(() {
      _currentUserRole = cache.role;
      _currentUserBranch = cache.branch;
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
    // Use a consistent ID based on the docId to allow for cancellation/rescheduling
    final notificationId = docId.hashCode & 0x7FFFFFFF;

    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: notificationId,
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
      _selectedSalesUserId = data['assigned_to']; // Retain assigned user
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
      final cache = UserCacheService.instance;
      await cache.ensureLoaded();
      assignedByName = cache.username ?? '';
      assignedTo = salesUser['uid'];
      assignedToName = salesUser['username'];
    } else {
      final cache = UserCacheService.instance;
      await cache.ensureLoaded();
      email = cache.email ?? user.email ?? 'unknown@example.com';
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
      await FirebaseFirestore.instance.collection('todo').doc(widget.docId!).update({
        'title': title,
        'userId': user.uid, // Add userId for daily_report
        'description': desc,
        'priority': _priority,
        'reminder': scheduledDate.toIso8601String(),
        'email': email,
        'created_by': createdBy,
        'assigned_by': assignedBy,
        'assigned_by_name': assignedByName,
        'assigned_to': assignedTo,
        'assigned_to_name': assignedToName,
        if (assignedBy != null) 'assignment_seen': false,
        // Optionally update other fields as needed
      });

      await _clearDraft();

      // Daily report entry for edits (deduplicated per 12PM–12PM IST window)
      await _createDailyReportIfNeeded(
        userId: createdBy,
        documentId: widget.docId!,
        type: 'todo',
      );

      // Reschedule notification if the reminder was changed
      // Only schedule for self-assigned tasks
      if (_currentUserRole != 'manager' || (_currentUserRole == 'manager' && (_selectedSalesUserId == null || _selectedSalesUserId == user.uid))) {
        await AwesomeNotifications().cancel(widget.docId!.hashCode & 0x7FFFFFFF); // Cancel old one
        await _scheduleNotification(scheduledDate, title, widget.docId!); // Schedule new one
      }

      await updateTodoWidgetFromFirestore(); // After saving/updating todo

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

    await _clearDraft();

    // Daily report entry for new todo (deduplicated per 12PM–12PM IST window)
    await _createDailyReportIfNeeded(
      userId: createdBy,
      documentId: todoRef.id,
      type: 'todo',
    );

    // 🔔 Only schedule notification if assigned to self
    if (_currentUserRole != 'manager' || (_currentUserRole == 'manager' && (_selectedSalesUserId == null || _selectedSalesUserId == user.uid))) {
      await _scheduleNotification(scheduledDate, title, todoRef.id);
    }

    await updateTodoWidgetFromFirestore(); // After saving/updating todo

    if (mounted) {
      Navigator.pop(context);
    }
    // Don't call setState after pop, as the widget is disposed
  }

  Future<void> _saveDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final draftData = {
      'title': _titleController.text,
      'description': _descController.text,
      'priority': _priority,
      'reminder': _reminderController.text,
      'selectedSalesUserId': _selectedSalesUserId,
      'reminder_date': _selectedReminderDate?.toIso8601String(),
      'reminder_hour': _selectedReminderTime?.hour,
      'reminder_minute': _selectedReminderTime?.minute,
    };
    await prefs.setString(TodoFormPage.DRAFT_KEY, jsonEncode(draftData));
  }

  Future<void> _loadDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final draftJson = prefs.getString(TodoFormPage.DRAFT_KEY);

    if (draftJson == null) return;

    final draftData = jsonDecode(draftJson) as Map<String, dynamic>;

    final hasData = (draftData['title'] as String? ?? '').isNotEmpty ||
                    (draftData['description'] as String? ?? '').isNotEmpty;

    if (hasData && mounted) {
      final load = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Draft Found'),
          content: const Text('An unsaved To-Do was found. Would you like to load it?'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Start New')),
            ElevatedButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Load Draft')),
          ],
        ),
      );

      if (load == true) {
        setState(() {
          _titleController.text = draftData['title'] ?? '';
          _descController.text = draftData['description'] ?? '';
          _priority = draftData['priority'] ?? 'High';
          _reminderController.text = draftData['reminder'] ?? '';
          _selectedSalesUserId = draftData['selectedSalesUserId'];
          if (draftData['reminder_date'] != null) {
            _selectedReminderDate = DateTime.tryParse(draftData['reminder_date']);
          }
          if (draftData['reminder_hour'] != null && draftData['reminder_minute'] != null) {
            _selectedReminderTime = TimeOfDay(hour: draftData['reminder_hour'], minute: draftData['reminder_minute']);
          }
        });
      }
    }
  }

  Future<void> _clearDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(TodoFormPage.DRAFT_KEY);
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
                onChanged: (_) => _saveDraft(),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: inputFillColor,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  hintText: 'Enter task title',
                  hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey),
                  errorText: _titleController.text.isEmpty ? 'Title is required' : null,
                ),
              ),
              const SizedBox(height: 18),
              Text('Description', style: TextStyle(color: labelColor, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              TextField(
                controller: _descController,
                style: TextStyle(color: inputTextColor),
                onChanged: (_) => _saveDraft(),
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
                      onChanged: (val) {
                        setState(() => _selectedSalesUserId = val);
                        _saveDraft();
                      },
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
                onChanged: (val) {
                  setState(() => _priority = val!);
                  _saveDraft();
                },
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
                      _saveDraft();
                    }
                  }
                },
              ),
              const SizedBox(height: 45), // Replaced Spacer with SizedBox for positioning
              // const Spacer(), // This was pushing the button to the bottom
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
