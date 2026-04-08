import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/dme_complaint.dart';
import '../services/dme_supabase_service.dart';

const Color primaryColor = Color(0xFF005BAC);

class DmeComplaintsManagementPage extends StatefulWidget {
  const DmeComplaintsManagementPage({super.key});

  @override
  State<DmeComplaintsManagementPage> createState() =>
      _DmeComplaintsManagementPageState();
}

class _DmeComplaintsManagementPageState
    extends State<DmeComplaintsManagementPage> {
  final _svc = DmeSupabaseService.instance;

  List<DmeComplaint> _complaints = [];
  List<DmeComplaint> _filteredComplaints = [];
  List<Map<String, dynamic>> _branches = [];
  bool _loading = true;

  String? _selectedBranch;
  String? _selectedStatus;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final user = uid != null ? await _svc.getCurrentUser(uid) : null;
      List<int>? userBranchIds;
      
      // Get branch IDs for non-admin users
      if (user != null && !user.isAdmin) {
        userBranchIds = await _svc.getUserBranchIds(user.id);
      }

      final results = await Future.wait([
        _svc.getBranches(),
        _svc.getComplaints(userBranchIds: userBranchIds),
      ]);

      if (mounted) {
        setState(() {
          _branches = results[0] as List<Map<String, dynamic>>;
          _complaints = results[1] as List<DmeComplaint>;
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
    _filteredComplaints = _complaints.where((complaint) {
      bool branchMatch = _selectedBranch == null ||
          _selectedBranch == 'All' ||
          complaint.branchId.toString() == _selectedBranch;
      bool statusMatch = _selectedStatus == null ||
          _selectedStatus == 'All' ||
          complaint.status == _selectedStatus;
      return branchMatch && statusMatch;
    }).toList();
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
        final uid = FirebaseAuth.instance.currentUser?.uid;
        final user = uid != null ? await _svc.getCurrentUser(uid) : null;
        
        if (user != null) {
          await _svc.updateComplaintStatus(
            complaint.id!,
            'CLOSED',
            user.id,
            user.username,
          );
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Complaint closed successfully')),
            );
            _loadData();
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
        title: const Text('Manage Complaints',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _loadData,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
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
                          'Filters',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF2C3E50),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildFilterDropdown(
                                label: 'Branch',
                                value: _selectedBranch,
                                items: [
                                  'All',
                                  ..._branches
                                      .map((b) => b['name'] as String),
                                ],
                                onChanged: (value) {
                                  setState(() {
                                    _selectedBranch = value;
                                    _applyFilters();
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildFilterDropdown(
                                label: 'Status',
                                value: _selectedStatus,
                                items: ['All', 'OPEN', 'CLOSED'],
                                onChanged: (value) {
                                  setState(() {
                                    _selectedStatus = value;
                                    _applyFilters();
                                  });
                                },
                              ),
                            ),
                          ],
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
                                  Icons.inbox_rounded,
                                  size: 64,
                                  color: Colors.grey[300],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No complaints found',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey[500],
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: _filteredComplaints.length,
                            itemBuilder: (ctx, index) {
                              final complaint = _filteredComplaints[index];
                              return _buildComplaintCard(complaint);
                            },
                          ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildFilterDropdown({
    required String label,
    required String? value,
    required List<String> items,
    required Function(String?) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[300]!),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButton<String>(
            value: value ?? 'All',
            isExpanded: true,
            underline: SizedBox(),
            items: items
                .map((item) => DropdownMenuItem(value: item, child: Text(item)))
                .toList(),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildComplaintCard(DmeComplaint complaint) {
    final dateFormat = DateFormat('dd MMM yyyy, hh:mm a');
    final isOpen = complaint.status == 'OPEN';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border(
            left: BorderSide(
              color: isOpen ? const Color(0xFFFF6B6B) : Colors.green,
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
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF2C3E50),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          complaint.customerPhone,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isOpen
                          ? const Color(0xFFFF6B6B).withValues(alpha: 0.1)
                          : Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      complaint.status,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isOpen
                            ? const Color(0xFFFF6B6B)
                            : Colors.green,
                      ),
                    ),
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
                        'Branch',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        complaint.branchName,
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
                        'Registered',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        dateFormat.format(complaint.createdAt),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF2C3E50),
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              // Close button for open complaints
              if (isOpen) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6B6B),
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
}
