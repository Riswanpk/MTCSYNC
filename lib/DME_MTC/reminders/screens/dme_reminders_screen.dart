import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/dme_reminder_model.dart';
import '../services/dme_reminder_service.dart';
import '../../models/dme_user.dart';
import '../../core/services/dme_supabase_service.dart';
import '../../users/services/dme_user_service.dart';
import 'dme_reminder_detail_screen.dart';

class DmeRemindersScreen extends StatefulWidget {
  final DmeUser dmeUser;

  const DmeRemindersScreen({super.key, required this.dmeUser});

  @override
  State<DmeRemindersScreen> createState() => _DmeRemindersScreenState();
}

class _DmeRemindersScreenState extends State<DmeRemindersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<DmeReminderModel> _allReminders = [];
  bool _loading = true;
  String _searchQuery = '';
  int? _selectedBranchId;
  List<Map<String, dynamic>> _branches = [];

  static const _blue = Color(0xFF005BAC);
  static const _green = Color(0xFF8CC63F);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadBranchesAndReminders();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadBranchesAndReminders() async {
    setState(() => _loading = true);
    final branches = await DmeMtcSupabaseService.instance.getBranches();

    List<int>? userBranchIds;
    if (!widget.dmeUser.isAdmin) {
      userBranchIds =
          await DmeUserService.instance.getUserBranchIds(widget.dmeUser.id);
    }

    final targetBranchIds = widget.dmeUser.isAdmin
        ? (_selectedBranchId != null ? [_selectedBranchId!] : null)
        : (_selectedBranchId != null
            ? [_selectedBranchId!]
            : (userBranchIds != null && userBranchIds.isNotEmpty
                ? userBranchIds
                : null));

    final reminders = await DmeReminderService.instance.getReminders(
      branchIds: targetBranchIds,
    );

    if (mounted) {
      setState(() {
        _branches = widget.dmeUser.isAdmin
            ? branches
            : branches
                .where((b) =>
                    userBranchIds != null &&
                    userBranchIds.contains(b['id'] as int?))
                .toList();
        _allReminders = reminders;
        _loading = false;
      });
    }
  }

  List<DmeReminderModel> _getFilteredList(String status) {
    return _allReminders.where((r) {
      final matchesStatus = status == 'pending'
          ? (r.status == 'pending')
          : status == 'call_again'
              ? (r.status == 'call_again')
              : (r.status == 'completed' || r.status == 'dismissed');

      if (!matchesStatus) return false;

      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final name = (r.customerName ?? '').toLowerCase();
        final phone = (r.customerPhone ?? '').toLowerCase();
        return name.contains(query) || phone.contains(query);
      }

      return true;
    }).toList();
  }

  Future<void> _makeCall(String? phone) async {
    if (phone == null || phone.isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reminders & Calls'),
        backgroundColor: _blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.sync_rounded),
            tooltip: 'Sync Reminders from Customers',
            onPressed: () async {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Syncing reminders from customer purchases...')),
              );
              final count = await DmeReminderService.instance.syncRemindersFromCustomers();
              await _loadBranchesAndReminders();
              if (context.mounted) {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(count > 0
                        ? 'Generated $count new reminders!'
                        : 'All customer reminders are up to date.'),
                  ),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Reload',
            onPressed: _loadBranchesAndReminders,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: _green,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Pending'),
            Tab(text: 'Call Again'),
            Tab(text: 'Completed'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Search & Branch Filter Bar
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search customer or phone...',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: isDark ? const Color(0xFF1A2332) : Colors.white,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (val) => setState(() => _searchQuery = val),
                  ),
                ),
                if (widget.dmeUser.isAdmin && _branches.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  DropdownButton<int?>(
                    value: _selectedBranchId,
                    hint: const Text('All Branches'),
                    underline: const SizedBox(),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('All Branches'),
                      ),
                      ..._branches.map((b) => DropdownMenuItem<int?>(
                            value: b['id'] as int?,
                            child: Text(b['name'] as String? ?? ''),
                          )),
                    ],
                    onChanged: (val) {
                      setState(() => _selectedBranchId = val);
                      _loadBranchesAndReminders();
                    },
                  ),
                ],
              ],
            ),
          ),

          // Tab Views
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildReminderList(_getFilteredList('pending'), isDark),
                      _buildReminderList(_getFilteredList('call_again'), isDark),
                      _buildReminderList(_getFilteredList('completed'), isDark),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildReminderList(List<DmeReminderModel> list, bool isDark) {
    if (list.isEmpty) {
      return const Center(
        child: Text(
          'No reminders found',
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadBranchesAndReminders,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: list.length,
        itemBuilder: (context, index) {
          final r = list[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            color: isDark ? const Color(0xFF1A2332) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              title: Text(
                r.customerName ?? 'Unknown Customer',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text('Phone: ${r.customerPhone ?? 'N/A'}'),
                  Text(
                    'Reminder Date: ${_formatDate(r.reminderDate)}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  if (r.purchasedForBranchName.isNotEmpty)
                    Text(
                      'Branch: ${r.purchasedForBranchName}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.phone, color: _green),
                    onPressed: () => _makeCall(r.customerPhone),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.grey),
                ],
              ),
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DmeReminderDetailScreen(
                      reminder: r,
                      dmeUser: widget.dmeUser,
                    ),
                  ),
                );
                _loadBranchesAndReminders();
              },
            ),
          );
        },
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
