import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:audioplayers/audioplayers.dart';
import '../Leads/presentfollowup.dart';
import 'sme_lead_form.dart';

class SmeLeadsPage extends StatefulWidget {
  const SmeLeadsPage({super.key});

  @override
  State<SmeLeadsPage> createState() => _SmeLeadsPageState();
}

class _SmeLeadsPageState extends State<SmeLeadsPage> {
  String selectedStatus = 'All';
  String selectedPriority = 'All';
  String searchQuery = '';
  bool sortAscending = false;
  bool _isSearching = false;
  bool _isLoading = false;

  List<DocumentSnapshot> _leads = [];
  DocumentSnapshot? _lastDocument;
  int _currentPage = 1;
  final int _leadsPerPage = 15;
  final Map<int, DocumentSnapshot?> _pageStartCursors = {1: null};

  final List<String> statusOptions = ['All', 'In Progress', 'Sold', 'Cancelled'];
  final List<String> priorityOptions = ['All', 'High', 'Medium', 'Low'];

  @override
  void initState() {
    super.initState();
    _fetchLeadsPage();
  }

  Future<void> _fetchLeadsPage({bool nextPage = false, bool prevPage = false, bool isSearch = false}) async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _isLoading = false);
      return;
    }

    Query query = FirebaseFirestore.instance
        .collection('follow_ups')
        .where('assigned_by', isEqualTo: uid);

    if (!isSearch || searchQuery.isEmpty) {
      if (selectedStatus != 'All') {
        final statusValue = selectedStatus == 'Sold' ? 'Sale' : selectedStatus;
        query = query.where('status', isEqualTo: statusValue);
      }
      if (selectedPriority != 'All') {
        query = query.where('priority', isEqualTo: selectedPriority);
      }
    }

    query = query.orderBy('created_at', descending: !sortAscending);

    QuerySnapshot snapshot;

    if (isSearch && searchQuery.isNotEmpty) {
      snapshot = await query.get();
    } else {
      DocumentSnapshot? cursor;
      if (nextPage) {
        cursor = _lastDocument;
        _currentPage++;
      } else if (prevPage && _currentPage > 1) {
        _currentPage--;
        cursor = _pageStartCursors[_currentPage];
      }

      if (cursor != null) {
        query = query.startAfterDocument(cursor);
      }

      snapshot = await query.limit(_leadsPerPage).get();
    }

    if (snapshot.docs.isNotEmpty && (!isSearch || searchQuery.isEmpty)) {
      _lastDocument = snapshot.docs.last;
      _pageStartCursors[_currentPage + 1] = _lastDocument;
    } else {
      _lastDocument = null;
    }

    setState(() {
      _leads = snapshot.docs;
      _isLoading = false;
    });
  }

  void _resetAndFetch() {
    _pageStartCursors.clear();
    _pageStartCursors[1] = null;
    _currentPage = 1;
    _lastDocument = null;
    _fetchLeadsPage();
  }

  Future<void> _playClickSound() async {
    final player = AudioPlayer();
    await player.play(AssetSource('sounds/click.mp3'), volume: 0.5);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                cursorColor: Colors.white,
                decoration: const InputDecoration(
                  hintText: 'Search by name...',
                  hintStyle: TextStyle(color: Colors.white54),
                  border: InputBorder.none,
                ),
                onChanged: (val) {
                  setState(() => searchQuery = val.toLowerCase().trim());
                  _fetchLeadsPage(isSearch: true);
                },
              )
            : const Text('SME Leads'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  searchQuery = '';
                  _fetchLeadsPage(isSearch: true);
                }
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Filters
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: [
                _buildFilterDropdown<String>(
                  value: selectedStatus,
                  items: statusOptions,
                  label: 'Status',
                  onChanged: (val) {
                    setState(() => selectedStatus = val!);
                    _resetAndFetch();
                  },
                ),
                const SizedBox(width: 2),
                _buildFilterDropdown<String>(
                  value: selectedPriority,
                  items: priorityOptions,
                  label: 'Priority',
                  onChanged: (val) {
                    setState(() => selectedPriority = val!);
                    _resetAndFetch();
                  },
                ),
                const SizedBox(width: 2),
                Flexible(
                  flex: 1,
                  child: SizedBox(
                    height: 36,
                    child: DropdownButtonFormField<bool>(
                      value: sortAscending,
                      items: const [
                        DropdownMenuItem(value: false, child: Text('Newest', style: TextStyle(fontSize: 10))),
                        DropdownMenuItem(value: true, child: Text('Oldest', style: TextStyle(fontSize: 10))),
                      ],
                      onChanged: (val) {
                        setState(() => sortAscending = val!);
                        _resetAndFetch();
                      },
                      decoration: InputDecoration(
                        labelText: 'Sort',
                        labelStyle: const TextStyle(fontSize: 9),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                        filled: true,
                        fillColor: const Color.fromARGB(255, 229, 237, 229),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      ),
                      style: const TextStyle(fontSize: 10, color: Colors.black),
                      dropdownColor: Colors.white,
                      icon: const Icon(Icons.arrow_drop_down, size: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Leads list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _leads.isEmpty
                    ? const Center(child: Text('No leads found.'))
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _leads.length,
                        itemBuilder: (context, index) {
                          final doc = _leads[index];
                          final data = doc.data() as Map<String, dynamic>;
                          final name = data['name'] ?? 'No Name';
                          final status = data['status'] ?? 'Unknown';
                          final priority = data['priority'] ?? 'High';
                          final assignedToName = data['assigned_to_name'] ?? 'Unknown';
                          final branch = data['branch'] ?? '';

                          if (searchQuery.isNotEmpty && !name.toLowerCase().contains(searchQuery)) {
                            return const SizedBox.shrink();
                          }

                          // Parse date
                          String formattedDate = 'No Date';
                          final date = data['date'];
                          DateTime? parsedDate;
                          if (date is Timestamp) {
                            parsedDate = date.toDate();
                          } else if (date is DateTime) {
                            parsedDate = date;
                          }
                          if (parsedDate != null) {
                            formattedDate = DateFormat('dd-MM-yyyy').format(parsedDate);
                          }

                          return GestureDetector(
                            onTap: () async {
                              await _playClickSound();
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => PresentFollowUp(docId: doc.id),
                                ),
                              ).then((_) => _fetchLeadsPage());
                            },
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF1A3333) : const Color(0xFFE0F2F1),
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: Theme.of(context).shadowColor.withOpacity(isDark ? 0.2 : 0.05),
                                    blurRadius: 12,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 12,
                                    height: 12,
                                    decoration: const BoxDecoration(
                                      color: Colors.teal,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        RichText(
                                          text: TextSpan(
                                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontSize: 16),
                                            children: [
                                              TextSpan(text: name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                              const TextSpan(text: ' '),
                                              TextSpan(text: '($status)', style: TextStyle(color: Theme.of(context).hintColor)),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text('Date: $formattedDate',
                                            style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 13, color: Theme.of(context).hintColor)),
                                        const SizedBox(height: 2),
                                        Text('Assigned to: $assignedToName ($branch)',
                                            style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 12, color: Colors.teal)),
                                        const SizedBox(height: 2),
                                        Text('Priority: $priority',
                                            style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 12, color: Colors.grey)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
          // Pagination
          if (!_isLoading && searchQuery.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: _currentPage > 1 ? () => _fetchLeadsPage(prevPage: true) : null,
                  ),
                  Text('$_currentPage', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.arrow_forward),
                    onPressed: _lastDocument != null && _leads.length == _leadsPerPage
                        ? () => _fetchLeadsPage(nextPage: true)
                        : null,
                  ),
                ],
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF8CC63F),
        child: const Icon(Icons.add),
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SmeLeadForm()),
          );
          if (result == true) _resetAndFetch();
        },
      ),
    );
  }

  Widget _buildFilterDropdown<T>({
    required T value,
    required List<T> items,
    required String label,
    required ValueChanged<T?> onChanged,
  }) {
    return Flexible(
      flex: 1,
      child: SizedBox(
        height: 36,
        child: DropdownButtonFormField<T>(
          value: value,
          items: items.map((item) => DropdownMenuItem(value: item, child: Text(item.toString(), style: const TextStyle(fontSize: 10)))).toList(),
          onChanged: onChanged,
          decoration: InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(fontSize: 9),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
            filled: true,
            fillColor: const Color.fromARGB(255, 229, 237, 229),
            contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          ),
          style: const TextStyle(fontSize: 10, color: Colors.black),
          dropdownColor: Colors.white,
          icon: const Icon(Icons.arrow_drop_down, size: 14),
        ),
      ),
    );
  }
}
