import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../dme_constants.dart';
import '../dme_config.dart';
import 'dme_assignment_service.dart';
import 'dme_reminder_detail_page.dart';
import 'dme_call_scanner_service.dart';

class DmeRemarksPendingPage extends StatefulWidget {
  const DmeRemarksPendingPage({super.key});

  @override
  State<DmeRemarksPendingPage> createState() => _DmeRemarksPendingPageState();
}

class _DmeRemarksPendingPageState extends State<DmeRemarksPendingPage> {
  List<Map<String, dynamic>> _pendingReminders = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchPendingRemarks();
  }

  Future<void> _fetchPendingRemarks() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (!mounted) return;
        setState(() {
          _error = 'Not logged in';
          _loading = false;
        });
        return;
      }

      // 1. Fetch user assigned branches
      List<int> userBranches = [];
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (doc.exists && doc.data()?['assigned_branches'] is List) {
          userBranches = (doc.data()!['assigned_branches'] as List)
              .map((e) => int.tryParse(e.toString()) ?? 0)
              .where((e) => e > 0)
              .toList();
        }
      } catch (_) {}

      // 2. Fetch today's assigned reminders for current user
      final assigned = await DmeAssignmentService.fetchUserAssignedReminders(
        userBranches: userBranches,
        currentUserId: user.uid,
      );

      // 3. Optional quick scan of call logs to catch any calls made just now
      if (assigned.isNotEmpty && user.email != null) {
        await DmeCallScannerService.scanTodayCallLog(assigned, userEmail: user.email!);
      }

      // 4. Filter for reminders where call was made/detected, but remarks are still empty
      final List<Map<String, dynamic>> pending = [];
      for (var r in assigned) {
        final remarks = (r['remarks'] ?? '').toString().trim();
        final status = (r['status'] ?? '').toString().toLowerCase();
        final duration = int.tryParse(r['call_duration']?.toString() ?? '') ?? 0;
        final calledTs = r['called_timestamp']?.toString();

        final bool hasCall = duration > 0 || (calledTs != null && calledTs.isNotEmpty);
        final bool isCompleted = (status == 'completed');

        if (hasCall && remarks.isEmpty && !isCompleted) {
          pending.add(r);
        }
      }

      // Also check if any called reminders from Supabase for today are missing remarks
      final client = await DmeConfig.getClient();
      if (client != null) {
        final todayStr = DmeAssignmentService.formatDate(DateTime.now());
        try {
          final res = await client
              .from('dme_reminders')
              .select(
                  'id, customer_id, reminder_date, last_purchase_date, last_purchase_branch, status, remarks, updated_at, call_duration, called_timestamp, called_by, assigned_to, assigned_date, is_overdue_leftover, dme_customers(id, name, phone, address, salesman)')
              .eq('status', 'called')
              .eq('assigned_to', user.uid)
              .eq('assigned_date', todayStr);

          for (var item in (res as List)) {
            final rem = Map<String, dynamic>.from(item);
            final remRemarks = (rem['remarks'] ?? '').toString().trim();
            final remId = rem['id'];
            if (remRemarks.isEmpty && !pending.any((p) => p['id'] == remId)) {
              final cust = rem['dme_customers'] as Map<String, dynamic>?;
              final bId = int.tryParse(rem['last_purchase_branch']?.toString() ?? '');
              rem['customer_name'] = cust?['name'] ?? 'Unknown Customer';
              rem['customer_phone'] = cust?['phone'] ?? '';
              rem['customer_address'] = cust?['address'] ?? '';
              rem['customer_salesman'] = cust?['salesman'] ?? '';
              rem['branch_id'] = bId;
              rem['branch_name'] = DmeConstants.getBranchName(bId);
              pending.add(rem);
            }
          }
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _pendingReminders = pending;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Error fetching pending remarks: $e');
      if (!mounted) return;
      setState(() {
        _error = 'Error loading pending remarks: $e';
        _loading = false;
      });
    }
  }

  void _openReminderDetail(Map<String, dynamic> reminder) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DmeReminderDetailPage(
          reminder: reminder,
          onUpdated: () => _fetchPendingRemarks(),
        ),
      ),
    );

    if (result == true) {
      _fetchPendingRemarks();
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color primaryBlue = Color(0xFF005BAC);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bgColor = isDark ? const Color(0xFF181A20) : const Color(0xFFE3F2FD);
    final cardColor = isDark ? const Color(0xFF23262B) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text(
          'DME Remarks Pending',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: primaryBlue,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Pending List',
            onPressed: _fetchPendingRemarks,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: TextStyle(color: textColor)))
              : _pendingReminders.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            size: 64,
                            color: Colors.green.shade400,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No pending remarks!',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: textColor,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'All detected calls have remarks added.',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Row(
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                color: Colors.orange.shade700,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Pending Remarks: ${_pendingReminders.length}',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.orange.shade300 : Colors.orange.shade800,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            itemCount: _pendingReminders.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, i) {
                              final reminder = _pendingReminders[i];
                              final customerName = (reminder['customer_name'] ?? 'Unknown Customer').toString().toUpperCase();
                              final phone = reminder['customer_phone']?.toString() ?? '';
                              final branch = reminder['branch_name'] ?? DmeConstants.getBranchName(reminder['branch_id']);
                              final duration = reminder['call_duration'];
                              final calledTs = reminder['called_timestamp'];

                              String callSubtitle = '';
                              if (duration != null) {
                                callSubtitle = 'Duration: ${duration}s';
                              }
                              if (calledTs != null) {
                                final dt = DateTime.tryParse(calledTs.toString());
                                if (dt != null) {
                                  final timeStr = DateFormat('hh:mm a').format(dt);
                                  callSubtitle = callSubtitle.isNotEmpty ? '$callSubtitle • $timeStr' : timeStr;
                                }
                              }

                              return Card(
                                color: cardColor,
                                elevation: 2,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(
                                    color: Colors.orange.withValues(alpha: 0.5),
                                    width: 1,
                                  ),
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  leading: CircleAvatar(
                                    backgroundColor: Colors.orange.withValues(alpha: 0.2),
                                    child: const Icon(Icons.edit_note, color: Colors.orange),
                                  ),
                                  title: Text(
                                    customerName,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: textColor,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 2),
                                      Text(
                                        '$phone • $branch',
                                        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                                      ),
                                      if (callSubtitle.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            const Icon(Icons.phone_callback_rounded, size: 13, color: Colors.green),
                                            const SizedBox(width: 4),
                                            Text(
                                              callSubtitle,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.green,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                                  onTap: () => _openReminderDetail(reminder),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
    );
  }
}
