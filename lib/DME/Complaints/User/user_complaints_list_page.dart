import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../models/dme_complaint_model.dart';
import '../services/dme_complaints_service.dart';
import 'complaint_detail_page.dart';

class UserComplaintsListPage extends StatefulWidget {
  const UserComplaintsListPage({super.key});

  @override
  State<UserComplaintsListPage> createState() => _UserComplaintsListPageState();
}

class _UserComplaintsListPageState extends State<UserComplaintsListPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<DmeComplaint> _complaints = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadComplaints();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadComplaints() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final list = await DmeComplaintsService.instance.fetchAssignedComplaints(uid);
      if (mounted) {
        setState(() {
          _complaints = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading assigned complaints: $e');
      if (mounted) setState(() => _isLoading = false);
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
        return 'ACTION SUBMITTED';
      case 'not_resolved':
        return 'ACTION REQUIRED';
      default:
        return 'PENDING ACTION';
    }
  }

  String _formatDate(DateTime dt) => DateFormat('dd MMM yyyy, hh:mm a').format(dt);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeComplaints = _complaints.where((c) => c.status != 'resolved').toList();
    final resolvedComplaints = _complaints.where((c) => c.status == 'resolved').toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Assigned Complaints'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadComplaints,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: const Color(0xFF8CC63F),
          indicatorWeight: 3,
          tabs: [
            Tab(text: 'Active (${activeComplaints.length})'),
            Tab(text: 'Resolved (${resolvedComplaints.length})'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildList(activeComplaints, isDark, emptyMsg: 'No active complaints assigned to you.'),
                _buildList(resolvedComplaints, isDark, emptyMsg: 'No resolved complaints.'),
              ],
            ),
    );
  }

  Widget _buildList(List<DmeComplaint> list, bool isDark, {required String emptyMsg}) {
    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline_rounded, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(emptyMsg, style: const TextStyle(fontSize: 15, color: Colors.grey)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadComplaints,
      child: ListView.builder(
        padding: const EdgeInsets.all(14),
        itemCount: list.length,
        itemBuilder: (context, index) {
          final c = list[index];
          final statusColor = _getStatusColor(c.status);
          final statusLabel = _getStatusLabel(c.status);

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
                            Text(
                              'Complaint #${c.id}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF005BAC)),
                            ),
                            if (c.isUnregistered) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.amber.shade700.withValues(alpha: 0.5)),
                                ),
                                child: Text(
                                  'Unregistered',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? Colors.amber.shade300 : Colors.amber.shade900,
                                  ),
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
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white70 : Colors.black87,
                        height: 1.3,
                      ),
                    ),
                    if (c.dmeResolutionRemarks != null && c.dmeResolutionRemarks!.isNotEmpty && c.status == 'not_resolved') ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_rounded, size: 14, color: Colors.red),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'DME Feedback: ${c.dmeResolutionRemarks}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const Divider(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Raised by: ${c.createdByName ?? 'DME'}',
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
    );
  }
}
