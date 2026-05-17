import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../Leads/presentfollowup.dart';

const Color _primaryBlue = Color(0xFF005BAC);

/// Shows DME leads (source == 'DME') for tracking purposes.
/// Non-admin dme_users see only their own leads.
/// dme_admin users see all DME leads.
class DmeLeadsPage extends StatefulWidget {
  final bool isAdmin;

  const DmeLeadsPage({super.key, this.isAdmin = false});

  @override
  State<DmeLeadsPage> createState() => _DmeLeadsPageState();
}

class _DmeLeadsPageState extends State<DmeLeadsPage> {
  static const Color _green = Color(0xFF8CC63F);

  String _selectedStatus = 'All';
  String _selectedPriority = 'All';
  String _searchQuery = '';
  bool _isSearching = false;
  bool _isLoading = false;
  bool _sortAscending = false;

  List<DocumentSnapshot> _leads = [];
  DocumentSnapshot? _lastDocument;
  int _currentPage = 1;
  static const int _leadsPerPage = 15;
  final Map<int, DocumentSnapshot?> _pageStartCursors = {1: null};

  final _statusOptions = ['All', 'In Progress', 'Sold', 'Cancelled'];
  final _priorityOptions = ['All', 'High', 'Medium', 'Low'];

  @override
  void initState() {
    super.initState();
    _fetchLeads();
  }

