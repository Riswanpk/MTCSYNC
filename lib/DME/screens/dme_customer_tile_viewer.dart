import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:call_log/call_log.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:getwidget/getwidget.dart';
import '../models/dme_reminder.dart';
import '../models/dme_user.dart';
import '../models/dme_sale.dart';
import '../services/dme_supabase_service.dart';
import '../widgets/complaint_popup_dialog.dart';

class DmeCustomerTileViewer extends StatefulWidget {
  final DmeReminder reminder;
  final DmeUser dmeUser;

  const DmeCustomerTileViewer({
    super.key,
    required this.reminder,
    required this.dmeUser,
  });

  @override
  State<DmeCustomerTileViewer> createState() => _DmeCustomerTileViewerState();
}

class _DmeCustomerTileViewerState extends State<DmeCustomerTileViewer>
    with WidgetsBindingObserver {
  final _svc = DmeSupabaseService.instance;
  final _remarksCtrl = TextEditingController();

  bool _called = false;
  bool _saving = false;
  bool _isPreexistinglyCompleted = false;
  bool _loadingSales = true;
  String? _pendingCallPhone;
  DateTime? _callStartTime;
  List<DmeSale> _sales = [];

  // Assign Lead state
  String? _selectedBranch;
  String? _selectedUserId;
  String? _selectedUserName;
  List<String> _branches = [];
  List<Map<String, dynamic>> _branchUsers = [];
  bool _loadingUsers = false;
  bool _assigningLead = false;

  // colours
  static const _blue = Color(0xFF005BAC);
  static const _green = Color(0xFF4CAF50);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Load purchase history
    _loadSalesData();
    
    // If reminder is already completed, load existing remarks and mark as called
    if (widget.reminder.status == 'completed') {
      _called = true;
      _isPreexistinglyCompleted = true;
      if (widget.reminder.notes != null && widget.reminder.notes!.isNotEmpty) {
        _remarksCtrl.text = widget.reminder.notes!;
      }
    } else {
      // For pending reminders, check for calls
      _restorePendingCallState();
      _checkForAnyRecentCall();
    }
  }

  Future<void> _loadSalesData() async {
    try {
      final sales = await _svc.getSalesForCustomer(widget.reminder.customerId);
      if (mounted) {
        setState(() {
          _sales = sales;
          _loadingSales = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading sales: $e');
      if (mounted) {
        setState(() => _loadingSales = false);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _remarksCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_pendingCallPhone != null) {
        _checkIfCallWasMade().then((_) {
          if (!_called && _pendingCallPhone != null && mounted) {
            Future.delayed(const Duration(seconds: 3), () {
              if (mounted && !_called) _checkIfCallWasMade();
            });
          }
        });
      } else if (!_called) {
        _checkForAnyRecentCall();
      }
    }
  }

  // ── SharedPreferences helpers ─────────────────────────────────

  String get _prefKey =>
      'dme_tv_${widget.reminder.customerId}_${widget.reminder.id}';

  Future<void> _savePendingCallState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('${_prefKey}_phone', _pendingCallPhone ?? '');
    await prefs.setInt(
        '${_prefKey}_time', _callStartTime?.millisecondsSinceEpoch ?? 0);
  }

  Future<void> _clearPendingCallState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('${_prefKey}_phone');
    await prefs.remove('${_prefKey}_time');
    _pendingCallPhone = null;
    _callStartTime = null;
  }

  Future<void> _restorePendingCallState() async {
    if (_called) return;
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('${_prefKey}_phone');
    final time = prefs.getInt('${_prefKey}_time');
    if (phone != null && phone.isNotEmpty && time != null && time > 0) {
      _pendingCallPhone = phone;
      _callStartTime = DateTime.fromMillisecondsSinceEpoch(time);
      _checkIfCallWasMade();
    }
  }

  // ── Call helpers ──────────────────────────────────────────────

  bool _numberMatches(String logNumber, String contact) {
    final clean = contact.replaceAll(RegExp(r'\D'), '');
    final logClean = logNumber.replaceAll(RegExp(r'\D'), '');
    if (clean.isEmpty || logClean.isEmpty) return false;
    return logClean.endsWith(clean) || clean.endsWith(logClean);
  }

  Future<void> _makeCall() async {
    final phone = widget.reminder.customerPhone;
    if (phone == null || phone.isEmpty) return;

    final status = await Permission.phone.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Phone permission denied')),
        );
      }
      return;
    }

    _pendingCallPhone = phone;
    _callStartTime = DateTime.now();
    await _savePendingCallState();

    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _checkIfCallWasMade() async {
    if (_callStartTime == null || _pendingCallPhone == null) return;
    try {
      final entries = await CallLog.query(
        dateFrom: _callStartTime!.millisecondsSinceEpoch,
        dateTo: DateTime.now().millisecondsSinceEpoch,
      );

      for (final entry in entries) {
        if ((entry.duration ?? 0) > 15 &&
            _numberMatches(entry.number ?? '', _pendingCallPhone!)) {
          if (mounted) setState(() {
            _called = true;
          });
          await _clearPendingCallState();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('✅ Call detected! Please add remarks.'),
              backgroundColor: Colors.green,
            ));
          }
          return;
        }
      }
    } catch (e) {
      debugPrint('checkIfCallWasMade error: $e');
    }
  }

  /// On page open, scan today's log: requires an outgoing call + any >15s call
  /// after it (mirrors SalesCustomerTileViewer logic).
  Future<void> _checkForAnyRecentCall() async {
    if (_called) return;
    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final entries = await CallLog.query(
        dateFrom: startOfDay.millisecondsSinceEpoch,
        dateTo: now.millisecondsSinceEpoch,
      );
      final phone = widget.reminder.customerPhone;
      if (phone == null || phone.isEmpty) return;

      // Step 1: latest outgoing call to this customer today
      int latestOutgoingTime = -1;
      int? latestDuration;
      for (final entry in entries) {
        if (entry.callType != CallType.outgoing) continue;
        final num = entry.number?.replaceAll(RegExp(r'\D'), '') ?? '';
        if (num.isEmpty) continue;
        if (_numberMatches(num, phone)) {
          if (entry.timestamp != null && entry.timestamp! > latestOutgoingTime) {
            latestOutgoingTime = entry.timestamp!;
            latestDuration = entry.duration;
          }
        }
      }
      if (latestOutgoingTime == -1) return;

      // Step 2: any call (in or out) > 15s after that outgoing call
      bool hasLongCall = entries.any((entry) {
        if (entry.timestamp == null || entry.timestamp! <= latestOutgoingTime) {
          return false;
        }
        final num = entry.number?.replaceAll(RegExp(r'\D'), '') ?? '';
        return _numberMatches(num, phone) && (entry.duration ?? 0) > 15;
      });

      // Also accept if the outgoing call itself was >15s
      if (!hasLongCall && (latestDuration ?? 0) > 15) hasLongCall = true;

      if (hasLongCall && mounted) {
        setState(() => _called = true);
        await _clearPendingCallState();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('✅ Call detected! Please add remarks.'),
            backgroundColor: Colors.green,
          ));
        }
      }
    } catch (e) {
      debugPrint('checkForAnyRecentCall error: $e');
    }
  }

  Future<void> _reloadCallStatus() async {
    if (_called) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Call already detected'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Scanning call log…')),
      );
    }
    
    await _checkCallLogAndUpdate();
    
    if (!_called && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No new calls detected'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  /// Check call log for matching calls and update reminder status if found
  Future<void> _checkCallLogAndUpdate() async {
    try {
      final status = await Permission.phone.request();
      if (!status.isGranted) return;

      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final phone = widget.reminder.customerPhone;
      
      if (phone == null || phone.isEmpty) return;

      final entries = await CallLog.query(
        dateFrom: startOfDay.millisecondsSinceEpoch,
        dateTo: now.millisecondsSinceEpoch,
      );

      // Check for calls matching the customer
      for (final entry in entries) {
        if (entry.duration != null &&
            entry.duration! > 15 &&
            _numberMatches(entry.number ?? '', phone)) {
          // Call found - update UI and show remarks section
          if (mounted) {
            setState(() => _called = true);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ Call detected! Please add remarks.'),
                backgroundColor: Colors.green,
              ),
            );
          }
          return;
        }
      }
    } catch (e) {
      debugPrint('checkCallLogAndUpdate error: $e');
    }
  }

  // ── Supabase ──────────────────────────────────────────────────

  Future<void> _saveRemarks() async {
    final remarks = _remarksCtrl.text.trim();
    if (remarks.isEmpty || !_called) return;
    setState(() => _saving = true);
    try {
      if (widget.reminder.id != null) {
        await _svc.updateReminderStatus(
          widget.reminder.id!,
          'completed',
          notes: remarks,
        );
      }
      if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Remarks saved & reminder marked complete ✅'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ── Assign Lead ────────────────────────────────────────────────

  Future<void> _loadBranches() async {
    try {
      final branches = await _svc.getBranches();
      if (mounted) {
        setState(() {
          _branches = branches.map((b) => b['name'] as String).toList();
          _branches.sort();
        });
      }
    } catch (e) {
      debugPrint('Error loading branches: $e');
    }
  }

  Future<void> _loadUsersForBranch(String branch) async {
    setState(() {
      _loadingUsers = true;
      _selectedUserId = null;
      _selectedUserName = null;
      _branchUsers = [];
    });

    try {
      final db = FirebaseFirestore.instance;
      // Fetch from users collection with branch and valid roles
      final snapshot = await db
          .collection('users')
          .where('branch', isEqualTo: branch)
          .where('role', whereIn: ['manager', 'asst_manager', 'sales', 'dme_user'])
          .get();

      final users = <Map<String, dynamic>>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        users.add({
          'id': data['uid'] ?? doc.id,
          'username': data['username'] ?? data['email'] ?? 'Unknown',
          'role': data['role'] ?? '',
        });
      }

      users.sort((a, b) =>
          (a['username'] as String).compareTo(b['username'] as String));

      if (mounted) {
        setState(() {
          _branchUsers = users;
          _loadingUsers = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingUsers = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading users: $e')),
        );
      }
      debugPrint('Error loading users: $e');
    }
  }

  Future<void> _assignLead() async {
    if (_selectedBranch == null || _selectedUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a branch and user')),
      );
      return;
    }

    setState(() => _assigningLead = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('User not logged in')));
        return;
      }

      final r = widget.reminder;
      
      // Create lead in Firestore
      await FirebaseFirestore.instance.collection('dme_leads').add({
        'date': DateTime.now(),
        'name': r.customerName ?? 'Unknown',
        'address': r.customerAddress ?? '',
        'phone': r.customerPhone ?? '',
        'status': 'In Progress',
        'branch': _selectedBranch,
        'created_by': user.uid,
        'assigned_to': _selectedUserId,
        'assigned_to_name': _selectedUserName,
        'source': 'dme_reminder',
        'reminder_id': r.id,
        'customer_id': r.customerId,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Lead assigned successfully ✅'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context); // Close assignment dialog
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
      debugPrint('Error assigning lead: $e');
    } finally {
      if (mounted) setState(() => _assigningLead = false);
    }
  }

  void _showAssignLeadDialog() {
    _selectedBranch = null;
    _selectedUserId = null;
    _selectedUserName = null;
    _branchUsers = [];
    _loadingUsers = false;
    _loadBranches();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Assign Lead'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Pre-filled customer info
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.blue.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Customer Details',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        _infoRow(
                            'Name', widget.reminder.customerName ?? 'Unknown'),
                        _infoRow('Phone', widget.reminder.customerPhone ?? ''),
                        _infoRow(
                            'Address', widget.reminder.customerAddress ?? ''),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Branch selector
                  Text('Select Branch *',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _selectedBranch,
                    items: _branches
                        .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => _selectedBranch = val);
                        _loadUsersForBranch(val);
                      }
                    },
                    decoration: InputDecoration(
                      hintText: 'Choose branch',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // User selector
                  Text('Select User *',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  if (_selectedBranch == null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Select a branch first',
                        style: TextStyle(
                          color: Colors.orange[700],
                          fontSize: 12,
                        ),
                      ),
                    )
                  else if (_loadingUsers)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else
                    DropdownButtonFormField<String>(
                      value: _selectedUserId,
                      items: _branchUsers
                          .map((u) => DropdownMenuItem(
                                value: u['id'] as String,
                                child: Text(
                                    '${u['username']} (${u['role']})'),
                              ))
                          .toList(),
                      onChanged: (val) {
                        if (val == null) return;
                        final user = _branchUsers
                            .firstWhere((u) => u['id'] == val);
                        setDialogState(() {
                          _selectedUserId = val;
                          _selectedUserName =
                              user['username'] as String;
                        });
                      },
                      decoration: InputDecoration(
                        hintText: 'Select user',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding:
                            const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                onPressed: _assigningLead
                    ? null
                    : () {
                        setDialogState(() => _assigningLead = true);
                        _assignLead();
                      },
                icon: _assigningLead
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white),
                        ),
                      )
                    : const Icon(Icons.check),
                label: const Text('Assign Lead'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF005BAC),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey[400],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text('$label: ',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12,
              )),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontSize: 12),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  // ── UI helpers ────────────────────────────────────────────────

  Future<bool> _onWillPop() async {
    if (_called && _remarksCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add remarks before leaving.'),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }
    return true;
  }

  Widget _detailRow(IconData icon, String label, String? value) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: _blue.withValues(alpha: 0.7)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                      letterSpacing: 0.4,
                    )),
                const SizedBox(height: 2),
                Text(value,
                    style: TextStyle(
                      fontSize: 15,
                      color: isDark ? Colors.white : Colors.black87,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.reminder;
    final primaryColor = _called ? _green : _blue;
    final dateFmt = DateFormat('dd MMM yyyy');
    final remarksEntered = _remarksCtrl.text.trim().isNotEmpty;

    return PopScope(
      canPop: !(_called && _remarksCtrl.text.trim().isEmpty),
      onPopInvoked: (didPop) {
        if (!didPop) _onWillPop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Customer Details',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          backgroundColor: primaryColor,
          iconTheme: const IconThemeData(color: Colors.white),
          actions: [
            IconButton(
              icon: const Icon(Icons.warning_rounded),
              tooltip: 'File Complaint',
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => ComplaintPopupDialog(
                    reminder: widget.reminder,
                    dmeUser: widget.dmeUser,
                    onComplaintSubmitted: () {
                      // Complaint submitted callback
                    },
                  ),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Reload Call Status',
              onPressed: _reloadCallStatus,
            ),
          ],
        ),
        body: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header gradient ──────────────────────────────────
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [primaryColor, primaryColor.withValues(alpha: 0.8)],
                  ),
                ),
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _called ? Icons.check_circle : Icons.person,
                        size: 48,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      r.customerName ?? 'Customer #${r.customerId}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    if (r.customerPhone != null && r.customerPhone!.isNotEmpty)
                      _called
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 28, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.phone, color: primaryColor),
                                  const SizedBox(width: 8),
                                  Text('Call Completed',
                                      style: TextStyle(
                                        color: primaryColor,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      )),
                                ],
                              ),
                            )
                          : GestureDetector(
                              onTap: _makeCall,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 28, vertical: 10),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.25),
                                  border: Border.all(
                                      color: Colors.white, width: 1.5),
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.phone, color: Colors.white),
                                    SizedBox(width: 8),
                                    Text('Make Call',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15)),
                                  ],
                                ),
                              ),
                            ),
                  ],
                ),
              ),

              // ── Status card ──────────────────────────────────────
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _called
                      ? _green.withValues(alpha: 0.08)
                      : Colors.orange.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _called ? _green : Colors.orange,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _called ? Icons.check_circle : Icons.pending,
                      color: _called ? _green : Colors.orange,
                      size: 26,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _called ? 'Call Completed' : 'Call Pending',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: _called ? _green : Colors.orange[700],
                            ),
                          ),
                          Text(
                            _called
                                ? 'Add remarks and save below'
                                : 'Tap the button above to call',
                            style: TextStyle(
                              fontSize: 13,
                              color: _called ? _green : Colors.orange[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ── Purchase History ─────────────────────────────────
              const SizedBox(height: 20),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text('Purchase History',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white
                          : Colors.black87,
                    )),
              ),
              const SizedBox(height: 8),
              if (_loadingSales)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: const CircularProgressIndicator(),
                )
              else if (_sales.isEmpty)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.grey[800]
                        : Colors.grey[100],
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text('No purchases recorded',
                      textAlign: TextAlign.center),
                )
              else
                ..._sales.map((s) => Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.grey[850]
                            : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Theme(
                        data: Theme.of(context).copyWith(
                          dividerColor: Colors.transparent,
                        ),
                        child: ExpansionTile(
                          leading: Icon(Icons.receipt_long,
                              color: const Color(0xFF005BAC),
                              size: 20),
                          title: Text(
                            dateFmt.format(s.date),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                          subtitle: Text(
                            s.salesman ?? 'Sale',
                            style: const TextStyle(fontSize: 12),
                          ),
                          children: [
                            if (s.items.isEmpty)
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text('No items',
                                    style: TextStyle(
                                        color: Theme.of(context).brightness ==
                                                Brightness.dark
                                            ? Colors.grey[400]
                                            : Colors.grey[600])),
                              )
                            else
                              ...s.items.map((item) => ListTile(
                                    dense: true,
                                    contentPadding:
                                        const EdgeInsets.symmetric(horizontal: 20),
                                    leading: Icon(Icons.inventory_2,
                                        size: 16,
                                        color: Colors.grey[600]),
                                    title: Text(item.productName,
                                        style: const TextStyle(fontSize: 14)),
                                    trailing: Text('Qty: ${item.quantity}',
                                        style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600)),
                                  )),
                          ],
                        ),
                      ),
                    )),

              // ── Customer details ─────────────────────────────────
              const SizedBox(height: 20),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text('Customer Details',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white
                          : Colors.black87,
                    )),
              ),
              _detailRow(Icons.phone, 'Phone', r.customerPhone),
              _detailRow(Icons.location_on, 'Address', r.customerAddress),
              _detailRow(
                Icons.calendar_today,
                'Reminder Date',
                dateFmt.format(r.reminderDate),
              ),
              _detailRow(
                Icons.shopping_cart,
                'Last Purchase',
                dateFmt.format(r.lastPurchaseDate),
              ),

              // ── Remarks section (only when call is detected) ────────────────────────────────
              if (_called) ...[
                const SizedBox(height: 16),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text('Call Remarks',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white
                            : Colors.black87,
                      )),
                ),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.grey[850]
                        : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _remarksCtrl,
                    maxLines: 4,
                    readOnly: _isPreexistinglyCompleted,
                    onChanged: (_) {
                      setState(() {}); // Trigger rebuild to enable/disable save button
                    },
                    decoration: InputDecoration(
                      hintText: _isPreexistinglyCompleted
                          ? 'Remarks (saved)'
                          : 'Enter call remarks…',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.all(14),
                      filled: _isPreexistinglyCompleted,
                      fillColor: _isPreexistinglyCompleted
                          ? (Theme.of(context).brightness == Brightness.dark
                              ? Colors.grey[900]
                              : Colors.grey[100])
                          : null,
                    ),
                  ),
                ),

                // ── Save button ──────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: ElevatedButton.icon(
                    onPressed: _isPreexistinglyCompleted
                        ? null
                        : ((remarksEntered && !_saving) ? _saveRemarks : null),
                    icon: _isPreexistinglyCompleted
                        ? const Icon(Icons.check_circle)
                        : (_saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.save)),
                    label: Text(
                      _isPreexistinglyCompleted ? 'Already Saved' : 'Save Remarks',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey[400],
                      disabledForegroundColor: Colors.white70,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),

                // ── Assign Lead button ───────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  child: ElevatedButton.icon(
                    onPressed: _showAssignLeadDialog,
                    icon: const Icon(Icons.person_add),
                    label: const Text(
                      'Assign Lead',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF008BD6),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
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
