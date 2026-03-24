import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:getwidget/getwidget.dart';
import '../Leads/leads_helpers.dart';
import '../Leads/contact_picker_modal.dart';
import '../Misc/user_cache_service.dart';

class SmeLeadForm extends StatefulWidget {
  const SmeLeadForm({super.key});

  @override
  State<SmeLeadForm> createState() => _SmeLeadFormState();
}

class _SmeLeadFormState extends State<SmeLeadForm> {
  final _formKey = GlobalKey<FormState>();

  static const Color _brandPrimary = Color(0xFF005BAC);
  static const Color _brandAccent = Color(0xFF008BD6);
  static const Color _surfaceBackground = Color(0xFFF4F8FC);

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _phoneController =
      TextEditingController(text: '+91 ');
  final TextEditingController _commentsController = TextEditingController();
  final TextEditingController _reminderController = TextEditingController();

  String _priority = 'High';
  TimeOfDay? _selectedReminderTime;
  List<Contact>? _deviceContacts;
  bool _deviceContactsLoading = false;
  bool _isSaving = false;

  // Assignment fields
  List<String> _branches = [];
  String? _selectedBranch;
  List<Map<String, dynamic>> _branchUsers = [];
  String? _selectedUserId;
  String? _selectedUserName;
  bool _loadingUsers = false;

  @override
  void initState() {
    super.initState();
    _loadBranches();
    _loadDeviceContacts();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _commentsController.dispose();
    _reminderController.dispose();
    super.dispose();
  }

  Future<void> _loadBranches() async {
    final branches = await UserCacheService.instance.getBranches();
    if (mounted) setState(() => _branches = branches);
  }

  Future<void> _loadUsersForBranch(String branch) async {
    setState(() {
      _loadingUsers = true;
      _selectedUserId = null;
      _selectedUserName = null;
      _branchUsers = [];
    });

    final snapshot = await FirebaseFirestore.instance
      .collection('users')
      .where('branch', isEqualTo: branch)
      .where('role', whereIn: ['manager', 'asst_manager', 'sales']).get();

    final users = snapshot.docs.map((doc) {
      final data = doc.data();
      return {
        'id': doc.id,
        'username': data['username'] ?? 'Unknown',
        'role': data['role'] ?? '',
      };
    }).toList();

    users.sort(
        (a, b) => (a['username'] as String).compareTo(b['username'] as String));

    if (mounted) {
      setState(() {
        _branchUsers = users;
        _loadingUsers = false;
      });
    }
  }

  Future<void> _loadDeviceContacts() async {
    if (_deviceContactsLoading ||
        (_deviceContacts != null && _deviceContacts!.isNotEmpty)) return;
    setState(() => _deviceContactsLoading = true);

    try {
      var status = await Permission.contacts.status;
      if (!status.isGranted) {
        await Permission.contacts.request();
        status = await Permission.contacts.status;
      }
      if (!status.isGranted) return;

      List<Contact> cached = await getCachedContacts();
      if (cached.isNotEmpty && mounted) {
        setState(() => _deviceContacts = cached);
      }

      final latestContacts = await FlutterContacts.getContacts(
          withProperties: true, withThumbnail: false);
      final encoded =
          jsonEncode(latestContacts.map((c) => c.toJson()).toList());
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('contacts_cache', encoded);
      if (mounted) setState(() => _deviceContacts = latestContacts);
    } finally {
      if (mounted) setState(() => _deviceContactsLoading = false);
    }
  }

