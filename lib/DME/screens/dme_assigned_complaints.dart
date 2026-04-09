import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../models/dme_complaint.dart';
import '../services/dme_complaint_service.dart';

const Color primaryColor = Color(0xFF005BAC);

class DmeAssignedComplaintsPage extends StatefulWidget {
  const DmeAssignedComplaintsPage({super.key});

  @override
  State<DmeAssignedComplaintsPage> createState() => _DmeAssignedComplaintsPageState();
}

class _DmeAssignedComplaintsPageState extends State<DmeAssignedComplaintsPage> {
  final _svc = DmeComplaintService.instance;
  final _auth = FirebaseAuth.instance;

  List<DmeComplaint> _complaints = [];
  List<DmeComplaint> _filteredComplaints = [];
  bool _loading = true;
  String? _selectedStatus;

  @override
  void initState() {
    super.initState();
    _loadComplaints();
  }

  Future<void> _loadComplaints() async {
    setState(() => _loading = true);
    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) throw Exception('User not authenticated');

      final complaints = await _svc.getAssignedComplaints(userId: userId);

      if (mounted) {
        setState(() {
          _complaints = complaints;
          _applyFilters();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  void _applyFilters() {
    if (_selectedStatus == null || _selectedStatus == 'All') {
      _filteredComplaints = _complaints;
    } else {
      _filteredComplaints = _complaints.where((c) => c.status == _selectedStatus).toList();
    }
  }

  void _onStatusChanged(String? status) {
    setState(() {
      _selectedStatus = status;
      _applyFilters();
    });
  }

  void _showRemarksDialog(DmeComplaint complaint) {
    final remarksController = TextEditingController(text: complaint.remarks ?? '');
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Add Remarks for ${complaint.customerName}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Complaint details
                Text(
                  'Complaint Details',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    complaint.complaintText,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF2C3E50),
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Remarks field
                Text(
                  'Your Remarks',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: remarksController,
                  maxLines: 4,
                  minLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Enter your remarks or action taken...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
              ),
              onPressed: isSubmitting
                  ? null
                  : () async {
                      if (remarksController.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please enter remarks')),
                        );
                        return;
                      }

                      setState(() => isSubmitting = true);

                      try {
                        final uid = _auth.currentUser?.uid;
                        if (uid != null && complaint.id != null) {
                          await _svc.addRemarks(
                            complaintId: complaint.id!,
                            remarks: remarksController.text.trim(),
                            userId: uid,
                          );

                          if (mounted) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Remarks added successfully'),
                                backgroundColor: Colors.green,
                              ),
                            );
                            _loadComplaints();
                          }
                        }
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error: $e')),
                        );
                      } finally {
                        if (mounted) {
                          setState(() => isSubmitting = false);
                        }
                      }
                    },
              child: isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : const Text(
                      'Submit Remarks',
                      style: TextStyle(color: Colors.white),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Assigned Complaints',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _loadComplaints,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadComplaints,
              child: Column(
                children: [
                  // Filter Section
                  Container(
                    color: Colors.grey[100],
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Status Filter',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF2C3E50),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _buildFilterChip('All', null),
                              _buildFilterChip('Raised', 'raised'),
                              _buildFilterChip('Resolved', 'case_resolved'),
                              _buildFilterChip('Closed', 'verified_closed'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Complaints List
                  Expanded(
                    child: _filteredComplaints.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.assignment_outlined,
                                  size: 48,
                                  color: Colors.grey[300],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No assigned complaints',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey[400],
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: _filteredComplaints.length,
                            itemBuilder: (ctx, index) {
                              return _buildComplaintCard(_filteredComplaints[index]);
                            },
                          ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildFilterChip(String label, String? value) {
    final isSelected = _selectedStatus == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) => _onStatusChanged(value),
        backgroundColor: Colors.white,
        selectedColor: primaryColor.withValues(alpha: 0.2),
        labelStyle: TextStyle(
          color: isSelected ? primaryColor : Colors.grey[600],
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
        side: BorderSide(
          color: isSelected ? primaryColor : Colors.grey[300]!,
        ),
      ),
    );
  }

  Widget _buildComplaintCard(DmeComplaint complaint) {
    final dateFormat = DateFormat('dd MMM yyyy, hh:mm a');
    final needsRemarks = complaint.status == 'raised';
    final hasRemarks = complaint.remarks != null && complaint.remarks!.isNotEmpty;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border(
            left: BorderSide(
              color: needsRemarks ? const Color(0xFFFF6B6B) : const Color(0xFF8CC63F),
              width: 4,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
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
                        Text(
                          complaint.customerName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF2C3E50),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          complaint.customerPhone,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: needsRemarks
                          ? const Color(0xFFFF6B6B).withValues(alpha: 0.1)
                          : Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _formatStatus(complaint.status),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: needsRemarks ? const Color(0xFFFF6B6B) : Colors.green,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Branch Info
              Text(
                'Branch: ${complaint.branchName}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),

              // Complaint Text
              Text(
                complaint.complaintText,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF2C3E50),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 12),

              // Created info
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Created By',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        complaint.createdByUsername ?? 'N/A',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF2C3E50),
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Created On',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        dateFormat.format(complaint.createdAt),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF2C3E50),
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              // Existing Remarks if available
              if (hasRemarks) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.05),
                    border: Border.all(color: Colors.green.withValues(alpha: 0.2)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your Remarks',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.green[700],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        complaint.remarks!,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF2C3E50),
                          height: 1.4,
                        ),
                      ),
                      if (complaint.remarkedAt != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          dateFormat.format(complaint.remarkedAt!),
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],

              // Action Button
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: needsRemarks ? const Color(0xFFFF6B6B) : primaryColor,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () => _showRemarksDialog(complaint),
                  icon: const Icon(Icons.edit, color: Colors.white),
                  label: Text(
                    needsRemarks ? 'Add Remarks' : 'Edit Remarks',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatStatus(String status) {
    switch (status) {
      case 'raised':
        return 'PENDING';
      case 'case_resolved':
        return 'RESOLVED';
      case 'verified_closed':
        return 'CLOSED';
      default:
        return status.toUpperCase();
    }
  }
}
