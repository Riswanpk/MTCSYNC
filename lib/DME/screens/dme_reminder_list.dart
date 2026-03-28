import 'package:flutter/material.dart';
import '../models/dme_reminder.dart';
import '../services/dme_supabase_service.dart';
import '../services/dme_reminder_scheduler.dart';
import 'dme_reminder_detail.dart';
import '../../Navigation/user_cache_service.dart';

class DmeReminderListPage extends StatefulWidget {
  const DmeReminderListPage({super.key});

  @override
  State<DmeReminderListPage> createState() => _DmeReminderListPageState();
}

class _DmeReminderListPageState extends State<DmeReminderListPage> {
  final _svc = DmeSupabaseService.instance;
  final _scheduler = DmeReminderScheduler.instance;

  List<DmeReminder> _todayReminders = [];
  List<DmeReminder> _previousDaysReminders = [];
  bool _loading = true;
  bool _expandPrevious = false;
  List<int> _userBranchIds = [];

  @override
  void initState() {
    super.initState();
    _loadReminders();
  }

  Future<void> _loadReminders() async {
    setState(() => _loading = true);
    try {
      final firebaseUid = UserCacheService.instance.uid;
      if (firebaseUid == null) throw Exception('User not authenticated');
      
      final currentUser = await _svc.getCurrentUser(firebaseUid);
      if (currentUser == null) throw Exception('DME user not found');
      
      _userBranchIds = await _svc.getUserBranchIds(currentUser.id);
      
      final today = await _scheduler.getRemindersForToday(_userBranchIds);
      final previous = await _scheduler.getPendingFromPreviousDays(_userBranchIds);

      if (mounted) {
        setState(() {
          _todayReminders = today;
          _previousDaysReminders = previous;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading reminders: $e'), 
            backgroundColor: Colors.red),
        );
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Call Reminders'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _loadReminders,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _todayReminders.isEmpty && _previousDaysReminders.isEmpty
              ? _buildEmptyState()
              : _buildReminderList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.done_all, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          const Text(
            'No pending call reminders',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          const Text(
            'All customers have been contacted!',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildReminderList() {
    return RefreshIndicator(
      onRefresh: _loadReminders,
      child: ListView(
        children: [
          // Today's Reminders Section
          if (_todayReminders.isNotEmpty)
            _buildSection(
              title: "Today's Reminders",
              count: _todayReminders.length,
              reminders: _todayReminders,
              isExpanded: true,
              color: const Color(0xFF005BAC),
            ),
          
          // Pending from Previous Days Section
          if (_previousDaysReminders.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildSection(
              title: 'Pending from Previous Days',
              count: _previousDaysReminders.length,
              reminders: _previousDaysReminders,
              isExpanded: _expandPrevious,
              onExpandToggle: (expanded) {
                setState(() => _expandPrevious = expanded);
              },
              color: Colors.orange,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required int count,
    required List<DmeReminder> reminders,
    required bool isExpanded,
    required Color color,
    ValueChanged<bool>? onExpandToggle,
  }) {
    return Column(
      children: [
        InkWell(
          onTap: onExpandToggle != null
              ? () => onExpandToggle(!isExpanded)
              : null,
          child: Container(
            padding: const EdgeInsets.all(16),
            color: color.withOpacity(0.1),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: color,
                        ),
                      ),
                      Text(
                        '$count ${count == 1 ? 'reminder' : 'reminders'}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onExpandToggle != null)
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: color,
                  ),
              ],
            ),
          ),
        ),
        if (isExpanded)
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: reminders.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, index) => _buildReminderTile(reminders[index]),
          ),
      ],
    );
  }

  Widget _buildReminderTile(DmeReminder reminder) {
    final isOverdue = DmeReminderScheduler.isOverdue(reminder);
    final daysUntil = DmeReminderScheduler.daysUntilReminder(reminder.reminderDate);
    
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      leading: FutureBuilder(
        future: Future.value(isOverdue),
        builder: (_, __) => CircleAvatar(
          backgroundColor: isOverdue ? Colors.red[100] : Colors.blue[50],
          child: Icon(
            Icons.phone_in_talk,
            color: isOverdue ? Colors.red : const Color(0xFF005BAC),
          ),
        ),
      ),
      title: Text(
        reminder.customerName ?? 'Unknown',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: isOverdue ? Colors.red : Colors.black87,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Text(
            reminder.customerPhone ?? '',
            style: const TextStyle(fontSize: 12),
          ),
          if (reminder.customerAddress != null && reminder.customerAddress!.isNotEmpty)
            Text(
              reminder.customerAddress!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          if (isOverdue)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'OVERDUE - Was due ${daysUntil.abs()} days ago',
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
      trailing: _buildTrailingBadge(reminder),
      onTap: () => _navigateToDetail(reminder),
    );
  }

  Widget _buildTrailingBadge(DmeReminder reminder) {
    final dateStr = DmeReminderScheduler.formatReminderDate(reminder.reminderDate);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          dateStr,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 4),
        Badge(
          label: Text(
            reminder.lastPurchaseDate.year == DateTime.now().year
                ? '${reminder.lastPurchaseDate.month}/${reminder.lastPurchaseDate.day}'
                : '${reminder.lastPurchaseDate.month}/${reminder.lastPurchaseDate.day}/${reminder.lastPurchaseDate.year}',
            style: const TextStyle(fontSize: 10, color: Colors.white),
          ),
          backgroundColor: Colors.amber,
        ),
      ],
    );
  }

  void _navigateToDetail(DmeReminder reminder) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DmeReminderDetailPage(reminder: reminder),
      ),
    );

    // Refresh if reminder was marked as complete
    if (result == 'completed' && mounted) {
      _loadReminders();
    }
  }
}
