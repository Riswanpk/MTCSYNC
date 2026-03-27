import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/dme_supabase_service.dart';
import '../models/dme_user.dart';
import '../models/dme_reminder.dart';
import '../models/dme_customer.dart';
import 'dme_customer_detail.dart';

class DmeRemindersPage extends StatefulWidget {
  final DmeUser dmeUser;
  const DmeRemindersPage({super.key, required this.dmeUser});

  @override
  State<DmeRemindersPage> createState() => _DmeRemindersPageState();
}

class _DmeRemindersPageState extends State<DmeRemindersPage> {
  final _svc = DmeSupabaseService.instance;

  List<DmeReminder> _reminders = [];
  List<int> _branchIds = [];
  bool _loading = true;
  String _filter = 'Today';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _branchIds = await _svc.getUserBranchIds(widget.dmeUser.id);
    await _loadReminders();
  }

  Future<void> _loadReminders() async {
    setState(() => _loading = true);
    final now = DateTime.now();
    DateTime? from;
    DateTime? to;

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
      case 'All':
        break;
    }

    final reminders = await _svc.getReminders(
      branchIds: widget.dmeUser.isAdmin ? null : _branchIds,
      status: 'pending',
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

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd-MMM-yy');
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reminders'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Filter chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: Row(
              children: ['Today', 'This Week', 'This Month', 'Overdue', 'All']
                  .map((f) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(f),
                          selected: _filter == f,
                          selectedColor: const Color(0xFF005BAC),
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
                        onRefresh: _loadReminders,
                        child: ListView.builder(
                          itemCount: _reminders.length,
                          itemBuilder: (_, i) {
                            final r = _reminders[i];
                            final isOverdue =
                                r.reminderDate.isBefore(DateTime.now());
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
                                child:
                                    const Icon(Icons.close, color: Colors.white),
                              ),
                              confirmDismiss: (direction) async {
                                if (direction == DismissDirection.startToEnd) {
                                  await _markComplete(r);
                                } else {
                                  await _dismiss(r);
                                }
                                return false; // We reload the list manually
                              },
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: isOverdue
                                      ? Colors.red.withOpacity(0.1)
                                      : const Color(0xFF005BAC)
                                          .withOpacity(0.1),
                                  child: Icon(
                                    isOverdue
                                        ? Icons.warning_amber
                                        : Icons.notifications_active,
                                    color:
                                        isOverdue ? Colors.red : const Color(0xFF005BAC),
                                  ),
                                ),
                                title: Text(r.customerName ?? 'Customer #${r.customerId}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                                subtitle: Text(
                                  [
                                    if (r.customerPhone != null) r.customerPhone,
                                    'Due: ${dateFmt.format(r.reminderDate)}',
                                    'Purchased: ${dateFmt.format(r.lastPurchaseDate)}',
                                  ].join(' • '),
                                  style: const TextStyle(fontSize: 12),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.phone,
                                          color: Colors.green, size: 20),
                                      onPressed: () {
                                        if (r.customerPhone != null) {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  DmeCustomerDetailPage(
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
                                        }
                                      },
                                      tooltip: 'Call',
                                    ),
                                    const Icon(Icons.chevron_right),
                                  ],
                                ),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          DmeCustomerDetailPage(
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
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
