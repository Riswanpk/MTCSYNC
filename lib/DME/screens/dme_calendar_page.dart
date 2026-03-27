import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/dme_supabase_service.dart';
import '../models/dme_user.dart';
import '../models/dme_reminder.dart';
import 'dme_customer_tile_viewer.dart';

class DmeCalendarPage extends StatefulWidget {
  final DmeUser dmeUser;
  const DmeCalendarPage({super.key, required this.dmeUser});

  @override
  State<DmeCalendarPage> createState() => _DmeCalendarPageState();
}

class _DmeCalendarPageState extends State<DmeCalendarPage>
    with WidgetsBindingObserver {
  final _svc = DmeSupabaseService.instance;

  DateTime _selectedDate = DateTime.now();
  List<DmeReminder> _reminders = [];
  List<int> _branchIds = [];
  bool _loading = true;

  static const _blue = Color(0xFF005BAC);

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
    if (state == AppLifecycleState.resumed) _loadReminders();
  }

  Future<void> _init() async {
    _branchIds = await _svc.getUserBranchIds(widget.dmeUser.id);
    await _loadReminders();
  }

  Future<void> _loadReminders() async {
    if (mounted) setState(() => _loading = true);
    final d = _selectedDate;
    final from = DateTime(d.year, d.month, d.day);
    final to = DateTime(d.year, d.month, d.day, 23, 59, 59);
    try {
      final reminders = await _svc.getReminders(
        branchIds: widget.dmeUser.isAdmin ? null : _branchIds,
        status: 'pending',
        from: from,
        to: to,
      );
      if (mounted) setState(() { _reminders = reminders; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _changeDate(int days) {
    setState(() => _selectedDate = _selectedDate.add(Duration(days: days)));
    _loadReminders();
  }

  void _goToday() {
    setState(() => _selectedDate = DateTime.now());
    _loadReminders();
  }

  bool get _isToday {
    final now = DateTime.now();
    return _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
  }

  Future<void> _openTileViewer(DmeReminder reminder) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DmeCustomerTileViewer(
          reminder: reminder,
          dmeUser: widget.dmeUser,
        ),
      ),
    );
    // Reload after returning — user may have marked reminder complete
    _loadReminders();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final labelFmt = DateFormat('EEE, dd MMM yyyy');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calling Calendar',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        backgroundColor: _blue,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (!_isToday)
            TextButton(
              onPressed: _goToday,
              child: const Text('Today',
                  style:
                      TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadReminders,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Date strip navigation ───────────────────────────
          Container(
            color: _blue,
            padding: const EdgeInsets.only(bottom: 12, left: 8, right: 8),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left,
                      color: Colors.white, size: 28),
                  onPressed: () => _changeDate(-1),
                  tooltip: 'Previous day',
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: _isToday ? null : _goToday,
                    child: Column(
                      children: [
                        if (_isToday)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text('TODAY',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                    letterSpacing: 1.2)),
                          ),
                        Text(
                          labelFmt.format(_selectedDate),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right,
                      color: Colors.white, size: 28),
                  onPressed: () => _changeDate(1),
                  tooltip: 'Next day',
                ),
              ],
            ),
          ),

          // ── Count bar ───────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[900] : Colors.grey[100],
              border: Border(
                bottom: BorderSide(
                    color: isDark ? Colors.grey[800]! : Colors.grey[300]!),
              ),
            ),
            child: _loading
                ? const SizedBox(
                    height: 16,
                    child: LinearProgressIndicator(),
                  )
                : Text(
                    _reminders.isEmpty
                        ? 'No customers to call this day'
                        : '${_reminders.length} customer${_reminders.length == 1 ? '' : 's'} to call',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.grey[700],
                    ),
                  ),
          ),

          // ── Customer list ───────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _reminders.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.event_available,
                                size: 64, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text(
                              'No customers to call on this day.',
                              style: TextStyle(
                                  fontSize: 15, color: Colors.grey[500]),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Use ‹ › to browse other days.',
                              style: TextStyle(
                                  fontSize: 13, color: Colors.grey[400]),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        itemCount: _reminders.length,
                        itemBuilder: (_, i) =>
                            _ReminderCard(
                          reminder: _reminders[i],
                          index: i,
                          onTap: () => _openTileViewer(_reminders[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

// ── Reminder list card ──────────────────────────────────────────

class _ReminderCard extends StatelessWidget {
  final DmeReminder reminder;
  final int index;
  final VoidCallback onTap;

  const _ReminderCard({
    required this.reminder,
    required this.index,
    required this.onTap,
  });

  static const _blue = Color(0xFF005BAC);

  @override
  Widget build(BuildContext context) {
    final r = reminder;
    final dateFmt = DateFormat('dd MMM yyyy');
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Index avatar
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _blue.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    color: _blue,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Customer info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.customerName ?? 'Customer #${r.customerId}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    if (r.customerPhone != null &&
                        r.customerPhone!.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(r.customerPhone!,
                          style: TextStyle(
                              fontSize: 13,
                              color: isDark
                                  ? Colors.grey[400]
                                  : Colors.grey[600])),
                    ],
                    const SizedBox(height: 3),
                    Text(
                      'Last purchase: ${dateFmt.format(r.lastPurchaseDate)}',
                      style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.grey[500] : Colors.grey[500]),
                    ),
                  ],
                ),
              ),
              // Chevron
              Icon(Icons.chevron_right,
                  color: isDark ? Colors.grey[600] : Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }
}
