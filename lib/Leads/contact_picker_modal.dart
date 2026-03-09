import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'leads_helpers.dart';

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
