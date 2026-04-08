import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:call_log/call_log.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/dme_supabase_service.dart';
import '../models/dme_user.dart';
import '../models/dme_reminder.dart';
import 'dme_customer_tile_viewer.dart';

const Color _primaryBlue = Color(0xFF005BAC);

class DmeRemindersAndCallsPage extends StatefulWidget {
  final DmeUser dmeUser;
  const DmeRemindersAndCallsPage({super.key, required this.dmeUser});

  @override
  State<DmeRemindersAndCallsPage> createState() =>
      _DmeRemindersAndCallsPageState();
}

class _DmeRemindersAndCallsPageState extends State<DmeRemindersAndCallsPage>
    with WidgetsBindingObserver {
  final _svc = DmeSupabaseService.instance;

  // Shared state
  List<DmeReminder> _reminders = [];
  List<int> _branchIds = [];
  bool _loading = true;

  // Reminders tab state
  String _filter = 'Today';
  String? _selectedBranch;
  List<Map<String, dynamic>> _availableBranches = [];

  // Call detection state
  Set<int> _calledIds = {};
  String? _pendingCallPhone;
  int? _pendingCallCustomerId;
  int? _pendingCallReminderId;
  DateTime? _callStartTime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_pendingCallPhone != null) {
        _checkIfCallWasMade();
      } else {
        _autoScanCallLog();
      }
    }
  }

  Future<void> _init() async {
    _branchIds = await _svc.getUserBranchIds(widget.dmeUser.id);
    
    // Load ONLY branches assigned to this user
    final allBranches = await _svc.getBranches();
    if (mounted) {
      setState(() {
        // Filter branches to only those assigned to user
        _availableBranches = allBranches
            .where((b) => _branchIds.contains(b['id'] as int?))
            .toList();
        
        // Auto-select first branch if user has only one
        if (_branchIds.length == 1 && _availableBranches.isNotEmpty) {
          _selectedBranch = _availableBranches[0]['name'] as String?;
        }
      });
    }
    await _loadReminders();
    _autoScanCallLog();
  }

  Future<void> _loadReminders() async {
    setState(() => _loading = true);
    final now = DateTime.now();
    DateTime? from;
    DateTime? to;

    String? status = 'pending';
    
    switch (_filter) {
      case 'Today':
        from = DateTime(now.year, now.month, now.day);
        to = DateTime(now.year, now.month, now.day, 23, 59, 59);
        break;
      case 'This Week':
        final weekStart = now.subtract(Duration(days: now.weekday - 1));
        from = DateTime(weekStart.year, weekStart.month, weekStart.day);
        to = from.add(const Duration(days: 7));
        break;
      case 'This Month':
        from = DateTime(now.year, now.month, 1);
        to = DateTime(now.year, now.month + 1, 0);
        break;
      case 'Overdue':
        to = DateTime(now.year, now.month, now.day);
        break;
      case 'Completed Today':
        status = 'completed';
        from = DateTime(now.year, now.month, now.day);
        to = DateTime(now.year, now.month, now.day, 23, 59, 59);
        break;
      case 'All':
        break;
    }

    // Determine which branch IDs to fetch based on selection
    List<int>? branchesToFetch;
    if (widget.dmeUser.isAdmin) {
      branchesToFetch = null; // Admin sees all branches
    } else if (_selectedBranch != null) {
      // Filter to selected branch
      final selectedBranchId = _availableBranches
          .firstWhere(
            (b) => (b['name'] as String?) == _selectedBranch,
            orElse: () => {'id': null},
          )['id'] as int?;
      branchesToFetch = selectedBranchId != null ? [selectedBranchId] : _branchIds;
    } else {
      branchesToFetch = _branchIds;
    }

    final reminders = await _svc.getReminders(
      branchIds: branchesToFetch,
      status: status,
      from: from,
      to: to,
    );
    if (mounted) setState(() { _reminders = reminders; _loading = false; });
  }



  Future<void> _markComplete(DmeReminder r) async {
    await _svc.updateReminderStatus(r.id!, 'completed');
    _loadReminders();
  }

  Future<void> _dismiss(DmeReminder r) async {
    await _svc.updateReminderStatus(r.id!, 'dismissed');
    _loadReminders();
  }

  // ── Call Detection Logic ──

  Future<void> _savePendingCallState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('dme_call_pending_phone', _pendingCallPhone ?? '');
    await prefs.setInt('dme_call_pending_cust', _pendingCallCustomerId ?? 0);
    await prefs.setInt('dme_call_pending_reminder', _pendingCallReminderId ?? 0);
    await prefs.setString(
        'dme_call_pending_time', _callStartTime?.toIso8601String() ?? '');
  }

  Future<void> _clearPendingCallState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('dme_call_pending_phone');
    await prefs.remove('dme_call_pending_cust');
    await prefs.remove('dme_call_pending_reminder');
    await prefs.remove('dme_call_pending_time');
    _pendingCallPhone = null;
    _pendingCallCustomerId = null;
    _pendingCallReminderId = null;
    _callStartTime = null;
  }

  Future<void> _checkIfCallWasMade() async {
    if (_callStartTime == null || _pendingCallCustomerId == null) return;

    await Future.delayed(const Duration(seconds: 2));

    final entries = await CallLog.query(
      dateFrom: _callStartTime!.millisecondsSinceEpoch,
      dateTo: DateTime.now().millisecondsSinceEpoch,
    );

    bool found = false;
    for (final entry in entries) {
      if (entry.duration != null &&
          entry.duration! > 15 &&
          _numberMatches(entry.number ?? '', _pendingCallPhone ?? '')) {
        found = true;
        setState(() => _calledIds.add(_pendingCallCustomerId!));
        break;
      }
    }

    if (!found) {
      // Retry after 3s
      await Future.delayed(const Duration(seconds: 3));
      final retryEntries = await CallLog.query(
        dateFrom: _callStartTime!.millisecondsSinceEpoch,
        dateTo: DateTime.now().millisecondsSinceEpoch,
      );
      for (final entry in retryEntries) {
        if (entry.duration != null &&
            entry.duration! > 15 &&
            _numberMatches(entry.number ?? '', _pendingCallPhone ?? '')) {
          found = true;
          setState(() => _calledIds.add(_pendingCallCustomerId!));
          break;
        }
      }
    }

    await _clearPendingCallState();

    if (found && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Call detected and logged!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _autoScanCallLog() async {
    final status = await Permission.phone.status;
    if (!status.isGranted) return;

    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);

    final entries = await CallLog.query(
      dateFrom: startOfDay.millisecondsSinceEpoch,
      dateTo: now.millisecondsSinceEpoch,
    );

    for (final r in _reminders) {
      if (_calledIds.contains(r.customerId)) continue;
      final phone = r.customerPhone;
      if (phone == null || phone.isEmpty) continue;

      for (final entry in entries) {
        if (entry.duration != null &&
            entry.duration! > 15 &&
            _numberMatches(entry.number ?? '', phone)) {
          setState(() => _calledIds.add(r.customerId));
          break;
        }
      }
    }
  }

  Future<void> _scanCallLogManual() async {
    final status = await Permission.phone.request();
    if (!status.isGranted) return;

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final entries = await CallLog.query(
      dateFrom: startOfDay.millisecondsSinceEpoch,
      dateTo: now.millisecondsSinceEpoch,
    );

    final matched = <DmeReminder>[];
    for (final r in _reminders) {
      if (_calledIds.contains(r.customerId)) continue;
      final phone = r.customerPhone;
      if (phone == null || phone.isEmpty) continue;

      for (final entry in entries) {
        if (entry.duration != null &&
            entry.duration! > 15 &&
            entry.callType == CallType.outgoing &&
            _numberMatches(entry.number ?? '', phone)) {
          matched.add(r);
          setState(() => _calledIds.add(r.customerId));
          break;
        }
      }
    }

    if (mounted) Navigator.pop(context); // dismiss loading

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(matched.isEmpty
              ? 'No new calls detected'
              : '✅ ${matched.length} call(s) detected'),
          backgroundColor: matched.isEmpty ? null : Colors.green,
        ),
      );
    }
  }

  bool _numberMatches(String logNumber, String contact) {
    final clean = contact.replaceAll(RegExp(r'\D'), '');
    final logClean = logNumber.replaceAll(RegExp(r'\D'), '');
    return logClean.endsWith(clean) || clean.endsWith(logClean);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reminders & Calls'),
        backgroundColor: _primaryBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.phonelink_ring),
            tooltip: 'Scan Call Log',
            onPressed: _scanCallLogManual,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload & Rescan',
            onPressed: () async {
              await _loadReminders();
              await _autoScanCallLog();
            },
          ),
        ],
      ),
      body: _buildRemindersTab(),
    );
  }

  Widget _buildRemindersTab() {
    final dateFmt = DateFormat('dd-MMM-yy');
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        // ── Branch selector ─────────────────────────────────────
        if (_availableBranches.isNotEmpty && !widget.dmeUser.isAdmin)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : Colors.grey[50],
              border: Border(
                bottom: BorderSide(
                  color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.business_rounded,
                  size: 20,
                  color: _primaryBlue,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    value: _selectedBranch,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: isDark
                              ? Colors.grey[700]!
                              : Colors.grey[300]!,
                        ),
                      ),
                      filled: true,
                      fillColor: isDark ? Colors.grey[900] : Colors.white,
                    ),
                    items: [
                      if (_availableBranches.length > 1)
                        const DropdownMenuItem(
                          value: null,
                          child: Text('All Branches'),
                        ),
                      ..._availableBranches.map(
                        (branch) => DropdownMenuItem(
                          value: branch['name'] as String,
                          child: Text(
                            branch['name'] as String,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ),
                    ],
                    onChanged: (val) {
                      setState(() => _selectedBranch = val);
                      _loadReminders();
                    },
                  ),
                ),
              ],
            ),
          ),

        // Filter chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(12),
          child: Row(
            children: ['Today', 'This Week', 'This Month', 'Overdue', 'Completed Today', 'All']
                .map((f) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(f),
                        selected: _filter == f,
                        selectedColor: _primaryBlue,
                        labelStyle: TextStyle(
                          color: _filter == f ? Colors.white : null,
                        ),
                        onSelected: (_) {
                          setState(() => _filter = f);
                          _loadReminders();
                        },
                      ),
                    ))
                .toList(),
          ),
        ),
        const Divider(height: 1),
        // Count
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${_reminders.length} reminder${_reminders.length == 1 ? '' : 's'}',
              style: TextStyle(
                  color: isDark ? Colors.white54 : Colors.grey[600],
                  fontSize: 13),
            ),
          ),
        ),
        // List
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _reminders.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle_outline,
                              size: 64, color: Colors.grey[300]),
                          const SizedBox(height: 12),
                          const Text('No pending reminders',
                              style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () async {
                        await _loadReminders();
                        await _autoScanCallLog();
                      },
                      child: ListView.builder(
                        itemCount: _reminders.length,
                        itemBuilder: (_, i) {
                          final r = _reminders[i];
                          final isOverdue =
                              r.reminderDate.isBefore(DateTime.now());
                          final called = _calledIds.contains(r.customerId);
                          final isCompleted = r.status == 'completed';
                          
                          return Dismissible(
                            key: Key('reminder_${r.id}'),
                            background: Container(
                              color: Colors.green,
                              alignment: Alignment.centerLeft,
                              padding: const EdgeInsets.only(left: 20),
                              child: const Icon(Icons.check,
                                  color: Colors.white),
                            ),
                            secondaryBackground: Container(
                              color: Colors.orange,
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              child: const Icon(Icons.close,
                                  color: Colors.white),
                            ),
                            confirmDismiss: (direction) async {
                              if (direction ==
                                  DismissDirection.startToEnd) {
                                await _markComplete(r);
                              } else {
                                await _dismiss(r);
                              }
                              return false; // We reload the list manually
                            },
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: called
                                    ? Colors.green.withValues(alpha: 0.1)
                                    : isCompleted
                                        ? Colors.purple.withValues(alpha: 0.1)
                                        : isOverdue
                                            ? Colors.red.withValues(alpha: 0.1)
                                            : _primaryBlue.withValues(alpha: 0.1),
                                child: Icon(
                                  called
                                      ? Icons.check
                                      : isCompleted
                                          ? Icons.task_alt
                                          : isOverdue
                                              ? Icons.warning_amber
                                              : Icons.notifications_active,
                                  color: called
                                      ? Colors.green
                                      : isCompleted
                                          ? Colors.purple
                                          : isOverdue
                                              ? Colors.red
                                              : _primaryBlue,
                                ),
                              ),
                              title: Text(
                                  r.customerName ??
                                      'Customer #${r.customerId}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    decoration: called
                                        ? TextDecoration.lineThrough
                                        : null,
                                  )),
                              subtitle: Text(
                                [
                                  if (r.customerPhone != null)
                                    r.customerPhone,
                                  if (r.salesman != null) r.salesman,
                                  'Due: ${dateFmt.format(r.reminderDate)}',
                                  'Purchased: ${dateFmt.format(r.lastPurchaseDate)}',
                                ].join(' • '),
                                style: const TextStyle(fontSize: 12),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: called
                                          ? Colors.green.withValues(alpha: 0.2)
                                          : isCompleted
                                              ? Colors.purple.withValues(alpha: 0.2)
                                              : isOverdue
                                                  ? Colors.red.withValues(alpha: 0.2)
                                                  : Colors.blue.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      called 
                                          ? 'Called' 
                                          : isCompleted
                                              ? 'Completed'
                                              : isOverdue 
                                                  ? 'Overdue' 
                                                  : 'Pending',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: called
                                            ? Colors.green
                                            : isCompleted
                                                ? Colors.purple
                                                : isOverdue
                                                    ? Colors.red
                                                    : Colors.blue,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.chevron_right),
                                ],
                              ),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        DmeCustomerTileViewer(
                                      reminder: r,
                                      dmeUser: widget.dmeUser,
                                    ),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }


}