  Future<void> _saveFollowUp() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedBranch == null || _selectedUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please select a branch and user to assign')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('User not logged in')));
        return;
      }

      final followUpRef =
          await FirebaseFirestore.instance.collection('follow_ups').add({
        'date': DateTime.now(),
        'name': _nameController.text.trim(),
        'address': _addressController.text.trim(),
        'phone': _phoneController.text.trim(),
        'status': 'In Progress',
        'priority': _priority,
        'comments': _commentsController.text.trim(),
        'reminder': _reminderController.text.trim(),
        'branch': _selectedBranch,
        'created_by': user.uid,
        'created_at': FieldValue.serverTimestamp(),
        'assigned_to': _selectedUserId,
        'assigned_to_name': _selectedUserName,
        'assigned_by': user.uid,
        'source': 'sme',
      });

      // Upsert customer profile
      await FirebaseFirestore.instance
          .collection('customer')
          .doc(_phoneController.text.trim())
          .set({
        'name': _nameController.text.trim(),
        'address': _addressController.text.trim(),
        'phone': _phoneController.text.trim(),
        'branch': _selectedBranch,
      }, SetOptions(merge: true));

      // Build the reminder Timestamp (if set) so the assigned user's device can schedule it
      Timestamp? reminderTimestamp;
      if (_selectedReminderTime != null &&
          _reminderController.text.isNotEmpty) {
        final reminderParts = _reminderController.text.split(' ');
        final datePart = reminderParts[0].split('-');
        final scheduledDate = DateTime(
          int.parse(datePart[2]),
          int.parse(datePart[1]),
          int.parse(datePart[0]),
          _selectedReminderTime!.hour,
          _selectedReminderTime!.minute,
        );
        reminderTimestamp = Timestamp.fromDate(scheduledDate);
      }

      // Call Cloud Function to send FCM push notification to assigned user
      final notifPayload = <String, dynamic>{
        'recipientUid': _selectedUserId,
        'title': 'New Lead Assigned',
        'body':
            'A new lead "${_nameController.text.trim()}" has been assigned to you by SME.',
        'leadDocId': followUpRef.id,
        'leadName': _nameController.text.trim(),
      };
      if (reminderTimestamp != null) {
        notifPayload['reminderAt'] = reminderTimestamp.millisecondsSinceEpoch;
      }
      await FirebaseFunctions.instanceFor(region: 'asia-south1')
          .httpsCallable('sendLeadAssignmentNotification')
          .call(notifPayload);

      // Daily report tracking
      await createDailyReportIfNeededLeads(
        userId: user.uid,
        documentId: followUpRef.id,
        type: 'leads',
      );

      if (mounted) {
        Navigator.of(context).pop(true); // Return true to indicate success
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _pickReminderDateTime() async {
    final now = DateTime.now();
    final initialDate = now;
    final initialTime = TimeOfDay(
      hour: now.add(const Duration(minutes: 1)).hour,
      minute: now.add(const Duration(minutes: 1)).minute,
    );
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: initialDate,
      lastDate: initialDate.add(const Duration(days: 365)),
    );
    if (pickedDate == null) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );
    if (pickedTime == null) return;

    setState(() {
      _selectedReminderTime = pickedTime;
      final dt = DateTime(pickedDate.year, pickedDate.month, pickedDate.day,
          pickedTime.hour, pickedTime.minute);
      final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final period = dt.hour >= 12 ? 'PM' : 'AM';
      _reminderController.text =
          '${dt.day.toString().padLeft(2, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.year} '
          '${hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} $period';
    });
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    Widget? suffixIcon,
    String? hint,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      prefixIcon: Icon(icon, color: _brandPrimary),
      suffixIcon: suffixIcon,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.blueGrey.shade100),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.blueGrey.shade100),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _brandPrimary, width: 1.8),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return GFCard(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      color: Colors.white,
      title: GFListTile(
        padding: const EdgeInsets.fromLTRB(0, 10, 0, 4),
        margin: EdgeInsets.zero,
        avatar: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: _brandPrimary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: _brandPrimary),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontFamily: 'Montserrat',
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Color(0xFF143A52),
          ),
        ),
      ),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          backgroundColor: _surfaceBackground,
          appBar: GFAppBar(
            titleSpacing: 0,
            elevation: 0,
            iconTheme: const IconThemeData(color: Colors.white),
            textTheme: const TextTheme(
              titleLarge: TextStyle(color: Colors.white, fontSize: 20),
            ),
            title: const Text(
              'New SME Lead',
              style: TextStyle(
                  fontFamily: 'Montserrat', fontWeight: FontWeight.w700),
            ),
            flexibleSpace: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [_brandPrimary, _brandAccent],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),
          body: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: const LinearGradient(
                      colors: [Color(0xFFE2F4FF), Color(0xFFF2FAFF)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(color: const Color(0xFFB3DEFA)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.add_task_rounded,
                            color: _brandPrimary),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Assign branch, select user, and capture lead details in one flow.',
                          style: TextStyle(
                            color: Color(0xFF13476B),
                            fontFamily: 'PTSans',
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _sectionCard(
                  title: 'Assignment',
                  icon: Icons.account_tree_rounded,
                  children: [
                    DropdownButtonFormField<String>(
                      value: _selectedBranch,
                      items: _branches
                          .map(
                              (b) => DropdownMenuItem(value: b, child: Text(b)))
                          .toList(),
                      onChanged: (val) {
                        setState(() => _selectedBranch = val);
                        if (val != null) _loadUsersForBranch(val);
                      },
                      decoration: _inputDecoration(
                        label: 'Assign to Branch *',
                        icon: Icons.business,
                        hint: 'Choose branch',
                      ),
                      validator: (v) => v == null ? 'Select a branch' : null,
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      value: _selectedUserId,
                      items: _branchUsers
                          .map((u) => DropdownMenuItem(
                                value: u['id'] as String,
                                child: Text('${u['username']} (${u['role']})'),
                              ))
                          .toList(),
                      onChanged: (val) {
                        if (val == null) {
                          setState(() {
                            _selectedUserId = null;
                            _selectedUserName = null;
                          });
                          return;
                        }
                        final user =
                            _branchUsers.firstWhere((u) => u['id'] == val);
                        setState(() {
                          _selectedUserId = val;
                          _selectedUserName = user['username'] as String;
                        });
                      },
                      decoration: _inputDecoration(
                        label: 'Assign to User *',
                        icon: Icons.person_add,
                        hint: _selectedBranch == null
                            ? 'Pick branch first'
                            : 'Select user',
                        suffixIcon: _loadingUsers
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                ),
                              )
                            : null,
                      ),
                      validator: (v) => v == null ? 'Select a user' : null,
                    ),
                  ],
                ),
                _sectionCard(
                  title: 'Lead Details',
                  icon: Icons.badge_rounded,
                  children: [
                    TextFormField(
                      controller: _nameController,
                      decoration: _inputDecoration(
                        label: 'Customer Name *',
                        icon: Icons.person,
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Enter name' : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _addressController,
                      decoration: _inputDecoration(
                        label: 'Address',
                        icon: Icons.location_on,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _phoneController,
                      decoration: _inputDecoration(
                        label: 'Phone *',
                        icon: Icons.phone,
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.paste),
                              tooltip: 'Paste from clipboard',
                              onPressed: () async {
                                final clipboardData =
                                    await Clipboard.getData('text/plain');
                                if (clipboardData?.text != null) {
                                  final digits = RegExp(r'\d')
                                      .allMatches(clipboardData!.text!)
                                      .map((m) => m.group(0))
                                      .join();
                                  if (digits.length >= 10) {
                                    final tenDigits =
                                        digits.substring(digits.length - 10);
                                    _phoneController.text =
                                        '+91 ${tenDigits.substring(0, 5)} ${tenDigits.substring(5)}';
                                  }
                                }
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.contacts),
                              tooltip: 'Pick from contacts',
                              onPressed: () async {
                                if (_deviceContacts == null &&
                                    !_deviceContactsLoading) {
                                  _loadDeviceContacts();
                                }
                                var status = await Permission.contacts.status;
                                if (!status.isGranted) {
                                  final granted =
                                      await FlutterContacts.requestPermission();
                                  if (!granted) return;
                                }
                                showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  backgroundColor: Colors.transparent,
                                  builder: (context) {
                                    return DraggableScrollableSheet(
                                      initialChildSize: 0.85,
                                      minChildSize: 0.4,
                                      maxChildSize: 0.95,
                                      expand: false,
                                      builder: (context, scrollController) {
                                        return ContactPickerModal(
                                          initialContacts: _deviceContacts,
                                          initialLoading:
                                              _deviceContactsLoading,
                                          scrollController: scrollController,
                                          onSelect: (name, phone) {
                                            final digits = RegExp(r'\d')
                                                .allMatches(phone)
                                                .map((m) => m.group(0))
                                                .join();
                                            if (digits.length >= 10) {
                                              final tenDigits =
                                                  digits.substring(
                                                      digits.length - 10);
                                              setState(() {
                                                _phoneController.text =
                                                    '+91 ${tenDigits.substring(0, 5)} ${tenDigits.substring(5)}';
                                                if (name.isNotEmpty)
                                                  _nameController.text = name;
                                              });
                                            }
                                          },
                                        );
                                      },
                                    );
                                  },
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      keyboardType: TextInputType.phone,
                      validator: (value) {
                        if (value == null ||
                            value.isEmpty ||
                            !value.startsWith('+91 '))
                          return 'Phone must start with +91';
                        if (value.trim() == '+91') return 'Enter phone number';
                        final digits = value.replaceAll(RegExp(r'\D'), '');
                        if (digits.length != 12)
                          return 'Enter a valid 10-digit number after +91';
                        return null;
                      },
                      onChanged: (val) {
                        if (!val.startsWith('+91 ')) {
                          _phoneController.text = '+91 ';
                          _phoneController.selection =
                              TextSelection.fromPosition(
                            TextPosition(offset: _phoneController.text.length),
                          );
                          return;
                        }
                        String raw =
                            val.replaceAll('+91 ', '').replaceAll(' ', '');
                        if (raw.length > 10) raw = raw.substring(0, 10);
                        if (raw.length > 5) {
                          _phoneController.text =
                              '+91 ${raw.substring(0, 5)} ${raw.substring(5)}';
                        } else {
                          _phoneController.text = '+91 $raw';
                        }
                        _phoneController.selection = TextSelection.fromPosition(
                          TextPosition(offset: _phoneController.text.length),
                        );
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _commentsController,
                      maxLines: 3,
                      decoration: _inputDecoration(
                        label: 'Comments *',
                        icon: Icons.comment,
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Enter comments'
                          : null,
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      value: _priority,
                      items: ['High', 'Medium', 'Low']
                          .map(
                              (p) => DropdownMenuItem(value: p, child: Text(p)))
                          .toList(),
                      onChanged: (val) =>
                          setState(() => _priority = val ?? 'High'),
                      decoration: _inputDecoration(
                        label: 'Priority',
                        icon: Icons.flag,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _reminderController,
                      readOnly: true,
                      onTap: _pickReminderDateTime,
                      decoration: _inputDecoration(
                        label: 'Reminder',
                        icon: Icons.alarm,
                        hint: 'Select date and time',
                        suffixIcon: _reminderController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  setState(() {
                                    _reminderController.clear();
                                    _selectedReminderTime = null;
                                  });
                                },
                              )
                            : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                GFButton(
                  onPressed: _isSaving ? null : _saveFollowUp,
                  text: 'Assign Lead',
                  icon: const Icon(Icons.send_rounded, color: Colors.white),
                  color: _brandPrimary,
                  textColor: Colors.white,
                  fullWidthButton: true,
                  size: GFSize.LARGE,
                  shape: GFButtonShape.standard,
                  borderShape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontFamily: 'Montserrat',
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_isSaving)
          Container(
            color: Colors.black.withOpacity(0.3),
            child: Center(
              child: GFLoader(
                type: GFLoaderType.android,
                androidLoaderColor:
                    const AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
          ),
      ],
    );
  }
}
