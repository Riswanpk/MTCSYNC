import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../Leads/presentfollowup.dart';

const Color _primaryBlue = Color(0xFF005BAC);

class SmeAllLeadsPage extends StatefulWidget {
  final DateTimeRange? initialDateRange;

  const SmeAllLeadsPage({super.key, this.initialDateRange});

  @override
  State<SmeAllLeadsPage> createState() => _SmeAllLeadsPageState();
}

class _SmeAllLeadsPageState extends State<SmeAllLeadsPage> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _leads = [];
  List<Map<String, dynamic>> _filteredLeads = [];

  late DateTime _startDate;
  late DateTime _endDate;

  String _selectedBranch = 'All';
  String _selectedUser = 'All';
  String _selectedStatus = 'All';

  List<String> _branches = ['All'];
  List<String> _users = ['All'];
  final List<String> _statuses = ['All', 'In Progress', 'Sale', 'Cancelled'];

  @override
  void initState() {
    super.initState();
    if (widget.initialDateRange != null) {
      _startDate = widget.initialDateRange!.start;
      _endDate = widget.initialDateRange!.end;
    } else {
      final now = DateTime.now();
      _startDate = DateTime(now.year, now.month, 1);
      _endDate = now;
    }
    _fetchLeads();
  }

  Future<void> _fetchLeads() async {
    setState(() => _isLoading = true);

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _isLoading = false);
      return;
    }

    final dayEnd = _endDate.add(const Duration(days: 1));

    final snapshot = await FirebaseFirestore.instance
        .collection('follow_ups')
        .where('assigned_by', isEqualTo: uid)
        .where('created_at', isGreaterThanOrEqualTo: Timestamp.fromDate(_startDate))
        .where('created_at', isLessThan: Timestamp.fromDate(dayEnd))
        .orderBy('created_at', descending: true)
        .get();

    final leads = snapshot.docs.map((doc) {
      final data = doc.data();
      data['docId'] = doc.id;
      return data;
    }).toList();

    final branchSet = <String>{};
    final userNameSet = <String>{};

    for (final lead in leads) {
      final branch = lead['branch'] as String? ?? '';
      if (branch.isNotEmpty) branchSet.add(branch);

      final userName = lead['assigned_to_name'] as String? ?? '';
      if (userName.isNotEmpty) userNameSet.add(userName);
    }

    final sortedBranches = branchSet.toList()..sort();
    final sortedUsers = userNameSet.toList()..sort();

    _leads = leads;
    _branches = ['All', ...sortedBranches];
    _users = ['All', ...sortedUsers];

    // Reset filters that no longer apply
    if (!_branches.contains(_selectedBranch)) _selectedBranch = 'All';
    if (!_users.contains(_selectedUser)) _selectedUser = 'All';

    setState(() => _isLoading = false);
    _applyFilters();
  }

  void _applyFilters() {
    final filtered = _leads.where((lead) {
      if (_selectedBranch != 'All' && (lead['branch'] ?? '') != _selectedBranch) return false;
      if (_selectedUser != 'All' && (lead['assigned_to_name'] ?? '') != _selectedUser) return false;
      if (_selectedStatus != 'All' && (lead['status'] ?? '') != _selectedStatus) return false;
      return true;
    }).toList();

    setState(() => _filteredLeads = filtered);
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: _primaryBlue),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _fetchLeads();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dateRangeStr =
        '${DateFormat('dd MMM').format(_startDate)} – ${DateFormat('dd MMM yyyy').format(_endDate)}';

    final total = _filteredLeads.length;
    final inProgress = _filteredLeads.where((l) => l['status'] == 'In Progress').length;
    final sold = _filteredLeads.where((l) => l['status'] == 'Sale').length;
    final cancelled = _filteredLeads.where((l) => l['status'] == 'Cancelled').length;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1A1B22) : const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Total Leads'),
        backgroundColor: _primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            icon: const Icon(Icons.date_range_rounded, size: 18),
            label: Text(
              dateRangeStr,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            onPressed: _pickDateRange,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: _primaryBlue,
              ),
            )
          : Column(
              children: [
                // ── Filter chips ────────────────────────────────────────
                Container(
                  color: isDark ? const Color(0xFF23242B) : Colors.white,
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _FilterChip(
                          label: 'Branch',
                          current: _selectedBranch,
                          options: _branches,
                          isDark: isDark,
                          onChanged: (val) {
                            setState(() => _selectedBranch = val);
                            _applyFilters();
                          },
                        ),
                        const SizedBox(width: 8),
                        _FilterChip(
                          label: 'User',
                          current: _selectedUser,
                          options: _users,
                          isDark: isDark,
                          onChanged: (val) {
                            setState(() => _selectedUser = val);
                            _applyFilters();
                          },
                        ),
                        const SizedBox(width: 8),
                        _FilterChip(
                          label: 'Status',
                          current: _selectedStatus,
                          options: _statuses,
                          isDark: isDark,
                          onChanged: (val) {
                            setState(() => _selectedStatus = val);
                            _applyFilters();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                // ── Summary row ─────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1A1B22) : const Color(0xFFF0F4FF),
                    border: Border(
                      bottom: BorderSide(
                        color: isDark ? Colors.white12 : Colors.black.withOpacity(0.07),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      _SummaryChip(label: 'Total', count: total, color: _primaryBlue),
                      _SummaryChip(label: 'Active', count: inProgress, color: Colors.orange),
                      _SummaryChip(label: 'Sold', count: sold, color: Colors.green),
                      _SummaryChip(label: 'Cancelled', count: cancelled, color: Colors.red),
                    ],
                  ),
                ),
                // ── Leads list ──────────────────────────────────────────
                Expanded(
                  child: _filteredLeads.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.search_off_rounded,
                                  size: 56,
                                  color: isDark ? Colors.white24 : Colors.black26),
                              const SizedBox(height: 12),
                              Text(
                                'No leads found',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: isDark ? Colors.white38 : Colors.black38,
                                ),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _fetchLeads,
                          color: _primaryBlue,
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                            itemCount: _filteredLeads.length,
                            itemBuilder: (context, index) =>
                                _LeadCard(lead: _filteredLeads[index], isDark: isDark, onRefresh: _fetchLeads),
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}

// ── Reusable filter chip widget ──────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  final String label;
  final String current;
  final List<String> options;
  final bool isDark;
  final ValueChanged<String> onChanged;

  const _FilterChip({
    required this.label,
    required this.current,
    required this.options,
    required this.isDark,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = current != 'All';
    return GestureDetector(
      onTap: () async {
        final selected = await showModalBottomSheet<String>(
          context: context,
          backgroundColor: isDark ? const Color(0xFF23242B) : Colors.white,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (_) => _PickerSheet(
            label: label,
            current: current,
            options: options,
            isDark: isDark,
          ),
        );
        if (selected != null) onChanged(selected);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? _primaryBlue.withOpacity(0.12)
              : (isDark ? const Color(0xFF2A2B33) : const Color(0xFFF0F4FF)),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isActive
                ? _primaryBlue.withOpacity(0.5)
                : (isDark ? Colors.white12 : Colors.black12),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isActive ? '$label: $current' : label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isActive
                    ? _primaryBlue
                    : (isDark ? Colors.white60 : Colors.black54),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.expand_more_rounded,
              size: 18,
              color: isActive
                  ? _primaryBlue
                  : (isDark ? Colors.white38 : Colors.black38),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickerSheet extends StatelessWidget {
  final String label;
  final String current;
  final List<String> options;
  final bool isDark;

  const _PickerSheet({
    required this.label,
    required this.current,
    required this.options,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
          child: Text(
            'Filter by $label',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 17,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ),
        const Divider(height: 1),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: options
                .map(
                  (opt) => ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                    title: Text(
                      opt,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                        fontWeight:
                            current == opt ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    leading: Icon(
                      current == opt
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: current == opt
                          ? _primaryBlue
                          : (isDark ? Colors.white30 : Colors.black26),
                      size: 22,
                    ),
                    onTap: () => Navigator.pop(context, opt),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

// ── Summary chip ─────────────────────────────────────────────────────────────

class _SummaryChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _SummaryChip(
      {required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              '$count',
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 18, color: color),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style:
                  TextStyle(fontSize: 10, color: color.withOpacity(0.8)),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Lead card ────────────────────────────────────────────────────────────────

class _LeadCard extends StatelessWidget {
  final Map<String, dynamic> lead;
  final bool isDark;
  final VoidCallback onRefresh;

  const _LeadCard(
      {required this.lead, required this.isDark, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final name = lead['name'] ?? 'Unknown';
    final status = lead['status'] ?? 'Unknown';
    final assignedTo = lead['assigned_to_name'] as String? ?? '';
    final branch = lead['branch'] as String? ?? '';
    final priority = lead['priority'] as String? ?? 'High';

    DateTime? createdAt;
    if (lead['created_at'] is Timestamp) {
      createdAt = (lead['created_at'] as Timestamp).toDate();
    }

    Color statusColor;
    switch (status) {
      case 'Sale':
        statusColor = Colors.green;
        break;
      case 'Cancelled':
        statusColor = Colors.red;
        break;
      default:
        statusColor = Colors.orange;
    }

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => PresentFollowUp(docId: lead['docId'])),
        ).then((_) => onRefresh());
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF23242B) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black26
                  : Colors.black.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Status bar
            Container(
              width: 4,
              height: 70,
              decoration: BoxDecoration(
                color: statusColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),
                          if (assignedTo.isNotEmpty)
                            Text(
                              assignedTo +
                                  (branch.isNotEmpty ? ' · $branch' : ''),
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? Colors.white60
                                    : Colors.black54,
                              ),
                            ),
                          if (createdAt != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              DateFormat('dd MMM yyyy, hh:mm a')
                                  .format(createdAt),
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? Colors.white38
                                    : Colors.black38,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
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
                        const SizedBox(height: 4),
                        Text(
                          priority,
                          style: TextStyle(
                            fontSize: 11,
                            color:
                                isDark ? Colors.white38 : Colors.black38,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
