import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mtcsync/Misc/notification_permission_service.dart';
import 'dart:convert';
import 'leads.dart';
import 'leads_helpers.dart';
import 'contact_picker_modal.dart';


class FollowUpForm extends StatefulWidget {
  static const String DRAFT_KEY = 'leads_form_draft';

  final String? initialName;
  final String? initialPhone;
  final String? initialAddress;
  final String source;

  const FollowUpForm({
    super.key,
    this.initialName,
    this.initialPhone,
    this.initialAddress,
    this.source = 'Sales',
  });

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

  // FocusNodes for RawAutocomplete widgets
  late FocusNode _nameFieldFocusNode;
  late FocusNode _phoneFieldFocusNode;

  String _status = 'In Progress';
  String _priority = 'High';
  TimeOfDay? _selectedReminderTime;
  List<Contact>? _deviceContacts; // Cache device contacts in memory
  bool _deviceContactsLoading = false;
  bool _isSaving = false;

  Future<void> _scheduleNotification(DateTime dateTime) async {
    await NotificationPermissionService.instance.safeCreateNotification(
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
      // Parse reminder date if provided for tracking original reminder date
      DateTime? parsedReminderDate;
      if (_reminderController.text.isNotEmpty && _selectedReminderTime != null) {
        final reminderParts = _reminderController.text.split(' ');
        final datePart = reminderParts[0].split('-');
        try {
          parsedReminderDate = DateTime(
            int.parse(datePart[2]),
            int.parse(datePart[1]),
            int.parse(datePart[0]),
            _selectedReminderTime!.hour,
            _selectedReminderTime!.minute,
          );
        } catch (e) {
          debugPrint('Error parsing reminder date: $e');
        }
      }

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
        'source': widget.source,
        // Track original reminder date for auto-reschedule logic
        if (parsedReminderDate != null) 'original_reminder_date': Timestamp.fromDate(parsedReminderDate),
        'reminder_date_changed': false, // Flag for manual reschedule
      });

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
        final notifId = int.tryParse(followUpRef.id.hashCode.abs().toString().substring(0, 7)) ?? 0;
        await NotificationPermissionService.instance.safeCreateNotification(
          content: NotificationContent(
            id: notifId,
            channelKey: 'basic_channel', // Use basic_channel for consistency
            title: 'Follow-Up Reminder',
            body: 'Reminder for ${_nameController.text.trim()}',
            notificationLayout: NotificationLayout.Default,
            payload: {
              'docId': followUpRef.id,
              'type': 'lead', // Specify that this is a lead
            },
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

      // Store daily_report (deduplicated per 12PM–12PM IST window)
      await createDailyReportIfNeededLeads(
        userId: user.uid,
        documentId: followUpRef.id,
        type: 'leads',
      );

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
    // Initialize FocusNodes
    _nameFieldFocusNode = FocusNode();
    _phoneFieldFocusNode = FocusNode();
    // REMOVE date field logic
    if (!_phoneController.text.startsWith('+91 ')) {
      _phoneController.text = '+91 ';
    }
    // Check for a draft when the form loads
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDraft());

    // PREFETCH device contacts to warm cache and speed up picker
    // (do not await here so UI startup is not blocked)
    _loadDeviceContacts();

    // Pre-fill fields if initial values are provided
    if (widget.initialName != null && widget.initialName!.isNotEmpty) {
      _nameController.text = widget.initialName!;
    }
    // If initialPhone is provided, always format it correctly
    if (widget.initialPhone != null && widget.initialPhone!.isNotEmpty) {
      _phoneController.text = formatIndianPhone(widget.initialPhone!);
    }
    if (widget.initialAddress != null && widget.initialAddress!.isNotEmpty) {
      _addressController.text = widget.initialAddress!;
    }
  }

