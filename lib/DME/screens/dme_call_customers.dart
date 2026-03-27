import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:call_log/call_log.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/dme_supabase_service.dart';
import '../models/dme_user.dart';
import '../models/dme_reminder.dart';
import '../models/dme_customer.dart';
import 'dme_customer_detail.dart';

class DmeCallCustomersPage extends StatefulWidget {
  final DmeUser dmeUser;
  const DmeCallCustomersPage({super.key, required this.dmeUser});

  @override
  State<DmeCallCustomersPage> createState() => _DmeCallCustomersPageState();
}

class _DmeCallCustomersPageState extends State<DmeCallCustomersPage>
    with WidgetsBindingObserver {
  final _svc = DmeSupabaseService.instance;

  List<DmeReminder> _reminders = [];
  List<int> _branchIds = [];
  Set<int> _calledIds = {};
  bool _loading = true;
  String? _pendingCallPhone;
  int? _pendingCallCustomerId;
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
    await _loadReminders();
    _autoScanCallLog();
  }

  Future<void> _loadReminders() async {
    setState(() => _loading = true);
    final now = DateTime.now();
    // Show today's reminders + overdue
    final reminders = await _svc.getReminders(
      branchIds: widget.dmeUser.isAdmin ? null : _branchIds,
      status: 'pending',
      to: DateTime(now.year, now.month, now.day, 23, 59, 59),
    );
    if (mounted) setState(() { _reminders = reminders; _loading = false; });
  }

  // ── Call Detection (reusing pattern from customer_list_target.dart) ──

  Future<void> _makeCall(DmeReminder r) async {
    final phone = r.customerPhone;
    if (phone == null || phone.isEmpty) return;

    final status = await Permission.phone.request();
    if (!status.isGranted) return;

    _pendingCallPhone = phone;
    _pendingCallCustomerId = r.customerId;
    _callStartTime = DateTime.now();
    await _savePendingCallState();

    final uri = Uri(scheme: 'tel', path: phone);
    await launchUrl(uri);
  }

  Future<void> _savePendingCallState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('dme_call_pending_phone', _pendingCallPhone ?? '');
    await prefs.setInt('dme_call_pending_cust', _pendingCallCustomerId ?? 0);
    await prefs.setString(
        'dme_call_pending_time', _callStartTime?.toIso8601String() ?? '');
  }

  Future<void> _clearPendingCallState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('dme_call_pending_phone');
    await prefs.remove('dme_call_pending_cust');
    await prefs.remove('dme_call_pending_time');
    _pendingCallPhone = null;
    _pendingCallCustomerId = null;
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
        await _svc.logCall(
          customerId: _pendingCallCustomerId!,
          calledBy: widget.dmeUser.id,
          callDate: DateTime.now(),
          durationSeconds: entry.duration,
        );
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
          await _svc.logCall(
            customerId: _pendingCallCustomerId!,
            calledBy: widget.dmeUser.id,
            callDate: DateTime.now(),
            durationSeconds: entry.duration,
          );
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

          await _svc.logCall(
            customerId: r.customerId,
            calledBy: widget.dmeUser.id,
            callDate: DateTime.now(),
            durationSeconds: entry.duration,
          );
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
    final dateFmt = DateFormat('dd-MMM-yy');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Call Customers'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.phonelink_ring),
            tooltip: 'Scan Call Log',
            onPressed: _scanCallLogManual,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadReminders,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _reminders.isEmpty
              ? const Center(child: Text('No customers to call today'))
              : ListView.builder(
                  itemCount: _reminders.length,
                  itemBuilder: (_, i) {
                    final r = _reminders[i];
                    final called = _calledIds.contains(r.customerId);
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: called
                            ? Colors.green.withOpacity(0.1)
                            : Colors.orange.withOpacity(0.1),
                        child: Icon(
                          called ? Icons.check : Icons.phone,
                          color: called ? Colors.green : Colors.orange,
                        ),
                      ),
                      title: Text(
                        r.customerName ?? 'Customer #${r.customerId}',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          decoration:
                              called ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      subtitle: Text(
                        [
                          if (r.customerPhone != null) r.customerPhone,
                          'Due: ${dateFmt.format(r.reminderDate)}',
                        ].join(' • '),
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: called
                          ? const Icon(Icons.check_circle,
                              color: Colors.green)
                          : IconButton(
                              icon: const Icon(Icons.phone_forwarded,
                                  color: Color(0xFF005BAC)),
                              onPressed: () => _makeCall(r),
                            ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => DmeCustomerDetailPage(
                              customer: DmeCustomer(
                                id: r.customerId,
                                name: r.customerName ?? '',
                                phone: r.customerPhone ?? '',
                                address: r.customerAddress,
                              ),
                              dmeUser: widget.dmeUser,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
    );
  }
}
