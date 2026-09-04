import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../Navigation/user_cache_service.dart';

class AssignTaskTab extends StatefulWidget {
  final List<String> branches;
  final VoidCallback onTaskAssigned;

  const AssignTaskTab({
    super.key,
    required this.branches,
    required this.onTaskAssigned,
  });

  @override
  State<AssignTaskTab> createState() => _AssignTaskTabState();
}

class _AssignTaskTabState extends State<AssignTaskTab> {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String? _selectedBranch;
  Map<String, dynamic>? _selectedUser;
  final Set<String> _selectedRoles = {};
  final TextEditingController _taskNameController = TextEditingController();
  final TextEditingController _taskController = TextEditingController();
  bool _isAssigning = false;

  List<Map<String, dynamic>> _eligibleUsers = [];
  List<Map<String, dynamic>> _filteredUsers = [];
  bool _isLoadingUsers = true;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    _taskNameController.dispose();
    _taskController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    try {
      final cachedUsers =
          await UserCacheService.instance.getAllUsers(forceRefresh: true);
      final eligible = cachedUsers.where((u) {
        final role = (u['role'] as String? ?? '').toLowerCase();
        return role == 'sales' || role == 'manager' || role == 'asst_manager';
      }).toList();

      eligible.sort((a, b) {
        final nameA = (a['username'] as String? ?? '').toLowerCase();
        final nameB = (b['username'] as String? ?? '').toLowerCase();
        return nameA.compareTo(nameB);
      });

      if (mounted) {
        setState(() {
          _eligibleUsers = eligible;
          _filteredUsers = eligible;
          _isLoadingUsers = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading users: $e');
      if (mounted) {
        setState(() => _isLoadingUsers = false);
      }
    }
  }

  void _filterUsers(String query) {
    setState(() {
      final branchFiltered = _eligibleUsers.where((u) {
        final uBranch = (u['branch'] as String? ?? '').toUpperCase().trim();
        return _selectedBranch == null || uBranch == _selectedBranch;
      }).toList();

      if (query.isEmpty) {
        _filteredUsers = branchFiltered;
      } else {
        final lower = query.toLowerCase();
        _filteredUsers = branchFiltered.where((u) {
          final name = (u['username'] as String? ?? '').toLowerCase();
          final email = (u['email'] as String? ?? '').toLowerCase();
          final branch = (u['branch'] as String? ?? '').toLowerCase();
          return name.contains(lower) ||
              email.contains(lower) ||
              branch.contains(lower);
        }).toList();
      }
    });
  }

  Future<void> _assignTask() async {
    final taskName = _taskNameController.text.trim();
    final taskDescription = _taskController.text.trim();
    if (taskName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a task name')),
      );
      return;
    }
    if (taskDescription.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a task description')),
      );
      return;
    }

    List<Map<String, dynamic>> targetUsers = [];
    if (_selectedRoles.isNotEmpty) {
      targetUsers = _eligibleUsers.where((u) {
        final role = (u['role'] as String? ?? '').toLowerCase();
        return _selectedRoles.contains(role);
      }).toList();

      if (targetUsers.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No users found for selected role(s)')),
        );
        return;
      }
    } else {
      if (_selectedUser == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Please select a role option or a recipient user')),
        );
        return;
      }
      targetUsers = [_selectedUser!];
    }

    setState(() => _isAssigning = true);

    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) throw Exception('No authenticated user found');

      final userCache = UserCacheService.instance;
      await userCache.ensureLoaded();
      final assignerName =
          userCache.username ?? currentUser.email ?? 'Core Team';
      final assignerEmail = userCache.email ?? currentUser.email ?? '';

      final String? massTaskId = targetUsers.length > 1
          ? 'mass_${DateTime.now().millisecondsSinceEpoch}'
          : null;

      for (final recipient in targetUsers) {
        final recipientUid = recipient['uid'] ?? recipient['id'] ?? '';
        final recipientEmail = recipient['email'] ?? '';
        final recipientName = recipient['username'] ?? '';

        if (recipientUid.toString().isEmpty) continue;

        // 1. Add to Firestore collection core_tasks
        final docRef = await _firestore.collection('core_tasks').add({
          'title': taskName,
          'description': taskDescription,
          'assigned_to': recipientUid,
          'assigned_to_email': recipientEmail,
          'assigned_to_name': recipientName,
          'assigned_to_branch': recipient['branch'] ?? 'None',
          'assigned_by': currentUser.uid,
          'assigned_by_name': assignerName,
          'assigned_by_email': assignerEmail,
          'status': 'pending',
          'timestamp': FieldValue.serverTimestamp(),
          'note': '',
          'completed_at': null,
          'is_mass_task': massTaskId != null,
          'mass_task_id': massTaskId,
        });

        // 2. Trigger push notification via Cloud Function
        unawaited(() async {
          try {
            await FirebaseFunctions.instanceFor(region: 'asia-south1')
                .httpsCallable('sendLeadAssignmentNotification')
                .call(<String, dynamic>{
              'recipientUid': recipientUid,
              'title': 'New Task Assigned',
              'body': 'Core Team assigned you a new task: "$taskName"',
              'notifType': 'core_task_assignment',
              'leadDocId': docRef.id,
            });
          } catch (error) {
            debugPrint('FCM Warning: failed to send task notification: $error');
          }
        }());
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(targetUsers.length > 1
                ? 'Tasks assigned successfully to ${targetUsers.length} users!'
                : 'Task assigned successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        _taskNameController.clear();
        _taskController.clear();
        setState(() {
          _selectedRoles.clear();
          _selectedBranch = null;
          _selectedUser = null;
          _filteredUsers = _eligibleUsers;
        });

        widget.onTaskAssigned();
      }
    } catch (e) {
      debugPrint('Error assigning task: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isAssigning = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isRoleActive = _selectedRoles.isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Assign a New Task',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 16),
          Card(
            color: isDark ? const Color(0xFF16253B) : Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '1. Target Role (Mass Assign)',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildRoleSelector(isDark),
                  const SizedBox(height: 20),
                  Text(
                    '2. Select Branch',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isRoleActive
                          ? (isDark ? Colors.white30 : Colors.black26)
                          : (isDark ? Colors.white70 : Colors.black54),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildBranchDropdown(isDark, isDisabled: isRoleActive),
                  const SizedBox(height: 20),
                  Text(
                    '3. Select Recipient',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isRoleActive
                          ? (isDark ? Colors.white30 : Colors.black26)
                          : (isDark ? Colors.white70 : Colors.black54),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildUserSelector(isDark, isDisabled: isRoleActive),
                  const SizedBox(height: 20),
                  Text(
                    '4. Task Name',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _taskNameController,
                    decoration: InputDecoration(
                      hintText: 'Enter task name...',
                      hintStyle: TextStyle(
                          color: isDark ? Colors.white30 : Colors.black38),
                      filled: true,
                      fillColor: isDark
                          ? const Color(0xFF0F1A2B)
                          : const Color(0xFFF3F4F6),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                    ),
                    style:
                        TextStyle(color: isDark ? Colors.white : Colors.black87),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '5. Task Description',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _taskController,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: 'Enter task details or instructions...',
                      hintStyle: TextStyle(
                          color: isDark ? Colors.white30 : Colors.black38),
                      filled: true,
                      fillColor: isDark
                          ? const Color(0xFF0F1A2B)
                          : const Color(0xFFF3F4F6),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.all(16),
                    ),
                    style:
                        TextStyle(color: isDark ? Colors.white : Colors.black87),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isAssigning ? null : _assignTask,
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 3,
                      ),
                      child: Ink(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF005BAC), Color(0xFF00897B)],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Container(
                          alignment: Alignment.center,
                          child: _isAssigning
                              ? const SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2.5),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.send_rounded,
                                        color: Colors.white, size: 20),
                                    const SizedBox(width: 8),
                                    Text(
                                      isRoleActive
                                          ? 'Assign Task to Selected Role(s)'
                                          : 'Assign Task',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleSelector(bool isDark) {
    final rolesOptions = [
      {'label': 'Sales', 'value': 'sales'},
      {'label': 'Asst. Manager', 'value': 'asst_manager'},
      {'label': 'Manager', 'value': 'manager'},
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: rolesOptions.map((role) {
        final key = role['value']!;
        final label = role['label']!;
        final isSelected = _selectedRoles.contains(key);

        return FilterChip(
          label: Text(label),
          selected: isSelected,
          selectedColor: const Color(0xFF00897B),
          checkmarkColor: Colors.white,
          labelStyle: TextStyle(
            color: isSelected
                ? Colors.white
                : (isDark ? Colors.white70 : Colors.black87),
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
          backgroundColor:
              isDark ? const Color(0xFF0F1A2B) : const Color(0xFFF3F4F6),
          side: BorderSide(
            color: isSelected
                ? const Color(0xFF00897B)
                : (isDark ? Colors.white24 : Colors.black12),
          ),
          onSelected: (selected) {
            setState(() {
              if (selected) {
                _selectedRoles.add(key);
                _selectedBranch = null;
                _selectedUser = null;
              } else {
                _selectedRoles.remove(key);
              }
            });
          },
        );
      }).toList(),
    );
  }

  Widget _buildBranchDropdown(bool isDark, {bool isDisabled = false}) {
    return Opacity(
      opacity: isDisabled ? 0.4 : 1.0,
      child: IgnorePointer(
        ignoring: isDisabled,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F1A2B) : const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(12),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedBranch,
              hint: Text(
                'Select a branch...',
                style: TextStyle(color: isDark ? Colors.white54 : Colors.black45),
              ),
              isExpanded: true,
              dropdownColor: isDark ? const Color(0xFF0F1A2B) : Colors.white,
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              items: widget.branches.map((branch) {
                return DropdownMenuItem<String>(
                  value: branch,
                  child: Text(branch),
                );
              }).toList(),
              onChanged: (val) {
                setState(() {
                  _selectedBranch = val;
                  _selectedUser = null;
                  _filterUsers('');
                });
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUserSelector(bool isDark, {bool isDisabled = false}) {
    if (_isLoadingUsers) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }

    return Opacity(
      opacity: isDisabled ? 0.4 : 1.0,
      child: IgnorePointer(
        ignoring: isDisabled,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_selectedUser != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF00897B).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: const Color(0xFF00897B), width: 1),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: const Color(0xFF00897B),
                      child: Text(
                        (_selectedUser!['username'] as String? ?? '?')
                                .isNotEmpty
                            ? (_selectedUser!['username'] as String)[0]
                                .toUpperCase()
                            : '?',
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _selectedUser!['username'] ?? 'Unknown User',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          Text(
                            '${_selectedUser!['role'] ?? ''} • Branch: ${_selectedUser!['branch'] ?? 'None'}',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.red),
                      onPressed: () => setState(() => _selectedUser = null),
                    ),
                  ],
                ),
              )
            else
              GestureDetector(
                onTap: _selectedBranch == null
                    ? () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Please select a branch first')),
                        );
                      }
                    : _showUserSelectionSheet,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF0F1A2B)
                        : const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.transparent),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _selectedBranch == null
                            ? 'Select a branch first...'
                            : 'Select a user...',
                        style: TextStyle(
                          color: isDark ? Colors.white54 : Colors.black45,
                        ),
                      ),
                      Icon(
                        Icons.arrow_drop_down,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showUserSelectionSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF0A1628) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateSheet) {
            return DraggableScrollableSheet(
              initialChildSize: 0.7,
              maxChildSize: 0.9,
              minChildSize: 0.5,
              expand: false,
              builder: (context, scrollController) {
                return Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white24 : Colors.black12,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Select User',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        decoration: InputDecoration(
                          hintText: 'Search by name, email, or branch...',
                          hintStyle: TextStyle(
                              color: isDark ? Colors.white30 : Colors.black38),
                          prefixIcon: Icon(Icons.search,
                              color: isDark ? Colors.white70 : Colors.black54),
                          filled: true,
                          fillColor: isDark
                              ? const Color(0xFF16253B)
                              : const Color(0xFFF3F4F6),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: EdgeInsets.zero,
                        ),
                        style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87),
                        onChanged: (val) {
                          _filterUsers(val);
                          setStateSheet(() {});
                        },
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: _filteredUsers.isEmpty
                            ? Center(
                                child: Text(
                                  'No users found',
                                  style: TextStyle(
                                    color:
                                        isDark ? Colors.white54 : Colors.black45,
                                  ),
                                ),
                              )
                            : ListView.separated(
                                controller: scrollController,
                                itemCount: _filteredUsers.length,
                                separatorBuilder: (context, i) => Divider(
                                  height: 1,
                                  color: isDark
                                      ? Colors.white12
                                      : Colors.black12,
                                ),
                                itemBuilder: (context, index) {
                                  final user = _filteredUsers[index];
                                  final name =
                                      user['username'] as String? ?? 'Unknown';
                                  final email =
                                      user['email'] as String? ?? '';
                                  final role = user['role'] as String? ?? '';
                                  final branch =
                                      user['branch'] as String? ?? 'None';

                                  return ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor:
                                          const Color(0xFF005BAC),
                                      child: Text(
                                        name.isNotEmpty
                                            ? name[0].toUpperCase()
                                            : '?',
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    title: Text(
                                      name,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: isDark
                                            ? Colors.white
                                            : Colors.black87,
                                      ),
                                    ),
                                    subtitle: Text(
                                      '$email • $role • Branch: $branch',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isDark
                                            ? Colors.white60
                                            : Colors.black54,
                                      ),
                                    ),
                                    onTap: () {
                                      setState(() {
                                        _selectedUser = user;
                                      });
                                      Navigator.pop(context);
                                    },
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    ).then((_) {
      _filterUsers('');
    });
  }
}
