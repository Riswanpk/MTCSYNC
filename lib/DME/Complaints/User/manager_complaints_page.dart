import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../models/dme_complaint_model.dart';
import '../services/dme_complaints_service.dart';
import 'complaint_detail_page.dart';

class ManagerComplaintsPage extends StatefulWidget {
  const ManagerComplaintsPage({super.key});

  @override
  State<ManagerComplaintsPage> createState() => _ManagerComplaintsPageState();
}

class _ManagerComplaintsPageState extends State<ManagerComplaintsPage> {
  String? _managerUid;
  String? _managerName;
  String? _managerEmail;
  String? _managerBranch;

  List<Map<String, dynamic>> _branchUsers = [];
  String? _selectedUserUid; // null or 'all' for all, or specific UID. Default: _managerUid
  bool _isLoadingUsers = true;

  List<DmeComplaint> _complaints = [];
  bool _isLoadingComplaints = false;

  @override
  void initState() {
    super.initState();
    _loadManagerAndUsers();
  }

  Future<void> _loadManagerAndUsers() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoadingUsers = false);
      return;
    }

    _managerUid = user.uid;
    _managerEmail = user.email;

    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists) {
        final data = doc.data()!;
        _managerName = data['username'] ?? data['name'] ?? user.email?.split('@').first ?? 'Manager';
        _managerBranch = (data['branch'] as String? ?? '').toUpperCase().trim();
      }

      if (_managerBranch != null && _managerBranch!.isNotEmpty) {
        final usersSnap = await FirebaseFirestore.instance
            .collection('users')
            .where('branch', isEqualTo: _managerBranch)
            .get();

        final users = <Map<String, dynamic>>[];
        for (var d in usersSnap.docs) {
          final uData = d.data();
          final role = (uData['role'] as String? ?? '').toLowerCase();
          if (role == 'sales' || role == 'asst_manager' || role == 'manager') {
            users.add({
              'uid': d.id,
              'name': uData['username'] ?? uData['name'] ?? uData['email'] ?? 'User',
              'role': role,
              'email': uData['email'] ?? '',
              'isSelf': d.id == _managerUid,
            });
          }
        }

        // Sort: Self first, then alphabetically
        users.sort((a, b) {
          if (a['isSelf'] == true) return -1;
          if (b['isSelf'] == true) return 1;
          return (a['name'] as String).compareTo(b['name'] as String);
        });

        _branchUsers = users;
      }

      // Default selected user is Self
      _selectedUserUid = _managerUid;

      if (mounted) {
        setState(() => _isLoadingUsers = false);
        _loadComplaints();
      }
    } catch (e) {
      debugPrint('Error loading manager branch users: $e');
      if (mounted) setState(() => _isLoadingUsers = false);
    }
  }

  Future<void> _loadComplaints() async {
    if (_managerBranch == null || _managerBranch!.isEmpty) return;

    setState(() => _isLoadingComplaints = true);
    try {
      final filterUid = (_selectedUserUid == 'all') ? null : _selectedUserUid;
      final list = await DmeComplaintsService.instance.fetchManagerComplaints(
        branch: _managerBranch!,
        userUid: filterUid,
      );

      if (mounted) {
        setState(() {
          _complaints = list;
          _isLoadingComplaints = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading manager complaints: $e');
      if (mounted) setState(() => _isLoadingComplaints = false);
    }
  }

  Future<void> _escalateComplaint(DmeComplaint complaint) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Escalate Complaint'),
        content: Text(
          'Do you want to escalate Complaint #${complaint.id} to yourself?\n\nIt will be assigned to you (${_managerName ?? 'Manager'}), and ${complaint.assignedToName ?? 'the former user'} will no longer see it in their assigned complaints list.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, foregroundColor: Colors.white),
            child: const Text('Escalate to Me'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await DmeComplaintsService.instance.escalateComplaint(
        complaintId: complaint.id,
        managerUid: _managerUid ?? '',
        managerName: _managerName ?? 'Manager',
        managerEmail: _managerEmail ?? '',
        formerAssignedToUid: complaint.assignedToUid,
        formerAssignedToName: complaint.assignedToName ?? 'Former User',
        formerAssignedToEmail: complaint.assignedToEmail ?? '',
        customerName: complaint.customerName,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Complaint successfully escalated to you!'),
            backgroundColor: Colors.green,
          ),
        );
        _loadComplaints();
      }
    } catch (e) {
      debugPrint('Error escalating: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to escalate: $e'), backgroundColor: Colors.red),
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

    return Scaffold(
      appBar: AppBar(
        title: Text('Branch Complaints (${_managerBranch ?? ''})'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadComplaints,
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Card: Dropdown to select User (Default: Self)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: isDark ? const Color(0xFF0F1B2B) : Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Filter by User:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    Text(
                      '${_complaints.length} complaint(s)',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF005BAC), fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_isLoadingUsers)
                  const LinearProgressIndicator(minHeight: 3)
                else
                  DropdownButtonFormField<String>(
                    value: _selectedUserUid,
                    isExpanded: true,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: isDark ? const Color(0xFF16253B) : const Color(0xFFF3F4F6),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                    items: [
                      DropdownMenuItem<String>(
                        value: _managerUid,
                        child: Text(
                          'Self (${_managerName ?? 'Manager'}) [Default]',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF005BAC)),
                        ),
                      ),
                      const DropdownMenuItem<String>(
                        value: 'all',
                        child: Text('All Branch Users (Overview)', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      ..._branchUsers.where((u) => u['uid'] != _managerUid).map((u) {
                        final role = (u['role'] as String? ?? '').toUpperCase();
                        return DropdownMenuItem<String>(
                          value: u['uid'] as String,
                          child: Row(
                            children: [
                              Text(u['name'] as String),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.grey.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(role, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                    onChanged: (val) {
                      setState(() => _selectedUserUid = val);
                      _loadComplaints();
                    },
                  ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Complaints List
          Expanded(
            child: _isLoadingComplaints
                ? const Center(child: CircularProgressIndicator())
                : _complaints.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.assignment_turned_in_outlined, size: 64, color: Colors.grey[400]),
                            const SizedBox(height: 12),
                            const Text(
                              'No complaints found for the selected view.',
                              style: TextStyle(fontSize: 15, color: Colors.grey),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadComplaints,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(14),
                          itemCount: _complaints.length,
                          itemBuilder: (context, index) {
                            final c = _complaints[index];
                            final statusColor = _getStatusColor(c.status);
                            final statusLabel = _getStatusLabel(c.status);
                            final isAssignedToSelf = c.assignedToUid == _managerUid;
                            final canEscalate = !isAssignedToSelf && c.status != 'resolved';

                            return Card(
                              elevation: 2,
                              margin: const EdgeInsets.only(bottom: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ComplaintDetailPage(
                                        complaintId: c.id,
                                        isUnregistered: c.isUnregistered,
                                      ),
                                    ),
                                  );
                                  if (mounted) _loadComplaints();
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
                                              if (c.isUnregistered) ...[
                                                const SizedBox(width: 6),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: Colors.amber.withValues(alpha: 0.15),
                                                    borderRadius: BorderRadius.circular(4),
                                                    border: Border.all(color: Colors.amber.shade700.withValues(alpha: 0.5)),
                                                  ),
                                                  child: Text(
                                                    'Unregistered',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.bold,
                                                      color: Theme.of(context).brightness == Brightness.dark
                                                          ? Colors.amber.shade300
                                                          : Colors.amber.shade900,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                              if (c.isEscalated) ...[
                                                const SizedBox(width: 6),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: Colors.amber.withValues(alpha: 0.15),
                                                    borderRadius: BorderRadius.circular(4),
                                                    border: Border.all(color: Colors.amber),
                                                  ),
                                                  child: const Text(
                                                    'ESCALATED',
                                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange),
                                                  ),
                                                ),
                                              ],
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
                                            'Progress / Action: ${c.actionRemarks}',
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                                          ),
                                        ),
                                      ],
                                      if (c.formerAssignedToName != null) ...[
                                        const SizedBox(height: 6),
                                        Text(
                                          'Former User: ${c.formerAssignedToName}',
                                          style: const TextStyle(fontSize: 11, color: Colors.orange, fontStyle: FontStyle.italic),
                                        ),
                                      ],
                                      const Divider(height: 16),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            'Assigned: ${c.assignedToName ?? 'User'}',
                                            style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.black54),
                                          ),
                                          if (canEscalate)
                                            ElevatedButton.icon(
                                              onPressed: () => _escalateComplaint(c),
                                              icon: const Icon(Icons.arrow_upward_rounded, size: 14),
                                              label: const Text('Escalate', style: TextStyle(fontSize: 11)),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.deepOrange,
                                                foregroundColor: Colors.white,
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                minimumSize: const Size(60, 28),
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                              ),
                                            )
                                          else
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
          ),
        ],
      ),
    );
  }
}
