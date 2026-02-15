import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
// import 'Todo & Leads/leadsform.dart';
// TODO: Update the import path below to the correct location of leadsform.dart
import '../Leads/leadsform.dart';

class AddCustomerPage extends StatefulWidget {
  @override
  State<AddCustomerPage> createState() => _AddCustomerPageState();
}

class _AddCustomerPageState extends State<AddCustomerPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _addressCtrl = TextEditingController();
  final TextEditingController _contactCtrl = TextEditingController();
  final TextEditingController _contact2Ctrl = TextEditingController();
  bool _loading = false;
  String? _error;

  List<Contact>? _deviceContacts;
  bool _deviceContactsLoading = false;

  Future<void> _addCustomer() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception("Not logged in");

      final now = DateTime.now();
      final monthYear = "${_monthName(now.month)} ${now.year}";
      final docRef = FirebaseFirestore.instance
          .collection('customer_target')
          .doc(monthYear)
          .collection('users')
          .doc(user.email!.toLowerCase());

      final docSnap = await docRef.get();
      List customers = [];
      if (docSnap.exists && docSnap.data()?['customers'] != null) {
        customers = List.from(docSnap.data()!['customers']);
      }
      customers.add({
        'name': _nameCtrl.text.trim(),
        'address': _addressCtrl.text.trim(),
        'contact1': _contactCtrl.text.trim(),
        'contact2': _contact2Ctrl.text.trim(),
        'callMade': false,
        'remarks': '',
      });
      await docRef.set({
        'user': user.email!.toLowerCase(),
        'customers': customers,
        'updated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _error = "Failed to add: $e";
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  // Helper to get month name
  String _monthName(int month) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return months[month - 1];
  }

  Future<void> _loadDeviceContacts() async {
    if (_deviceContactsLoading || (_deviceContacts != null && _deviceContacts!.isNotEmpty)) {
      return;
    }
    setState(() {
      _deviceContactsLoading = true;
    });
    try {
      var status = await Permission.contacts.status;
      if (!status.isGranted) {
        await Permission.contacts.request();
        status = await Permission.contacts.status;
      }
      if (!status.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Contact permission denied')));
        }
        return;
      }
      // Load from cache first
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('contacts_cache');
      if (cached != null) {
        final List<dynamic> decoded = jsonDecode(cached);
        setState(() {
          _deviceContacts = decoded.map((c) => Contact.fromJson(c)).toList();
        });
      }
      // Fetch latest contacts and update cache/state
      final latestContacts = await FlutterContacts.getContacts(withProperties: true, withThumbnail: false);
      final encoded = jsonEncode(latestContacts.map((c) => c.toJson()).toList());
      await prefs.setString('contacts_cache', encoded);
      if (mounted) {
        setState(() => _deviceContacts = latestContacts);
      }
    } finally {
      if (mounted) setState(() => _deviceContactsLoading = false);
    }
  }

  void _showContactPicker(TextEditingController controller, {TextEditingController? nameController}) async {
    // Load cached contacts fast for immediate display
    List<Contact> cachedContacts = [];
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('contacts_cache');
    if (cached != null) {
      final List<dynamic> decoded = jsonDecode(cached);
      cachedContacts = decoded.map((c) => Contact.fromJson(c)).toList();
    }
    // Show modal immediately with cached (or empty) contacts
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _ContactPickerModal(
          initialContacts: cachedContacts,
          initialLoading: _deviceContactsLoading,
          onSelect: (contact) {
            final phones = contact.phones;
            String phone1 = phones.isNotEmpty ? (phones[0].number ?? '') : '';
            String phone2 = phones.length > 1 ? (phones[1].number ?? '') : '';
            String phone1Digits = RegExp(r'\d').allMatches(phone1).map((m) => m.group(0)).join();
            String phone2Digits = RegExp(r'\d').allMatches(phone2).map((m) => m.group(0)).join();
            if (phone1Digits.length >= 10) {
              phone1Digits = phone1Digits.substring(phone1Digits.length - 10);
              controller.text = phone1Digits;
              controller.selection = TextSelection.fromPosition(TextPosition(offset: controller.text.length));
            }
            if (nameController != null && (nameController.text.isEmpty)) {
              nameController.text = contact.displayName ?? '';
            }
            if (phone2Digits.length >= 10) {
              phone2Digits = phone2Digits.substring(phone2Digits.length - 10);
              _contact2Ctrl.text = phone2Digits;
            }
            Navigator.pop(context);
          },
        );
      },
    );
  }

  Future<void> _pasteFromClipboard(TextEditingController controller) async {
    final clipboardData = await Clipboard.getData('text/plain');
    if (clipboardData != null && clipboardData.text != null) {
      final digits = RegExp(r'\d').allMatches(clipboardData.text!).map((m) => m.group(0)).join();
      if (digits.length >= 10) {
        // Always select the last 10 digits
        final tenDigits = digits.substring(digits.length - 10);
        controller.text = tenDigits;
        controller.selection = TextSelection.fromPosition(TextPosition(offset: controller.text.length));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Clipboard does not contain 10 digits')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Customer', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF8CC63F),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_error!, style: const TextStyle(color: Colors.red)),
                ),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Customer Name'),
                validator: (v) => v == null || v.trim().isEmpty ? 'Enter name' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _addressCtrl,
                decoration: const InputDecoration(labelText: 'Address'),
                validator: (v) => v == null || v.trim().isEmpty ? 'Enter address' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _contactCtrl,
                decoration: InputDecoration(
                  labelText: 'Contact Number 1',
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.paste),
                        tooltip: 'Paste from clipboard',
                        onPressed: () => _pasteFromClipboard(_contactCtrl),
                      ),
                      IconButton(
                        icon: const Icon(Icons.contacts),
                        tooltip: 'Pick from contacts',
                        onPressed: () => _showContactPicker(_contactCtrl, nameController: _nameCtrl),
                      ),
                    ],
                  ),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Enter contact';
                  if (v.length != 10) return 'Enter exactly 10 digits';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _contact2Ctrl,
                decoration: const InputDecoration(
                  labelText: 'Contact Number 2 (optional)',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                validator: (v) {
                  if (v != null && v.isNotEmpty && v.length != 10) return 'Enter exactly 10 digits';
                  return null;
                },
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _addCustomer,
                  child: _loading
                      ? const SizedBox(
                          width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Add Customer'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8CC63F),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContactPickerModal extends StatefulWidget {
  final List<Contact> initialContacts;
  final bool initialLoading;
  final void Function(Contact contact) onSelect;

  const _ContactPickerModal({
    required this.initialContacts,
    required this.initialLoading,
    required this.onSelect,
  });

  @override
  State<_ContactPickerModal> createState() => _ContactPickerModalState();
}

class _ContactPickerModalState extends State<_ContactPickerModal> {
  List<Contact> _contacts = [];
  List<Contact> _filtered = [];
  bool _loading = true;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _contacts = widget.initialContacts;
    _filtered = List.from(_contacts);
    _loading = widget.initialLoading;
    // Show cached contacts immediately, then refresh in background
    _refreshContactsInBackground();
    _searchController.addListener(() {
      _applyFilter(_searchController.text);
    });
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
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
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
                ),
              ),
              Expanded(
                child: _loading && _contacts.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : (_filtered.isEmpty
                        ? Center(child: Text(_contacts.isEmpty ? 'No contacts found' : 'No matching contacts'))
                        : ListView.builder(
                            controller: scrollController,
                            itemCount: _filtered.length,
                            itemBuilder: (context, index) {
                              final contact = _filtered[index];
                              final phones = contact.phones;
                              final phone1 = phones.isNotEmpty ? (phones[0].number ?? '') : '';
                              final phone2 = phones.length > 1 ? (phones[1].number ?? '') : '';
                              return ListTile(
                                leading: const Icon(Icons.person_outline),
                                title: Text(contact.displayName ?? ''),
                                subtitle: Text(
                                  phone2.isNotEmpty
                                      ? '$phone1, $phone2'
                                      : phone1,
                                ),
                                onTap: () => widget.onSelect(contact),
                              );
                            },
                          )),
              ),
            ],
          ),
        );
      },
    );
  }
}
