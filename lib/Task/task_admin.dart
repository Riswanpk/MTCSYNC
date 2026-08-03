import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../Navigation/user_cache_service.dart';

class CoreTeamTaskPage extends StatefulWidget {
  const CoreTeamTaskPage({super.key});

  @override
  State<CoreTeamTaskPage> createState() => _CoreTeamTaskPageState();
}

class _CoreTeamTaskPageState extends State<CoreTeamTaskPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // Form State
  String? _selectedBranch;
  Map<String, dynamic>? _selectedUser;
  final Set<String> _selectedRoles = {}; // 'sales', 'asst_manager', 'manager'
  final TextEditingController _taskNameController = TextEditingController();
  final TextEditingController _taskController = TextEditingController();
  bool _isAssigning = false;

  // Cached Users list for search
  List<Map<String, dynamic>> _eligibleUsers = [];
  List<Map<String, dynamic>> _filteredUsers = [];
  String _userSearchQuery = '';
  bool _isLoadingUsers = true;

  final List<String> _branches = [
    'BGR', 'CBE', 'CHN', 'CLT', 'EKM', 'JBL', 'KKM', 'KSD',
    'KTM', 'PKD', 'PKT', 'PMN', 'TRR', 'TSR', 'TLY', 'TVM',
    'UDP', 'VDK', 'WND',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadUsers();
  }

  @override
  void dispose() {
    _tabController.dispose();
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

      // Sort alphabetically by username
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
      _userSearchQuery = query;
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
        const SnackBar(
            content: Text('Please enter a task name')),
      );
      return;
    }
    if (taskDescription.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please enter a task description')),
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
          const SnackBar(
              content: Text('No users found for selected role(s)')),
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

      final functions = FirebaseFunctions.instanceFor(region: 'asia-south1');

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
          'assigned_by': currentUser.uid,
          'assigned_by_name': assignerName,
          'assigned_by_email': assignerEmail,
          'status': 'pending',
          'timestamp': FieldValue.serverTimestamp(),
          'note': '',
          'completed_at': null,
        });

      // 2. Trigger push notification via Cloud Function
      FirebaseFunctions.instanceFor(region: 'asia-south1')
          .httpsCallable('sendLeadAssignmentNotification')
          .call(<String, dynamic>{
        'recipientUid': recipientUid,
        'title': 'New Task Assigned',
        'body': 'Core Team assigned you a new task: "$taskName"',
        'notifType': 'core_task_assignment',
        'leadDocId': docRef.id,
      }).catchError((error) {
        debugPrint('FCM Warning: failed to send task notification: $error');
      });

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
          _userSearchQuery = '';
          _filteredUsers = _eligibleUsers;
        });
        // Jump to assigned tasks list
        _tabController.animateTo(1);
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
        debugPrint('Error cancelling scheduled notification for deleted task: $e');
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
              const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          tabs: const [
            Tab(icon: Icon(Icons.add_task_rounded), text: 'Assign Task'),
            Tab(icon: Icon(Icons.assignment_rounded), text: 'Assigned Tasks'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildAssignTaskTab(isDark),
          _buildAssignedTasksTab(isDark),
        ],
      ),
    );
  }

  Widget _buildAssignTaskTab(bool isDark) {
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
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                    style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87),
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
                    style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87),
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
              items: _branches.map((branch) {
                return DropdownMenuItem<String>(
                  value: branch,
                  child: Text(branch),
                );
              }).toList(),
              onChanged: (val) {
                setState(() {
                  _selectedBranch = val;
                  _selectedUser = null; // Clear selected user when branch changes
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
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF00897B).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF00897B), width: 1),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: const Color(0xFF00897B),
                      child: Text(
                        (_selectedUser!['username'] as String? ?? '?').isNotEmpty
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
                          const SnackBar(content: Text('Please select a branch first')),
                        );
                      }
                    : _showUserSelectionSheet,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color:
                        isDark ? const Color(0xFF0F1A2B) : const Color(0xFFF3F4F6),
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
                                  'No matching users found',
                                  style: TextStyle(
                                      color: isDark
                                          ? Colors.white38
                                          : Colors.black38),
                                ),
                              )
                            : ListView.builder(
                                controller: scrollController,
                                itemCount: _filteredUsers.length,
                                itemBuilder: (context, index) {
                                  final user = _filteredUsers[index];
                                  final String name =
                                      user['username'] ?? 'No Name';
                                  final String email =
                                      user['email'] ?? 'No Email';
                                  final String role = user['role'] ?? 'sales';
                                  final String branch =
                                      user['branch'] ?? 'None';

                                  return ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    leading: CircleAvatar(
                                      backgroundColor: const Color(0xFF005BAC),
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
      // Clear filters on pop
      _filterUsers('');
    });
  }

  Widget _buildAssignedTasksTab(bool isDark) {
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) {
      return const Center(child: Text('User not logged in'));
    }

    return StreamBuilder<QuerySnapshot>(
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
                  Icons.playlist_add_check_rounded,
                  size: 64,
                  color: isDark ? Colors.white24 : Colors.black26,
                ),
                const SizedBox(height: 16),
                Text(
                  'No tasks assigned yet',
                  style: TextStyle(
                    fontSize: 16,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
              ],
            ),
          );
        }

        // Sort by timestamp local side (Firestore requires composite index if mixing where + orderby)
        final sortedDocs = docs.toList()
          ..sort((a, b) {
            final tsA = a['timestamp'] as Timestamp?;
            final tsB = b['timestamp'] as Timestamp?;
            if (tsA == null) return 1;
            if (tsB == null) return -1;
            return tsB.compareTo(tsA); // Newest first
          });

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: sortedDocs.length,
          itemBuilder: (context, index) {
            final doc = sortedDocs[index];
            final data = doc.data() as Map<String, dynamic>;
            final String docId = doc.id;
            final String title = data['title'] ?? '';
            final String assignedToName = data['assigned_to_name'] ?? 'Unknown';
            final String assignedToEmail = data['assigned_to_email'] ?? '';
            final String status = data['status'] ?? 'pending';
            final Timestamp? createdTs = data['timestamp'] as Timestamp?;
            final Timestamp? completedTs = data['completed_at'] as Timestamp?;
            final String note = data['note'] ?? '';

            final createdDateStr = createdTs != null
                ? DateFormat('dd MMM yyyy, hh:mm a').format(createdTs.toDate())
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
                        // Recipient Name
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'To: $assignedToName',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
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
                              color: isPending ? Colors.amber : Colors.green,
                              width: 1,
                            ),
                          ),
                          child: Text(
                            isPending ? 'Pending' : 'Completed',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isPending ? Colors.amber : Colors.green,
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
                    if ((data['description'] as String? ?? '').isNotEmpty) ...[
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
                              color: isDark ? Colors.white70 : Colors.black,
                            ),
                          ),
                        ),
                      ],
                      if (data['attachments'] != null && (data['attachments'] as List).isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Attachments:',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 80,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: (data['attachments'] as List).length,
                            itemBuilder: (context, idx) {
                              final att = (data['attachments'] as List)[idx];
                              final String url = att['url'] ?? '';
                              final String type = att['type'] ?? 'image';
                              
                              return GestureDetector(
                                onTap: () {
                                  if (type == 'video') {
                                    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                                  } else {
                                    showDialog(
                                      context: context,
                                      builder: (context) => Dialog(
                                        backgroundColor: Colors.transparent,
                                        insetPadding: const EdgeInsets.all(12),
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
                                                backgroundColor: Colors.black54,
                                                child: IconButton(
                                                  icon: const Icon(Icons.close, color: Colors.white),
                                                  onPressed: () => Navigator.pop(context),
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
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: isDark ? Colors.white24 : Colors.black12),
                                    color: isDark ? Colors.white10 : Colors.black12,
                                  ),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      if (type == 'image')
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: Image.network(
                                            url,
                                            fit: BoxFit.cover,
                                            errorBuilder: (context, error, stackTrace) =>
                                                const Center(child: Icon(Icons.broken_image)),
                                          ),
                                        )
                                      else
                                        const Center(child: Icon(Icons.video_library_rounded, color: Colors.orange, size: 36)),
                                      if (type == 'video')
                                        Positioned(
                                          bottom: 4,
                                          right: 4,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.black,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: const Text(
                                              'VIDEO',
                                              style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
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
                    // Action button (Allow deleting tasks)
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
    );
  }
}
