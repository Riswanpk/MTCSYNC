import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../leads_widgets.dart';
import '../presentfollowup.dart';

/// Month calendar of leads, plotted by their follow-up reminder date.
class LeadsCalendarView extends StatefulWidget {
  final String? branch;
  final String? userId;
  final String priority;
  final String source;

  const LeadsCalendarView({
    super.key,
    required this.branch,
    required this.userId,
    required this.priority,
    required this.source,
  });

  @override
  State<LeadsCalendarView> createState() => _LeadsCalendarViewState();
}

class _CalLead {
  final String id;
  final String name;
  final String status;
  final String priority;
  final String? source;
  final String reminderRaw;
  final DateTime day;
  _CalLead(this.id, this.name, this.status, this.priority, this.source,
      this.reminderRaw, this.day);
}

class _LeadsCalendarViewState extends State<LeadsCalendarView> {
  static const _blue = Color(0xFF005BAC);
  static const _green = Color(0xFF8CC63F);

  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _selected = _dateOnly(DateTime.now());
  bool _includeClosed = false;
  bool _loading = false;
  Map<DateTime, List<_CalLead>> _byDay = {};

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant LeadsCalendarView old) {
    super.didUpdateWidget(old);
    if (old.branch != widget.branch ||
        old.userId != widget.userId ||
        old.priority != widget.priority ||
        old.source != widget.source) {
      _load();
    }
  }

  DateTime? _parseReminder(String r) {
    if (r.isEmpty || r == 'No Reminder') return null;
    final first = r.trim().split(' ').first;
    try {
      return _dateOnly(DateTime.parse(first));
    } catch (_) {}
    try {
      return _dateOnly(DateFormat('dd-MM-yyyy').parseStrict(first));
    } catch (_) {}
    return null;
  }

  Future<void> _load() async {
    final branch = widget.branch;
    if (branch == null || branch.isEmpty) {
      setState(() => _byDay = {});
      return;
    }
    setState(() => _loading = true);
    try {
      Query q = FirebaseFirestore.instance
          .collection('follow_ups')
          .where('branch', isEqualTo: branch);
      if (widget.userId != null) {
        q = q.where(Filter.or(
          Filter('created_by', isEqualTo: widget.userId),
          Filter('assigned_to', isEqualTo: widget.userId),
          Filter('screened_by', isEqualTo: widget.userId),
        ));
      }
      if (!_includeClosed) {
        q = q.where('status', isEqualTo: 'In Progress');
      }
      if (widget.priority != 'All') {
        q = q.where('priority', isEqualTo: widget.priority);
      }
      final snap = await q.limit(1000).get();
      final map = <DateTime, List<_CalLead>>{};
      for (final doc in snap.docs) {
        final d = doc.data() as Map<String, dynamic>;
        final src = (d['source'] as String?)?.toLowerCase() ?? 'sales';
        if (widget.source != 'All' && src != widget.source.toLowerCase()) {
          continue;
        }
        if (src == 'sme' && d['screening_status'] != 'promoted') continue;
        final reminder = (d['reminder'] ?? '').toString();
        final day = _parseReminder(reminder);
        if (day == null) continue;
        map.putIfAbsent(day, () => []).add(_CalLead(
              doc.id,
              (d['name'] ?? 'No Name').toString(),
              (d['status'] ?? 'Unknown').toString(),
              (d['priority'] ?? 'High').toString(),
              d['source'] as String?,
              reminder,
              day,
            ));
      }
      if (!mounted) return;
      setState(() {
        _byDay = map;
        _loading = false;
      });
    } catch (e) {
      debugPrint('LeadsCalendarView load error: $e');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  int get _overdueCount {
    final today = _dateOnly(DateTime.now());
    var c = 0;
    _byDay.forEach((day, list) {
      if (day.isBefore(today)) {
        c += list.where((l) => l.status == 'In Progress').length;
      }
    });
    return c;
  }

  int get _monthCount {
    var c = 0;
    _byDay.forEach((day, list) {
      if (day.year == _month.year && day.month == _month.month) c += list.length;
    });
    return c;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final today = _dateOnly(DateTime.now());
    final todayCount = _byDay[today]?.length ?? 0;
    final selectedLeads = List<_CalLead>.from(_byDay[_selected] ?? [])
      ..sort((a, b) => _prioRank(a.priority).compareTo(_prioRank(b.priority)));

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 90),
        children: [
          // Summary chips
          Row(
            children: [
              _statChip('Today', todayCount, _blue),
              const SizedBox(width: 8),
              _statChip('Overdue', _overdueCount, Colors.red.shade400),
              const SizedBox(width: 8),
              _statChip('This Month', _monthCount, _green),
            ],
          ),
          const SizedBox(height: 10),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                children: [
                  _monthHeader(),
                  const SizedBox(height: 6),
                  _weekdayRow(theme),
                  const SizedBox(height: 4),
                  _loading
                      ? const SizedBox(
                          height: 260,
                          child: Center(child: CircularProgressIndicator()))
                      : _monthGrid(theme, isDark, today),
                  const SizedBox(height: 6),
                  _legend(),
                ],
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  DateFormat('EEEE, dd MMM yyyy').format(_selected),
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              FilterChip(
                label: const Text('Include closed'),
                selected: _includeClosed,
                onSelected: (v) {
                  setState(() => _includeClosed = v);
                  _load();
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (selectedLeads.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 30),
              child: Center(child: Text('No follow-ups on this day.')),
            )
          else
            ...selectedLeads.map((l) => _leadTile(l, theme, isDark, today)),
        ],
      ),
    );
  }

  int _prioRank(String p) => p == 'High' ? 0 : (p == 'Medium' ? 1 : 2);

  Widget _statChip(String label, int value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Column(
          children: [
            Text('$value',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold, color: color)),
            Text(label, style: TextStyle(fontSize: 12, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _monthHeader() {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: () => setState(
              () => _month = DateTime(_month.year, _month.month - 1)),
        ),
        Expanded(
          child: Center(
            child: Text(
              DateFormat('MMMM yyyy').format(_month),
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.bold, color: _blue),
            ),
          ),
        ),
        TextButton(
          onPressed: () {
            final now = DateTime.now();
            setState(() {
              _month = DateTime(now.year, now.month);
              _selected = _dateOnly(now);
            });
          },
          child: const Text('Today'),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: () => setState(
              () => _month = DateTime(_month.year, _month.month + 1)),
        ),
      ],
    );
  }

  Widget _weekdayRow(ThemeData theme) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Row(
      children: days
          .map((d) => Expanded(
                child: Center(
                  child: Text(d,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: theme.hintColor)),
                ),
              ))
          .toList(),
    );
  }

  Widget _monthGrid(ThemeData theme, bool isDark, DateTime today) {
    final first = DateTime(_month.year, _month.month, 1);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final leading = first.weekday - 1; // Monday start
    final totalCells = ((leading + daysInMonth + 6) ~/ 7) * 7;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: totalCells,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 7, childAspectRatio: 0.9),
      itemBuilder: (context, i) {
        final dayNum = i - leading + 1;
        if (dayNum < 1 || dayNum > daysInMonth) return const SizedBox.shrink();
        final day = DateTime(_month.year, _month.month, dayNum);
        final leads = _byDay[day] ?? const [];
        final isToday = day == today;
        final isSelected = day == _selected;
        final hasOverdue = day.isBefore(today) &&
            leads.any((l) => l.status == 'In Progress');

        return GestureDetector(
          onTap: () => setState(() => _selected = day),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: isSelected
                  ? _blue
                  : (isToday ? _blue.withValues(alpha: 0.12) : null),
              borderRadius: BorderRadius.circular(10),
              border: isToday && !isSelected
                  ? Border.all(color: _blue, width: 1.2)
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$dayNum',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? Colors.white
                        : (hasOverdue ? Colors.red.shade400 : null),
                  ),
                ),
                const SizedBox(height: 3),
                if (leads.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.white
                          : (hasOverdue ? Colors.red.shade400 : _green),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${leads.length}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isSelected ? _blue : Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _legend() {
    Widget item(Color c, String t) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
            const SizedBox(width: 4),
            Text(t, style: const TextStyle(fontSize: 11)),
          ],
        );
    return Wrap(
      spacing: 14,
      children: [
        item(_green, 'Follow-ups'),
        item(Colors.red.shade400, 'Overdue'),
        item(_blue, 'Today / Selected'),
      ],
    );
  }

  Widget _leadTile(_CalLead l, ThemeData theme, bool isDark, DateTime today) {
    final overdue = l.day.isBefore(today) && l.status == 'In Progress';
    final statusColor = l.status == 'Sale'
        ? Colors.green
        : (l.status == 'Cancelled' ? Colors.red : _blue);
    final time = l.reminderRaw.trim().contains(' ')
        ? l.reminderRaw.trim().split(' ').skip(1).join(' ')
        : '';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: getPriorityBackgroundColor(l.priority, isDark),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => PresentFollowUp(docId: l.id)),
          );
          _load();
        },
        leading: CircleAvatar(
          backgroundColor: getPriorityColor(l.priority),
          child: Text(
            l.name.isNotEmpty ? l.name[0].toUpperCase() : '?',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(l.name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          [
            '${l.priority} priority',
            if ((l.source ?? '').isNotEmpty) l.source!.toUpperCase(),
            if (time.isNotEmpty) time,
          ].join(' • '),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: (overdue ? Colors.red : statusColor).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            overdue ? 'Overdue' : l.status,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: overdue ? Colors.red : statusColor),
          ),
        ),
      ),
    );
  }
}
