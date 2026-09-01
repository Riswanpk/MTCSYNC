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

  final String? docId;
  final String? initialName;
  final String? initialPhone;
  final String? initialAddress;
  final String? initialComments;
  final String? initialPlatform;
  final String? initialPriority;
  final String? initialAdName;
  final String source;

  const FollowUpForm({
    super.key,
    this.docId,
    this.initialName,
    this.initialPhone,
    this.initialAddress,
    this.initialComments,
    this.initialPlatform,
    this.initialPriority,
    this.initialAdName,
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
  final TextEditingController _adNameController = TextEditingController();

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
        channelKey: 'basic_channel',
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
        preciseAlarm: true,
        allowWhileIdle: true,
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

      final payload = <String, dynamic>{
        'name': _nameController.text.trim(),
        'address': _addressController.text.trim(),
        'phone': _phoneController.text.trim(),
        'status': _status,
        'priority': _priority,
        'comments': _commentsController.text.trim(),
        'reminder': _reminderController.text.trim(),
        'branch': branch,
        'source': widget.source,
        if (widget.initialPlatform != null && widget.initialPlatform!.isNotEmpty) 'platform': widget.initialPlatform,
        if (widget.initialAdName != null && widget.initialAdName!.isNotEmpty) 'ad_name': widget.initialAdName,
        if (parsedReminderDate != null) 'original_reminder_date': Timestamp.fromDate(parsedReminderDate),
        'reminder_date_changed': false,
      };

      DocumentReference followUpRef;
      if (widget.docId != null && widget.docId!.isNotEmpty) {
        followUpRef = FirebaseFirestore.instance.collection('follow_ups').doc(widget.docId);
        await followUpRef.update(payload);
      } else {
        payload['date'] = DateTime.now();
        payload['created_by'] = user.uid;
        payload['created_at'] = FieldValue.serverTimestamp();
        followUpRef = await FirebaseFirestore.instance.collection('follow_ups').add(payload);
      }

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
        final hashStr = followUpRef.id.hashCode.abs().toString();
        final notifId = int.tryParse(hashStr.length >= 7 ? hashStr.substring(0, 7) : hashStr) ?? 0;
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
            allowWhileIdle: true,
          ),
        );
      }

      if (widget.source == 'SME') {
        if (mounted) Navigator.pop(context, true);
      } else {
        Navigator.pop(context);
        // After saving, navigate to LeadsPage
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => LeadsPage(branch: branch),
            ),
          );
        }
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
    if (widget.initialComments != null && widget.initialComments!.isNotEmpty) {
      _commentsController.text = widget.initialComments!;
    }
    if (widget.initialPriority != null && widget.initialPriority!.isNotEmpty) {
      _priority = widget.initialPriority!;
    }
    if (widget.initialAdName != null && widget.initialAdName!.isNotEmpty) {
      _adNameController.text = widget.initialAdName!;
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryGradient = const LinearGradient(
      colors: [Color(0xFF005BAC), Color(0xFF008BD6)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    InputDecoration buildInputDecoration({
      required String label,
      required IconData icon,
      Widget? suffixIcon,
    }) {
      return InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        prefixIcon: Icon(icon, color: const Color(0xFF005BAC), size: 20),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF005BAC), width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
        ),
      );
    }

    Widget buildCardSection({required String title, required IconData icon, required List<Widget> children}) {
      return Container(
        margin: const EdgeInsets.only(bottom: 20),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.04),
              blurRadius: 14,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF005BAC).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: const Color(0xFF005BAC), size: 18),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            ...children,
          ],
        ),
      );
    }

    return Stack(
      children: [
        Scaffold(
          backgroundColor: isDark ? const Color(0xFF0B0F17) : const Color(0xFFF1F5F9),
          appBar: AppBar(
            title: const Text(
              'New Follow Up',
              style: TextStyle(fontWeight: FontWeight.w700, fontFamily: 'Montserrat'),
            ),
            flexibleSpace: Container(decoration: BoxDecoration(gradient: primaryGradient)),
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  buildCardSection(
                    title: 'Customer Details',
                    icon: Icons.person_rounded,
                    children: [
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
                            optionsBuilder: (TextEditingValue textEditingValue) async {
                              if (textEditingValue.text.isEmpty || !mounted) {
                                return const Iterable<Map<String, dynamic>>.empty();
                              }
                              try {
                                return await fetchCustomerSuggestions(textEditingValue.text, branch);
                              } catch (e) {
                                debugPrint('Error in name autocomplete: $e');
                                return const Iterable<Map<String, dynamic>>.empty();
                              }
                            },
                            displayStringForOption: (option) => option['name'] ?? '',
                            fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                              return TextFormField(
                                controller: controller,
                                focusNode: focusNode,
                                decoration: buildInputDecoration(label: 'Customer Name', icon: Icons.person_outline_rounded),
                                validator: (value) => value!.isEmpty ? 'Enter customer name' : null,
                                onChanged: (_) {
                                  if (mounted) _saveDraft();
                                },
                              );
                            },
                            optionsViewBuilder: (context, onSelected, options) {
                              if (options.isEmpty) return const SizedBox.shrink();
                              return Align(
                                alignment: Alignment.topLeft,
                                child: Material(
                                  elevation: 8.0,
                                  borderRadius: BorderRadius.circular(14),
                                  child: Container(
                                    constraints: const BoxConstraints(maxHeight: 200, maxWidth: 320),
                                    decoration: BoxDecoration(
                                      color: isDark ? const Color(0xFF1E293B) : Colors.white,
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: ListView.separated(
                                      padding: EdgeInsets.zero,
                                      shrinkWrap: true,
                                      itemCount: options.length,
                                      separatorBuilder: (_, __) => Divider(height: 1, color: isDark ? Colors.grey.shade800 : Colors.grey.shade200),
                                      itemBuilder: (context, index) {
                                        final option = options.elementAt(index);
                                        return ListTile(
                                          title: Text(option['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                          subtitle: Text(option['phone'] ?? '', style: const TextStyle(fontSize: 11)),
                                          onTap: () => onSelected(option),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              );
                            },
                            onSelected: (selectedCustomer) {
                              if (mounted) {
                                setState(() {
                                  _nameController.text = selectedCustomer['name'] ?? '';
                                  _addressController.text = selectedCustomer['address'] ?? '';
                                  _phoneController.text = formatIndianPhone(selectedCustomer['phone'] ?? '');
                                });
                              }
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _addressController,
                        decoration: buildInputDecoration(label: 'Address', icon: Icons.location_on_outlined),
                        validator: (value) => value!.isEmpty ? 'Enter address' : null,
                        onChanged: (_) => _saveDraft(),
                      ),
                      const SizedBox(height: 14),
                      RawAutocomplete<Map<String, dynamic>>(
                        textEditingController: _phoneController,
                        focusNode: _phoneFieldFocusNode,
                        optionsBuilder: (TextEditingValue textEditingValue) async {
                          if (textEditingValue.text.isEmpty || !mounted) {
                            return const Iterable<Map<String, dynamic>>.empty();
                          }
                          try {
                            final user = FirebaseAuth.instance.currentUser;
                            if (user == null) return const Iterable<Map<String, dynamic>>.empty();
                            final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
                            final branch = userDoc.data()?['branch'] ?? '';
                            return await fetchCustomerSuggestions(textEditingValue.text, branch);
                          } catch (e) {
                            debugPrint('Error in phone autocomplete: $e');
                            return const Iterable<Map<String, dynamic>>.empty();
                          }
                        },
                        displayStringForOption: (option) => option['phone'] ?? '',
                        fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                          return TextFormField(
                            controller: controller,
                            focusNode: focusNode,
                            decoration: buildInputDecoration(
                              label: 'Phone',
                              icon: Icons.phone_outlined,
                              suffixIcon: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.paste_rounded, color: Color(0xFF005BAC), size: 19),
                                    tooltip: 'Paste from clipboard',
                                    onPressed: () async {
                                      final clipboardData = await Clipboard.getData('text/plain');
                                      if (clipboardData != null && clipboardData.text != null) {
                                        final digits = RegExp(r'\d').allMatches(clipboardData.text!).map((m) => m.group(0)).join();
                                        if (digits.length >= 10) {
                                          final tenDigits = digits.substring(digits.length - 10);
                                          final formatted = '+91 ${tenDigits.substring(0, 5)} ${tenDigits.substring(5)}';
                                          _phoneController.text = formatted;
                                          _phoneController.selection = TextSelection.fromPosition(TextPosition(offset: formatted.length));
                                        } else {
                                          if (mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Clipboard does not contain 10 digits')));
                                          }
                                        }
                                      }
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.contacts_rounded, color: Color(0xFF005BAC), size: 19),
                                    tooltip: 'Pick from contacts',
                                    onPressed: () async {
                                      if (_deviceContacts == null && !_deviceContactsLoading) {
                                        _loadDeviceContacts();
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
                                                    final digits = RegExp(r'\d').allMatches(phone).map((m) => m.group(0)).join();
                                                    if (digits.length >= 10) {
                                                      final tenDigits = digits.substring(digits.length - 10);
                                                      final formatted = '+91 ${tenDigits.substring(0, 5)} ${tenDigits.substring(5)}';
                                                      if (mounted) {
                                                        setState(() {
                                                          _phoneController.text = formatted;
                                                          _phoneController.selection = TextSelection.fromPosition(TextPosition(offset: formatted.length));
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
                              if (mounted) _saveDraft();
                              if (!val.startsWith('+91 ')) {
                                controller.text = '+91 ';
                                controller.selection = TextSelection.fromPosition(TextPosition(offset: controller.text.length));
                                return;
                              }
                              String raw = val.replaceAll('+91 ', '').replaceAll(' ', '');
                              if (raw.length > 10) raw = raw.substring(0, 10);
                              String formatted = raw.length > 5 ? '+91 ${raw.substring(0, 5)} ${raw.substring(5)}' : '+91 $raw';
                              if (controller.text != formatted) {
                                controller.text = formatted;
                                controller.selection = TextSelection.fromPosition(TextPosition(offset: formatted.length));
                              }
                            },
                          );
                        },
                        optionsViewBuilder: (context, onSelected, options) {
                          if (options.isEmpty) return const SizedBox.shrink();
                          return Align(
                            alignment: Alignment.topLeft,
                            child: Material(
                              elevation: 8.0,
                              borderRadius: BorderRadius.circular(14),
                              child: Container(
                                constraints: const BoxConstraints(maxHeight: 200, maxWidth: 320),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF1E293B) : Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: ListView.separated(
                                  padding: EdgeInsets.zero,
                                  shrinkWrap: true,
                                  itemCount: options.length,
                                  separatorBuilder: (_, __) => Divider(height: 1, color: isDark ? Colors.grey.shade800 : Colors.grey.shade200),
                                  itemBuilder: (context, index) {
                                    final option = options.elementAt(index);
                                    return ListTile(
                                      title: Text(option['phone'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                      subtitle: Text(option['name'] ?? '', style: const TextStyle(fontSize: 11)),
                                      onTap: () => onSelected(option),
                                    );
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                        onSelected: (selectedCustomer) {
                          if (mounted) {
                            setState(() {
                              _nameController.text = selectedCustomer['name'] ?? '';
                              _addressController.text = selectedCustomer['address'] ?? '';
                              _phoneController.text = formatIndianPhone(selectedCustomer['phone'] ?? '');
                            });
                          }
                        },
                      ),
                    ],
                  ),

                  buildCardSection(
                    title: 'Follow-Up Info',
                    icon: Icons.assignment_outlined,
                    children: [
                      TextFormField(
                        controller: _commentsController,
                        maxLines: 3,
                        decoration: buildInputDecoration(label: 'Comments / Notes', icon: Icons.comment_outlined),
                        validator: (value) => value!.isEmpty ? 'Enter comments' : null,
                        onChanged: (_) => _saveDraft(),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Priority Level',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              for (final p in ['High', 'Medium', 'Low']) ...[
                                () {
                                  final isSelected = _priority == p;
                                  Color color;
                                  if (p == 'High') color = const Color(0xFFEF4444);
                                  else if (p == 'Medium') color = const Color(0xFFF59E0B);
                                  else color = const Color(0xFF10B981);

                                  return Expanded(
                                    child: GestureDetector(
                                      onTap: () {
                                        setState(() => _priority = p);
                                        _saveDraft();
                                      },
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 200),
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? color.withValues(alpha: 0.15)
                                              : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC)),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: isSelected ? color : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                                            width: isSelected ? 1.8 : 1.0,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.flag_rounded,
                                              size: 14,
                                              color: isSelected ? color : (isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              p,
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                                color: isSelected ? color : (isDark ? Colors.grey.shade300 : Colors.grey.shade700),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                }(),
                                if (p != 'Low') const SizedBox(width: 8),
                              ]
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _reminderController,
                        readOnly: true,
                        decoration: buildInputDecoration(label: 'Reminder', icon: Icons.alarm_outlined),
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
                    ],
                  ),

                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saveFollowUp,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        elevation: 4,
                        shadowColor: const Color(0xFF005BAC).withValues(alpha: 0.4),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        backgroundColor: Colors.transparent,
                      ).copyWith(
                        elevation: WidgetStateProperty.all(4),
                      ),
                      child: Ink(
                        decoration: BoxDecoration(
                          gradient: primaryGradient,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          alignment: Alignment.center,
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.save_rounded, color: Colors.white, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Save Follow Up',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.3),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_isSaving)
          Container(
            color: Colors.black.withValues(alpha: 0.4),
            child: const Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }
}
