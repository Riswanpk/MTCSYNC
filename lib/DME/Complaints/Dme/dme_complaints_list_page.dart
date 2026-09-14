import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/dme_complaint_model.dart';
import '../services/dme_complaints_service.dart';
import 'dme_manual_complaint_search_page.dart';
import '../User/complaint_detail_page.dart';

class DmeComplaintsListPage extends StatefulWidget {
  const DmeComplaintsListPage({super.key});

  @override
  State<DmeComplaintsListPage> createState() => _DmeComplaintsListPageState();
}

class _DmeComplaintsListPageState extends State<DmeComplaintsListPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<DmeComplaint> _allComplaints = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _loadComplaints();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadComplaints() async {
    setState(() => _isLoading = true);
    try {
      final complaints = await DmeComplaintsService.instance.fetchDmeComplaints();
      if (mounted) {
        setState(() {
          _allComplaints = complaints;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading DME complaints: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<DmeComplaint> _getFilteredComplaints(int tabIndex) {
    switch (tabIndex) {
      case 1: // Under Review / Action Taken
        return _allComplaints.where((c) => c.status == 'action_taken').toList();
      case 2: // Pending Action / Reopened
        return _allComplaints.where((c) => c.status == 'assigned' || c.status == 'not_resolved').toList();
      case 3: // Resolved
        return _allComplaints.where((c) => c.status == 'resolved').toList();
      case 0: // All
      default:
        return _allComplaints;
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
        title: const Text('Customer Complaints'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadComplaints,
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded, size: 26),
            tooltip: 'Register Complaint Manually',
            onPressed: () async {
              final res = await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DmeManualComplaintSearchPage()),
              );
              if (res == true && mounted) {
                _loadComplaints();
              }
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: const Color(0xFF8CC63F),
          indicatorWeight: 3,
          tabs: [
            Tab(text: 'All (${_allComplaints.length})'),
            Tab(text: 'Action Taken (${_allComplaints.where((c) => c.status == 'action_taken').length})'),
            Tab(text: 'Pending (${_allComplaints.where((c) => c.status == 'assigned' || c.status == 'not_resolved').length})'),
            Tab(text: 'Resolved (${_allComplaints.where((c) => c.status == 'resolved').length})'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final res = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const DmeManualComplaintSearchPage()),
          );
          if (res == true && mounted) {
            _loadComplaints();
          }
        },
        backgroundColor: const Color(0xFF8CC63F),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Register Complaint', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: List.generate(4, (tabIndex) {
                final list = _getFilteredComplaints(tabIndex);
                if (list.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.assignment_turned_in_outlined, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 12),
                        const Text(
                          'No complaints found in this tab.',
                          style: TextStyle(fontSize: 15, color: Colors.grey),
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: _loadComplaints,
                  child: ListView.builder(
                    padding: const EdgeInsets.only(left: 14, right: 14, top: 14, bottom: 80),
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
                                builder: (_) => ComplaintDetailPage(complaintId: c.id),
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
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isDark ? Colors.white70 : Colors.black87,
                                    height: 1.3,
                                  ),
                                ),
                                if (c.actionRemarks != null && c.actionRemarks!.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: isDark ? const Color(0xFF16253B) : const Color(0xFFF3F7FA),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: const Color(0xFF005BAC).withValues(alpha: 0.2)),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.chat_bubble_outline_rounded, size: 14, color: Color(0xFF005BAC)),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            'Latest Action: ${c.actionRemarks}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
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
                                      'Assigned: ${c.assignedToName ?? 'User'}',
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
              }),
            ),
    );
  }
}
