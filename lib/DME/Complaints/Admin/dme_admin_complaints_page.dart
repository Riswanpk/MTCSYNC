import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:mtcsync/DME/Misc/dme_constants.dart';
import '../models/dme_complaint_model.dart';
import '../services/dme_complaints_service.dart';
import '../User/complaint_detail_page.dart';

class DmeAdminComplaintsPage extends StatefulWidget {
  const DmeAdminComplaintsPage({super.key});

  @override
  State<DmeAdminComplaintsPage> createState() => _DmeAdminComplaintsPageState();
}

class _DmeAdminComplaintsPageState extends State<DmeAdminComplaintsPage> {
  String? _selectedBranch;
  String? _selectedUserUid;
  List<Map<String, dynamic>> _usersForBranch = [];
  bool _isLoadingUsers = false;

  List<DmeComplaint> _complaints = [];
  bool _isLoadingComplaints = false;
  bool _hasSearched = false; // Do not auto load data on open!

  @override
  void initState() {
    super.initState();
    // Intentionally empty: Do NOT auto-load any data on page open
  }

  Future<void> _onBranchChanged(String? branch) async {
    setState(() {
      _selectedBranch = branch;
      _selectedUserUid = null;
      _usersForBranch = [];
      _isLoadingUsers = true;
    });

    if (branch == null || branch.isEmpty) {
      setState(() => _isLoadingUsers = false);
      return;
    }

    try {
      var query = FirebaseFirestore.instance.collection('users');
      QuerySnapshot snap;
      if (branch == 'All') {
        snap = await query.get();
      } else {
        snap = await query.where('branch', isEqualTo: branch).get();
      }

      final users = <Map<String, dynamic>>[];
      for (var doc in snap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final role = (data['role'] as String? ?? '').toLowerCase();
        if (role == 'sales' || role == 'manager' || role == 'asst_manager' || role == 'dme_user') {
          users.add({
            'uid': doc.id,
            'name': data['username'] ?? data['name'] ?? data['email'] ?? 'User',
            'role': role,
            'branch': data['branch'] ?? '',
          });
        }
      }

      users.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));

      if (mounted) {
        setState(() {
          _usersForBranch = users;
          _isLoadingUsers = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading users for branch: $e');
      if (mounted) setState(() => _isLoadingUsers = false);
    }
  }

  Future<void> _searchComplaints() async {
    if (_selectedBranch == null || _selectedBranch!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a branch first.')),
      );
      return;
    }

    setState(() {
      _isLoadingComplaints = true;
      _hasSearched = true;
    });

    try {
      final branchFilter = _selectedBranch == 'All' ? '' : _selectedBranch!;
      final userFilter = (_selectedUserUid == 'All' || _selectedUserUid == null) ? null : _selectedUserUid;

      final list = await DmeComplaintsService.instance.fetchAdminComplaints(
        branch: branchFilter,
        userUid: userFilter,
      );

      if (mounted) {
        setState(() {
          _complaints = list;
          _isLoadingComplaints = false;
        });
      }
    } catch (e) {
      debugPrint('Error searching admin complaints: $e');
      if (mounted) {
        setState(() => _isLoadingComplaints = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'resolved':
        return Colors.green;
      case 'action_taken':
        return const Color(0xFF005BAC);
      case 'not_resolved':
        return Colors.deepOrange;
      default:
        return Colors.orange[800]!;
    }
  }

  String _getStatusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'resolved':
        return 'RESOLVED';
      case 'action_taken':
        return 'ACTION TAKEN';
      case 'not_resolved':
        return 'NOT RESOLVED';
      default:
        return 'ASSIGNED';
    }
  }