  @override
  void dispose() {
    _nameFieldFocusNode.dispose();
    _phoneFieldFocusNode.dispose();
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _commentsController.dispose();
    _reminderController.dispose();
    super.dispose();
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
                        focusNode: _nameFieldFocusNode,
                        optionsBuilder:
                            (TextEditingValue textEditingValue) async {
                          if (textEditingValue.text.isEmpty) {
                            return const Iterable<Map<String, dynamic>>.empty();
                          }
                          // Check if widget is still mounted before making async call
                          if (!mounted) {
                            return const Iterable<Map<String, dynamic>>.empty();
                          }
                          try {
                            return await fetchCustomerSuggestions(
                                textEditingValue.text, branch);
                          } catch (e) {
                            debugPrint('Error in name autocomplete: $e');
                            return const Iterable<Map<String, dynamic>>.empty();
                          }
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
                            onChanged: (_) {
                              // Only save draft if widget is still mounted
                              if (mounted) {
                                _saveDraft();
                              }
                            },
                          );
                        },
                        optionsViewBuilder: (context, onSelected, options) {
                          if (options.isEmpty) {
                            return const SizedBox.shrink();
                          }
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
                          // Check if widget is still mounted before calling setState
                          if (mounted) {
                            setState(() {
                              _nameController.text =
                                  selectedCustomer['name'] ?? '';
                              _addressController.text =
                                  selectedCustomer['address'] ?? '';
                              _phoneController.text =
                                  formatIndianPhone(selectedCustomer['phone'] ?? '');
                            });
                          }
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
                    focusNode: _phoneFieldFocusNode,
                    optionsBuilder:
                        (TextEditingValue textEditingValue) async {
                      if (textEditingValue.text.isEmpty) {
                        return const Iterable<Map<String, dynamic>>.empty();
                      }
                      // Check if widget is still mounted before making async call
                      if (!mounted) {
                        return const Iterable<Map<String, dynamic>>.empty();
                      }
                      try {
                        final user = FirebaseAuth.instance.currentUser;
                        if (user == null) return const Iterable<Map<String, dynamic>>.empty();
                        final userDoc = await FirebaseFirestore.instance
                            .collection('users')
                            .doc(user.uid)
                            .get();
                        final branch = userDoc.data()?['branch'] ?? '';
                        return await fetchCustomerSuggestions(
                            textEditingValue.text, branch);
                      } catch (e) {
                        debugPrint('Error in phone autocomplete: $e');
                        return const Iterable<Map<String, dynamic>>.empty();
                      }
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
                                      if (mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(const SnackBar(
                                                content: Text(
                                                    'Clipboard does not contain 10 digits')));
                                      }
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
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Contact permission denied')),
                                        );
                                      }
                                      return;
                                    }
                                  }

                                  // Open modal immediately with whatever we have in memory (may be cached)
                                  if (mounted) {
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
                                                  if (mounted) {
                                                    setState(() {
                                                      _phoneController.text = formatted;
                                                      _phoneController.selection = TextSelection.fromPosition(
                                                        TextPosition(offset: formatted.length),
                                                      );
                                                      if (name.isNotEmpty) _nameController.text = name;
                                                    });
                                                  }
                                                } else {
                                                  if (mounted) {
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      const SnackBar(content: Text('Contact does not contain a valid 10-digit phone number')),
                                                    );
                                                  }
                                                }
                                              },
                                            );
                                          },
                                        );
                                      },
                                    );
                                  }
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
                          // Only save draft if widget is still mounted
                          if (mounted) {
                            _saveDraft();
                          }
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
                      if (options.isEmpty) {
                        return const SizedBox.shrink();
                      }
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
                      // Check if widget is still mounted before calling setState
                      if (mounted) {
                        setState(() {
                          _nameController.text = selectedCustomer['name'] ?? '';
                          _addressController.text = selectedCustomer['address'] ?? '';
                          _phoneController.text = formatIndianPhone(selectedCustomer['phone'] ?? '');
                        });
                      }
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
                              lastDate: initialDate.add(const Duration(days: 15)),
                            );
                            if (pickedDate == null) return;
                            final pickedTime = await showTimePicker(
                              context: context,
                              initialTime: initialTime,
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
            color: Colors.black.withValues(alpha: 0.3),
            child: const Center(
              child: CircularProgressIndicator(),
            ),
          ),
      ],
    );
  }
}
