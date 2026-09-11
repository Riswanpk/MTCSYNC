import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../dme_constants.dart';
import '../dme_config.dart';
import '../User/dme_assignment_service.dart';

const Color _primaryBlue = Color(0xFF005BAC);
const Color _whatsappGreen = Color(0xFF25D366);
const Color _pendingOrange = Color(0xFFFF9800);

class DmeAdminReminderDetailPage extends StatefulWidget {
  final Map<String, dynamic> reminder;
  final VoidCallback? onUpdated;

  const DmeAdminReminderDetailPage({
    super.key,
    required this.reminder,
    this.onUpdated,
  });

  @override
  State<DmeAdminReminderDetailPage> createState() => _DmeAdminReminderDetailPageState();
}

class _DmeAdminReminderDetailPageState extends State<DmeAdminReminderDetailPage>
    with SingleTickerProviderStateMixin {
  late Map<String, dynamic> _reminder;
  late TabController _tabController;

  bool _isLoadingCustomer = true;
  bool _isLoadingHistory = true;
  bool _isSavingEdit = false;

  Map<String, dynamic> _customer = {};
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _salesHistory = [];
  List<Map<String, dynamic>> _reminderHistory = [];
  List<Map<String, dynamic>> _dmeUsers = [];
  Map<String, dynamic>? _whatsappProof;

  @override
  void initState() {
    super.initState();
    _reminder = Map<String, dynamic>.from(widget.reminder);
    _tabController = TabController(length: 3, vsync: this);
    _loadAllDetails();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _formatDate(dynamic date) {
    if (date == null) return 'N/A';
    if (date is DateTime) return DateFormat('dd-MM-yyyy').format(date);
    final str = date.toString().trim();
    if (str.isEmpty) return 'N/A';
    final parsed = DateTime.tryParse(str);
    if (parsed != null) return DateFormat('dd-MM-yyyy').format(parsed);
    return str;
  }

  Future<void> _loadAllDetails() async {
    await Future.wait([
      _loadCustomerAndBranches(),
      _loadSalesAndCallHistory(),
      _loadDmeUsers(),
      _loadWhatsAppProof(),
    ]);
  }

  Future<void> _loadWhatsAppProof() async {
    final client = await DmeConfig.getClient();
    final reminderId = _reminder['id'];
    if (client == null || reminderId == null) return;

    try {
      final res = await client
          .from('dme_whatsapp_proofs')
          .select('id, image_url, remarks, created_at, uploaded_by')
          .eq('reminder_id', reminderId)
          .maybeSingle();

      if (mounted && res != null) {
        setState(() {
          _whatsappProof = Map<String, dynamic>.from(res);
        });
      }
    } catch (e) {
      debugPrint('Error loading WhatsApp proof: $e');
    }
  }

  Future<void> _loadCustomerAndBranches() async {
    final client = await DmeConfig.getClient();
    final customerId = _reminder['customer_id'];
    if (client == null || customerId == null) {
      if (mounted) setState(() => _isLoadingCustomer = false);
      return;
    }

    try {
      final custRes = await client
          .from('dme_customers')
          .select('id, name, phone, address, salesman, creation_date, created_at, primary_branch')
          .eq('id', customerId)
          .maybeSingle();

      final branchRes = await client
          .from('dme_customer_branches')
          .select('branch_id, category_id, customer_type_id, created_at')
          .eq('customer_id', customerId);

      if (mounted) {
        setState(() {
          if (custRes != null) {
            _customer = Map<String, dynamic>.from(custRes);
          } else {
            _customer = {
              'name': _reminder['customer_name'] ?? 'Unknown Customer',
              'phone': _reminder['customer_phone'] ?? 'N/A',
              'address': _reminder['customer_address'] ?? '',
              'salesman': _reminder['customer_salesman'] ?? '',
            };
          }
          _branches = List<Map<String, dynamic>>.from(branchRes as List);
          _isLoadingCustomer = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading customer details: $e');
      if (mounted) setState(() => _isLoadingCustomer = false);
    }
  }

  Future<void> _loadSalesAndCallHistory() async {
    final client = await DmeConfig.getClient();
    final customerId = _reminder['customer_id'];
    if (client == null || customerId == null) {
      if (mounted) setState(() => _isLoadingHistory = false);
      return;
    }

    try {
      // 1. Sales history
      final salesRes = await client
          .from('dme_sales')
          .select('id, date, purchased_branch, salesman, category_id, customer_type_id, dme_sales_detail(products)')
          .eq('customer_id', customerId)
          .order('date', ascending: false)
          .limit(20);

      // 2. Reminder / Call history
      dynamic remindersRes;
      try {
        remindersRes = await client
            .from('dme_reminders')
            .select(
                'id, reminder_date, last_purchase_branch, status, remarks, call_duration, called_timestamp, called_by, assigned_to, updated_at')
            .eq('customer_id', customerId)
            .order('reminder_date', ascending: false)
            .limit(30);
      } catch (_) {
        remindersRes = await client
            .from('dme_reminders')
            .select(
                'id, reminder_date, last_purchase_branch, status, remarks, call_duration, called_timestamp, assigned_to, updated_at')
            .eq('customer_id', customerId)
            .order('reminder_date', ascending: false)
            .limit(30);
      }

      if (mounted) {
        setState(() {
          _salesHistory = List<Map<String, dynamic>>.from(salesRes as List);
          _reminderHistory = List<Map<String, dynamic>>.from(remindersRes as List);
          _isLoadingHistory = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading history: $e');
      if (mounted) setState(() => _isLoadingHistory = false);
    }
  }

  Future<void> _loadDmeUsers() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('role', whereIn: ['dme_user', 'dme_admin'])
          .get();

      List<Map<String, dynamic>> users = [];
      for (var doc in snap.docs) {
        final data = doc.data();
        final email = data['email']?.toString() ?? '';
        final username =
            data['username']?.toString() ?? data['name']?.toString() ?? (email.isNotEmpty ? email.split('@').first : 'User');

        users.add({
          'uid': doc.id,
          'email': email,
          'username': username,
        });
      }
      users.sort((a, b) => (a['username'] as String).toLowerCase().compareTo((b['username'] as String).toLowerCase()));

      if (mounted) {
        setState(() => _dmeUsers = users);
      }
    } catch (e) {
      debugPrint('Error loading users in reminder detail: $e');
    }
  }

  String _getUserDisplayName(String? uid) {
    if (uid == null || uid.isEmpty) return 'Unassigned';
    final user = _dmeUsers.firstWhere((u) => u['uid'] == uid, orElse: () => {});
    if (user.isNotEmpty) {
      return '${user['username']} (${user['email']})';
    }
    return uid;
  }

  // --- EDIT REMINDER MODAL BOTTOM SHEET ---
  void _openEditReminderSheet() {
    final remarksController = TextEditingController(text: _reminder['remarks'] ?? '');
    String status = (_reminder['status'] ?? 'pending').toString();
    DateTime reminderDate = DateTime.tryParse(_reminder['reminder_date']?.toString() ?? '') ?? DateTime.now();
    String? assignedTo = _reminder['assigned_to']?.toString();
    int? duration = int.tryParse(_reminder['call_duration']?.toString() ?? '');
    final durationController = TextEditingController(text: duration != null ? duration.toString() : '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (sheetContext, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 18,
                right: 18,
                top: 20,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: _primaryBlue.withValues(alpha: 0.15),
                          child: const Icon(Icons.edit_note_rounded, color: _primaryBlue, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _customer['name'] ?? _reminder['customer_name'] ?? 'Edit Reminder',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'Reminder ID: #${_reminder['id']} • Branch: ${_reminder['branch_name'] ?? DmeConstants.getBranchName(_reminder['last_purchase_branch'])}',
                                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(sheetContext),
                        ),
                      ],
                    ),
                    const Divider(height: 24),

                    // 1. Status Selection
                    const Text('Call Status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: status,
                          items: const [
                            DropdownMenuItem(value: 'pending', child: Text('Pending (Awaiting Call)')),
                            DropdownMenuItem(value: 'completed', child: Text('Completed (Call Verified)')),
                            DropdownMenuItem(value: 'rescheduled', child: Text('Rescheduled (Schedule for another day)')),
                            DropdownMenuItem(value: 'not_interested', child: Text('Not Interested / Declined')),
                            DropdownMenuItem(value: 'invalid_number', child: Text('Invalid / Wrong Number')),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setModalState(() {
                                status = val;
                                if (val == 'rescheduled') {
                                  reminderDate = DmeAssignmentService.getNextWorkingDate();
                                }
                              });
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // 2. Reminder Date
                    Text(
                      status == 'rescheduled' ? 'Rescheduled Date (Working Day)' : 'Scheduled Reminder Date',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: reminderDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (picked != null) {
                          setModalState(() => reminderDate = picked);
                        }
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: status == 'rescheduled' ? _primaryBlue : Colors.grey.shade300,
                            width: status == 'rescheduled' ? 1.5 : 1.0,
                          ),
                          borderRadius: BorderRadius.circular(10),
                          color: status == 'rescheduled' ? _primaryBlue.withValues(alpha: 0.05) : null,
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_today_rounded,
                                size: 18, color: status == 'rescheduled' ? _primaryBlue : Colors.grey[700]),
                            const SizedBox(width: 10),
                            Text(
                              DateFormat('dd-MM-yyyy (EEEE)').format(reminderDate),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: status == 'rescheduled' ? FontWeight.bold : FontWeight.normal,
                                color: status == 'rescheduled' ? _primaryBlue : null,
                              ),
                            ),
                            const Spacer(),
                            const Icon(Icons.arrow_drop_down, color: Colors.grey),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // 3. Assign / Reassign to User
                    const Text('Assign To DME User', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String?>(
                          isExpanded: true,
                          value: assignedTo,
                          hint: const Text('Unassigned (System will assign on reminder date)'),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('Unassigned', style: TextStyle(color: Colors.grey)),
                            ),
                            ..._dmeUsers.map(
                              (u) => DropdownMenuItem<String?>(
                                value: u['uid'],
                                child: Text('${u['username']} (${u['email']})', style: const TextStyle(fontSize: 13)),
                              ),
                            ),
                          ],
                          onChanged: (val) {
                            setModalState(() => assignedTo = val);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // 4. Call Duration (if completed)
                    if (status == 'completed') ...[
                      const Text('Call Duration (seconds)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: durationController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          hintText: 'e.g. 45',
                          prefixIcon: const Icon(Icons.timer_rounded, size: 18),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],

                    // 5. Remarks Field
                    const Text('Remarks / Discussion Notes', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: remarksController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Enter customer feedback, inquiry notes, or reasons for reschedule...',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.all(12),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Action buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(sheetContext),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            onPressed: _isSavingEdit
                                ? null
                                : () async {
                                    setModalState(() => _isSavingEdit = true);
                                    await _saveReminderChanges(
                                      reminderId: _reminder['id'] as int,
                                      newStatus: status,
                                      newRemarks: remarksController.text.trim(),
                                      newReminderDate: reminderDate,
                                      newAssignedTo: assignedTo,
                                      callDuration: int.tryParse(durationController.text.trim()),
                                    );
                                    setModalState(() => _isSavingEdit = false);
                                    if (mounted) Navigator.pop(sheetContext);
                                  },
                            icon: _isSavingEdit
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                  )
                                : const Icon(Icons.save_rounded),
                            label: Text(_isSavingEdit ? 'Saving...' : 'Save Changes'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _primaryBlue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _saveReminderChanges({
    required int reminderId,
    required String newStatus,
    required String newRemarks,
    required DateTime newReminderDate,
    required String? newAssignedTo,
    int? callDuration,
  }) async {
    final client = await DmeConfig.getClient();
    if (client == null) return;

    setState(() => _isSavingEdit = true);

    try {
      final formattedDate = DateFormat('yyyy-MM-dd').format(newReminderDate);
      final userEmail = FirebaseAuth.instance.currentUser?.email;

      final Map<String, dynamic> updatePayload = {
        'status': newStatus == 'rescheduled' ? 'pending' : newStatus,
        'remarks': newRemarks,
        'reminder_date': formattedDate,
        'assigned_to': newAssignedTo,
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (callDuration != null) {
        updatePayload['call_duration'] = callDuration;
      }

      if (newStatus == 'completed') {
        updatePayload['called_timestamp'] = DateTime.now().toIso8601String();
        if (userEmail != null && userEmail.isNotEmpty) {
          updatePayload['called_by'] = userEmail;
        }
      } else if (newStatus == 'rescheduled') {
        updatePayload['assigned_date'] = null;
        updatePayload['is_overdue_leftover'] = false;
        if (newRemarks.isEmpty) {
          updatePayload['remarks'] = 'Rescheduled by Admin for $formattedDate';
        }
      }

      try {
        await client.from('dme_reminders').update(updatePayload).eq('id', reminderId);
      } catch (err) {
        if (err.toString().contains('called_by')) {
          updatePayload.remove('called_by');
          await client.from('dme_reminders').update(updatePayload).eq('id', reminderId);
        } else {
          rethrow;
        }
      }

      setState(() {
        _reminder['status'] = updatePayload['status'];
        _reminder['remarks'] = updatePayload['remarks'];
        _reminder['reminder_date'] = updatePayload['reminder_date'];
        _reminder['assigned_to'] = updatePayload['assigned_to'];
        if (callDuration != null) _reminder['call_duration'] = callDuration;
        if (updatePayload.containsKey('called_by')) _reminder['called_by'] = updatePayload['called_by'];
        _isSavingEdit = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reminder updated successfully!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }

      widget.onUpdated?.call();
      _loadSalesAndCallHistory();
    } catch (e) {
      debugPrint('Error saving reminder changes: $e');
      if (mounted) {
        setState(() => _isSavingEdit = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating reminder: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final customerName = _customer['name'] ?? _reminder['customer_name'] ?? 'Unnamed Customer';

    return Scaffold(
      appBar: AppBar(
        title: Text(customerName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: _primaryBlue,
        foregroundColor: Colors.white,
        actions: [
          // Top Right Edit Button
          TextButton.icon(
            onPressed: _openEditReminderSheet,
            icon: const Icon(Icons.edit_rounded, color: Colors.white, size: 18),
            label: const Text(
              'Edit',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: _isLoadingCustomer
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(14.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Current Reminder Details Card ("first show the current reminder details")
                  _buildCurrentReminderCard(isDark),
                  const SizedBox(height: 14),

                  // 2. Customer Profile Card
                  _buildCustomerProfileCard(isDark),
                  const SizedBox(height: 16),

                  // 3. Section Title for History
                  Row(
                    children: [
                      const Icon(Icons.history_rounded, size: 20, color: _primaryBlue),
                      const SizedBox(width: 8),
                      Text(
                        'Customer History & Records',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // 4. Tab Bar for History Categories
                  Container(
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[850] : Colors.grey[200],
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      indicator: BoxDecoration(
                        color: _primaryBlue,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      labelColor: Colors.white,
                      unselectedLabelColor: isDark ? Colors.white70 : Colors.black87,
                      labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      tabs: const [
                        Tab(text: 'Call History'),
                        Tab(text: 'Sales History'),
                        Tab(text: 'Branches'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 5. Tab View Content (Fixed Height Scrollable)
                  SizedBox(
                    height: 400,
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildCallHistoryTab(isDark),
                        _buildSalesHistoryTab(isDark),
                        _buildBranchesTab(isDark),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  // --- 1. CUSTOMER PROFILE CARD ---
  Widget _buildCustomerProfileCard(bool isDark) {
    final customerName = _customer['name'] ?? _reminder['customer_name'] ?? 'Unnamed Customer';
    final customerPhone = _customer['phone'] ?? _reminder['customer_phone'] ?? 'N/A';
    final customerAddress = _customer['address'] ?? _reminder['customer_address'] ?? '';
    final salesman = _customer['salesman'] ?? _reminder['customer_salesman'] ?? '';
    final primaryBranchId = _customer['primary_branch'] as int?;
    final primaryBranchName =
        primaryBranchId != null ? DmeConstants.getBranchName(primaryBranchId) : (_reminder['branch_name'] ?? 'N/A');
    final creationDateStr = _customer['creation_date'] ?? _customer['created_at'];

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: _primaryBlue.withValues(alpha: 0.12),
                  child: const Icon(Icons.person_rounded, color: _primaryBlue, size: 26),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        customerName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Phone: $customerPhone',
                        style: TextStyle(fontSize: 13, color: Colors.grey[800], fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _primaryBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    primaryBranchName,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _primaryBlue),
                  ),
                ),
              ],
            ),
            const Divider(height: 18),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                if (salesman.isNotEmpty) ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.badge_outlined, size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text('Salesman: $salesman', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                    ],
                  ),
                ],
                if (creationDateStr != null) ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.calendar_today_outlined, size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text('Created: ${_formatDate(creationDateStr)}',
                          style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                    ],
                  ),
                ],
                if (customerAddress.isNotEmpty) ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.location_on_outlined, size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text('Address: $customerAddress', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                    ],
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  // --- 2. CURRENT REMINDER DETAILS CARD ---
  Widget _buildCurrentReminderCard(bool isDark) {
    final status = (_reminder['status'] ?? 'pending').toString().toLowerCase();
    final isCompleted = status == 'completed';
    final isWhatsApp = _reminder['is_whatsapp'] == true || (_reminder['remarks'] ?? '').toString().startsWith('[WhatsApp]');
    final isLeftover = _reminder['is_overdue_leftover'] == true;

    Color statusColor;
    String statusLabel;
    IconData statusIcon;

    if (isCompleted) {
      if (isWhatsApp) {
        statusColor = _whatsappGreen;
        statusLabel = 'Completed (WhatsApp)';
        statusIcon = Icons.chat_bubble_rounded;
      } else {
        statusColor = const Color(0xFF0E7A38);
        statusLabel = 'Completed (Call)';
        statusIcon = Icons.phone_callback_rounded;
      }
    } else {
      statusColor = _pendingOrange;
      statusLabel = isLeftover ? 'Pending (Overdue Leftover)' : 'Pending';
      statusIcon = isLeftover ? Icons.warning_amber_rounded : Icons.pending_actions_rounded;
    }

    final reminderDateStr = _reminder['reminder_date']?.toString();
    final lastPurchaseDate = _reminder['last_purchase_date'];
    final branchId = int.tryParse(_reminder['last_purchase_branch']?.toString() ?? '');
    final branchName = DmeConstants.getBranchName(branchId);
    final assignedToUid = _reminder['assigned_to']?.toString();
    final calledBy = _reminder['called_by']?.toString();
    final callDuration = _reminder['call_duration'];
    final calledTimestamp = _reminder['called_timestamp'];
    final remarks = (_reminder['remarks'] ?? '').toString().trim();
    final proofUrl = _whatsappProof?['image_url']?.toString() ?? _reminder['proof_url']?.toString();

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: statusColor.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Card Title & Status Badge
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.notifications_active_rounded, color: statusColor, size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      'Current Reminder Details',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: statusColor.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 13, color: statusColor),
                      const SizedBox(width: 4),
                      Text(
                        statusLabel,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: statusColor),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 20),

            // Key-Value Grid
            _buildDetailRow('Scheduled Due Date', _formatDate(reminderDateStr), icon: Icons.calendar_today_rounded),
            const SizedBox(height: 8),
            _buildDetailRow('Purchase Branch', branchName, icon: Icons.store_rounded),
            if (lastPurchaseDate != null) ...[
              const SizedBox(height: 8),
              _buildDetailRow('Last Purchase Date', _formatDate(lastPurchaseDate), icon: Icons.shopping_bag_outlined),
            ],
            const SizedBox(height: 8),
            _buildDetailRow('Assigned DME User', _getUserDisplayName(assignedToUid), icon: Icons.person_pin_circle_rounded),

            if (calledBy != null && calledBy.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildDetailRow('Called By User', calledBy, icon: Icons.verified_user_rounded),
            ],

            if (callDuration != null) ...[
              const SizedBox(height: 8),
              _buildDetailRow('Call Duration', '${callDuration}s', icon: Icons.timer_rounded),
            ],

            if (calledTimestamp != null) ...[
              const SizedBox(height: 8),
              _buildDetailRow('Action Timestamp', _formatDate(calledTimestamp), icon: Icons.access_time_rounded),
            ],

            // Remarks
            const SizedBox(height: 12),
            const Text('Discussion Remarks:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[800] : Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Text(
                remarks.isNotEmpty ? remarks : 'No remarks recorded yet.',
                style: TextStyle(
                  fontSize: 13,
                  fontStyle: remarks.isNotEmpty ? FontStyle.normal : FontStyle.italic,
                  color: remarks.isNotEmpty ? null : Colors.grey,
                ),
              ),
            ),

            // WhatsApp Proof Image Preview (if present)
            if (proofUrl != null && proofUrl.isNotEmpty) ...[
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.chat_bubble_rounded, size: 14, color: _whatsappGreen),
                      SizedBox(width: 6),
                      Text('WhatsApp Proof Attachment', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    ],
                  ),
                  if (_whatsappProof?['uploaded_by'] != null)
                    Text(
                      'Uploaded by: ${_whatsappProof!['uploaded_by']}',
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (_) => Dialog(
                      backgroundColor: Colors.transparent,
                      insetPadding: const EdgeInsets.all(12),
                      child: Stack(
                        alignment: Alignment.topRight,
                        children: [
                          InteractiveViewer(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: proofUrl.startsWith('data:image/')
                                  ? Image.memory(
                                      base64Decode(proofUrl.split(',').last),
                                      fit: BoxFit.contain,
                                    )
                                  : Image.network(
                                      proofUrl,
                                      fit: BoxFit.contain,
                                    ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white, size: 28),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),
                  );
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    height: 160,
                    width: double.infinity,
                    color: isDark ? Colors.grey[850] : Colors.grey[200],
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        proofUrl.startsWith('data:image/')
                            ? Image.memory(
                                base64Decode(proofUrl.split(',').last),
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Center(child: Text('Could not load image')),
                              )
                            : Image.network(
                                proofUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Center(child: Text('Could not load image')),
                              ),
                        Positioned(
                          right: 8,
                          bottom: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.fullscreen, color: Colors.white, size: 14),
                                SizedBox(width: 4),
                                Text('Tap to zoom', style: TextStyle(color: Colors.white, fontSize: 11)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {IconData? icon}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 15, color: Colors.grey[600]),
          const SizedBox(width: 8),
        ],
        SizedBox(
          width: 140,
          child: Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  // --- 3. CALL HISTORY TAB ---
  Widget _buildCallHistoryTab(bool isDark) {
    if (_isLoadingHistory) return const Center(child: CircularProgressIndicator());
    if (_reminderHistory.isEmpty) {
      return Center(
        child: Text('No previous reminder records found.', style: TextStyle(color: Colors.grey[600])),
      );
    }

    return ListView.separated(
      itemCount: _reminderHistory.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final r = _reminderHistory[index];
        final isCurrent = r['id'] == _reminder['id'];
        final status = (r['status'] ?? '').toString();
        final isCompleted = status == 'completed';
        final rDate = _formatDate(r['reminder_date']);
        final remarks = (r['remarks'] ?? '').toString().trim();
        final bName = DmeConstants.getBranchName(int.tryParse(r['last_purchase_branch']?.toString() ?? ''));
        final calledBy = r['called_by']?.toString();
        final dur = r['call_duration'];

        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isCurrent
                ? _primaryBlue.withValues(alpha: 0.06)
                : (isDark ? Colors.grey[850] : Colors.white),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isCurrent ? _primaryBlue : Colors.grey.shade300,
              width: isCurrent ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(rDate, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      if (isCurrent) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _primaryBlue,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('CURRENT', style: TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isCompleted ? Colors.green.withValues(alpha: 0.15) : _pendingOrange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      status.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isCompleted ? Colors.green[800] : _pendingOrange,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Branch: $bName${calledBy != null ? ' • Called by: $calledBy' : ''}${dur != null ? ' (${dur}s)' : ''}',
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
              if (remarks.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  remarks,
                  style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // --- 4. SALES HISTORY TAB ---
  Widget _buildSalesHistoryTab(bool isDark) {
    if (_isLoadingHistory) return const Center(child: CircularProgressIndicator());
    if (_salesHistory.isEmpty) {
      return Center(
        child: Text('No previous purchases recorded.', style: TextStyle(color: Colors.grey[600])),
      );
    }

    return ListView.separated(
      itemCount: _salesHistory.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final sale = _salesHistory[index];
        final dateStr = _formatDate(sale['date']);
        final bName = DmeConstants.getBranchName(int.tryParse(sale['purchased_branch']?.toString() ?? ''));
        final catName = DmeConstants.getCategoryName(int.tryParse(sale['category_id']?.toString() ?? ''));
        final sm = sale['salesman']?.toString() ?? '';
        final detail = sale['dme_sales_detail'] as Map<String, dynamic>?;
        final products = detail?['products']?.toString() ?? '';

        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isDark ? Colors.grey[850] : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(dateStr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  Text(bName, style: const TextStyle(fontSize: 12, color: _primaryBlue, fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 4),
              Text('Category: $catName${sm.isNotEmpty ? ' • Salesman: $sm' : ''}',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600])),
              if (products.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('Items: $products', style: const TextStyle(fontSize: 12)),
              ],
            ],
          ),
        );
      },
    );
  }

  // --- 5. BRANCHES TAB ---
  Widget _buildBranchesTab(bool isDark) {
    if (_branches.isEmpty) {
      return Center(
        child: Text('No branch junction records.', style: TextStyle(color: Colors.grey[600])),
      );
    }

    return ListView.separated(
      itemCount: _branches.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final b = _branches[index];
        final bId = int.tryParse(b['branch_id']?.toString() ?? '');
        final bName = DmeConstants.getBranchName(bId);
        final catName = DmeConstants.getCategoryName(int.tryParse(b['category_id']?.toString() ?? ''));
        final typeName = DmeConstants.getCustomerTypeName(int.tryParse(b['customer_type_id']?.toString() ?? ''));
        final createdStr = _formatDate(b['created_at']);

        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isDark ? Colors.grey[850] : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(bName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _primaryBlue)),
                  Text('Joined: $createdStr', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                ],
              ),
              const SizedBox(height: 4),
              Text('Category: $catName • Type: $typeName', style: TextStyle(fontSize: 12, color: Colors.grey[800])),
            ],
          ),
        );
      },
    );
  }
}
