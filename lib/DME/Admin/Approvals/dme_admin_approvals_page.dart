import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../dme_config.dart';
import '../../dme_constants.dart';
import '../../User/dme_user_stats_service.dart';

class DmeAdminApprovalsPage extends StatefulWidget {
  const DmeAdminApprovalsPage({super.key});

  @override
  State<DmeAdminApprovalsPage> createState() => _DmeAdminApprovalsPageState();
}

class _DmeAdminApprovalsPageState extends State<DmeAdminApprovalsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  String _searchQuery = '';
  String _selectedTypeFilter = 'all'; // 'all', 'phone_number_change', 'preference_change'

  List<Map<String, dynamic>> _allRequests = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadRequests();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadRequests() async {
    if (mounted) setState(() => _isLoading = true);

    try {
      final client = await DmeConfig.getClient();
      if (client == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final res = await client
          .from(DmeConstants.tableChangeRequests)
          .select('*')
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _allRequests = List<Map<String, dynamic>>.from(res as List);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading change requests: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load requests: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  List<Map<String, dynamic>> _filterByStatus(String status) {
    return _allRequests.where((req) {
      final reqStatus = (req['status'] ?? 'pending').toString().toLowerCase();
      if (reqStatus != status.toLowerCase()) return false;

      // Type filter
      if (_selectedTypeFilter != 'all') {
        final type = (req['request_type'] ?? '').toString().toLowerCase();
        if (type != _selectedTypeFilter.toLowerCase()) return false;
      }

      // Search filter
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final name = (req['customer_name'] ?? '').toString().toLowerCase();
        final phone = (req['customer_phone'] ?? '').toString().toLowerCase();
        final newPhone = (req['new_value'] ?? '').toString().toLowerCase();
        final requestedBy = (req['requested_by'] ?? '').toString().toLowerCase();
        final reason = (req['reason'] ?? '').toString().toLowerCase();

        return name.contains(query) ||
            phone.contains(query) ||
            newPhone.contains(query) ||
            requestedBy.contains(query) ||
            reason.contains(query);
      }

      return true;
    }).toList();
  }

  Future<void> _approveRequest(Map<String, dynamic> request) async {
    final customerName = request['customer_name'] ?? 'Customer';
    final requestType = request['request_type'] ?? '';
    final isPhoneChange = requestType == 'phone_number_change';
    final isCallCompletion = requestType == 'call_completion';
    final newValue = (request['new_value'] ?? '').toString().trim();
    final customerId = int.tryParse(request['customer_id']?.toString() ?? '');
    final reminderId = int.tryParse(request['reminder_id']?.toString() ?? '');

    if (customerId == null || newValue.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid request data.'), backgroundColor: Colors.red),
      );
      return;
    }

    int callDuration = 0;
    String completionRemarks = '';
    String requestingUserUid = '';
    String requestingUserEmail = (request['requested_by'] ?? '').toString();

    if (isCallCompletion) {
      if (newValue.startsWith('{')) {
        try {
          final data = jsonDecode(newValue);
          callDuration = int.tryParse(data['duration']?.toString() ?? '') ?? 0;
          completionRemarks = data['remarks']?.toString() ?? '';
          requestingUserUid = data['user_uid']?.toString() ?? '';
          if (requestingUserEmail.isEmpty) {
            requestingUserEmail = data['user_email']?.toString() ?? '';
          }
        } catch (_) {}
      } else {
        callDuration = int.tryParse(newValue) ?? 0;
        completionRemarks = request['reason']?.toString() ?? '';
      }
    }

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.green),
            const SizedBox(width: 8),
            Text(
              isCallCompletion ? 'Approve Call Completion' : 'Approve Request',
              style: const TextStyle(fontSize: 18),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to approve this request for $customerName?',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            if (isCallCompletion) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.purple.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.purple.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Action: Mark Call Status as Completed',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.purple),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Call Duration: $callDuration sec',
                      style: TextStyle(fontSize: 12, color: Colors.grey[800], fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Called By: $requestingUserEmail',
                      style: TextStyle(fontSize: 12, color: Colors.grey[800]),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Call Timestamp: ${DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now())} (Current Time)',
                      style: TextStyle(fontSize: 12, color: Colors.grey[800]),
                    ),
                    if (completionRemarks.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Remarks: $completionRemarks',
                        style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey[800]),
                      ),
                    ],
                  ],
                ),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isPhoneChange ? 'New Phone Number:' : 'New Preference:',
                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      newValue,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.green),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirm Approve'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final client = await DmeConfig.getClient();
      if (client == null) return;

      final adminUser = FirebaseAuth.instance.currentUser;
      final adminEmail = adminUser?.email ?? adminUser?.displayName ?? 'admin';
      final now = DateTime.now();
      final nowIso = now.toIso8601String();

      // 1. Process changes
      if (isCallCompletion) {
        if (reminderId != null) {
          final payload = <String, dynamic>{
            'status': 'completed',
            'call_duration': callDuration,
            'called_timestamp': nowIso,
            'called_by': requestingUserEmail,
            'remarks': completionRemarks,
            'updated_at': nowIso,
          };
          await client.from('dme_reminders').update(payload).eq('id', reminderId);
        }

        // Increment daily call count for the requesting user
        try {
          final statDate = DateFormat('yyyy-MM-dd').format(now);
          final uid = requestingUserUid.isNotEmpty ? requestingUserUid : requestingUserEmail;
          await DmeUserStatsService.incrementCallCount(
            userUid: uid,
            userEmail: requestingUserEmail,
            statDate: statDate,
          );
        } catch (statErr) {
          debugPrint('Notice updating user daily stats: $statErr');
        }
      } else if (isPhoneChange) {
        await client.from(DmeConstants.tableCustomers).update({
          'phone': newValue,
          'updated_at': nowIso,
        }).eq('id', customerId);
      } else {
        await client.from(DmeConstants.tableCustomers).update({
          'preference': newValue,
          'updated_at': nowIso,
        }).eq('id', customerId);
      }

      // 2. Update change request record
      await client.from(DmeConstants.tableChangeRequests).update({
        'status': 'approved',
        'reviewed_by': adminEmail,
        'updated_at': nowIso,
      }).eq('id', request['id']);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isCallCompletion
                  ? 'Call status approved & marked as completed with $callDuration sec!'
                  : (isPhoneChange
                      ? 'Phone number updated to $newValue! Reminder unlocked.'
                      : 'Preference updated to $newValue successfully!'),
            ),
            backgroundColor: Colors.green,
          ),
        );
        _loadRequests();
      }
    } catch (e) {
      debugPrint('Error approving request: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error approving request: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _rejectRequest(Map<String, dynamic> request) async {
    final noteController = TextEditingController();

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(
          children: [
            const Icon(Icons.cancel_rounded, color: Colors.red),
            const SizedBox(width: 8),
            const Text('Reject Request', style: TextStyle(fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Reject change request for ${request['customer_name'] ?? 'Customer'}?',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              decoration: InputDecoration(
                labelText: 'Reason for Rejection (Optional)',
                hintText: 'e.g. Invalid phone format, verified existing number is active',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirm Reject'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final client = await DmeConfig.getClient();
      if (client == null) return;

      final adminUser = FirebaseAuth.instance.currentUser;
      final adminEmail = adminUser?.email ?? adminUser?.displayName ?? 'admin';
      final now = DateTime.now().toIso8601String();

      await client.from(DmeConstants.tableChangeRequests).update({
        'status': 'rejected',
        'reviewed_by': adminEmail,
        'admin_notes': noteController.text.trim(),
        'updated_at': now,
      }).eq('id', request['id']);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Request marked as rejected.'),
            backgroundColor: Colors.orange,
          ),
        );
        _loadRequests();
      }
    } catch (e) {
      debugPrint('Error rejecting request: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error rejecting request: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _formatDateTime(dynamic ts) {
    if (ts == null) return 'N/A';
    final parsed = DateTime.tryParse(ts.toString());
    if (parsed == null) return ts.toString();
    return DateFormat('dd-MM-yyyy hh:mm a').format(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final pendingList = _filterByStatus('pending');
    final approvedList = _filterByStatus('approved');
    final rejectedList = _filterByStatus('rejected');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Approvals & Requests', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _loadRequests,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF8CC63F),
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Pending'),
                  if (pendingList.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade800,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${pendingList.length}',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Approved'),
                  if (approvedList.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green.shade700,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${approvedList.length}',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Rejected'),
                  if (rejectedList.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red.shade700,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${rejectedList.length}',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Search & Filter Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            color: isDark ? Colors.grey[900] : Colors.grey[50],
            child: Column(
              children: [
                // Search Input
                TextField(
                  onChanged: (val) => setState(() => _searchQuery = val.trim()),
                  decoration: InputDecoration(
                    hintText: 'Search by customer name, phone, user...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    filled: true,
                    fillColor: isDark ? Colors.grey[800] : Colors.white,
                  ),
                ),
                const SizedBox(height: 8),

                // Filter Chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ChoiceChip(
                        label: const Text('All Requests'),
                        selected: _selectedTypeFilter == 'all',
                        onSelected: (val) {
                          if (val) setState(() => _selectedTypeFilter = 'all');
                        },
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        avatar: const Icon(Icons.phone_iphone_rounded, size: 16),
                        label: const Text('Phone Changes'),
                        selected: _selectedTypeFilter == 'phone_number_change',
                        selectedColor: Colors.orange.withValues(alpha: 0.25),
                        onSelected: (val) {
                          if (val) setState(() => _selectedTypeFilter = 'phone_number_change');
                        },
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        avatar: const Icon(Icons.swap_horiz_rounded, size: 16),
                        label: const Text('Preference Changes'),
                        selected: _selectedTypeFilter == 'preference_change',
                        selectedColor: const Color(0xFF005BAC).withValues(alpha: 0.25),
                        onSelected: (val) {
                          if (val) setState(() => _selectedTypeFilter = 'preference_change');
                        },
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        avatar: const Icon(Icons.check_circle_outline_rounded, size: 16),
                        label: const Text('Call Completions'),
                        selected: _selectedTypeFilter == 'call_completion',
                        selectedColor: Colors.purple.withValues(alpha: 0.25),
                        onSelected: (val) {
                          if (val) setState(() => _selectedTypeFilter = 'call_completion');
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Tab Views
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildRequestList(pendingList, isPendingTab: true),
                      _buildRequestList(approvedList),
                      _buildRequestList(rejectedList, isRejectedTab: true),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestList(List<Map<String, dynamic>> list, {bool isPendingTab = false, bool isRejectedTab = false}) {
    if (list.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadRequests,
        child: ListView(
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.2),
            Center(
              child: Column(
                children: [
                  Icon(
                    isPendingTab
                        ? Icons.task_alt_rounded
                        : isRejectedTab
                            ? Icons.cancel_outlined
                            : Icons.check_circle_outline_rounded,
                    size: 54,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isPendingTab
                        ? 'No pending approval requests!'
                        : isRejectedTab
                            ? 'No rejected requests found.'
                            : 'No approved requests found.',
                    style: TextStyle(color: Colors.grey[600], fontSize: 15),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return RefreshIndicator(
      onRefresh: _loadRequests,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: list.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final req = list[index];
          final type = (req['request_type'] ?? '').toString();
          final isCallCompletion = type == 'call_completion';
          final isPhone = type == 'phone_number_change';
          final status = (req['status'] ?? 'pending').toString().toLowerCase();
          final customerName = req['customer_name'] ?? 'Unnamed Customer';
          final currentVal = req['current_value'] ?? 'N/A';
          final newVal = req['new_value'] ?? 'N/A';
          final reason = req['reason'] ?? '';
          final requestedBy = req['requested_by'] ?? 'User';
          final createdAtStr = _formatDateTime(req['created_at']);
          final reviewedBy = req['reviewed_by'] ?? '';
          final adminNotes = req['admin_notes'] ?? '';

          int completionDuration = 0;
          String completionRemarks = '';
          String completionNote = '';
          if (isCallCompletion) {
            if (newVal.startsWith('{')) {
              try {
                final d = jsonDecode(newVal);
                completionDuration = int.tryParse(d['duration']?.toString() ?? '') ?? 0;
                completionRemarks = d['remarks']?.toString() ?? '';
                completionNote = d['reason']?.toString() ?? '';
              } catch (_) {}
            } else {
              completionDuration = int.tryParse(newVal) ?? 0;
            }
          }

          return Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(14.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Row: Type Badge + Status
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isCallCompletion
                              ? Colors.purple.withValues(alpha: 0.15)
                              : (isPhone ? Colors.orange.withValues(alpha: 0.15) : const Color(0xFF005BAC).withValues(alpha: 0.15)),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isCallCompletion
                                  ? Icons.check_circle_outline_rounded
                                  : (isPhone ? Icons.phone_iphone_rounded : Icons.swap_horiz_rounded),
                              size: 13,
                              color: isCallCompletion
                                  ? Colors.purple.shade900
                                  : (isPhone ? Colors.orange.shade900 : const Color(0xFF005BAC)),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isCallCompletion
                                  ? 'CALL COMPLETION'
                                  : (isPhone ? 'PHONE CHANGE' : 'PREFERENCE CHANGE'),
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: isCallCompletion
                                    ? Colors.purple.shade900
                                    : (isPhone ? Colors.orange.shade900 : const Color(0xFF005BAC)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: status == 'approved'
                              ? Colors.green.withValues(alpha: 0.15)
                              : status == 'rejected'
                                  ? Colors.red.withValues(alpha: 0.15)
                                  : Colors.amber.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          status.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: status == 'approved'
                                ? Colors.green
                                : status == 'rejected'
                                    ? Colors.red
                                    : Colors.amber.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // Customer Name
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: const Color(0xFF005BAC).withValues(alpha: 0.1),
                        foregroundColor: const Color(0xFF005BAC),
                        child: const Icon(Icons.person, size: 18),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          customerName,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // Change Details Container
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[850] : Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isCallCompletion) ...[
                          Row(
                            children: [
                              Text(
                                'Requested Action: ',
                                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                              ),
                              const Text(
                                'Mark Call as Completed',
                                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.purple),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text(
                                'Call Duration: ',
                                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                              ),
                              Text(
                                '${completionDuration > 0 ? '$completionDuration sec' : newVal}',
                                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.purple),
                              ),
                            ],
                          ),
                          if (completionRemarks.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Remarks: ',
                                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                ),
                                Expanded(
                                  child: Text(
                                    completionRemarks,
                                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (completionNote.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'User Note: ',
                                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                ),
                                Expanded(
                                  child: Text(
                                    completionNote,
                                    style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ] else ...[
                          Row(
                            children: [
                              Text(
                                isPhone ? 'Current Phone: ' : 'Current Preference: ',
                                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                              ),
                              Text(
                                currentVal,
                                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text(
                                isPhone ? 'New Phone: ' : 'New Preference: ',
                                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                              ),
                              Text(
                                newVal,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: isPhone ? Colors.green.shade700 : const Color(0xFF005BAC),
                                ),
                              ),
                            ],
                          ),
                          if (reason.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Reason: ',
                                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                ),
                                Expanded(
                                  child: Text(
                                    reason,
                                    style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Request Meta
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'By: $requestedBy',
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      ),
                      Text(
                        createdAtStr,
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      ),
                    ],
                  ),

                  if (reviewedBy.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Reviewed by: $reviewedBy ${adminNotes.isNotEmpty ? "($adminNotes)" : ""}',
                      style: TextStyle(fontSize: 11, color: Colors.grey[700], fontStyle: FontStyle.italic),
                    ),
                  ],

                  // Action Buttons (for pending status)
                  if (status == 'pending') ...[
                    const Divider(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => _rejectRequest(req),
                          icon: const Icon(Icons.close_rounded, size: 16),
                          label: const Text('Reject'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: () => _approveRequest(req),
                          icon: const Icon(Icons.check_rounded, size: 16),
                          label: const Text('Approve'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
