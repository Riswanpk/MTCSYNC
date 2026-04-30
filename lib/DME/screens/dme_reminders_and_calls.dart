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

    final permStatus = await Permission.phone.status;
    if (!permStatus.isGranted) return;

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
      backgroundColor: const Color(0xFFF0F4FA),
      appBar: AppBar(
        elevation: 0,
        title: const Text(
          'Reminders & Calls',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.3),
        ),
        backgroundColor: _primaryBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.phonelink_ring_rounded),
            tooltip: 'Scan Call Log',
            onPressed: _scanCallLogManual,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
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
    final dateFmt = DateFormat('dd MMM yy');
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        // ── Branch selector ──────────────────────────────────────
        if (_availableBranches.isNotEmpty && !widget.dmeUser.isAdmin)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            color: _primaryBlue,
            child: Row(
              children: [
                const Icon(Icons.store_rounded, size: 18, color: Colors.white70),
                const SizedBox(width: 10),
                Expanded(
                  child: Theme(
                    data: Theme.of(context).copyWith(
                      canvasColor: _primaryBlue,
                    ),
                    child: DropdownButtonFormField<String?>(
                      value: _selectedBranch,
                      dropdownColor: _primaryBlue,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      iconEnabledColor: Colors.white70,
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: Colors.white30),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: Colors.white),
                        ),
                        filled: true,
                        fillColor: Colors.white12,
                      ),
                      items: [
                        if (_availableBranches.length > 1)
                          const DropdownMenuItem(
                            value: null,
                            child: Text('All Branches',
                                style: TextStyle(color: Colors.white)),
                          ),
                        ..._availableBranches.map(
                          (b) => DropdownMenuItem(
                            value: b['name'] as String,
                            child: Text(b['name'] as String,
                                style: const TextStyle(color: Colors.white)),
                          ),
                        ),
                      ],
                      onChanged: (val) {
                        setState(() => _selectedBranch = val);
                        _loadReminders();
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),

        // ── Filter chips ──────────────────────────────────────────
        Container(
          color: _primaryBlue,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                'Today',
                'This Week',
                'This Month',
                'Overdue',
                'Completed Today',
                'All'
              ].map((f) {
                final selected = _filter == f;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () {
                      setState(() => _filter = f);
                      _loadReminders();
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: selected
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: selected
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        f,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: selected ? _primaryBlue : Colors.white,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),

        // ── Count bar ─────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: isDark ? Colors.grey[850] : Colors.white,
          child: Row(
            children: [
              Icon(Icons.notifications_rounded,
                  size: 16, color: _primaryBlue.withValues(alpha: 0.7)),
              const SizedBox(width: 6),
              Text(
                '${_reminders.length} reminder${_reminders.length == 1 ? '' : 's'}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white60 : Colors.grey[700],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, thickness: 1),

        // ── Reminder cards ────────────────────────────────────────
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _reminders.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.check_circle_rounded,
                                size: 56, color: Colors.green),
                          ),
                          const SizedBox(height: 16),
                          const Text('All clear!',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text('No reminders for this period',
                              style: TextStyle(color: Colors.grey[500])),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () async {
                        await _loadReminders();
                        await _autoScanCallLog();
                      },
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                        itemCount: _reminders.length,
                        itemBuilder: (_, i) {
                          final r = _reminders[i];
                          return _ReminderCard(
                            reminder: r,
                            dateFmt: dateFmt,
                            called: _calledIds.contains(r.customerId),
                            onMarkComplete: () => _markComplete(r),
                            onDismiss: () => _dismiss(r),
                            onCallTap: r.customerPhone != null
                                ? () async {
                                    _pendingCallPhone = r.customerPhone;
                                    _pendingCallCustomerId = r.customerId;
                                    _pendingCallReminderId = r.id;
                                    _callStartTime = DateTime.now();
                                    await _savePendingCallState();
                                    final uri = Uri(
                                        scheme: 'tel',
                                        path: r.customerPhone);
                                    if (await canLaunchUrl(uri)) {
                                      await launchUrl(uri);
                                    }
                                  }
                                : null,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => DmeCustomerTileViewer(
                                  reminder: r,
                                  dmeUser: widget.dmeUser,
                                ),
                              ),
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

// ─── Reminder Card Widget ────────────────────────────────────────────────────

class _ReminderCard extends StatelessWidget {
  final DmeReminder reminder;
  final DateFormat dateFmt;
  final bool called;
  final VoidCallback onMarkComplete;
  final VoidCallback onDismiss;
  final VoidCallback? onCallTap;
  final VoidCallback onTap;

  const _ReminderCard({
    required this.reminder,
    required this.dateFmt,
    required this.called,
    required this.onMarkComplete,
    required this.onDismiss,
    required this.onCallTap,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isOverdue = reminder.reminderDate.isBefore(DateTime.now()) &&
        reminder.status == 'pending';
    final isCompleted = reminder.status == 'completed';

    Color statusColor;
    IconData statusIcon;
    String statusLabel;

    if (called) {
      statusColor = Colors.green;
      statusIcon = Icons.phone_in_talk_rounded;
      statusLabel = 'Called';
    } else if (isCompleted) {
      statusColor = Colors.purple;
      statusIcon = Icons.task_alt_rounded;
      statusLabel = 'Done';
    } else if (isOverdue) {
      statusColor = Colors.red;
      statusIcon = Icons.warning_amber_rounded;
      statusLabel = 'Overdue';
    } else {
      statusColor = _primaryBlue;
      statusIcon = Icons.notifications_active_rounded;
      statusLabel = 'Pending';
    }

    return Dismissible(
      key: Key('reminder_${reminder.id}'),
      background: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.green,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 24),
        child: const Row(
          children: [
            Icon(Icons.check_rounded, color: Colors.white),
            SizedBox(width: 8),
            Text('Complete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
      secondaryBackground: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.orange,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text('Dismiss', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            SizedBox(width: 8),
            Icon(Icons.close_rounded, color: Colors.white),
          ],
        ),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          onMarkComplete();
        } else {
          onDismiss();
        }
        return false;
      },
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF1E2A3A)
                : Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
            border: isOverdue
                ? Border.all(color: Colors.red.withValues(alpha: 0.3), width: 1.5)
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Status icon circle
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(statusIcon, color: statusColor, size: 22),
                ),
                const SizedBox(width: 12),
                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              reminder.customerName ??
                                  'Customer #${reminder.customerId}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                decoration:
                                    called ? TextDecoration.lineThrough : null,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 9, vertical: 3),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              statusLabel,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: statusColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      if (reminder.customerPhone != null)
                        Text(
                          reminder.customerPhone!,
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey[600]),
                        ),
                      if (reminder.salesman != null)
                        Text(
                          reminder.salesman!,
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey[500]),
                        ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.calendar_today_rounded,
                              size: 12, color: statusColor),
                          const SizedBox(width: 4),
                          Text(
                            'Due: ${dateFmt.format(reminder.reminderDate)}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: statusColor,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Icon(Icons.shopping_bag_rounded,
                              size: 12, color: Colors.grey[400]),
                          const SizedBox(width: 4),
                          Text(
                            dateFmt.format(reminder.lastPurchaseDate),
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[500]),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Call button
                if (onCallTap != null)
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: onCallTap,
                      borderRadius: BorderRadius.circular(24),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: called
                              ? Colors.green.withValues(alpha: 0.12)
                              : _primaryBlue.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          called
                              ? Icons.phone_in_talk_rounded
                              : Icons.phone_rounded,
                          color: called ? Colors.green : _primaryBlue,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