  String _formatDate(DateTime dt) => DateFormat('dd MMM yyyy, hh:mm a').format(dt);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final branchOptions = ['All', ...DmeConstants.branches.map((b) => b.name)];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Complaints Tracking (Read Only)'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Filter Selection Card
          Container(
            padding: const EdgeInsets.all(16),
            color: isDark ? const Color(0xFF0F1B2B) : Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Select Branch & User to Track:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    // Branch Dropdown
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _selectedBranch,
                        hint: const Text('Select Branch'),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: isDark ? const Color(0xFF16253B) : const Color(0xFFF3F4F6),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        items: branchOptions.map((b) {
                          return DropdownMenuItem<String>(
                            value: b,
                            child: Text(b),
                          );
                        }).toList(),
                        onChanged: _onBranchChanged,
                      ),
                    ),
                    const SizedBox(width: 10),

                    // User Dropdown
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _selectedUserUid,
                        hint: Text(_isLoadingUsers ? 'Loading...' : 'Select User'),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: isDark ? const Color(0xFF16253B) : const Color(0xFFF3F4F6),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        items: [
                          const DropdownMenuItem<String>(
                            value: 'All',
                            child: Text('All Users'),
                          ),
                          ..._usersForBranch.map((u) {
                            return DropdownMenuItem<String>(
                              value: u['uid'] as String,
                              child: Text(u['name'] as String, overflow: TextOverflow.ellipsis),
                            );
                          }),
                        ],
                        onChanged: _usersForBranch.isEmpty && _selectedBranch != 'All'
                            ? null
                            : (val) => setState(() => _selectedUserUid = val),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isLoadingComplaints ? null : _searchComplaints,
                    icon: _isLoadingComplaints
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.search, size: 20),
                    label: const Text('View Complaints', style: TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8CC63F),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Content Area
          Expanded(
            child: _isLoadingComplaints
                ? const Center(child: CircularProgressIndicator())
                : !_hasSearched
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.filter_list_rounded, size: 64, color: Colors.grey[400]),
                            const SizedBox(height: 12),
                            const Text(
                              'Please select a branch and user above,\nthen tap "View Complaints" to track records.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 14, color: Colors.grey, height: 1.4),
                            ),
                          ],
                        ),
                      )
                    : _complaints.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.assignment_turned_in_outlined, size: 64, color: Colors.grey[400]),
                                const SizedBox(height: 12),
                                const Text(
                                  'No complaints found for the selected branch & user.',
                                  style: TextStyle(fontSize: 15, color: Colors.grey),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(14),
                            itemCount: _complaints.length,
                            itemBuilder: (context, index) {
                              final c = _complaints[index];
                              final statusColor = _getStatusColor(c.status);
                              final statusLabel = _getStatusLabel(c.status);

                              return Card(
                                elevation: 2,
                                margin: const EdgeInsets.only(bottom: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(14),
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ComplaintDetailPage(
                                          complaintId: c.id,
                                          readOnly: true,
                                        ),
                                      ),
                                    );
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.all(14.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Row(
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFF005BAC).withValues(alpha: 0.1),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Text(
                                                    '#${c.id}',
                                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF005BAC)),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFF8CC63F).withValues(alpha: 0.15),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Text(
                                                    c.branch,
                                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF8CC63F)),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: statusColor.withValues(alpha: 0.12),
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(color: statusColor.withValues(alpha: 0.5)),
                                              ),
                                              child: Text(
                                                statusLabel,
                                                style: TextStyle(
                                                  color: statusColor,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        Text(
                                          c.customerName,
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          c.customerPhone,
                                          style: const TextStyle(fontSize: 13, color: Color(0xFF005BAC), fontWeight: FontWeight.w600),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          c.description,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.black87),
                                        ),
                                        if (c.actionRemarks != null && c.actionRemarks!.isNotEmpty) ...[
                                          const SizedBox(height: 8),
                                          Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: isDark ? const Color(0xFF16253B) : const Color(0xFFF3F7FA),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              'Action Taken: ${c.actionRemarks}',
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                                            ),
                                          ),
                                        ],
                                        const Divider(height: 16),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              'Assigned: ${c.assignedToName ?? 'User'} (${c.assignedToRole ?? 'sales'})',
                                              style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.black54),
                                            ),
                                            Text(
                                              _formatDate(c.createdAt),
                                              style: TextStyle(fontSize: 11, color: isDark ? Colors.white54 : Colors.black45),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
