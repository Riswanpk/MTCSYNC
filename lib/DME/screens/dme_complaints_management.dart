import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../Navigation/user_cache_service.dart';
import '../models/dme_complaint.dart';
import '../services/dme_complaint_service.dart';
import '../services/dme_supabase_service.dart';
import 'dme_complaint_detail_page.dart';

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
  bool _loading = true;

  String? _selectedStatus;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _initSupabaseAndLoad();
  }

  Future<void> _initSupabaseAndLoad() async {
    try {
      // Initialize Supabase before loading complaints
      await DmeSupabaseService.instance.ensureInitialized();
      await _load();
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

      // Load all complaints – Supabase init is handled inside the service.
      final complaints = await _svc.getAllComplaints();

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
    if (_selectedStatus == null || _selectedStatus == 'All') {
      _filtered = _all;
    } else {
      _filtered =
          _all.where((c) => c.status == _selectedStatus).toList();
    }
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
          onUpdate: _load,
        ),
      ),
    );
  }

  /// Get username for a user ID, with caching
  Future<String?> _getUsername(String userId) async {
    if (_usernameCache.containsKey(userId)) {
      return _usernameCache[userId];
    }
    final username = await _svc.getUsernameById(userId);
    _usernameCache[userId] = username;
    return username;
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
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
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
            ),
    );
  }

  Widget _buildFilterBar() {
    final statuses = [
      {'label': 'All', 'value': null},
      {'label': 'Raised', 'value': 'raised'},
      {'label': 'Resolved', 'value': 'case_resolved'},
      {'label': 'Closed', 'value': 'verified_closed'},
    ];
    return Container(
      color: Colors.grey[100],
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: statuses.map((s) {
            final val = s['value'] as String?;
            final isSelected = _selectedStatus == val;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilterChip(
                label: Text(s['label'] as String),
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
    );
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
