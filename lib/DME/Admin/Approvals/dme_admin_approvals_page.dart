import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../Misc/dme_config.dart';
import '../../Misc/dme_constants.dart';
import '../../User/dme_user_stats_service.dart';
import '../../User/Requests/dme_notification_service.dart';

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
  final Map<String, String> _userNames = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadUserNames();
    _loadRequests();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadUserNames() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('users').get();
      for (var doc in snap.docs) {
        final data = doc.data();
        final uid = doc.id;
        final email = data['email']?.toString() ?? '';
        final username = data['username']?.toString() ??
            data['name']?.toString() ??
            (email.isNotEmpty ? email.split('@').first : 'User');
        _userNames[uid] = username;
        if (email.isNotEmpty) {
          _userNames[email] = username;
          _userNames[email.toLowerCase()] = username;
        }
      }
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Notice loading user names for admin approvals: $e');
    }
  }

  String _getUserDisplayName(dynamic userIdentifier) {
    if (userIdentifier == null) return '';
    final raw = userIdentifier.toString().trim();
    if (raw.isEmpty) return '';
    if (_userNames.containsKey(raw)) return _userNames[raw]!;
    if (_userNames.containsKey(raw.toLowerCase())) return _userNames[raw.toLowerCase()]!;
    if (raw.contains('@')) {
      final prefix = raw.split('@').first;
      if (prefix.isNotEmpty) {
        return prefix[0].toUpperCase() + prefix.substring(1);
      }
      return prefix;
    }
    return raw;
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

      final requests = List<Map<String, dynamic>>.from(res as List);

      // Collect customer IDs and reminder IDs to fetch branch and salesman
      final customerIds = <int>{};
      final reminderIds = <int>{};

      for (final req in requests) {
        final cid = int.tryParse(req['customer_id']?.toString() ?? '');
        if (cid != null) customerIds.add(cid);
        final rid = int.tryParse(req['reminder_id']?.toString() ?? '');
        if (rid != null) reminderIds.add(rid);
      }

      final customerMap = <int, Map<String, dynamic>>{};
      if (customerIds.isNotEmpty) {
        try {
          final custRes = await client
              .from(DmeConstants.tableCustomers)
              .select('id, salesman, primary_branch')
              .filter('id', 'in', customerIds.toList());
          for (final c in (custRes as List)) {
            final cid = int.tryParse(c['id']?.toString() ?? '');
            if (cid != null) {
              customerMap[cid] = Map<String, dynamic>.from(c as Map);
            }
          }
        } catch (ce) {
          debugPrint('Notice loading customer info for approvals: $ce');
        }
      }

      final reminderMap = <int, Map<String, dynamic>>{};
      if (reminderIds.isNotEmpty) {
        try {
          final remRes = await client
              .from(DmeConstants.tableReminders)
              .select('id, last_purchase_branch')
              .filter('id', 'in', reminderIds.toList());
          for (final r in (remRes as List)) {
            final rid = int.tryParse(r['id']?.toString() ?? '');
            if (rid != null) {
              reminderMap[rid] = Map<String, dynamic>.from(r as Map);
            }
          }
        } catch (re) {
          debugPrint('Notice loading reminder info for approvals: $re');
        }
      }

      // Attach branch and salesman to each request map
      for (final req in requests) {
        final cid = int.tryParse(req['customer_id']?.toString() ?? '');
        final rid = int.tryParse(req['reminder_id']?.toString() ?? '');

        final cust = cid != null ? customerMap[cid] : null;
        final rem = rid != null ? reminderMap[rid] : null;

        // Salesman priority: request's salesman/payload -> customer's salesman
        String? salesman = req['salesman']?.toString();
        if (salesman == null || salesman.trim().isEmpty) {
          salesman = cust?['salesman']?.toString();
        }

        // Branch priority: request's branch_name/branch_id -> reminder's last_purchase_branch -> customer's primary_branch
        int? branchId = int.tryParse(req['branch_id']?.toString() ?? '');
        branchId ??= int.tryParse(rem?['last_purchase_branch']?.toString() ?? '');
        branchId ??= int.tryParse(cust?['primary_branch']?.toString() ?? '');

        String? branchName = req['branch_name']?.toString();
        if (branchName == null || branchName.trim().isEmpty) {
          if (branchId != null) {
            branchName = DmeConstants.getBranchName(branchId);
          }
        }

        req['_computed_salesman'] = (salesman != null && salesman.trim().isNotEmpty) ? salesman.trim() : null;
        req['_computed_branch'] = (branchName != null && branchName.trim().isNotEmpty && branchName != 'N/A' && branchName != 'Unknown')
            ? branchName.trim()
            : (branchId != null ? DmeConstants.getBranchName(branchId) : null);
      }

      if (mounted) {
        setState(() {
          _allRequests = requests;
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
    final now = DateTime.now();
    final todayStr = DateFormat('yyyy-MM-dd').format(now);

    return _allRequests.where((req) {
      final reqStatus = (req['status'] ?? 'pending').toString().toLowerCase();
      if (reqStatus != status.toLowerCase()) return false;

      // For 'approved' tab, only show requests approved today
      if (status.toLowerCase() == 'approved') {
        final approvedAtStr = req['updated_at']?.toString() ?? req['created_at']?.toString() ?? '';
        final approvedDate = DateTime.tryParse(approvedAtStr)?.toLocal();
        if (approvedDate == null) return false;
        final approvedDayStr = DateFormat('yyyy-MM-dd').format(approvedDate);
        if (approvedDayStr != todayStr) return false;
      }

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
        final requestedByName = _getUserDisplayName(req['requested_by']).toLowerCase();
        final reason = (req['reason'] ?? '').toString().toLowerCase();
        final salesman = (req['_computed_salesman'] ?? '').toString().toLowerCase();
        final branch = (req['_computed_branch'] ?? '').toString().toLowerCase();

        return name.contains(query) ||
            phone.contains(query) ||
            newPhone.contains(query) ||
            requestedBy.contains(query) ||
            requestedByName.contains(query) ||
            reason.contains(query) ||
            salesman.contains(query) ||
            branch.contains(query);
      }

      return true;
    }).toList();
  }

  Future<void> _approveRequest(Map<String, dynamic> request) async {
    final customerName = request['customer_name'] ?? 'Customer';
    final requestType = request['request_type'] ?? '';
    final isPhoneChange = requestType == 'phone_number_change';
    final isCallCompletion = requestType == 'call_completion';
    final isEditCustomerDetails = requestType == 'edit_customer_details';
    final newValue = (request['new_value'] ?? '').toString().trim();
    final customerId = int.tryParse(request['customer_id']?.toString() ?? '');
    final reminderId = int.tryParse(request['reminder_id']?.toString() ?? '');

    if (customerId == null || (!isPhoneChange && newValue.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid request data.'), backgroundColor: Colors.red),
      );
      return;
    }

    int callDuration = 0;
    String completionRemarks = '';
    String requestingUserUid = '';
    String requestingUserEmail = (request['requested_by'] ?? '').toString();
    DateTime? submissionDateTime;
    String? calledTimestampIso;

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
          calledTimestampIso = data['called_timestamp']?.toString();
        } catch (_) {}
      } else {
        callDuration = int.tryParse(newValue) ?? 0;
        completionRemarks = request['reason']?.toString() ?? '';
      }

      // Take request submission time from request['created_at'] if not already in JSON
      calledTimestampIso ??= request['created_at']?.toString();
      if (calledTimestampIso != null && calledTimestampIso.isNotEmpty) {
        submissionDateTime = DateTime.tryParse(calledTimestampIso);
      }
      submissionDateTime ??= DateTime.now();
      calledTimestampIso = submissionDateTime.toIso8601String();
    }

    String? phoneToUpdate;
    Map<String, dynamic> newDetails = {};
    Map<String, dynamic> oldDetails = {};

    if (isPhoneChange) {
      // Prompt Admin to enter the new phone number
      final phoneController = TextEditingController(
        text: newValue.isNotEmpty && newValue != 'N/A' ? newValue : '',
      );
      final phoneFormKey = GlobalKey<FormState>();

      final bool? proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Row(
            children: [
              Icon(Icons.phone_iphone_rounded, color: Colors.green),
              SizedBox(width: 8),
              Text('Enter & Approve Phone', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Form(
            key: phoneFormKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Customer: $customerName', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 4),
                Text('Current Phone: ${(request['customer_phone'] ?? 'N/A')}', style: TextStyle(color: Colors.grey[700], fontSize: 13)),
                if ((request['reason'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Reason for request:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange.shade900)),
                        const SizedBox(height: 2),
                        Text(request['reason'].toString(), style: const TextStyle(fontSize: 12.5)),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                TextFormField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'New Verified Phone Number *',
                    hintText: 'e.g. 9876543210 or +971501234567',
                    prefixIcon: const Icon(Icons.phone_rounded),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) return 'Please enter the new phone number';
                    final clean = val.replaceAll(RegExp(r'[\s\-\(\)]'), '');
                    if (clean.length < 6) return 'Enter at least 6 digits';
                    final currClean = (request['customer_phone'] ?? '').toString().replaceAll(RegExp(r'[\s\-\(\)]'), '');
                    if (clean == currClean) return 'New number cannot match the current number';
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                if (phoneFormKey.currentState!.validate()) {
                  Navigator.pop(ctx, true);
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
              child: const Text('Approve & Save Phone'),
            ),
          ],
        ),
      );

      if (proceed != true) return;
      phoneToUpdate = phoneController.text.trim();
    } else if (isEditCustomerDetails) {
      try {
        newDetails = jsonDecode(newValue);
      } catch (_) {}
      try {
        oldDetails = jsonDecode((request['current_value'] ?? '').toString());
      } catch (_) {}

      final newCustName = newDetails['name']?.toString().trim();
      final newCatName = newDetails['category_name']?.toString();
      final newTypeName = newDetails['customer_type_name']?.toString();
      final changedFields = (newDetails['changed_fields'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];

      final bool? confirmEdit = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Row(
            children: [
              Icon(Icons.manage_accounts_rounded, color: Color(0xFF007A87)),
              SizedBox(width: 8),
              Text('Approve Customer Edit', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Approve customer detail updates for $customerName?', style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF007A87).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF007A87).withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (changedFields.contains('name') && newCustName != null) ...[
                      Text('Name:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey[700])),
                      Text('${oldDetails['name'] ?? 'N/A'}  ➔  $newCustName', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF007A87))),
                      const SizedBox(height: 6),
                    ],
                    if (changedFields.contains('customer_type') && newTypeName != null) ...[
                      Text('Customer Type:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey[700])),
                      Text('${oldDetails['customer_type_name'] ?? 'N/A'}  ➔  $newTypeName', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF007A87))),
                      const SizedBox(height: 6),
                    ],
                    if (changedFields.contains('category') && newCatName != null) ...[
                      Text('Category:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey[700])),
                      Text('${oldDetails['category_name'] ?? 'N/A'}  ➔  $newCatName', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF007A87))),
                    ],
                  ],
                ),
              ),
              if ((request['reason'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 10),
                Text('Reason: ${request['reason']}', style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF007A87), foregroundColor: Colors.white),
              child: const Text('Confirm & Apply'),
            ),
          ],
        ),
      );

      if (confirmEdit != true) return;
    } else {
      // Call completion or Preference change dialog
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
                        'Call Timestamp: ${DateFormat('dd MMM yyyy, hh:mm a').format(submissionDateTime ?? DateTime.now())} (Request Submission Time)',
                        style: TextStyle(fontSize: 12, color: Colors.grey[800], fontWeight: FontWeight.w600),
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
                        'New Preference:',
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
    }

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
            'called_timestamp': calledTimestampIso,
            'called_by': requestingUserEmail,
            'remarks': completionRemarks,
            'updated_at': nowIso,
          };
          await client.from('dme_reminders').update(payload).eq('id', reminderId);
        }

        // Increment daily call count for the requesting user on the day the call was requested/made
        try {
          final statDate = DateFormat('yyyy-MM-dd').format(submissionDateTime ?? now);
          final uid = requestingUserUid.isNotEmpty ? requestingUserUid : requestingUserEmail;
          await DmeUserStatsService.incrementCallCount(
            userUid: uid,
            userEmail: requestingUserEmail,
            statDate: statDate,
          );
        } catch (statErr) {
          debugPrint('Notice updating user daily stats: $statErr');
        }

        // Record the completed call in dme_call_logs table with the request submission timestamp
        try {
          await client.from('dme_call_logs').insert({
            if (reminderId != null) 'reminder_id': reminderId,
            'customer_id': customerId,
            'caller_uid': requestingUserUid.isNotEmpty ? requestingUserUid : requestingUserEmail,
            'caller_email': requestingUserEmail,
            'attempt_timestamp': calledTimestampIso,
            'ring_duration': callDuration,
            'call_type': 'outgoing',
            'is_answered': true,
            'call_day': DateFormat('yyyy-MM-dd').format(submissionDateTime ?? now),
          });
        } catch (callLogErr) {
          debugPrint('Notice logging call attempt to dme_call_logs: $callLogErr');
        }
      } else if (isPhoneChange) {
        await client.from(DmeConstants.tableCustomers).update({
          'phone': phoneToUpdate,
          'updated_at': nowIso,
        }).eq('id', customerId);
      } else if (isEditCustomerDetails) {
        final newCustName = newDetails['name']?.toString().trim();
        final newCatId = int.tryParse(newDetails['category_id']?.toString() ?? '');
        final newTypeId = int.tryParse(newDetails['customer_type_id']?.toString() ?? '');
        final changedFields = (newDetails['changed_fields'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];

        // 1. Update customer name if changed
        if (changedFields.contains('name') && newCustName != null && newCustName.isNotEmpty) {
          await client.from(DmeConstants.tableCustomers).update({
            'name': newCustName,
            'updated_at': nowIso,
          }).eq('id', customerId);
        }

        // 2. Update customer branches (customer_type_id, category_id)
        final branchUpdates = <String, dynamic>{};
        if (changedFields.contains('customer_type') && newTypeId != null) {
          branchUpdates['customer_type_id'] = newTypeId;
        }
        if (changedFields.contains('category') && newCatId != null) {
          branchUpdates['category_id'] = newCatId;
        }

        if (branchUpdates.isNotEmpty) {
          final existing = await client
              .from(DmeConstants.tableCustomerBranches)
              .select('id')
              .eq('customer_id', customerId);

          if ((existing as List).isNotEmpty) {
            await client
                .from(DmeConstants.tableCustomerBranches)
                .update(branchUpdates)
                .eq('customer_id', customerId);
          } else {
            await client.from(DmeConstants.tableCustomerBranches).insert({
              'customer_id': customerId,
              'branch_id': 1,
              ...branchUpdates,
            });
          }
        }
      } else {
        await client.from(DmeConstants.tableCustomers).update({
          'preference': newValue,
          'updated_at': nowIso,
        }).eq('id', customerId);
      }

      // 2. Update change request record
      final reqUpdates = <String, dynamic>{
        'status': 'approved',
        'reviewed_by': adminEmail,
        'updated_at': nowIso,
      };
      if (isPhoneChange && phoneToUpdate != null) {
        reqUpdates['new_value'] = phoneToUpdate;
      }
      await client.from(DmeConstants.tableChangeRequests).update(reqUpdates).eq('id', request['id']);

      // Notify the requesting user that their request has been approved
      unawaited(DmeNotificationService.instance.notifyUserOnRequestDecision(
        requestedByUid: requestingUserUid.isNotEmpty ? requestingUserUid : null,
        requestedByEmail: requestingUserEmail.isNotEmpty ? requestingUserEmail : null,
        customerName: customerName,
        requestType: requestType,
        isApproved: true,
        requestId: request['id']?.toString(),
      ));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isCallCompletion
                  ? 'Call status approved & marked as completed with $callDuration sec!'
                  : (isPhoneChange
                      ? 'Phone number updated to $phoneToUpdate! Reminder unlocked.'
                      : (isEditCustomerDetails
                          ? 'Customer details updated successfully!'
                          : 'Preference updated to $newValue successfully!')),
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

      final rejectionReason = noteController.text.trim();
      await client.from(DmeConstants.tableChangeRequests).update({
        'status': 'rejected',
        'reviewed_by': adminEmail,
        'admin_notes': rejectionReason,
        'updated_at': now,
      }).eq('id', request['id']);

      // Notify the requesting user that their request has been rejected
      final customerName = (request['customer_name'] ?? 'Customer').toString();
      final requestType = (request['request_type'] ?? '').toString();
      final requestedByEmail = (request['requested_by'] ?? '').toString();
      String? requestedByUid;
      final newVal = (request['new_value'] ?? '').toString();
      if (newVal.startsWith('{')) {
        try {
          final parsed = jsonDecode(newVal);
          if (parsed is Map && parsed['user_uid'] != null && parsed['user_uid'].toString().isNotEmpty) {
            requestedByUid = parsed['user_uid'].toString();
          }
        } catch (_) {}
      }

      unawaited(DmeNotificationService.instance.notifyUserOnRequestDecision(
        requestedByUid: requestedByUid,
        requestedByEmail: requestedByEmail.isNotEmpty ? requestedByEmail : null,
        customerName: customerName,
        requestType: requestType,
        isApproved: false,
        rejectionReason: rejectionReason.isNotEmpty ? rejectionReason : null,
        requestId: request['id']?.toString(),
      ));

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
                        avatar: const Icon(Icons.manage_accounts_rounded, size: 16),
                        label: const Text('Customer Details'),
                        selected: _selectedTypeFilter == 'edit_customer_details',
                        selectedColor: const Color(0xFF007A87).withValues(alpha: 0.25),
                        onSelected: (val) {
                          if (val) setState(() => _selectedTypeFilter = 'edit_customer_details');
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
          final isEditDetails = type == 'edit_customer_details';
          final status = (req['status'] ?? 'pending').toString().toLowerCase();
          final customerName = req['customer_name'] ?? 'Unnamed Customer';
          final currentVal = req['current_value'] ?? 'N/A';
          final newVal = req['new_value'] ?? 'N/A';
          final reason = req['reason'] ?? '';
          final requestedBy = req['requested_by'] ?? 'User';
          final createdAtStr = _formatDateTime(req['created_at']);
          final reviewedBy = req['reviewed_by'] ?? '';
          final adminNotes = req['admin_notes'] ?? '';
          final branchName = req['_computed_branch']?.toString() ?? '';
          final salesmanName = req['_computed_salesman']?.toString() ?? '';

          int completionDuration = 0;
          String completionRemarks = '';
          String completionNote = '';
          String? completionCalledTs;
          if (isCallCompletion) {
            if (newVal.startsWith('{')) {
              try {
                final d = jsonDecode(newVal);
                completionDuration = int.tryParse(d['duration']?.toString() ?? '') ?? 0;
                completionRemarks = d['remarks']?.toString() ?? '';
                completionNote = d['reason']?.toString() ?? '';
                completionCalledTs = d['called_timestamp']?.toString();
              } catch (_) {}
            } else {
              completionDuration = int.tryParse(newVal) ?? 0;
            }
            completionCalledTs ??= req['created_at']?.toString();
          }

          Map<String, dynamic> oldDetails = {};
          Map<String, dynamic> newDetails = {};
          if (isEditDetails) {
            try {
              oldDetails = jsonDecode(currentVal.toString());
            } catch (_) {}
            try {
              newDetails = jsonDecode(newVal.toString());
            } catch (_) {}
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
                              : (isPhone
                                  ? Colors.orange.withValues(alpha: 0.15)
                                  : (isEditDetails
                                      ? const Color(0xFF007A87).withValues(alpha: 0.15)
                                      : const Color(0xFF005BAC).withValues(alpha: 0.15))),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isCallCompletion
                                  ? Icons.check_circle_outline_rounded
                                  : (isPhone
                                      ? Icons.phone_iphone_rounded
                                      : (isEditDetails
                                          ? Icons.manage_accounts_rounded
                                          : Icons.swap_horiz_rounded)),
                              size: 13,
                              color: isCallCompletion
                                  ? Colors.purple.shade900
                                  : (isPhone
                                      ? Colors.orange.shade900
                                      : (isEditDetails
                                          ? const Color(0xFF005B66)
                                          : const Color(0xFF005BAC))),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isCallCompletion
                                  ? 'CALL COMPLETION'
                                  : (isPhone
                                      ? 'PHONE CHANGE'
                                      : (isEditDetails
                                          ? 'CUSTOMER DETAILS'
                                          : 'PREFERENCE CHANGE')),
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: isCallCompletion
                                    ? Colors.purple.shade900
                                    : (isPhone
                                        ? Colors.orange.shade900
                                        : (isEditDetails
                                            ? const Color(0xFF005B66)
                                            : const Color(0xFF005BAC))),
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

                  // Customer Name, Branch Badge & Salesman
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: const Color(0xFF005BAC).withValues(alpha: 0.1),
                        foregroundColor: const Color(0xFF005BAC),
                        child: const Icon(Icons.person, size: 18),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Text(
                                    customerName,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5),
                                  ),
                                ),
                                if (branchName.isNotEmpty) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF005BAC).withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: const Color(0xFF005BAC).withValues(alpha: 0.25), width: 0.8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.store_rounded, size: 11, color: Color(0xFF005BAC)),
                                        const SizedBox(width: 3),
                                        Text(
                                          branchName,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF005BAC),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            if (salesmanName.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Icon(Icons.badge_outlined, size: 13, color: Colors.grey[600]),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Salesman: ',
                                    style: TextStyle(fontSize: 11.5, color: Colors.grey[600]),
                                  ),
                                  Text(
                                    salesmanName,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: isDark ? Colors.grey[300] : Colors.grey[800],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
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
                          if (completionCalledTs != null) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Text(
                                  'Called Time: ',
                                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                ),
                                Text(
                                  _formatDateTime(completionCalledTs),
                                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '(Submission Time)',
                                  style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey[600]),
                                ),
                              ],
                            ),
                          ],
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
                        ] else if (isEditDetails) ...[
                          // Customer Details Changes
                          if (newDetails['name'] != null && newDetails['name'] != oldDetails['name']) ...[
                            Row(
                              children: [
                                Text('Name: ', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                                Text('${oldDetails['name'] ?? 'N/A'}  ➔  ', style: const TextStyle(fontSize: 12.5)),
                                Text(
                                  '${newDetails['name']}',
                                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF007A87)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                          ],
                          if (newDetails['customer_type_name'] != null &&
                              newDetails['customer_type_name'] != oldDetails['customer_type_name']) ...[
                            Row(
                              children: [
                                Text('Customer Type: ', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                                Text('${oldDetails['customer_type_name'] ?? 'N/A'}  ➔  ', style: const TextStyle(fontSize: 12.5)),
                                Text(
                                  '${newDetails['customer_type_name']}',
                                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF007A87)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                          ],
                          if (newDetails['category_name'] != null &&
                              newDetails['category_name'] != oldDetails['category_name']) ...[
                            Row(
                              children: [
                                Text('Category: ', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                                Text('${oldDetails['category_name'] ?? 'N/A'}  ➔  ', style: const TextStyle(fontSize: 12.5)),
                                Text(
                                  '${newDetails['category_name']}',
                                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF007A87)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                          ],
                          if (reason.isNotEmpty) ...[
                            const SizedBox(height: 4),
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
                              if (isPhone && (newVal.isEmpty || newVal == 'N/A' || newVal == 'Pending Admin Entry'))
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'Admin will enter new number upon approval',
                                    style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.orange),
                                  ),
                                )
                              else
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
                        'By: ${_getUserDisplayName(requestedBy)}',
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
                      'Reviewed by: ${_getUserDisplayName(reviewedBy)} ${adminNotes.isNotEmpty ? "($adminNotes)" : ""}',
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
