import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:intl/intl.dart';
import 'mass_task_model.dart';
import 'mass_task_users_page.dart';
import 'video_player_dialog.dart';

class AdminTaskListTab extends StatefulWidget {
  final String filterStatus; // 'pending' or 'completed'
  final List<String> branches;

  const AdminTaskListTab({
    super.key,
    required this.filterStatus,
    required this.branches,
  });

  @override
  State<AdminTaskListTab> createState() => _AdminTaskListTabState();
}

class _AdminTaskListTabState extends State<AdminTaskListTab> {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String? _selectedFilterBranch;

  Future<void> _deleteTask(String docId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Task?'),
        content: const Text(
            'Are you sure you want to delete this task? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _firestore.collection('core_tasks').doc(docId).delete();
      try {
        final notifId = docId.hashCode & 0x7FFFFFFF;
        await AwesomeNotifications().cancel(notifId);
      } catch (e) {
        debugPrint(
            'Error cancelling scheduled notification for deleted task: $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Task deleted successfully'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      debugPrint('Error deleting task: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to delete task: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteMassTask(MassTaskGroup group) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Mass Task?'),
        content: Text(
            'Are you sure you want to delete this mass task for all ${group.userTasks.length} users? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final batch = _firestore.batch();
      for (final doc in group.userTasks) {
        batch.delete(doc.reference);
        try {
          final notifId = doc.id.hashCode & 0x7FFFFFFF;
          await AwesomeNotifications().cancel(notifId);
        } catch (_) {}
      }
      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Mass task deleted successfully'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      debugPrint('Error deleting mass task: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to delete mass task: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildBranchFilterHeader(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF101C2E) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.white10 : Colors.black12,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.filter_alt_outlined,
            size: 20,
            color: isDark ? Colors.white70 : const Color(0xFF005BAC),
          ),
          const SizedBox(width: 8),
          Text(
            'Branch:',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF16253B) : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isDark ? Colors.white24 : Colors.black12,
                ),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedFilterBranch,
                  isDense: true,
                  isExpanded: true,
                  hint: Text(
                    'All Branches',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                  ),
                  dropdownColor:
                      isDark ? const Color(0xFF16253B) : Colors.white,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('All Branches'),
                    ),
                    ...widget.branches.map((b) => DropdownMenuItem<String>(
                          value: b,
                          child: Text(b),
                        )),
                  ],
                  onChanged: (val) {
                    setState(() {
                      _selectedFilterBranch = val;
                    });
                  },
                ),
              ),
            ),
          ),
          if (_selectedFilterBranch != null) ...[
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.clear_rounded, size: 18),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: 'Clear filter',
              color: isDark ? Colors.white70 : Colors.black54,
              onPressed: () {
                setState(() {
                  _selectedFilterBranch = null;
                });
              },
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) {
      return const Center(child: Text('User not logged in'));
    }

    final isPendingTab = widget.filterStatus == 'pending';

    return Column(
      children: [
        _buildBranchFilterHeader(isDark),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _firestore
                .collection('core_tasks')
                .where('assigned_by', isEqualTo: currentUserId)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }

              final docs = snapshot.data?.docs ?? [];
              if (docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isPendingTab
                            ? Icons.pending_actions_rounded
                            : Icons.task_alt_rounded,
                        size: 64,
                        color: isDark ? Colors.white24 : Colors.black26,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        isPendingTab ? 'No pending tasks' : 'No completed tasks',
                        style: TextStyle(
                          fontSize: 16,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                );
              }

              // Group by mass_task_id for mass tasks
              final Map<String, List<DocumentSnapshot>> massGroups = {};
              final List<dynamic> displayItems = [];

              for (final doc in docs) {
                final data = doc.data() as Map<String, dynamic>;
                final bool isMass = data['is_mass_task'] == true &&
                    data['mass_task_id'] != null;

                if (isMass) {
                  final String massId = data['mass_task_id'];
                  if (!massGroups.containsKey(massId)) {
                    massGroups[massId] = [];
                  }
                  massGroups[massId]!.add(doc);
                } else {
                  final st = (data['status'] as String? ?? 'pending').toLowerCase();
                  if (st == widget.filterStatus) {
                    // Apply branch filter
                    if (_selectedFilterBranch != null &&
                        _selectedFilterBranch!.isNotEmpty) {
                      final docBranch = (data['assigned_to_branch'] as String? ??
                              data['branch'] ??
                              '')
                          .toString()
                          .trim()
                          .toUpperCase();
                      if (docBranch != _selectedFilterBranch) {
                        continue;
                      }
                    }
                    displayItems.add(doc);
                  }
                }
              }

              massGroups.forEach((massId, docsList) {
                if (docsList.isNotEmpty) {
                  // If branch filter is set, only consider userTasks matching that branch
                  final relevantDocs = _selectedFilterBranch == null
                      ? docsList
                      : docsList.where((d) {
                          final data = d.data() as Map<String, dynamic>;
                          final b = (data['assigned_to_branch'] as String? ??
                                  data['branch'] ??
                                  '')
                              .toString()
                              .trim()
                              .toUpperCase();
                          return b == _selectedFilterBranch;
                        }).toList();

                  if (relevantDocs.isEmpty) return;

                  final totalUsers = relevantDocs.length;
                  final completedCount = relevantDocs
                      .where((d) =>
                          (d.data() as Map<String, dynamic>)['status'] ==
                          'completed')
                      .length;
                  final pendingCount = totalUsers - completedCount;

                  // In pending tab, show mass task if it has pending subtasks. In completed tab, show if it has completed subtasks.
                  final bool shouldInclude =
                      isPendingTab ? pendingCount > 0 : completedCount > 0;

                  if (shouldInclude) {
                    final firstDoc = relevantDocs.first;
                    final data = firstDoc.data() as Map<String, dynamic>;

                    Timestamp? latestTs = data['timestamp'] as Timestamp?;
                    for (final d in relevantDocs) {
                      final ts = (d.data() as Map<String, dynamic>)['timestamp']
                          as Timestamp?;
                      if (ts != null &&
                          (latestTs == null || ts.compareTo(latestTs) > 0)) {
                        latestTs = ts;
                      }
                    }

                    displayItems.add(MassTaskGroup(
                      massTaskId: massId,
                      title: data['title'] ?? '',
                      description: data['description'] ?? '',
                      assignedByName: data['assigned_by_name'] ?? 'Core Team',
                      assignedByEmail: data['assigned_by_email'] ?? '',
                      timestamp: latestTs,
                      userTasks: relevantDocs,
                    ));
                  }
                }
              });

              if (displayItems.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isPendingTab
                            ? Icons.pending_actions_rounded
                            : Icons.task_alt_rounded,
                        size: 64,
                        color: isDark ? Colors.white24 : Colors.black26,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _selectedFilterBranch != null
                            ? 'No tasks found for branch $_selectedFilterBranch'
                            : (isPendingTab
                                ? 'No pending tasks'
                                : 'No completed tasks'),
                        style: TextStyle(
                          fontSize: 16,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                );
              }

              // Sort by timestamp newest first
              displayItems.sort((a, b) {
                final tsA = a is DocumentSnapshot
                    ? (a.data() as Map<String, dynamic>)['timestamp'] as Timestamp?
                    : (a as MassTaskGroup).timestamp;
                final tsB = b is DocumentSnapshot
                    ? (b.data() as Map<String, dynamic>)['timestamp'] as Timestamp?
                    : (b as MassTaskGroup).timestamp;
                if (tsA == null) return 1;
                if (tsB == null) return -1;
                return tsB.compareTo(tsA);
              });

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: displayItems.length,
                itemBuilder: (context, index) {
                  final item = displayItems[index];

                  if (item is MassTaskGroup) {
                    final group = item;
                    final totalUsers = group.userTasks.length;
                    final completedUsers = group.userTasks
                        .where((d) =>
                            (d.data() as Map<String, dynamic>)['status'] ==
                            'completed')
                        .length;
                    final createdTs = group.timestamp;
                    final createdDateStr = createdTs != null
                        ? DateFormat('dd MMM yyyy, hh:mm a')
                            .format(createdTs.toDate())
                        : 'N/A';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      color: isDark ? const Color(0xFF16253B) : Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 1.5,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => MassTaskUsersPage(
                                group: group,
                                initialStatusFilter: widget.filterStatus,
                              ),
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                          color: Colors.blue, width: 1),
                                    ),
                                    child: const Text(
                                      'Mass Task',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: completedUsers == totalUsers
                                          ? Colors.green.withValues(alpha: 0.15)
                                          : Colors.amber.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: completedUsers == totalUsers
                                            ? Colors.green
                                            : Colors.amber,
                                        width: 1,
                                      ),
                                    ),
                                    child: Text(
                                      'Completed: $completedUsers / $totalUsers',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: completedUsers == totalUsers
                                            ? Colors.green
                                            : Colors.amber,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(height: 20),
                              Text(
                                group.title,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                              if (group.description.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  group.description,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color:
                                        isDark ? Colors.white70 : Colors.black87,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Assigned: $createdDateStr',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark
                                          ? Colors.white38
                                          : Colors.black38,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        color: Colors.redAccent, size: 20),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: () => _deleteMassTask(group),
                                    tooltip: 'Delete Mass Task Record',
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }

                  final doc = item as DocumentSnapshot;
                  final data = doc.data() as Map<String, dynamic>;
                  final String docId = doc.id;
                  final String title = data['title'] ?? '';
                  final String assignedToName =
                      data['assigned_to_name'] ?? 'Unknown';
                  final String assignedToEmail =
                      data['assigned_to_email'] ?? '';
                  final String assignedBranch =
                      data['assigned_to_branch'] ?? data['branch'] ?? 'None';
                  final String status = data['status'] ?? 'pending';
                  final Timestamp? createdTs = data['timestamp'] as Timestamp?;
                  final Timestamp? completedTs =
                      data['completed_at'] as Timestamp?;
                  final String note = data['note'] ?? '';

                  final createdDateStr = createdTs != null
                      ? DateFormat('dd MMM yyyy, hh:mm a')
                          .format(createdTs.toDate())
                      : 'N/A';
                  final completedDateStr = completedTs != null
                      ? DateFormat('dd MMM yyyy, hh:mm a')
                          .format(completedTs.toDate())
                      : '';

                  final bool isPending = status == 'pending';

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    color: isDark ? const Color(0xFF16253B) : Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 1.5,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Recipient Name & Branch
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          'To: $assignedToName',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                            color: isDark
                                                ? Colors.white
                                                : Colors.black87,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: isDark
                                                ? Colors.white12
                                                : Colors.black.withValues(alpha: 0.05),
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            assignedBranch,
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color: isDark
                                                  ? Colors.white70
                                                  : Colors.black87,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (assignedToEmail.isNotEmpty)
                                      Text(
                                        assignedToEmail,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isDark
                                              ? Colors.white54
                                              : Colors.black54,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              // Status badge
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: isPending
                                      ? Colors.amber.withValues(alpha: 0.15)
                                      : Colors.green.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color:
                                        isPending ? Colors.amber : Colors.green,
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  isPending ? 'Pending' : 'Completed',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color:
                                        isPending ? Colors.amber : Colors.green,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 20),
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          if ((data['description'] as String? ?? '')
                              .isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              data['description'] as String,
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? Colors.white70 : Colors.black87,
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Text(
                            'Assigned: $createdDateStr',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? Colors.white38 : Colors.black38,
                            ),
                          ),
                          if (!isPending) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Completed: $completedDateStr',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                            if (note.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? const Color(0xFF0F1A2B)
                                      : const Color(0xFFF3F4F6),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'Note: "$note"',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontStyle: FontStyle.italic,
                                    color:
                                        isDark ? Colors.white70 : Colors.black,
                                  ),
                                ),
                              ),
                            ],
                            if (data['attachments'] != null &&
                                (data['attachments'] as List).isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Text(
                                'Attachments:',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color:
                                      isDark ? Colors.white60 : Colors.black54,
                                ),
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                height: 80,
                                child: ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  itemCount:
                                      (data['attachments'] as List).length,
                                  itemBuilder: (context, idx) {
                                    final att =
                                        (data['attachments'] as List)[idx];
                                    final String url = att['url'] ?? '';
                                    final String type = att['type'] ?? 'image';

                                    return GestureDetector(
                                      onTap: () {
                                        if (type == 'video') {
                                          showDialog(
                                            context: context,
                                            barrierColor: Colors.black87,
                                            builder: (context) =>
                                                InAppVideoPlayerDialog(
                                                    videoUrl: url),
                                          );
                                        } else {
                                          showDialog(
                                            context: context,
                                            builder: (context) => Dialog(
                                              backgroundColor:
                                                  Colors.transparent,
                                              insetPadding:
                                                  const EdgeInsets.all(12),
                                              child: Stack(
                                                alignment: Alignment.topRight,
                                                children: [
                                                  InteractiveViewer(
                                                    child: Image.network(url),
                                                  ),
                                                  Positioned(
                                                    top: 8,
                                                    right: 8,
                                                    child: CircleAvatar(
                                                      backgroundColor:
                                                          Colors.black54,
                                                      child: IconButton(
                                                        icon: const Icon(
                                                            Icons.close,
                                                            color: Colors.white),
                                                        onPressed: () =>
                                                            Navigator.pop(
                                                                context),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        }
                                      },
                                      child: Container(
                                        margin: const EdgeInsets.only(right: 8),
                                        width: 80,
                                        height: 80,
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          border: Border.all(
                                            color: type == 'video'
                                                ? Colors.orangeAccent
                                                    .withValues(alpha: 0.7)
                                                : (isDark
                                                    ? Colors.white24
                                                    : Colors.black12),
                                            width: type == 'video' ? 1.5 : 1,
                                          ),
                                          color: isDark
                                              ? Colors.white10
                                              : Colors.black12,
                                        ),
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            if (type == 'image')
                                              ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                child: Image.network(
                                                  url,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (context, error,
                                                          stackTrace) =>
                                                      const Center(
                                                          child: Icon(Icons
                                                              .broken_image)),
                                                ),
                                              )
                                            else
                                              ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(7),
                                                child: Container(
                                                  decoration:
                                                      const BoxDecoration(
                                                    gradient: LinearGradient(
                                                      begin: Alignment.topLeft,
                                                      end:
                                                          Alignment.bottomRight,
                                                      colors: [
                                                        Color(0xFF1A1A2E),
                                                        Color(0xFF16213E)
                                                      ],
                                                    ),
                                                  ),
                                                  child: Center(
                                                    child: Container(
                                                      width: 32,
                                                      height: 32,
                                                      decoration: BoxDecoration(
                                                        shape: BoxShape.circle,
                                                        color: Colors
                                                            .orangeAccent
                                                            .withValues(alpha: 0.9),
                                                        boxShadow: [
                                                          BoxShadow(
                                                            color: Colors
                                                                .orangeAccent
                                                                .withValues(alpha: 0.4),
                                                            blurRadius: 8,
                                                            spreadRadius: 2,
                                                          ),
                                                        ],
                                                      ),
                                                      child: const Icon(
                                                        Icons.play_arrow_rounded,
                                                        color: Colors.white,
                                                        size: 20,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            if (type == 'video')
                                              Positioned(
                                                bottom: 4,
                                                left: 4,
                                                child: Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 4, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: Colors.orangeAccent,
                                                    borderRadius:
                                                        BorderRadius.circular(4),
                                                  ),
                                                  child: const Text(
                                                    'VIDEO',
                                                    style: TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 7,
                                                        fontWeight:
                                                            FontWeight.bold),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ],
                          // Action button
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    color: Colors.redAccent, size: 20),
                                onPressed: () => _deleteTask(docId),
                                tooltip: 'Delete Task Record',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
