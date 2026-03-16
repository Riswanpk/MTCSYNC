import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../Leads/presentfollowup.dart';

class SmeDailyDashboard extends StatefulWidget {
  const SmeDailyDashboard({super.key});

  @override
  State<SmeDailyDashboard> createState() => _SmeDailyDashboardState();
}

class _SmeDailyDashboardState extends State<SmeDailyDashboard> {
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = true;
  List<Map<String, dynamic>> _leads = [];
  int _totalToday = 0;
  int _inProgress = 0;
  int _sold = 0;
  int _cancelled = 0;

  @override
  void initState() {
    super.initState();
    _fetchDailyLeads();
  }

  Future<void> _fetchDailyLeads() async {
    setState(() => _isLoading = true);

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _isLoading = false);
      return;
    }

    final dayStart = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    final dayEnd = dayStart.add(const Duration(days: 1));

    final snapshot = await FirebaseFirestore.instance
        .collection('follow_ups')
        .where('assigned_by', isEqualTo: uid)
        .where('created_at', isGreaterThanOrEqualTo: Timestamp.fromDate(dayStart))
        .where('created_at', isLessThan: Timestamp.fromDate(dayEnd))
        .orderBy('created_at', descending: true)
        .get();

    final leads = <Map<String, dynamic>>[];
    int inProgress = 0, sold = 0, cancelled = 0;

    for (final doc in snapshot.docs) {
      final data = doc.data();
      data['docId'] = doc.id;
      leads.add(data);

      switch (data['status']) {
        case 'In Progress':
          inProgress++;
          break;
        case 'Sale':
          sold++;
          break;
        case 'Cancelled':
          cancelled++;
          break;
      }
    }

    setState(() {
      _leads = leads;
      _totalToday = leads.length;
      _inProgress = inProgress;
      _sold = sold;
      _cancelled = cancelled;
      _isLoading = false;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      _fetchDailyLeads();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dateStr = DateFormat('dd MMM yyyy').format(_selectedDate);
    final isToday = DateFormat('yyyy-MM-dd').format(_selectedDate) ==
        DateFormat('yyyy-MM-dd').format(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: Text(isToday ? "Today's Leads" : 'Leads on $dateStr'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today),
            tooltip: 'Pick date',
            onPressed: _pickDate,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchDailyLeads,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Summary cards
                    GridView.count(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      shrinkWrap: true,
                      childAspectRatio: 1.8,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        _statCard('Total', _totalToday, const Color(0xFF005BAC), Icons.leaderboard, isDark),
                        _statCard('In Progress', _inProgress, Colors.orange, Icons.hourglass_top, isDark),
                        _statCard('Sold', _sold, Colors.green, Icons.check_circle, isDark),
                        _statCard('Cancelled', _cancelled, Colors.red, Icons.cancel, isDark),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Leads List',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_leads.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            children: [
                              Icon(Icons.inbox_rounded, size: 48, color: isDark ? Colors.white30 : Colors.black26),
                              const SizedBox(height: 8),
                              Text('No leads for this day', style: TextStyle(color: isDark ? Colors.white38 : Colors.black38)),
                            ],
                          ),
                        ),
                      )
                    else
                      ...List.generate(_leads.length, (index) {
                        final lead = _leads[index];
                        final name = lead['name'] ?? 'Unknown';
                        final status = lead['status'] ?? 'Unknown';
                        final assignedTo = lead['assigned_to_name'] ?? 'Unknown';
                        final branch = lead['branch'] ?? '';
                        final priority = lead['priority'] ?? 'High';

                        DateTime? createdAt;
                        if (lead['created_at'] is Timestamp) {
                          createdAt = (lead['created_at'] as Timestamp).toDate();
                        }

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

                        return GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => PresentFollowUp(docId: lead['docId'])),
                            ).then((_) => _fetchDailyLeads());
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
                                      Text(name,
                                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: isDark ? Colors.white : Colors.black87)),
                                      const SizedBox(height: 4),
                                      Text('Assigned to: $assignedTo ($branch)',
                                          style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.black54)),
                                      if (createdAt != null)
                                        Text('Time: ${DateFormat('hh:mm a').format(createdAt)}',
                                            style: TextStyle(fontSize: 11, color: isDark ? Colors.white38 : Colors.black38)),
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
                      }),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _statCard(String title, int count, Color color, IconData icon, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [color.withOpacity(0.3), color.withOpacity(0.15)]
              : [color.withOpacity(0.15), color.withOpacity(0.05)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const Spacer(),
              Text(
                '$count',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? Colors.white70 : Colors.black54)),
        ],
      ),
    );
  }
}
