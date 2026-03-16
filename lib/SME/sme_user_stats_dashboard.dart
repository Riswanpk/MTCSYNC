import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../Leads/presentfollowup.dart';

class SmeUserStatsDashboard extends StatefulWidget {
  const SmeUserStatsDashboard({super.key});

  @override
  State<SmeUserStatsDashboard> createState() => _SmeUserStatsDashboardState();
}

class _SmeUserStatsDashboardState extends State<SmeUserStatsDashboard> {
  bool _isLoading = true;
  List<_UserStat> _userStats = [];
  DateTime _startDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _endDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _fetchStats();
  }

  Future<void> _fetchStats() async {
    setState(() => _isLoading = true);

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _isLoading = false);
      return;
    }

    final dayEnd = _endDate.add(const Duration(days: 1));

    final snapshot = await FirebaseFirestore.instance
        .collection('follow_ups')
        .where('assigned_by', isEqualTo: uid)
        .where('created_at', isGreaterThanOrEqualTo: Timestamp.fromDate(_startDate))
        .where('created_at', isLessThan: Timestamp.fromDate(dayEnd))
        .get();

    // Group by assigned_to
    final Map<String, _UserStat> statMap = {};

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final assignedTo = data['assigned_to'] as String? ?? 'unknown';
      final assignedName = data['assigned_to_name'] as String? ?? 'Unknown';
      final branch = data['branch'] as String? ?? '';
      final status = data['status'] as String? ?? 'In Progress';

      if (!statMap.containsKey(assignedTo)) {
        statMap[assignedTo] = _UserStat(
          uid: assignedTo,
          name: assignedName,
          branch: branch,
        );
      }

      final stat = statMap[assignedTo]!;
      stat.total++;
      switch (status) {
        case 'In Progress':
          stat.inProgress++;
          break;
        case 'Sale':
          stat.sold++;
          break;
        case 'Cancelled':
          stat.cancelled++;
          break;
      }
    }

    final stats = statMap.values.toList();
    stats.sort((a, b) => b.total.compareTo(a.total));

    setState(() {
      _userStats = stats;
      _isLoading = false;
    });
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _fetchStats();
    }
  }

  void _showUserLeads(_UserStat stat) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _UserLeadsDetailPage(
          smeUid: uid,
          assignedToUid: stat.uid,
          assignedToName: stat.name,
          startDate: _startDate,
          endDate: _endDate,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dateRangeStr =
        '${DateFormat('dd MMM').format(_startDate)} - ${DateFormat('dd MMM yyyy').format(_endDate)}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('User Assignment Stats'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.date_range),
            tooltip: 'Change date range',
            onPressed: _pickDateRange,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Date range indicator
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: isDark ? const Color(0xFF23242B) : const Color(0xFFF0F4FF),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today, size: 16, color: Color(0xFF005BAC)),
                      const SizedBox(width: 8),
                      Text(dateRangeStr, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      const Spacer(),
                      Text('${_userStats.length} users',
                          style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.black45)),
                    ],
                  ),
                ),
                // Summary row
                Container(
                  padding: const EdgeInsets.all(12),
                  color: isDark ? const Color(0xFF1A1B22) : Colors.white,
                  child: Row(
                    children: [
                      _summaryChip('Total', _userStats.fold(0, (s, u) => s + u.total), const Color(0xFF005BAC)),
                      _summaryChip('In Progress', _userStats.fold(0, (s, u) => s + u.inProgress), Colors.orange),
                      _summaryChip('Sold', _userStats.fold(0, (s, u) => s + u.sold), Colors.green),
                      _summaryChip('Cancelled', _userStats.fold(0, (s, u) => s + u.cancelled), Colors.red),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // Table header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  color: isDark ? const Color(0xFF1E2028) : const Color(0xFFF5F7FA),
                  child: const Row(
                    children: [
                      Expanded(flex: 3, child: Text('User', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                      Expanded(flex: 1, child: Text('Total', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.center)),
                      Expanded(flex: 1, child: Text('Active', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.orange), textAlign: TextAlign.center)),
                      Expanded(flex: 1, child: Text('Sold', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.green), textAlign: TextAlign.center)),
                      Expanded(flex: 1, child: Text('Cancel', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.red), textAlign: TextAlign.center)),
                    ],
                  ),
                ),
                // User stat rows
                Expanded(
                  child: _userStats.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.people_outline, size: 48, color: isDark ? Colors.white30 : Colors.black26),
                              const SizedBox(height: 8),
                              Text('No assignments in this period',
                                  style: TextStyle(color: isDark ? Colors.white38 : Colors.black38)),
                            ],
                          ),
                        )
                      : ListView.separated(
                          itemCount: _userStats.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final stat = _userStats[index];
                            final conversionRate = stat.total > 0
                                ? (stat.sold / stat.total * 100).toStringAsFixed(1)
                                : '0.0';

                            return InkWell(
                              onTap: () => _showUserLeads(stat),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(stat.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                          Text('${stat.branch} · $conversionRate% conv.',
                                              style: TextStyle(fontSize: 11, color: isDark ? Colors.white54 : Colors.black45)),
                                        ],
                                      ),
                                    ),
                                    Expanded(flex: 1, child: Text('${stat.total}', style: const TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                                    Expanded(flex: 1, child: Text('${stat.inProgress}', style: const TextStyle(color: Colors.orange), textAlign: TextAlign.center)),
                                    Expanded(flex: 1, child: Text('${stat.sold}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w600), textAlign: TextAlign.center)),
                                    Expanded(flex: 1, child: Text('${stat.cancelled}', style: const TextStyle(color: Colors.red), textAlign: TextAlign.center)),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _summaryChip(String label, int count, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text('$count', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color)),
            Text(label, style: TextStyle(fontSize: 10, color: color.withOpacity(0.8))),
          ],
        ),
      ),
    );
  }
}

