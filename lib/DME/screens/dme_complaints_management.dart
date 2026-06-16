import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../Navigation/user_cache_service.dart';
import '../models/dme_complaint.dart';
import '../services/dme_complaint_service.dart';
import '../services/dme_supabase_service.dart';
import 'dme_complaint_detail_page.dart';
import 'dme_complaints_report_page.dart';

const Color _primary = Color(0xFF005BAC);

/// Complaints page for manager / asst_manager / sales roles.
/// Shows all complaints. Tapping a complaint opens the detail page.
/// Only the assigned user can add remarks.
class DmeComplaintsManagementPage extends StatefulWidget {
  const DmeComplaintsManagementPage({super.key});

  @override
  State<DmeComplaintsManagementPage> createState() =>
      _DmeComplaintsManagementPageState();
}

class _DmeComplaintsManagementPageState
    extends State<DmeComplaintsManagementPage> {
  final _svc = DmeComplaintService.instance;
  final _cache = UserCacheService.instance;
  final Map<String, String?> _usernameCache = {}; // Cache for user ID -> username mappings

  List<DmeComplaint> _all = [];
  List<DmeComplaint> _filtered = [];
  bool _loading = false;

  String? _selectedStatus;
  String? _selectedAssignedTo; // user ID
  String? _currentUserId;
  String? _managerBranchName;
  String? _currentRole;
  bool _sortNewestFirst = true;

  // ── Admin filter-first state ─────────────────────────────────
  bool _isAdminRole = false;
  bool _hasSearched = false;
  DateTime _dateFrom = DateTime.now().subtract(const Duration(days: 29));
  DateTime _dateTo = DateTime.now();
  int? _filterBranchId;
  String _filterBranchName = 'All Branches';
  List<Map<String, dynamic>> _branchesForFilter = [];

  @override
  void initState() {
    super.initState();
    _initSupabaseAndLoad();
  }

  Future<void> _initSupabaseAndLoad() async {
    try {
      // Initialize Supabase before loading complaints
      await DmeSupabaseService.instance.ensureInitialized();
      await _cache.ensureLoaded();
      _currentUserId = FirebaseAuth.instance.currentUser?.uid;
      _currentRole = _cache.role;
      _isAdminRole = (_currentRole == 'dme_admin' || _currentRole == 'admin');

      if (_isAdminRole) {
        // For admin: load branch list for filter, but do NOT fetch all complaints yet
        final branches = await DmeSupabaseService.instance.getBranches();
        if (mounted) {
          setState(() {
            _branchesForFilter = branches;
          });
        }
      } else {
        await _load();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Init error: $e')));
      }
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      await _cache.ensureLoaded();
      _currentUserId = FirebaseAuth.instance.currentUser?.uid;
      final role = _cache.role;
      _currentRole = role;
      final uid = _cache.uid;

      // Fetch only relevant complaints based on role
      List<DmeComplaint> complaints = [];
      if (role == 'manager') {
        // Managers: fetch only their branch's complaints
        _managerBranchName = _cache.branch;
        debugPrint('[Complaints Management] Manager branch: $_managerBranchName');
        
        if (_managerBranchName != null) {
          // Get branch ID and fetch complaints for that branch at DB level
          final branchId = await _svc.getBranchIdByName(_managerBranchName!);
          if (branchId != null) {
            complaints = await _svc.getComplaintsForBranch(branchId: branchId);
            debugPrint('[Complaints Management] Manager: ${complaints.length} complaints for branch "$_managerBranchName" (ID: $branchId)');
          } else {
            debugPrint('[Complaints Management] Manager: Branch ID not found for "$_managerBranchName"');
          }
        }
      } else if ((role == 'sales' || role == 'asst_manager') && uid != null && uid.isNotEmpty) {
        // Sales/Asst Manager: fetch only assigned to them
        complaints = await _svc.getAssignedComplaints(userId: uid);
        debugPrint('[Complaints Management] $role $uid: ${complaints.length} complaints');
      } else {
        // Admin: fetch with date range + optional branch filter
        final endOfDay = DateTime(
            _dateTo.year, _dateTo.month, _dateTo.day, 23, 59, 59, 999);
        complaints = await _svc.getAllComplaints(
          branchId: _filterBranchId,
          dateFrom: _dateFrom,
          dateTo: endOfDay,
        );
        _hasSearched = true;
        debugPrint('[Complaints Management] Admin: ${complaints.length} complaints');
      }

      // Pre-fetch usernames for all assigned_to users to avoid multiple queries
      final userIds = complaints.map((c) => c.assignedToId).toSet().cast<String>();
      debugPrint('[Complaints Management] Fetching usernames for ${userIds.length} users');
      for (final userId in userIds) {
        if (!_usernameCache.containsKey(userId)) {
          final username = await _svc.getUsernameById(userId);
          _usernameCache[userId] = username;
          debugPrint('[Complaints Management] User $userId -> $username');
        }
      }

      if (mounted) {
        setState(() {
          _all = complaints;
          _applyFilter();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _applyFilter() {
    List<DmeComplaint> complaints = _all;
    
    // Apply status filtering only (role-based filtering already done in _load)
    if (_selectedStatus != null && _selectedStatus != 'All') {
      complaints = complaints.where((c) => c.status == _selectedStatus).toList();
    }
    if (_selectedAssignedTo != null) {
      complaints = complaints.where((c) => c.assignedToId == _selectedAssignedTo).toList();
    }
    // Sort by date
    complaints = List<DmeComplaint>.from(complaints);
    complaints.sort((a, b) => _sortNewestFirst
        ? b.createdAt.compareTo(a.createdAt)
        : a.createdAt.compareTo(b.createdAt));
    _filtered = complaints;
  }

  void _openDetail(DmeComplaint complaint) {
    final isAssigned = complaint.assignedToId == _currentUserId;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DmeComplaintDetailPage(
          complaint: complaint,
          isDmeUser: false,
          isAssignedUser: isAssigned,
          isManagerRole: _currentRole == 'manager',
          onUpdate: _load,
        ),
      ),
    );
  }

  // ─── BUILD ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Complaints',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600)),
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(
              _sortNewestFirst ? Icons.arrow_downward : Icons.arrow_upward,
            ),
            tooltip: _sortNewestFirst ? 'Newest first' : 'Oldest first',
            onPressed: () {
              setState(() {
                _sortNewestFirst = !_sortNewestFirst;
                _applyFilter();
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
          if (_isAdminRole)
            IconButton(
              icon: const Icon(Icons.assessment_outlined),
              tooltip: 'Reports',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DmeComplaintsReportPage(
                      userRole: _currentRole ?? 'dme_admin',
                      userId: _currentUserId,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (!_isAdminRole || _hasSearched)
              ? RefreshIndicator(
                  onRefresh: _load,
                  child: Column(
                    children: [
                      _buildFilterBar(),
                      Expanded(
                        child: _filtered.isEmpty
                            ? _buildEmpty()
                            : ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: _filtered.length,
                                itemBuilder: (_, i) {
                                final complaint = _filtered[i];
                                final username = _usernameCache[complaint.assignedToId] ?? complaint.assignedToId;
                                return _buildCard(complaint, username);
                              },
                            ),
                      ),
                    ],
                  ),
                )
              : _buildAdminFilterPrompt(),
    );
  }

  Widget _buildFilterBar() {
    final statuses = [
      {'label': 'All', 'value': null},
      {'label': 'Raised', 'value': 'raised'},
      {'label': 'Resolved', 'value': 'case_resolved'},
      {'label': 'Closed', 'value': 'verified_closed'},
    ];

    // Build a sorted list of assignable users from the username cache
    final assignedUsers = _usernameCache.entries
        .where((e) => e.value != null)
        .map((e) => MapEntry(e.key, e.value!))
        .toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    return Container(
      color: Colors.grey[100],
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Admin: date range + branch summary row with change button
          if (_isAdminRole) ...[            
            Row(
              children: [
                const Icon(Icons.date_range, size: 14, color: _primary),
                const SizedBox(width: 4),
                Text(
                  '${DateFormat('dd MMM yy').format(_dateFrom)} – ${DateFormat('dd MMM yy').format(_dateTo)}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _primary),
                ),
                const SizedBox(width: 10),
                const Icon(Icons.location_on, size: 14, color: Colors.teal),
                const SizedBox(width: 2),
                Text(
                  _filterBranchName,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.teal),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() => _hasSearched = false),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Change', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          // Status filter row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: statuses.map((s) {
                // ignore: unnecessary_cast
                final val = s['value'] as String?;
                final isSelected = _selectedStatus == val;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(s['label'].toString()),
                    selected: isSelected,
                    onSelected: (_) {
                      setState(() {
                        _selectedStatus = val;
                        _applyFilter();
                      });
                    },
                    backgroundColor: Colors.white,
                    selectedColor: _primary.withValues(alpha: 0.15),
                    labelStyle: TextStyle(
                      color: isSelected ? _primary : Colors.grey[600],
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                    side: BorderSide(
                        color: isSelected ? _primary : Colors.grey[300]!),
                  ),
                );
              }).toList(),
            ),
          ),
          // Assigned To filter – manager only, only when there are multiple assignees
          if (_currentRole == 'manager' && assignedUsers.isNotEmpty) ...
            [
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    // "All users" chip
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: const Text('All Users'),
                        selected: _selectedAssignedTo == null,
                        onSelected: (_) {
                          setState(() {
                            _selectedAssignedTo = null;
                            _applyFilter();
                          });
                        },
                        backgroundColor: Colors.white,
                        selectedColor: Colors.teal.withValues(alpha: 0.15),
                        labelStyle: TextStyle(
                          color: _selectedAssignedTo == null ? Colors.teal : Colors.grey[600],
                          fontWeight: _selectedAssignedTo == null
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                        side: BorderSide(
                            color: _selectedAssignedTo == null
                                ? Colors.teal
                                : Colors.grey[300]!),
                      ),
                    ),
                    ...assignedUsers.map((entry) {
                      final isSelected = _selectedAssignedTo == entry.key;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          label: Text(entry.value),
                          selected: isSelected,
                          onSelected: (_) {
                            setState(() {
                              _selectedAssignedTo =
                                  isSelected ? null : entry.key;
                              _applyFilter();
                            });
                          },
                          backgroundColor: Colors.white,
                          selectedColor: Colors.teal.withValues(alpha: 0.15),
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.teal : Colors.grey[600],
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                          side: BorderSide(
                              color: isSelected
                                  ? Colors.teal
                                  : Colors.grey[300]!),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],
        ],
      ),
    );
  }

  Widget _buildAdminFilterPrompt() {
    final dateFmt = DateFormat('dd MMM yyyy');
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          const Icon(Icons.search, size: 52, color: _primary),
          const SizedBox(height: 16),
          const Text(
            'Filter to Load Complaints',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Select a date range and optionally a branch, then tap Search.',
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),
          // Date range card
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: const Icon(Icons.date_range, color: _primary),
              title: const Text('Date Range',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                '${dateFmt.format(_dateFrom)}  →  ${dateFmt.format(_dateTo)}',
              ),
              trailing: TextButton(
                onPressed: _pickDateRange,
                child: const Text('Change'),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Branch filter card
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: DropdownButtonFormField<int?>(
                value: _filterBranchId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Branch',
                  border: InputBorder.none,
                ),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('All Branches')),
                  ..._branchesForFilter.map((b) => DropdownMenuItem<int?>(
                        value: b['id'] as int?,
                        child: Text(b['name'] as String? ?? ''),
                      )),
                ],
                onChanged: (val) {
                  setState(() {
                    _filterBranchId = val;
                    _filterBranchName = val == null
                        ? 'All Branches'
                        : (_branchesForFilter.firstWhere(
                                (b) => b['id'] == val,
                                orElse: () => {'name': 'Unknown'})
                            ['name'] as String? ?? 'Unknown');
                  });
                },
              ),
            ),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.search),
              label: const Text('Search Complaints',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: _dateFrom, end: _dateTo),
    );
    if (picked != null && mounted) {
      setState(() {
        _dateFrom = picked.start;
        _dateTo = picked.end;
      });
    }
  }

  Widget _buildCard(DmeComplaint c, String assignedUsername) {
    final hasRemarks = c.remarks != null && c.remarks!.isNotEmpty;
    final isAssigned = c.assignedToId == _currentUserId;
    final statusColor = _statusColor(c.status);
    final dateFormat = DateFormat('dd MMM yyyy');

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 2,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openDetail(c),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border(left: BorderSide(color: statusColor, width: 4)),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.customerName,
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(c.customerPhone,
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[600])),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _buildStatusBadge(c.status),
                      if (isAssigned) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: _primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text('Assigned to me',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: _primary,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Complaint snippet
              Text(
                c.complaintText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF2C3E50),
                    height: 1.4),
              ),
              const SizedBox(height: 10),
              // Meta row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Branch: ${c.branchName}',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey[600])),
                  Text(dateFormat.format(c.createdAt),
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey[600])),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text('Assigned: ',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey[600])),
                  Expanded(
                    child: Text(
                      assignedUsername,
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              // Remarks teaser
              if (hasRemarks) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: Colors.blue.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.comment,
                          size: 14, color: Colors.blue),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(c.remarks!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.blue)),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    final color = _statusColor(status);
    final label = _statusLabel(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox_rounded, size: 52, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text('No complaints found',
              style: TextStyle(fontSize: 16, color: Colors.grey[400])),
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'raised':
        return Colors.red;
      case 'case_resolved':
        return Colors.orange;
      case 'verified_closed':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'raised':
        return 'RAISED';
      case 'case_resolved':
        return 'RESOLVED';
      case 'verified_closed':
        return 'CLOSED';
      default:
        return status.toUpperCase();
    }
  }
}
