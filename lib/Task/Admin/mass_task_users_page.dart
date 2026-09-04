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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Retrieve unique branches from the user tasks in this group
    final Set<String> uniqueBranches = {};
    for (final doc in widget.group.userTasks) {
      final data = doc.data() as Map<String, dynamic>;
      final branch = (data['assigned_to_branch'] as String? ?? data['branch'] ?? 'Unknown').toString().trim().toUpperCase();
      if (branch.isNotEmpty) {
        uniqueBranches.add(branch);
      }
    }
    final sortedBranches = uniqueBranches.toList()..sort();

    // Filtered tasks list
    final filteredTasks = widget.group.userTasks.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      if (widget.initialStatusFilter != null) {
        final st = (data['status'] as String? ?? 'pending').toLowerCase();
        if (st != widget.initialStatusFilter) return false;
      }
      if (_selectedBranch == null || _selectedBranch!.isEmpty) {
        return true;
      }
      final branch = (data['assigned_to_branch'] as String? ?? data['branch'] ?? 'Unknown').toString().trim().toUpperCase();
      return branch == _selectedBranch;
    }).toList();

    // Calculate completions for the FILTERED tasks
    final totalFiltered = filteredTasks.length;
    final completedFiltered = filteredTasks.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return (data['status'] ?? 'pending') == 'completed';
    }).length;

    final double completionRatio = totalFiltered > 0 ? completedFiltered / totalFiltered : 0.0;
    final int completionPercent = (completionRatio * 100).round();

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A1628) : const Color(0xFFF6F7FB),
      appBar: AppBar(
        title: Text(widget.group.title),
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
          // Description Card
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Card(
              color: isDark ? const Color(0xFF16253B) : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Description',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.group.description.isNotEmpty ? widget.group.description : 'No description provided.',
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Branch Filter Dropdown
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                Text(
                  'Filter Branch: ',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: isDark ? Colors.white70 : Colors.black,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF16253B) : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isDark ? Colors.white24 : Colors.black12,
                      ),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedBranch,
                        hint: const Text('Show All Branches'),
                        isExpanded: true,
                        dropdownColor: isDark ? const Color(0xFF16253B) : Colors.white,
                        style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                        items: [
                          const DropdownMenuItem<String>(
                            value: null,
                            child: Text('All Branches'),
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
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Completion Progress Bar Card
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Card(
              color: isDark ? const Color(0xFF16253B) : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Filtered Completion Rate',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                        ),
                        Text(
                          '$completedFiltered / $totalFiltered ($completionPercent%)',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Color(0xFF00897B),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: completionRatio,
                        minHeight: 10,
                        backgroundColor: isDark ? Colors.white12 : Colors.black12,
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF00897B)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Text(
              'Recipients Status:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: filteredTasks.isEmpty
                ? Center(
                    child: Text(
                      'No recipients found in selected branch',
                      style: TextStyle(
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    itemCount: filteredTasks.length,
                    itemBuilder: (context, index) {
                      final doc = filteredTasks[index];
                      final data = doc.data() as Map<String, dynamic>;
                      final String name = data['assigned_to_name'] ?? 'Unknown User';
                      final String email = data['assigned_to_email'] ?? '';
                      final String status = data['status'] ?? 'pending';
                      final bool isCompleted = status == 'completed';
                      final String branch = (data['assigned_to_branch'] as String? ?? data['branch'] ?? 'Unknown').toString().trim().toUpperCase();

                      return Card(
                        color: isDark ? const Color(0xFF1E2F4C) : Colors.white,
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text(
                            name,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          subtitle: Text(
                            '$email • Branch: $branch',
                            style: TextStyle(
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                          ),
                          trailing: isCompleted
                              ? const Icon(Icons.check_circle_rounded, color: Colors.green)
                              : const Icon(Icons.cancel_rounded, color: Colors.red),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => UserTaskDetailPage(taskDoc: doc),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
