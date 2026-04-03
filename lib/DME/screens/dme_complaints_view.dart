import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/dme_complaint.dart';
import '../services/dme_complaint_service.dart';
import '../../Navigation/user_cache_service.dart';

class DmeComplaintsViewPage extends StatefulWidget {
  const DmeComplaintsViewPage({super.key});

  @override
  State<DmeComplaintsViewPage> createState() => _DmeComplaintsViewPageState();
}

class _DmeComplaintsViewPageState extends State<DmeComplaintsViewPage> {
  final _complaintService = DmeComplaintService.instance;
  final _auth = FirebaseAuth.instance;

  List<DmeComplaint> _complaints = [];
  bool _loading = true;
  String _selectedStatus = 'All'; // All, raised, case_resolved, verified_closed
  String? _userName;
  String? _userRole;
  String? _userBranch;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    try {
      await UserCacheService.instance.ensureLoaded();
      _userName = _auth.currentUser?.uid;
      _userBranch = UserCacheService.instance.branch;
      _userRole = UserCacheService.instance.role;
      
      await _loadComplaints();
    } catch (e) {
      debugPrint('Error loading user info: $e');
      setState(() => _loading = false);
    }
  }

  Future<void> _loadComplaints() async {
    setState(() => _loading = true);
    try {
      List<DmeComplaint> complaints = [];

      // Load based on user role
      if (_userRole == 'dme_admin') {
        // Admin sees all complaints
        complaints = await _complaintService.getAllComplaints();
      } else if (_userRole == 'dme_user') {
        // DME user sees complaints they raised
        complaints = await _complaintService.getComplaintsByUser(
          userId: _userName!,
        );
      } else if (_userBranch != null) {
        // Branch user sees complaints from their branch
        complaints = await _complaintService.getComplaintsForBranch(
          branch: _userBranch!,
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

  List<DmeComplaint> _getFilteredComplaints() {
    if (_selectedStatus == 'All') {
      return _complaints;
    }
    return _complaints
        .where((c) => c.status == _selectedStatus)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Complaints'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _loadComplaints,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildComplaintsView(),
    );
  }

  Widget _buildComplaintsView() {
    final filtered = _getFilteredComplaints();

    return Column(
      children: [
        // Status filter chips
        Padding(
          padding: const EdgeInsets.all(12),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                'All',
                'raised',
                'case_resolved',
                'verified_closed',
              ]
                  .map((status) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(status == 'All'
                          ? 'All (${_complaints.length})'
                          : status == 'raised'
                              ? 'Raised (${_complaints.where((c) => c.status == 'raised').length})'
                              : status == 'case_resolved'
                                  ? 'Case Resolved (${_complaints.where((c) => c.status == 'case_resolved').length})'
                                  : 'Closed (${_complaints.where((c) => c.status == 'verified_closed').length})'),
                      selected: _selectedStatus == status,
                      onSelected: (_) {
                        setState(() => _selectedStatus = status);
                      },
                    ),
                  ))
                  .toList(),
            ),
          ),
        ),
        
        if (filtered.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.done_all, size: 80, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  Text(
                    _selectedStatus == 'All'
                        ? 'No complaints'
                        : 'No $_selectedStatus complaints',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ),
        
        if (filtered.isNotEmpty)
          Expanded(
            child: ListView.separated(
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, index) => _buildComplaintTile(filtered[index]),
            ),
          ),
      ],
    );
  }

  Widget _buildComplaintTile(DmeComplaint complaint) {
    final statusColor = _getStatusColorAndIcon(complaint.status);

    return InkWell(
      onTap: () => _showComplaintDetail(complaint),
      child: Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: statusColor['color'] as Color?,
                  child: Icon(
                    statusColor['icon'] as IconData,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        complaint.customerName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        complaint.category,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: (statusColor['color'] as Color?)?.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    complaint.status == 'verified_closed'
                        ? 'Closed'
                        : complaint.status.replaceAll('_', ' ').toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: statusColor['color'] as Color?,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              complaint.complaintText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.phone, size: 14, color: Colors.grey[400]),
                const SizedBox(width: 6),
                Text(
                  complaint.customerPhone,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const Spacer(),
                Text(
                  _formatDate(complaint.createdAt),
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showComplaintDetail(DmeComplaint complaint) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (_) => _ComplaintDetailSheet(
        complaint: complaint,
        userRole: _userRole,
        onStatusChanged: _loadComplaints,
      ),
    );
  }

  Map<String, dynamic> _getStatusColorAndIcon(String status) {
    switch (status) {
      case 'raised':
        return {'color': Colors.red, 'icon': Icons.flag};
      case 'case_resolved':
        return {'color': Colors.orange, 'icon': Icons.check_circle};
      case 'verified_closed':
        return {'color': Colors.green, 'icon': Icons.done_all};
      default:
        return {'color': Colors.grey, 'icon': Icons.help};
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final complaintDay = DateTime(date.year, date.month, date.day);

    if (complaintDay == today) {
      return 'Today';
    } else if (complaintDay == today.subtract(const Duration(days: 1))) {
      return 'Yesterday';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}

// Complaint Detail Sheet
class _ComplaintDetailSheet extends StatefulWidget {
  final DmeComplaint complaint;
  final String? userRole;
  final VoidCallback? onStatusChanged;

  const _ComplaintDetailSheet({
    required this.complaint,
    this.userRole,
    this.onStatusChanged,
  });

  @override
  State<_ComplaintDetailSheet> createState() => _ComplaintDetailSheetState();
}

class _ComplaintDetailSheetState extends State<_ComplaintDetailSheet> {
  final _complaintService = DmeComplaintService.instance;
  final _auth = FirebaseAuth.instance;

  bool _updating = false;

  Future<void> _updateStatus(String newStatus) async {
    setState(() => _updating = true);
    try {
      await _complaintService.updateComplaintStatus(
        complaintId: widget.complaint.id ?? '',
        newStatus: newStatus,
        userId: _auth.currentUser?.uid ?? '',
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Status updated'),
            backgroundColor: Colors.green,
          ),
        );
        widget.onStatusChanged?.call();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
        setState(() => _updating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Complaint Details',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Customer Info
            _buildDetailRow('Customer:', widget.complaint.customerName),
            _buildDetailRow('Phone:', widget.complaint.customerPhone),
            _buildDetailRow('Branch:', widget.complaint.branch),
            _buildDetailRow('Category:', widget.complaint.category),
            
            const SizedBox(height: 16),
            const Text(
              'Complaint',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                widget.complaint.complaintText,
                style: const TextStyle(fontSize: 13),
              ),
            ),

            const SizedBox(height: 16),

            // Status and workflow
            _buildStatusWorkflow(),

            const SizedBox(height: 20),

            // Action buttons (based on role and status)
            if (widget.userRole != 'dme_user' &&
                widget.complaint.status == 'raised')
              ElevatedButton.icon(
                onPressed: _updating
                    ? null
                    : () => _updateStatus('case_resolved'),
                icon: _updating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle),
                label: const Text('Mark Case Resolved'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
              ),
            
            if ((widget.userRole == 'dme_admin' ||
                    widget.userRole == 'dme_user') &&
                widget.complaint.status == 'case_resolved')
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _updating
                        ? null
                        : () => _updateStatus('verified_closed'),
                    icon: _updating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                        : const Icon(Icons.done_all),
                    label: const Text('Verify & Close'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusWorkflow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Workflow',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _buildStatusStep('Raised', widget.complaint.status != 'raised'),
            const SizedBox(width: 12),
            _buildStatusStep('Case Resolved',
                widget.complaint.status == 'verified_closed'),
            const SizedBox(width: 12),
            _buildStatusStep('Closed', false),
          ],
        ),
        if (widget.complaint.resolvedAt != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'Case resolved by: ${widget.complaint.resolvedBy}',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
        if (widget.complaint.closedAt != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Closed by: ${widget.complaint.closedBy}',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
      ],
    );
  }

  Widget _buildStatusStep(String label, bool completed) {
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: completed ? Colors.green : Colors.grey[300],
            ),
            child: Icon(
              completed ? Icons.check : Icons.circle,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: completed ? Colors.green : Colors.grey,
              fontWeight: completed ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}
