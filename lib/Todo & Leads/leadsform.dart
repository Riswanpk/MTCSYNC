import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import 'leads.dart'; // Make sure this import exists
import '../../Dashboard/leadscount.dart'; // <-- Add this import

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

// Add this helper:
Future<List<Contact>> getCachedContacts() async {
  final prefs = await SharedPreferences.getInstance();
  final cached = prefs.getString('contacts_cache');
  if (cached != null) {
    final List<dynamic> decoded = jsonDecode(cached);
    return decoded.map((c) => Contact.fromJson(c)).toList();
  }
  return [];
}

class FollowUpForm extends StatefulWidget {
  static const String DRAFT_KEY = 'leads_form_draft';

  const FollowUpForm({super.key});

  @override
  State<FollowUpForm> createState() => _FollowUpFormState();
}

class _FollowUpFormState extends State<FollowUpForm> {
  final _formKey = GlobalKey<FormState>();

  // REMOVE date controller
  // final TextEditingController _dateController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController(text: '+91 ');
  final TextEditingController _commentsController = TextEditingController();
  final TextEditingController _reminderController = TextEditingController();

  String _status = 'In Progress';
  String _priority = 'High';
  TimeOfDay? _selectedReminderTime;
  List<Contact>? _deviceContacts; // Cache device contacts in memory
  bool _deviceContactsLoading = false;
  bool _isSaving = false;

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
        'date': DateTime.now(),
        'name': _nameController.text.trim(),
        'address': _addressController.text.trim(),
        'phone': _phoneController.text.trim(),
        'status': _status,
        'priority': _priority,
        'comments': _commentsController.text.trim(),
        'reminder': _reminderController.text.trim(),
        'branch': branch,
        'created_by': user.uid,
        'created_at': FieldValue.serverTimestamp(),
      });

      // Increment global leads count
      await LeadCountService.incrementLeadCount(branch: branch);

      await _clearDraft(); // Clear draft on successful save

      // Upsert customer profile
      await FirebaseFirestore.instance
          .collection('customer')
          .doc(_phoneController.text)
          .set({
        'name': _nameController.text,
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

        final scheduledDate = DateTime( // Swapped year and day
          int.parse(datePart[2]),
          int.parse(datePart[1]),
          int.parse(datePart[0]),
          _selectedReminderTime!.hour,
          _selectedReminderTime!.minute,
        );

        // Schedule notification with Edit button and docId payload
        await AwesomeNotifications().createNotification(
          content: NotificationContent(
            id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
            channelKey: 'basic_channel', // Use basic_channel for consistency
            title: 'Follow-Up Reminder',
            body: 'Reminder for ${_nameController.text.trim()}',
            notificationLayout: NotificationLayout.Default,
            payload: {
              'docId': followUpRef.id,
              'type': 'lead', // Specify that this is a lead
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

  Future<void> _saveDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final draftData = {
      'name': _nameController.text,
      'address': _addressController.text,
      'phone': _phoneController.text,
      'comments': _commentsController.text,
      'reminder': _reminderController.text,
      'status': _status,
      'priority': _priority,
      'reminder_hour': _selectedReminderTime?.hour,
      'reminder_minute': _selectedReminderTime?.minute,
    };
    await prefs.setString(FollowUpForm.DRAFT_KEY, jsonEncode(draftData));
  }

  Future<void> _loadDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final draftJson = prefs.getString(FollowUpForm.DRAFT_KEY);

    if (draftJson == null) return;

    final draftData = jsonDecode(draftJson) as Map<String, dynamic>;

    final hasData = (draftData['name'] as String? ?? '').isNotEmpty ||
                    (draftData['phone'] as String? ?? '').isNotEmpty ||
                    (draftData['comments'] as String? ?? '').isNotEmpty;

    if (hasData && mounted) {
      final load = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Draft Found'),
          content: const Text('An unsaved follow-up form was found. Would you like to load it?'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Start New')),
            ElevatedButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Load Draft')),
          ],
        ),
      );

      if (load == true) {
        setState(() {
          _nameController.text = draftData['name'] ?? '';
          _addressController.text = draftData['address'] ?? '';
          _phoneController.text = draftData['phone'] ?? '+91 ';
          _commentsController.text = draftData['comments'] ?? '';
          _reminderController.text = draftData['reminder'] ?? '';
          _status = draftData['status'] ?? 'In Progress';
          _priority = draftData['priority'] ?? 'High';
          if (draftData['reminder_hour'] != null && draftData['reminder_minute'] != null) {
            _selectedReminderTime = TimeOfDay(hour: draftData['reminder_hour'], minute: draftData['reminder_minute']);
          }
        });
      }
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
        _addressController.text = data['address'] ?? '';
        // You can add more fields if needed
      });
    }
  }

  Future<void> _clearDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(FollowUpForm.DRAFT_KEY);
  }

  @override
  void initState() {
    super.initState();
    // REMOVE date field logic
    if (!_phoneController.text.startsWith('+91 ')) {
      _phoneController.text = '+91 ';
    }
    // Check for a draft when the form loads
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDraft());

    // PREFETCH device contacts to warm cache and speed up picker
    // (do not await here so UI startup is not blocked)
    _loadDeviceContacts();
  }

  Future<void> _loadDeviceContacts() async {
    if (_deviceContactsLoading || (_deviceContacts != null && _deviceContacts!.isNotEmpty)) {
      // Already loading or already loaded contacts, no need to fetch again immediately
      return;
    }

    setState(() {
      _deviceContactsLoading = true;
    });

    try {
      var status = await Permission.contacts.status;
      if (!status.isGranted) {
        await Permission.contacts.request(); // Request if not granted (fallback)
        status = await Permission.contacts.status;
      }
      if (!status.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Contact permission denied')));
        }
        return;
      }

      // Load from cache first for immediate display
      List<Contact> cached = await getCachedContacts();
      if (cached.isNotEmpty && mounted) {
        setState(() {
          _deviceContacts = cached;
        });
      }

      // Fetch latest contacts in background and update cache/state
      final latestContacts = await FlutterContacts.getContacts(withProperties: true, withThumbnail: false);
      final encoded = jsonEncode(latestContacts.map((c) => c.toJson()).toList());
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('contacts_cache', encoded);
      if (mounted) {
        setState(() => _deviceContacts = latestContacts);
      }
    } finally {
      if (mounted) setState(() => _deviceContactsLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
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
                  // REMOVE date field from form
                  // TextFormField(
                  //   controller: _dateController,
                  //   readOnly: true,
                  //   decoration: const InputDecoration(
                  //     labelText: 'Date',
                  //     prefixIcon: Icon(Icons.calendar_today),
                  //   ),
                  // ),
                  // const SizedBox(height: 16),
                  FutureBuilder<DocumentSnapshot>(
                    future: FirebaseFirestore.instance
                        .collection('users')
                        .doc(FirebaseAuth.instance.currentUser!.uid)
                        .get(),
                    builder: (context, userSnap) {
                      if (!userSnap.hasData) return const SizedBox();
                      final branch = userSnap.data!.get('branch') ?? '';
                      return RawAutocomplete<Map<String, dynamic>>(
                        textEditingController: _nameController,
                        focusNode: FocusNode(),
                        optionsBuilder:
                            (TextEditingValue textEditingValue) async {
                          if (textEditingValue.text.isEmpty) {
                            return const Iterable<Map<String, dynamic>>.empty();
                          }
                          return await fetchCustomerSuggestions(
                              textEditingValue.text, branch);
                        },
                        displayStringForOption: (option) => option['name'] ?? '',
                        fieldViewBuilder:
                            (context, controller, focusNode, onFieldSubmitted) {
                          return TextFormField(
                            controller: controller,
                            focusNode: focusNode,
                            decoration: const InputDecoration(
                              labelText: 'Customer Name',
                              prefixIcon: Icon(Icons.person),
                            ),
                            validator: (value) =>
                                value!.isEmpty ? 'Enter name' : null,
                            onChanged: (_) => _saveDraft(),
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
                                      onTap: () => onSelected(option),
                                    );
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                        onSelected: (selectedCustomer) {
                          setState(() {
                            _nameController.text =
                                selectedCustomer['name'] ?? '';
                            _addressController.text =
                                selectedCustomer['address'] ?? '';
                            _phoneController.text =
                                selectedCustomer['phone'] ?? '';
                          });
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _addressController,
                    decoration: const InputDecoration(
                      labelText: 'Address',
                      prefixIcon: Icon(Icons.location_on),
                    ),
                    validator: (value) => value!.isEmpty ? 'Enter address' : null,
                    onChanged: (_) => _saveDraft(),
                  ),
                  const SizedBox(height: 16),
                  RawAutocomplete<Map<String, dynamic>>(
                    textEditingController: _phoneController,
                    focusNode: FocusNode(),
                    optionsBuilder:
                        (TextEditingValue textEditingValue) async {
                      if (textEditingValue.text.isEmpty) {
                        return const Iterable<Map<String, dynamic>>.empty();
                      }
                      final user = FirebaseAuth.instance.currentUser;
                      if (user == null) return const Iterable<Map<String, dynamic>>.empty();
                      final userDoc = await FirebaseFirestore.instance
                          .collection('users')
                          .doc(user.uid)
                          .get();
                      final branch = userDoc.data()?['branch'] ?? '';
                      return await fetchCustomerSuggestions(
                          textEditingValue.text, branch);
                    },
                    displayStringForOption: (option) => option['phone'] ?? '',
                    fieldViewBuilder:
                        (context, controller, focusNode, onFieldSubmitted) {
                      return TextFormField(
                        controller: controller,
                        focusNode: focusNode,
                        decoration: InputDecoration(
                          labelText: 'Phone',
                          prefixIcon: const Icon(Icons.phone),
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.paste),
                                tooltip: 'Paste from clipboard',
                                onPressed: () async {
                                  final clipboardData =
                                      await Clipboard.getData('text/plain');
                                  if (clipboardData != null &&
                                      clipboardData.text != null) {
                                    final digits = RegExp(r'\d')
                                        .allMatches(clipboardData.text!)
                                        .map((m) => m.group(0))
                                        .join();
                                    if (digits.length >= 10) {
                                      final tenDigits =
                                          digits.substring(digits.length - 10);
                                      final formatted =
                                          '+91 ${tenDigits.substring(0, 5)} ${tenDigits.substring(5)}';
                                      _phoneController.text = formatted;
                                      _phoneController.selection =
                                          TextSelection.fromPosition(
                                        TextPosition(offset: formatted.length),
                                      );
                                    } else {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(const SnackBar(
                                              content: Text(
                                                  'Clipboard does not contain 10 digits')));
                                    }
                                  }
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.contacts),
                                tooltip: 'Pick from contacts',
                                onPressed: () async {
                                  // Trigger background refresh if not already loading
                                  if (_deviceContacts == null && !_deviceContactsLoading) {
                                    _loadDeviceContacts(); // do not await - open modal immediately
                                  }

                                  var status = await Permission.contacts.status;
                                  if (!status.isGranted) {
                                    final granted = await FlutterContacts.requestPermission();
                                    if (!granted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Contact permission denied')),
                                      );
                                      return;
                                    }
                                  }

                                  // Open modal immediately with whatever we have in memory (may be cached)
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
                                            initialLoading: _deviceContactsLoading,
                                            scrollController: scrollController,
                                            onSelect: (name, phone) {
                                              final digits = RegExp(r'\d')
                                                  .allMatches(phone)
                                                  .map((m) => m.group(0))
                                                  .join();
                                              if (digits.length >= 10) {
                                                final tenDigits = digits.substring(digits.length - 10);
                                                final formatted =
                                                    '+91 ${tenDigits.substring(0, 5)} ${tenDigits.substring(5)}';
                                                setState(() {
                                                  _phoneController.text = formatted;
                                                  _phoneController.selection = TextSelection.fromPosition(
                                                    TextPosition(offset: formatted.length),
                                                  );
                                                  if (name.isNotEmpty) _nameController.text = name;
                                                });
                                              } else {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  const SnackBar(content: Text('Contact does not contain a valid 10-digit phone number')),
                                                );
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
                          if (value == null || value.isEmpty || !value.startsWith('+91 ')) {
                            return 'Phone must start with +91 ';
                          }
                          if (value.trim() == '+91') {
                            return 'Enter phone number';
                          }
                          final digits = value.replaceAll(RegExp(r'\D'), '');
                          if (digits.length != 12) {
                            return 'Enter a valid 10-digit number after +91';
                          }
                          return null;
                        },
                        onChanged: (val) {
                          _saveDraft();
                          if (!val.startsWith('+91 ')) {
                            controller.text = '+91 ';
                            controller.selection = TextSelection.fromPosition(
                              TextPosition(offset: controller.text.length),
                            );
                            return;
                          }
                          String raw = val.replaceAll('+91 ', '').replaceAll(' ', '');
                          if (raw.length > 10) raw = raw.substring(0, 10);
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
                                  onTap: () => onSelected(option),
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
                        _addressController.text = selectedCustomer['address'] ?? '';
                        _phoneController.text = selectedCustomer['phone'] ?? '';
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _commentsController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Comments',
                      alignLabelWithHint: true,
                      prefixIcon: Padding(
                        padding: EdgeInsets.only(bottom: 60.0),
                        child: Icon(Icons.comment),
                      ),
                    ),
                    validator: (value) => value!.isEmpty ? 'Enter comments' : null,
                    onChanged: (_) => _saveDraft(),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<String>(
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
                          onChanged: (value) {
                            setState(() => _priority = value!);
                            _saveDraft();
                          },
                          validator: (value) => value == null || value.isEmpty ? 'Select priority' : null,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          controller: _reminderController,
                          readOnly: true,
                          decoration: const InputDecoration(
                            labelText: 'Reminder',
                            prefixIcon: Icon(Icons.alarm),
                          ),
                          onTap: () async {
                            final pickedDate = await showDatePicker(
                              context: context,
                              initialDate: DateTime.now(),
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now().add(const Duration(days: 15)),
                            );
                            if (pickedDate == null) return;
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
                              _reminderController.text =
                                  "${formatted.day.toString().padLeft(2, '0')}-${formatted.month.toString().padLeft(2, '0')}-${formatted.year} ${pickedTime.format(context)}";
                              _saveDraft();
                            }
                          },
                          validator: (value) => value!.isEmpty ? 'Select reminder' : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),
                  ElevatedButton(
                    onPressed: _saveFollowUp,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF005BAC),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Save Follow Up',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
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

// Add the modal widget below the class (or near the end of the file)
class ContactPickerModal extends StatefulWidget {
  final List<Contact>? initialContacts;
  final bool initialLoading;
  final ScrollController scrollController;
  final void Function(String name, String phone) onSelect;

  const ContactPickerModal({
    super.key,
    required this.initialContacts,
    required this.initialLoading,
    required this.scrollController,
    required this.onSelect,
  });

  @override
  State<ContactPickerModal> createState() => _ContactPickerModalState();
}

class _ContactPickerModalState extends State<ContactPickerModal> {
  List<Contact> _contacts = [];
  List<Contact> _filtered = [];
  bool _loading = true;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _contacts = widget.initialContacts ?? [];
    _filtered = List.from(_contacts);
    _loading = widget.initialLoading;
    // If no contacts available immediately, load cached contacts fast
    if (_contacts.isEmpty) {
      _loadCachedThenFresh();
    } else {
      // even if we have some in-memory contacts, still refresh in background for freshness
      _refreshContactsInBackground();
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _loadCachedThenFresh() async {
    setState(() => _loading = true);
    try {
      // Try cached first (fast)
      final cached = await getCachedContacts();
      if (cached.isNotEmpty && mounted) {
        setState(() {
          _contacts = cached;
          _filtered = List.from(_contacts);
          _loading = false;
        });
      }
      // Fetch latest contacts in background and update cache & UI when ready
      await _refreshContactsInBackground();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshContactsInBackground() async {
    try {
      final granted = await FlutterContacts.requestPermission();
      if (!granted) return;
      final latest = await FlutterContacts.getContacts(withProperties: true, withPhoto: false);
      if (!mounted) return;
      // update shared prefs cache
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(latest.map((c) => c.toJson()).toList());
      await prefs.setString('contacts_cache', encoded);

      setState(() {
        _contacts = latest;
        _applyFilter(_searchController.text);
        _loading = false;
      });
    } catch (e) {
      // ignore errors - leave whatever we have
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyFilter(String q) {
    final qLower = q.toLowerCase();
    final qDigits = RegExp(r'\d').allMatches(q).map((m) => m.group(0)).join();
    setState(() {
      if (q.isEmpty) {
        _filtered = List.from(_contacts);
        return;
      }
      _filtered = _contacts.where((c) {
        final name = (c.displayName ?? '').toLowerCase();
        final phoneRaw = c.phones.isNotEmpty ? (c.phones.first.number ?? '') : '';
        final phoneDigits = RegExp(r'\d').allMatches(phoneRaw).map((m) => m.group(0)).join();
        final matchesName = name.contains(qLower);
        final matchesPhone = qDigits.isNotEmpty ? phoneDigits.contains(qDigits) : phoneRaw.toLowerCase().contains(qLower);
        return matchesName || matchesPhone;
      }).toList();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search contacts...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    _searchController.clear();
                    _applyFilter('');
                  },
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onChanged: (v) => _applyFilter(v), // filter on each keypress
            ),
          ),
          Expanded(
            child: _loading && _contacts.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : (_filtered.isEmpty
                    ? Center(child: Text(_contacts.isEmpty ? 'No contacts found' : 'No matching contacts'))
                    : ListView.builder(
                        controller: widget.scrollController,
                        itemCount: _filtered.length,
                        itemBuilder: (context, index) {
                          final contact = _filtered[index];
                          final phone = contact.phones.isNotEmpty ? (contact.phones.first.number ?? 'No number') : 'No number';
                          return ListTile(
                            leading: const Icon(Icons.person_outline),
                            title: Text(contact.displayName ?? ''),
                            subtitle: Text(phone),
                            onTap: () {
                              widget.onSelect(contact.displayName ?? '', phone);
                              Navigator.pop(context);
                            },
                          );
                        },
                      )),
          ),
        ],
      ),
    );
  }
}
