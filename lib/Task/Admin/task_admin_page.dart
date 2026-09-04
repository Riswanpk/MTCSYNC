import 'package:flutter/material.dart';
import 'assign_task_tab.dart';
import 'admin_task_list_tab.dart';

class CoreTeamTaskPage extends StatefulWidget {
  const CoreTeamTaskPage({super.key});

  @override
  State<CoreTeamTaskPage> createState() => _CoreTeamTaskPageState();
}

class _CoreTeamTaskPageState extends State<CoreTeamTaskPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final List<String> _branches = [
    'BGR', 'CBE', 'CHN', 'CLT', 'EKM', 'JBL', 'KKM', 'KSD',
    'KTM', 'PKD', 'PKT', 'PMN', 'TRR', 'TSR', 'TLY', 'TVM',
    'UDP', 'VDK', 'WND',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0A1628) : const Color(0xFFF6F7FB),
      appBar: AppBar(
        title: const Text('Core Team Tasks'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF005BAC), Color(0xFF00897B)],
            ),
          ),
        ),
        foregroundColor: Colors.white,
        elevation: 4,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle:
              const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          tabs: const [
            Tab(icon: Icon(Icons.add_task_rounded), text: 'Assign Task'),
            Tab(icon: Icon(Icons.pending_actions_rounded), text: 'Pending'),
            Tab(icon: Icon(Icons.task_alt_rounded), text: 'Completed'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          AssignTaskTab(
            branches: _branches,
            onTaskAssigned: () {
              // Jump to Pending tasks tab
              _tabController.animateTo(1);
            },
          ),
          AdminTaskListTab(
            filterStatus: 'pending',
            branches: _branches,
          ),
          AdminTaskListTab(
            filterStatus: 'completed',
            branches: _branches,
          ),
        ],
      ),
    );
  }
}