class _UserStat {
  final String uid;
  final String name;
  final String branch;
  int total = 0;
  int inProgress = 0;
  int sold = 0;
  int cancelled = 0;

  _UserStat({required this.uid, required this.name, required this.branch});
}

/// Detail page showing all leads assigned to a specific user by the SME
class _UserLeadsDetailPage extends StatefulWidget {
  final String smeUid;
  final String assignedToUid;
  final String assignedToName;
  final DateTime startDate;
  final DateTime endDate;

  const _UserLeadsDetailPage({
    required this.smeUid,
    required this.assignedToUid,
    required this.assignedToName,
    required this.startDate,
    required this.endDate,
  });

  @override
  State<_UserLeadsDetailPage> createState() => _UserLeadsDetailPageState();
}

class _UserLeadsDetailPageState extends State<_UserLeadsDetailPage> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _leads = [];

  @override
  void initState() {
    super.initState();
    _fetchLeads();
  }

  Future<void> _fetchLeads() async {
    setState(() => _isLoading = true);

    final dayEnd = widget.endDate.add(const Duration(days: 1));

    final snapshot = await FirebaseFirestore.instance
        .collection('follow_ups')
        .where('assigned_by', isEqualTo: widget.smeUid)
        .where('assigned_to', isEqualTo: widget.assignedToUid)
        .where('created_at', isGreaterThanOrEqualTo: Timestamp.fromDate(widget.startDate))
        .where('created_at', isLessThan: Timestamp.fromDate(dayEnd))
        .orderBy('created_at', descending: true)
        .get();

    setState(() {
      _leads = snapshot.docs.map((doc) {
        final data = doc.data();
        data['docId'] = doc.id;
        return data;
      }).toList();
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.assignedToName}\'s Leads'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _leads.isEmpty
              ? const Center(child: Text('No leads found.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _leads.length,
                  itemBuilder: (context, index) {
                    final lead = _leads[index];
                    final name = lead['name'] ?? 'Unknown';
                    final status = lead['status'] ?? 'Unknown';
                    final priority = lead['priority'] ?? 'High';

                    Color statusColor;
                    switch (status) {
                      case 'Sale':
                        statusColor = Colors.green;
                        break;
                      case 'Cancelled':
                        statusColor = Colors.red;
                        break;
                      default:
                        statusColor = Colors.orange;
                    }

                    DateTime? createdAt;
                    if (lead['created_at'] is Timestamp) {
                      createdAt = (lead['created_at'] as Timestamp).toDate();
                    }

                    return GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => PresentFollowUp(docId: lead['docId'])),
                        ).then((_) => _fetchLeads());
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF23242B) : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: isDark ? Colors.black26 : Colors.black.withOpacity(0.06),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 4,
                              height: 50,
                              decoration: BoxDecoration(
                                color: statusColor,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: isDark ? Colors.white : Colors.black87)),
                                  const SizedBox(height: 4),
                                  if (createdAt != null)
                                    Text(DateFormat('dd MMM yyyy, hh:mm a').format(createdAt),
                                        style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.black45)),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: statusColor.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(status, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: statusColor)),
                                ),
                                const SizedBox(height: 4),
                                Text(priority, style: TextStyle(fontSize: 11, color: isDark ? Colors.white38 : Colors.black38)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
