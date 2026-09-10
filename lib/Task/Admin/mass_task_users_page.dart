import 'package:flutter/material.dart';
import 'mass_task_model.dart';
import 'user_task_detail_page.dart';

class MassTaskUsersPage extends StatefulWidget {
  final MassTaskGroup group;
  final String? initialStatusFilter; // 'pending', 'completed', or null
  const MassTaskUsersPage({super.key, required this.group, this.initialStatusFilter});

  @override
  State<MassTaskUsersPage> createState() => _MassTaskUsersPageState();
}

class _MassTaskUsersPageState extends State<MassTaskUsersPage> {
  String? _selectedBranch;
  late String _selectedStatus;

  @override
  void initState() {
    super.initState();
    _selectedStatus = widget.initialStatusFilter ?? 'all';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Retrieve unique branches from the user tasks in this group
    final Set<String> uniqueBranches = {};
    for (final doc in widget.group.userTasks) {
      final data = doc.data() as Map<String, dynamic>;
      final branch = (data['assigned_to_branch'] as String? ?? data['branch'] ?? 'Unknown')
          .toString()
          .trim()
          .toUpperCase();
      if (branch.isNotEmpty) {
        uniqueBranches.add(branch);
      }
    }
    final sortedBranches = uniqueBranches.toList()..sort();

    // Overall group counts (unfiltered by status, but respects branch if selected)
    final branchTasks = widget.group.userTasks.where((doc) {
      if (_selectedBranch == null || _selectedBranch!.isEmpty) return true;
      final data = doc.data() as Map<String, dynamic>;
      final branch = (data['assigned_to_branch'] as String? ?? data['branch'] ?? 'Unknown')
          .toString()
          .trim()
          .toUpperCase();
      return branch == _selectedBranch;
    }).toList();

    final int totalInScope = branchTasks.length;
    final int completedInScope = branchTasks.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return (data['status'] ?? 'pending').toString().toLowerCase() == 'completed';
    }).length;
    final int pendingInScope = totalInScope - completedInScope;
    final double completionRatio = totalInScope > 0 ? completedInScope / totalInScope : 0.0;
    final int completionPercent = (completionRatio * 100).round();

    // Filtered tasks list (respects both branch and status filter)
    final filteredTasks = branchTasks.where((doc) {
      if (_selectedStatus == 'all') return true;
      final data = doc.data() as Map<String, dynamic>;
      final st = (data['status'] as String? ?? 'pending').toLowerCase();
      return st == _selectedStatus;
    }).toList();

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A1628) : const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.group.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            Text(
              'Assigned by ${widget.group.assignedByName.isNotEmpty ? widget.group.assignedByName : "Admin"}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.85),
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        elevation: 0,
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
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Card: Description & Progress Overview
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF132238) : Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.group.description.isNotEmpty) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.subject_rounded,
                        size: 18,
                        color: isDark ? const Color(0xFF4DD0E1) : const Color(0xFF005BAC),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.group.description,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            height: 1.35,
                            color: isDark ? Colors.white70 : const Color(0xFF334155),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],

                // Completion Progress Bar
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Overall Progress',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                    Text(
                      '$completedInScope / $totalInScope ($completionPercent%)',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: completionPercent == 100
                            ? const Color(0xFF10B981)
                            : const Color(0xFF00897B),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: completionRatio,
                    minHeight: 7,
                    backgroundColor: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      completionPercent == 100
                          ? const Color(0xFF10B981)
                          : const Color(0xFF00897B),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Filters: Branch Dropdown & Quick Status Filter Chips
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                // Branch Selector
                Expanded(
                  child: Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF16253B) : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
                      ),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedBranch,
                        hint: Row(
                          children: [
                            Icon(Icons.apartment_rounded,
                                size: 16,
                                color: isDark ? Colors.white54 : Colors.black45),
                            const SizedBox(width: 6),
                            Text(
                              'All Branches',
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? Colors.white60 : Colors.black54,
                              ),
                            ),
                          ],
                        ),
                        isExpanded: true,
                        dropdownColor: isDark ? const Color(0xFF16253B) : Colors.white,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        items: [
                          DropdownMenuItem<String>(
                            value: null,
                            child: Row(
                              children: [
                                Icon(Icons.apartment_rounded,
                                    size: 16,
                                    color: isDark ? Colors.white54 : Colors.black45),
                                const SizedBox(width: 6),
                                const Text('All Branches'),
                              ],
                            ),
                          ),
                          ...sortedBranches.map((br) => DropdownMenuItem<String>(
                                value: br,
                                child: Text(br),
                              )),
                        ],
                        onChanged: (val) {
                          setState(() {
                            _selectedBranch = val;
                          });
                        },
                      ),
                    ),
                  ),
                ),
                if (_selectedBranch != null) ...[
                  const SizedBox(width: 6),
                  IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 18),
                    tooltip: 'Clear Branch',
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(8),
                    color: isDark ? Colors.white60 : Colors.black54,
                    onPressed: () {
                      setState(() {
                        _selectedBranch = null;
                      });
                    },
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 10),

          // Status Filter Segment Chips
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                _buildStatusChip(
                  label: 'All',
                  count: totalInScope,
                  statusKey: 'all',
                  isDark: isDark,
                  activeColor: const Color(0xFF005BAC),
                ),
                const SizedBox(width: 8),
                _buildStatusChip(
                  label: 'Pending',
                  count: pendingInScope,
                  statusKey: 'pending',
                  isDark: isDark,
                  activeColor: const Color(0xFFF59E0B),
                ),
                const SizedBox(width: 8),
                _buildStatusChip(
                  label: 'Completed',
                  count: completedInScope,
                  statusKey: 'completed',
                  isDark: isDark,
                  activeColor: const Color(0xFF10B981),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Recipients Count & Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recipients (${filteredTasks.length})',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: isDark ? Colors.white70 : const Color(0xFF475569),
                  ),
                ),
                if (_selectedBranch != null || _selectedStatus != 'all')
                  Text(
                    'Filtered',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? const Color(0xFF4DD0E1) : const Color(0xFF005BAC),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Recipients List
          Expanded(
            child: filteredTasks.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.people_outline_rounded,
                            size: 48,
                            color: isDark ? Colors.white24 : Colors.black26,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No recipients match the selected filter',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: isDark ? Colors.white54 : Colors.black45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: filteredTasks.length,
                    itemBuilder: (context, index) {
                      final doc = filteredTasks[index];
                      final data = doc.data() as Map<String, dynamic>;
                      final String name = (data['assigned_to_name'] as String? ?? '').trim();
                      final displayName = name.isNotEmpty ? name : 'Unknown User';
                      final String status = (data['status'] as String? ?? 'pending').toLowerCase();
                      final bool isCompleted = status == 'completed';
                      final String branch = (data['assigned_to_branch'] as String? ??
                              data['branch'] ??
                              'Unknown')
                          .toString()
                          .trim()
                          .toUpperCase();

                      // First letter for avatar
                      final initial = displayName.isNotEmpty
                          ? displayName[0].toUpperCase()
                          : '?';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF16253B) : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isCompleted
                                ? const Color(0xFF10B981).withValues(alpha: isDark ? 0.35 : 0.25)
                                : isDark
                                    ? Colors.white10
                                    : const Color(0xFFE2E8F0),
                            width: isCompleted ? 1.2 : 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                              blurRadius: 4,
                              offset: const Offset(0, 1.5),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => UserTaskDetailPage(taskDoc: doc),
                                ),
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              child: Row(
                                children: [
                                  // User Initial Avatar
                                  CircleAvatar(
                                    radius: 20,
                                    backgroundColor: isCompleted
                                        ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                        : (isDark
                                            ? const Color(0xFF233554)
                                            : const Color(0xFFE2E8F0)),
                                    child: Text(
                                      initial,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                        color: isCompleted
                                            ? const Color(0xFF10B981)
                                            : (isDark ? Colors.white70 : const Color(0xFF334155)),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),

                                  // Name and Branch
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          displayName,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.business_rounded,
                                              size: 13,
                                              color: isDark ? Colors.white38 : Colors.black38,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              branch,
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                                color: isDark ? Colors.white60 : const Color(0xFF64748B),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Status Badge
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 9, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isCompleted
                                          ? const Color(0xFF10B981).withValues(alpha: 0.12)
                                          : const Color(0xFFF59E0B).withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: isCompleted
                                            ? const Color(0xFF10B981).withValues(alpha: 0.5)
                                            : const Color(0xFFF59E0B).withValues(alpha: 0.5),
                                        width: 1,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          isCompleted
                                              ? Icons.check_circle_rounded
                                              : Icons.schedule_rounded,
                                          size: 13,
                                          color: isCompleted
                                              ? const Color(0xFF10B981)
                                              : const Color(0xFFF59E0B),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          isCompleted ? 'Completed' : 'Pending',
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.bold,
                                            color: isCompleted
                                              ? const Color(0xFF10B981)
                                              : const Color(0xFFF59E0B),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.chevron_right_rounded,
                                    size: 18,
                                    color: isDark ? Colors.white24 : Colors.black26,
                                  ),
                                ],
                              ),
                            ),
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

  Widget _buildStatusChip({
    required String label,
    required int count,
    required String statusKey,
    required bool isDark,
    required Color activeColor,
  }) {
    final bool isSelected = _selectedStatus == statusKey;

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            setState(() {
              _selectedStatus = statusKey;
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(
              color: isSelected
                  ? activeColor.withValues(alpha: isDark ? 0.22 : 0.12)
                  : (isDark ? const Color(0xFF16253B) : Colors.white),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected
                    ? activeColor
                    : (isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected
                        ? activeColor
                        : (isDark ? Colors.white70 : const Color(0xFF475569)),
                  ),
                ),
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? activeColor
                        : (isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: isSelected
                          ? Colors.white
                          : (isDark ? Colors.white70 : const Color(0xFF64748B)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