  Future<void> _fetchLeads({
    bool nextPage = false,
    bool prevPage = false,
    bool isSearch = false,
  }) async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _isLoading = false);
      return;
    }

    Query query = FirebaseFirestore.instance
        .collection('follow_ups')
        .where('source', whereIn: ['DME', 'dme']);

    // Non-admin users see only their own leads
    if (!widget.isAdmin) {
      query = query.where('created_by', isEqualTo: uid);
    }

    if (!isSearch || _searchQuery.isEmpty) {
      if (_selectedStatus != 'All') {
        final statusValue =
            _selectedStatus == 'Sold' ? 'Sale' : _selectedStatus;
        query = query.where('status', isEqualTo: statusValue);
      }
      if (_selectedPriority != 'All') {
        query = query.where('priority', isEqualTo: _selectedPriority);
      }
    }

    query = query.orderBy('created_at', descending: !_sortAscending);

    QuerySnapshot snapshot;

    if (isSearch && _searchQuery.isNotEmpty) {
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

    if (snapshot.docs.isNotEmpty && (!isSearch || _searchQuery.isEmpty)) {
      _lastDocument = snapshot.docs.last;
      _pageStartCursors[_currentPage + 1] = _lastDocument;
    } else {
      _lastDocument = null;
    }

    if (mounted) {
      setState(() {
        _leads = snapshot.docs;
        _isLoading = false;
      });
    }
  }

  void _resetAndFetch() {
    _pageStartCursors.clear();
    _pageStartCursors[1] = null;
    _currentPage = 1;
    _lastDocument = null;
    _fetchLeads();
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'in progress':
        return _primaryBlue;
      case 'sale':
      case 'sold':
        return _green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Color _priorityColor(String priority) {
    switch (priority.toLowerCase()) {
      case 'high':
        return Colors.red;
      case 'medium':
        return Colors.orange;
      case 'low':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  void _showFilterSheet(
    String title,
    List<String> options,
    String current,
    void Function(String) onSelect,
  ) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          ...options.map((opt) => ListTile(
                title: Text(opt),
                trailing: opt == current
                    ? const Icon(Icons.check, color: _primaryBlue)
                    : null,
                onTap: () {
                  Navigator.pop(context);
                  onSelect(opt);
                },
              )),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isActive = value != 'All';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? color.withValues(alpha: 0.12) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? color : Colors.grey.shade300,
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: isActive ? color : Colors.grey),
            const SizedBox(width: 5),
            Text(
              '$label: $value',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isActive ? color : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSortChip() {
    return GestureDetector(
      onTap: () {
        setState(() => _sortAscending = !_sortAscending);
        _resetAndFetch();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
              size: 15,
              color: Colors.grey.shade700,
            ),
            const SizedBox(width: 5),
            Text(
              _sortAscending ? 'Oldest' : 'Newest',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A1628) : Colors.grey[100],
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
                  setState(() => _searchQuery = val.toLowerCase().trim());
                  _fetchLeads(isSearch: true);
                },
              )
            : const Text('My Leads',
                style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: _primaryBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchQuery = '';
                  _fetchLeads(isSearch: true);
                }
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _resetAndFetch,
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter bar
          Container(
            margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1A2332) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.07),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  _buildFilterChip(
                    label: 'Status',
                    value: _selectedStatus,
                    icon: Icons.check_circle_rounded,
                    color: const Color(0xFFFF8F00),
                    onTap: () => _showFilterSheet(
                      'Select Status',
                      _statusOptions,
                      _selectedStatus,
                      (val) {
                        setState(() => _selectedStatus = val);
                        _resetAndFetch();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                    label: 'Priority',
                    value: _selectedPriority,
                    icon: Icons.flag_rounded,
                    color: const Color(0xFFE53935),
                    onTap: () => _showFilterSheet(
                      'Select Priority',
                      _priorityOptions,
                      _selectedPriority,
                      (val) {
                        setState(() => _selectedPriority = val);
                        _resetAndFetch();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildSortChip(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Leads list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _leads.isEmpty
                    ? _buildEmpty(isDark)
                    : RefreshIndicator(
                        onRefresh: () async => _resetAndFetch(),
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(14, 6, 14, 80),
                          itemCount: _leads.length,
                          itemBuilder: (context, index) {
                            final doc = _leads[index];
                            final data = doc.data() as Map<String, dynamic>;
                            final name = data['name'] ?? 'No Name';

                            if (_searchQuery.isNotEmpty &&
                                !name
                                    .toLowerCase()
                                    .contains(_searchQuery)) {
                              return const SizedBox.shrink();
                            }

                            return _buildLeadCard(doc, data, isDark);
                          },
                        ),
                      ),
          ),
          // Pagination controls
          if (!_isLoading && _leads.isNotEmpty)
            _buildPagination(isDark),
        ],
      ),
    );
  }

  Widget _buildLeadCard(
    DocumentSnapshot doc,
    Map<String, dynamic> data,
    bool isDark,
  ) {
    final name = data['name'] ?? 'No Name';
    final status = data['status'] ?? 'In Progress';
    final priority = data['priority'] ?? 'High';
    final phone = data['phone'] ?? '';
    final branch = data['branch'] ?? '';
    final assignedToName = data['assigned_to_name'] ?? '';
    final comments = data['comments'] ?? '';

    String formattedDate = 'No Date';
    final rawDate = data['created_at'] ?? data['date'];
    if (rawDate is Timestamp) {
      formattedDate = DateFormat('dd MMM yyyy').format(rawDate.toDate());
    }

    final statusColor = _statusColor(status);
    final priorityColor = _priorityColor(priority);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => PresentFollowUp(docId: doc.id)),
        ).then((_) => _fetchLeads());
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C2C3C) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color:
                  Colors.black.withValues(alpha: isDark ? 0.25 : 0.07),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Status accent bar
                Container(width: 5, color: statusColor),
                // Content
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Name + status badge
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: isDark
                                      ? Colors.white
                                      : const Color(0xFF143A52),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 9, vertical: 3),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: statusColor.withValues(alpha: 0.4)),
                              ),
                              child: Text(
                                status,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: statusColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        // Phone + branch
                        if (phone.isNotEmpty || branch.isNotEmpty)
                          Row(
                            children: [
                              if (phone.isNotEmpty) ...[
                                Icon(Icons.phone_rounded,
                                    size: 13,
                                    color: isDark
                                        ? Colors.white54
                                        : Colors.grey.shade500),
                                const SizedBox(width: 4),
                                Text(phone,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark
                                          ? Colors.white54
                                          : Colors.grey.shade600,
                                    )),
                                const SizedBox(width: 12),
                              ],
                              if (branch.isNotEmpty) ...[
                                Icon(Icons.business_rounded,
                                    size: 13,
                                    color: isDark
                                        ? Colors.white54
                                        : Colors.grey.shade500),
                                const SizedBox(width: 4),
                                Text(branch,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark
                                          ? Colors.white54
                                          : Colors.grey.shade600,
                                    )),
                              ],
                            ],
                          ),
                        const SizedBox(height: 6),
                        // Comments
                        if (comments.isNotEmpty)
                          Text(
                            comments,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? Colors.white60
                                  : Colors.grey.shade700,
                            ),
                          ),
                        const SizedBox(height: 8),
                        // Footer: date + priority + assigned
                        Row(
                          children: [
                            Icon(Icons.calendar_today_rounded,
                                size: 12,
                                color: isDark
                                    ? Colors.white38
                                    : Colors.grey.shade400),
                            const SizedBox(width: 4),
                            Text(formattedDate,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark
                                      ? Colors.white38
                                      : Colors.grey.shade500,
                                )),
                            const Spacer(),
                            // Priority badge
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color:
                                    priorityColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                priority,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: priorityColor,
                                ),
                              ),
                            ),
                            if (assignedToName.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Icon(Icons.person_rounded,
                                  size: 12,
                                  color: isDark
                                      ? Colors.white38
                                      : Colors.grey.shade400),
                              const SizedBox(width: 3),
                              Text(
                                assignedToName,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark
                                      ? Colors.white54
                                      : Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: _primaryBlue.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.folder_open_rounded,
                size: 40, color: _primaryBlue.withValues(alpha: 0.4)),
          ),
          const SizedBox(height: 18),
          Text(
            'No leads found',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : const Color(0xFF143A52),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Leads you add will appear here',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPagination(bool isDark) {
    final canPrev = _currentPage > 1;
    final canNext = _leads.length >= _leadsPerPage;
    return Container(
      color: isDark ? const Color(0xFF0A1628) : Colors.grey[100],
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextButton.icon(
            onPressed: canPrev
                ? () => _fetchLeads(prevPage: true)
                : null,
            icon: const Icon(Icons.chevron_left_rounded),
            label: const Text('Prev'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Page $_currentPage',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          TextButton.icon(
            onPressed: canNext
                ? () => _fetchLeads(nextPage: true)
                : null,
            icon: const Icon(Icons.chevron_right_rounded),
            label: const Text('Next'),
          ),
        ],
      ),
    );
  }
}
