import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../models/dme_complaint.dart';
import '../services/dme_complaint_service.dart';

const Color primaryColor = Color(0xFF005BAC);

class DmeUserComplaintsPage extends StatefulWidget {
  const DmeUserComplaintsPage({super.key});

  @override
  State<DmeUserComplaintsPage> createState() => _DmeUserComplaintsPageState();
}

class _DmeUserComplaintsPageState extends State<DmeUserComplaintsPage> {
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

      final complaints = await _svc.getMyComplaints(userId: userId);

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

  Future<void> _closeComplaint(DmeComplaint complaint) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Close Complaint'),
        content: Text(
          'Are you sure you want to close this complaint for ${complaint.customerName}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Close', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final uid = _auth.currentUser?.uid;
        if (uid != null && complaint.id != null) {
          await _svc.updateComplaintStatus(
            complaintId: complaint.id!,
            newStatus: 'verified_closed',
            userId: uid,
          );

          // Mark remarks as read
          await _svc.markRemarksAsRead(complaintId: complaint.id!);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Complaint closed successfully'),
                backgroundColor: Colors.green,
              ),
            );
            _loadComplaints();
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Complaints',
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
                                  'No complaints yet',
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
    final hasNewRemarks = complaint.hasNewRemarks;
    final isResolved = complaint.status == 'case_resolved';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border(
            left: BorderSide(
              color: hasNewRemarks
                  ? const Color(0xFFFFA500) // Orange for new remarks
                  : (complaint.isClosed ? Colors.green : const Color(0xFFFF6B6B)),
              width: 4,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with Status
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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: hasNewRemarks
                              ? const Color(0xFFFFA500).withValues(alpha: 0.1)
                              : (complaint.isClosed
                                  ? Colors.green.withValues(alpha: 0.1)
                                  : const Color(0xFFFF6B6B).withValues(alpha: 0.1)),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _formatStatus(complaint.status),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: hasNewRemarks
                                ? const Color(0xFFFFA500)
                                : (complaint.isClosed ? Colors.green : const Color(0xFFFF6B6B)),
                          ),
                        ),
                      ),
                      if (hasNewRemarks) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFA500),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'New Remarks',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Complaint Details
              Text(
                'Complaint',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                complaint.complaintText,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF2C3E50),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 12),

              // Metadata Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Assigned To',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        complaint.assignedToUsername ?? 'N/A',
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
                        'Created',
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

              // Remarks preview if available
              if (complaint.remarks != null && complaint.remarks!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFA500).withValues(alpha: 0.05),
                    border: Border.all(color: const Color(0xFFFFA500).withValues(alpha: 0.2)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Remarks from ${complaint.remarkedByUsername ?? "User"}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFFFA500),
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
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
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

              // Close button for resolved complaints
              if (isResolved) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFA500),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () => _closeComplaint(complaint),
                    child: const Text(
                      'Close Complaint',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatStatus(String status) {
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
