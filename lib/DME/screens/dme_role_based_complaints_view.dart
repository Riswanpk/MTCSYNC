import 'package:flutter/material.dart';
import '../models/dme_complaint.dart';
import '../models/dme_user.dart';
import '../services/dme_complaint_service.dart';
import '../widgets/complaint_details_dialog.dart';

class DmeRoleBasedComplaintsView extends StatefulWidget {
  final DmeUser user;

  const DmeRoleBasedComplaintsView({
    super.key,
    required this.user,
  });

  @override
  State<DmeRoleBasedComplaintsView> createState() =>
      _DmeRoleBasedComplaintsViewState();
}

class _DmeRoleBasedComplaintsViewState
    extends State<DmeRoleBasedComplaintsView> {
  final _svc = DmeComplaintService.instance;
  List<DmeComplaint> _complaints = [];
  bool _loading = true;
  String? _selectedStatus;

  @override
  void initState() {
    super.initState();
    _loadComplaints();
  }

  /// Load complaints based on user's role and branch
  Future<void> _loadComplaints() async {
    setState(() => _loading = true);
    try {
      List<DmeComplaint> complaints = [];

      // Manager: See ALL complaints in their branch
      if (widget.user.role == 'manager') {
        complaints = await _svc.getComplaintsForBranch(
          branchId: widget.user.branchId,
          status: _selectedStatus,
        );
      }
      // Assigned user (asst_manager, sales): See only assigned to them
      else {
        complaints = await _svc.getAssignedComplaints(
          userId: widget.user.firebaseUid,
          status: _selectedStatus,
        );
      }

      if (mounted) {
        setState(() {
          _complaints = complaints;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading complaints: $e');
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading complaints: $e')),
        );
      }
    }
  }

  /// Check if the user can edit a complaint
  bool _canEditComplaint(DmeComplaint complaint) {
    // Manager can edit if assigned to them
    if (widget.user.role == 'manager') {
      return complaint.assignedToId == widget.user.firebaseUid;
    }
    // Others can edit only if assigned to them
    return complaint.assignedToId == widget.user.firebaseUid;
  }

  void _showComplaintDetails(DmeComplaint complaint) {
    final canEdit = _canEditComplaint(complaint);

    showDialog(
      context: context,
      builder: (context) => ComplaintDetailsDialog(
        complaint: complaint,
        canEdit: canEdit,
        onUpdate: () {
          _loadComplaints(); // Reload after update
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Complaints'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
        actions: [
          PopupMenuButton<String?>(
            onSelected: (status) {
              setState(() => _selectedStatus = status);
              _loadComplaints();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: null, child: Text('All')),
              const PopupMenuItem(value: 'raised', child: Text('Raised')),
              const PopupMenuItem(
                value: 'case_resolved',
                child: Text('Case Resolved'),
              ),
              const PopupMenuItem(
                value: 'verified_closed',
                child: Text('Verified Closed'),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Icon(
                Icons.filter_list,
                color: _selectedStatus != null ? Colors.yellow : Colors.white,
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _complaints.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.assignment_turned_in_outlined,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          widget.user.role == 'manager'
                              ? 'No complaints in your branch'
                              : 'No complaints assigned to you',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _complaints.length,
                  itemBuilder: (context, index) {
                    final complaint = _complaints[index];
                    final statusColor = _getStatusColor(complaint.status);

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      color: isDark ? const Color(0xFF1A2332) : Colors.white,
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.warning_rounded,
                            color: statusColor,
                          ),
                        ),
                        title: Text(
                          complaint.customerName,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text(
                              complaint.complaintText,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isDark
                                    ? Colors.white70
                                    : Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Status: ${complaint.status}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: statusColor,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                if (complaint.hasNewRemarks)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'New Remarks',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.green,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                        trailing: Icon(
                          Icons.arrow_forward_ios,
                          size: 18,
                          color: Colors.grey,
                        ),
                        onTap: () => _showComplaintDetails(complaint),
                      ),
                    );
                  },
                ),
      floatingActionButton: widget.user.role != 'manager'
          ? null
          : FloatingActionButton.extended(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Complaints must be created from reminders'),
                  ),
                );
              },
              label: const Text('New Complaint'),
              icon: const Icon(Icons.add),
              backgroundColor: const Color(0xFF005BAC),
            ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'raised':
        return const Color(0xFFFF6B6B);
      case 'case_resolved':
        return const Color(0xFFFFA500);
      case 'verified_closed':
        return const Color(0xFF8CC63F);
      default:
        return Colors.grey;
    }
  }
}
