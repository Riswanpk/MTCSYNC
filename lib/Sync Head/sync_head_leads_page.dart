import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

const Color _primaryBlue = Color(0xFF005BAC);
const Color _primaryGreen = Color(0xFF8CC63F);

class SyncHeadLeadsPage extends StatefulWidget {
  const SyncHeadLeadsPage({super.key});

  @override
  State<SyncHeadLeadsPage> createState() => _SyncHeadLeadsPageState();
}

class _SyncHeadLeadsPageState extends State<SyncHeadLeadsPage> {
  List<String> _branches = [];
  String? _selectedBranch;
  DateTimeRange? _selectedRange;
  bool _loading = false;
  bool _branchesLoading = true;
  List<Map<String, dynamic>> _userStats = [];

  // Totals
  int get _totalCreated  => _userStats.fold(0, (s, u) => s + (u['created']  as int));
  int get _totalSale     => _userStats.fold(0, (s, u) => s + (u['sale']     as int));
  int get _totalCancelled => _userStats.fold(0, (s, u) => s + (u['cancelled'] as int));

  @override
  void initState() {
    super.initState();
    _fetchBranches();
    // Default: current month — but do NOT auto-fetch until branch is chosen
    final now = DateTime.now();
    _selectedRange = DateTimeRange(
      start: DateTime(now.year, now.month, 1),
      end: DateTime(now.year, now.month + 1, 0, 23, 59, 59),
    );
  }

  Future<void> _fetchBranches() async {
    final snap = await FirebaseFirestore.instance.collection('users').get();
    final branches = snap.docs
        .map((d) => d.data()['branch'] as String?)
        .where((b) => b != null && b.isNotEmpty)
        .toSet()
        .cast<String>()
        .toList()
      ..sort();
    setState(() {
      _branches = branches;
      // No auto-selection — user must pick a branch
      _selectedBranch = null;
      _branchesLoading = false;
    });
  }

  Future<void> _fetchStats() async {
    if (_selectedBranch == null || _selectedRange == null) return;
    setState(() => _loading = true);

    final rangeStart = _selectedRange!.start;
    final rangeEnd = DateTime(
      _selectedRange!.end.year,
      _selectedRange!.end.month,
      _selectedRange!.end.day,
      23,
      59,
      59,
    );

    // Fetch all users in selected branch
    final usersSnap = await FirebaseFirestore.instance
        .collection('users')
        .where('branch', isEqualTo: _selectedBranch)
        .get();

    final users = usersSnap.docs
        .map((d) {
          final data = d.data();
          return {
            'uid': d.id,
            'username': data['username'] ?? 'Unknown',
            'role': data['role'] ?? 'sales',
          };
        })
        .where(
            (u) => u['role'] != 'admin' && u['role'] != 'sync_head')
        .toList();

    // For each user, run parallel queries
    final List<Map<String, dynamic>> stats = [];
    await Future.wait(users.map((user) async {
      final uid = user['uid'] as String;

      final results = await Future.wait([
        // Created in range
        FirebaseFirestore.instance
            .collection('follow_ups')
            .where('created_by', isEqualTo: uid)
            .where('branch', isEqualTo: _selectedBranch)
            .where('created_at',
                isGreaterThanOrEqualTo: Timestamp.fromDate(rangeStart))
            .where('created_at',
                isLessThanOrEqualTo: Timestamp.fromDate(rangeEnd))
            .get(),
        // Sale in range
        FirebaseFirestore.instance
            .collection('follow_ups')
            .where('created_by', isEqualTo: uid)
            .where('branch', isEqualTo: _selectedBranch)
            .where('status', isEqualTo: 'Sale')
            .where('completed_at',
                isGreaterThanOrEqualTo: Timestamp.fromDate(rangeStart))
            .where('completed_at',
                isLessThanOrEqualTo: Timestamp.fromDate(rangeEnd))
            .get(),
        // Closed in range
        FirebaseFirestore.instance
            .collection('follow_ups')
            .where('created_by', isEqualTo: uid)
            .where('branch', isEqualTo: _selectedBranch)
            .where('status', isEqualTo: 'Cancelled')
            .where('completed_at',
                isGreaterThanOrEqualTo: Timestamp.fromDate(rangeStart))
            .where('completed_at',
                isLessThanOrEqualTo: Timestamp.fromDate(rangeEnd))
            .get(),
      ]);

      stats.add({
        'username': user['username'],
        'role': user['role'],
        'created': (results[0] as QuerySnapshot).size,
        'sale':    (results[1] as QuerySnapshot).size,
        'cancelled': (results[2] as QuerySnapshot).size,
      });
    }));

    // Sort by created count descending
    stats.sort(
        (a, b) => (b['created'] as int).compareTo(a['created'] as int));

    setState(() {
      _userStats = stats;
      _loading = false;
    });
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023, 1, 1),
      lastDate: DateTime(2100),
      initialDateRange: _selectedRange,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: _primaryBlue,
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _selectedRange = picked);
      _fetchStats();
    }
  }

  String _formatDate(DateTime d) => DateFormat('dd MMM yyyy').format(d);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0A1628) : const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Leads Report'),
        backgroundColor: _primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // ── Filters ──────────────────────────────────────────────────
          Container(
            color: isDark ? const Color(0xFF0D2137) : Colors.white,
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              children: [
                // Date range picker
                InkWell(
                  onTap: _pickDateRange,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: _primaryBlue.withOpacity(0.4)),
                      borderRadius: BorderRadius.circular(10),
                      color: isDark
                          ? const Color(0xFF162236)
                          : const Color(0xFFF0F5FF),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.date_range_rounded,
                            color: _primaryBlue, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _selectedRange == null
                                ? 'Select Date Range'
                                : '${_formatDate(_selectedRange!.start)}  →  ${_formatDate(_selectedRange!.end)}',
                            style: TextStyle(
                              color: isDark
                                  ? Colors.white
                                  : _primaryBlue,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        Icon(Icons.arrow_drop_down_rounded,
                            color: isDark
                                ? Colors.white54
                                : _primaryBlue),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // Branch dropdown
                _branchesLoading
                    ? const LinearProgressIndicator()
                    : DropdownButtonFormField<String>(
                        value: _selectedBranch,
                        decoration: InputDecoration(
                          labelText: 'Branch',
                          labelStyle:
                              const TextStyle(color: _primaryBlue),
                          prefixIcon: const Icon(
                              Icons.location_city_rounded,
                              color: _primaryBlue,
                              size: 20),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                                color: _primaryBlue.withOpacity(0.4)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                                color: _primaryBlue.withOpacity(0.4)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                                color: _primaryBlue, width: 1.5),
                          ),
                          filled: true,
                          fillColor: isDark
                              ? const Color(0xFF162236)
                              : const Color(0xFFF0F5FF),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                        ),
                        dropdownColor: isDark
                            ? const Color(0xFF162236)
                            : Colors.white,
                        style: TextStyle(
                            color: isDark
                                ? Colors.white
                                : Colors.black87,
                            fontSize: 14),
                        items: _branches
                            .map((b) => DropdownMenuItem(
                                value: b, child: Text(b)))
                            .toList(),
                        onChanged: (val) {
                          setState(() => _selectedBranch = val);
                          _fetchStats();
                        },
                      ),
              ],
            ),
          ),

          // ── Summary bar ──────────────────────────────────────────────
          if (!_loading && _userStats.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
              color: isDark
                  ? const Color(0xFF0A1628)
                  : const Color(0xFFF5F7FA),
              child: Row(
                children: [
                  _SummaryChip(
                    label: 'Created',
                    value: _totalCreated,
                    color: _primaryBlue,
                  ),
                  const SizedBox(width: 8),
                  _SummaryChip(
                    label: 'Sale',
                    value: _totalSale,
                    color: _primaryGreen,
                  ),
                  const SizedBox(width: 8),
                  _SummaryChip(
                    label: 'Cancelled',
                    value: _totalCancelled,
                    color: Colors.red,
                  ),
                ],
              ),
            ),

          // ── User cards list ──────────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: _primaryBlue))
                : _userStats.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.people_outline_rounded,
                                size: 56,
                                color: isDark
                                    ? Colors.white24
                                    : Colors.black26),
                            const SizedBox(height: 12),
                            Text(
                              _selectedBranch == null
                                  ? 'Select a branch to view stats'
                                  : 'No users found in this branch',
                              style: TextStyle(
                                color: isDark
                                    ? Colors.white38
                                    : Colors.black38,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _userStats.length,
                        itemBuilder: (ctx, i) {
                          final stat = _userStats[i];
                          return _UserLeadCard(
                            username: stat['username'] as String,
                            role: stat['role'] as String,
                            created: stat['created'] as int,
                            sale: stat['sale'] as int,
                            closed: stat['cancelled'] as int,
                            isDark: isDark,
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

// ── Summary chip widget ────────────────────────────────────────────────────────

class _SummaryChip extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _SummaryChip(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding:
            const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: color,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text('$value',
                style: TextStyle(
                    fontSize: 22,
                    color: color,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

// ── Per-user card ──────────────────────────────────────────────────────────────

class _UserLeadCard extends StatelessWidget {
  final String username;
  final String role;
  final int created;
  final int sale;
  final int closed;
  final bool isDark;

  const _UserLeadCard({
    required this.username,
    required this.role,
    required this.created,
    required this.sale,
    required this.closed,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final conversionRate =
        created > 0 ? ((sale + closed) / created * 100).round() : 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0D2137) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              CircleAvatar(
                backgroundColor: _primaryBlue.withOpacity(0.15),
                child: Text(
                  username.isNotEmpty
                      ? username[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    color: _primaryBlue,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      username,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: isDark
                            ? Colors.white
                            : Colors.black87,
                      ),
                    ),
                    Text(
                      role.isNotEmpty
                          ? role[0].toUpperCase() +
                              role.substring(1)
                          : role,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? Colors.white54
                            : Colors.black45,
                      ),
                    ),
                  ],
                ),
              ),
              if (created > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _primaryBlue.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$conversionRate%',
                    style: const TextStyle(
                      fontSize: 12,
                      color: _primaryBlue,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          // Stats row: Created | Sale | Closed
          Row(
            children: [
              Expanded(
                child: _StatPill(
                  icon: Icons.add_circle_outline_rounded,
                  label: 'Created',
                  value: created,
                  color: _primaryBlue,
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatPill(
                  icon: Icons.handshake_rounded,
                  label: 'Sale',
                  value: sale,
                  color: _primaryGreen,
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatPill(
                  icon: Icons.cancel_rounded,
                  label: 'Cancelled',
                  value: closed,
                  color: Colors.red,
                  isDark: isDark,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final int value;
  final Color color;
  final bool isDark;

  const _StatPill({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(isDark ? 0.12 : 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      color: color,
                      fontWeight: FontWeight.w500)),
              Text(
                '$value',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
