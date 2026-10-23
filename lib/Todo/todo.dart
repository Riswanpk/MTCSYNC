import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'todoform.dart' as todoform;
import 'report_todo.dart';
import '../Navigation/user_cache_service.dart';
import 'dart:async';

import 'todo_widgets.dart' as todowidgets;
import 'todo_list_body.dart';
import 'todo_manager_tab.dart';
import 'todo_cache_service.dart';

// Re-export so existing imports of TaskDetailPage/TaskDetailPageFromId keep working
export 'task_detail_widgets.dart';

class TodoPage extends StatefulWidget {
  const TodoPage({super.key});

  @override
  State<TodoPage> createState() => _TodoPageState();
}

class _TodoPageState extends State<TodoPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _todoController = TextEditingController();
  final GlobalKey<TodoListBodyState> _pendingKey = GlobalKey<TodoListBodyState>();
  final GlobalKey<TodoListBodyState> _doneKey = GlobalKey<TodoListBodyState>();
  String? _userEmail;
  String? _userRole;
  bool _isReloading = false;
  late Future<void> _userInfoFuture;

  TabController? _tabController;

  @override
  void initState() {
    super.initState();
    _userInfoFuture = _loadUserInfo().then((_) {
      _deleteOldTasks();
    });

    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> _loadUserInfo() async {
    final user = _auth.currentUser;
    if (user == null) return;
    final cache = UserCacheService.instance;
    await cache.ensureLoaded();
    _userEmail = cache.email ?? 'unknown@example.com';
    _userRole = cache.role ?? 'sales';
  }

  @override
  void dispose() {
    _tabController?.dispose();
    _todoController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Widget _buildTab(IconData icon, String label) {
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ==================== Build ====================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FutureBuilder<void>(
      future: _userInfoFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }

        final isManager = _userRole == 'manager' || _userRole == 'asst_manager';
        final tabCount = isManager ? 3 : 2;
        final isDark = theme.brightness == Brightness.dark;

        _tabController ??= TabController(length: tabCount, vsync: this);

        return Theme(
          data: theme.copyWith(
            appBarTheme: AppBarTheme(
              backgroundColor: Colors.transparent,
              foregroundColor: Colors.white,
              iconTheme: const IconThemeData(color: Colors.white),
              titleTextStyle: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
              elevation: 0,
            ),
            tabBarTheme: TabBarThemeData(
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              indicator: BoxDecoration(
                borderRadius: BorderRadius.circular(50),
                color: Colors.white.withValues(alpha: 0.2),
              ),
              labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              unselectedLabelStyle: const TextStyle(fontSize: 12),
            ),
          ),
          child: DefaultTabController(
            length: tabCount,
            child: Scaffold(
              resizeToAvoidBottomInset: true,
              backgroundColor: isDark ? const Color(0xFF0A1628) : Colors.white,
                appBar: PreferredSize(
                  preferredSize: const Size.fromHeight(kToolbarHeight + 56),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          todowidgets.primaryBlue,
                          todowidgets.primaryBlue.withValues(alpha: 0.9),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: todowidgets.primaryBlue.withValues(alpha: 0.3),
                          blurRadius: 15,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: AppBar(
                      title: const Text('Todo List'),
                      leading: IconButton(
                        icon: const Icon(Icons.arrow_back_rounded),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      backgroundColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      actions: [
                        if (_userRole == 'admin')
                          IconButton(
                            icon: const Icon(Icons.bar_chart_rounded,
                                color: Colors.white),
                            tooltip: 'Todo Report',
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (context) => const ReportTodoPage()),
                              );
                            },
                          ),
                        IconButton(
                          icon: _isReloading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.refresh_rounded,
                                  color: Colors.white),
                          tooltip: 'Reload from database',
                          onPressed: _isReloading ? null : _reloadFromDatabase,
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_sweep_rounded,
                              color: Colors.white),
                          tooltip: 'Clear All Tasks',
                          onPressed: _clearAllTodos,
                        ),
                      ],
                      bottom: PreferredSize(
                        preferredSize: const Size.fromHeight(56),
                        child: Container(
                          height: 48,
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(25),
                          ),
                          child: TabBar(
                            controller: _tabController,
                            indicatorSize: TabBarIndicatorSize.tab,
                            dividerColor: Colors.transparent,
                            indicatorPadding: const EdgeInsets.all(4),
                            indicator: BoxDecoration(
                              borderRadius: BorderRadius.circular(22),
                              color: Colors.white.withValues(alpha: 0.25),
                            ),
                            tabs: isManager
                                ? [
                                    _buildTab(Icons.pending_actions_rounded, 'Pending'),
                                    _buildTab(Icons.check_circle_rounded, 'Completed'),
                                    _buildTab(Icons.group_rounded, 'Others'),
                                  ]
                                : [
                                    _buildTab(Icons.pending_actions_rounded, 'Pending'),
                                    _buildTab(Icons.check_circle_rounded, 'Completed'),
                                  ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                body: TabBarView(
                  controller: _tabController,
                  children: isManager
                      ? [
                          TodoListBody(
                            key: _pendingKey,
                            status: 'pending',
                            userEmail: _userEmail,
                            onToggleStatus: _toggleStatus,
                            onDelete: _deleteTodo,
                            onPostpone: _postponeTodo,
                            getUsernameByEmail: _getUsernameByEmail,
                            role: _userRole,
                          ),
                          TodoListBody(
                            key: _doneKey,
                            status: 'done',
                            userEmail: _userEmail,
                            onToggleStatus: _toggleStatus,
                            onDelete: _deleteTodo,
                            onPostpone: _postponeTodo,
                            getUsernameByEmail: _getUsernameByEmail,
                            role: _userRole,
                          ),
                          SalesTodosForManagerTab(
                            userEmail: _userEmail,
                            firestore: _firestore,
                            auth: _auth,
                            getUsernameByEmail: _getUsernameByEmail,
                          ),
                        ]
                      : [
                          TodoListBody(
                            key: _pendingKey,
                            status: 'pending',
                            userEmail: _userEmail,
                            onToggleStatus: _toggleStatus,
                            onDelete: _deleteTodo,
                            onPostpone: _postponeTodo,
                            getUsernameByEmail: _getUsernameByEmail,
                            role: _userRole,
                          ),
                          TodoListBody(
                            key: _doneKey,
                            status: 'done',
                            userEmail: _userEmail,
                            onToggleStatus: _toggleStatus,
                            onDelete: _deleteTodo,
                            onPostpone: _postponeTodo,
                            getUsernameByEmail: _getUsernameByEmail,
                            role: _userRole,
                          ),
                        ],
                ),
                floatingActionButton: FloatingActionButton(
                  backgroundColor: todowidgets.primaryBlue,
                  foregroundColor: Colors.white,
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const todoform.TodoFormPage(),
                      ),
                    );
                  },
                  tooltip: 'Add New Task',
                  child: const Icon(Icons.add_rounded, size: 28),
                ),
              ),
            ),
          );
      },
    );
  }

  // ==================== Helper Methods ====================

  Future<void> _deleteOldTasks() async {
    if (_userEmail == null) return;
    final now = DateTime.now();

    final uid = _auth.currentUser?.uid;
    final List<DocumentSnapshot<Map<String, dynamic>>> allDocs = [];
    final seenIds = <String>{};

    final snapEmail = await _firestore
        .collection('todo')
        .where('email', isEqualTo: _userEmail)
        .where('status', isEqualTo: 'done')
        .get();
    for (var d in snapEmail.docs) {
      if (seenIds.add(d.id)) allDocs.add(d);
    }

    if (uid != null && uid.isNotEmpty) {
      final snapUid = await _firestore
          .collection('todo')
          .where('created_by', isEqualTo: uid)
          .where('status', isEqualTo: 'done')
          .get();
      for (var d in snapUid.docs) {
        if (seenIds.add(d.id)) allDocs.add(d);
      }
    }

    final batch = _firestore.batch();

    for (var doc in allDocs) {
      final data = doc.data();
      if (data == null) continue;
      final timestamp = data['timestamp'];
      if (timestamp is Timestamp) {
        final todoTime = timestamp.toDate();
        final difference = now.difference(todoTime);
        // Auto deletion of todo after 40 days has passed since todo creation
        if (difference.inDays >= 40) {
          batch.delete(doc.reference);
        }
      }
    }

    await batch.commit();
  }

  @override
  didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // App is active, check for old tasks
      _deleteOldTasks();
    }
  }

  // ignore: unused_element
  Future<void> _sendTodo() async {
    final text = _todoController.text.trim();
    if (text.isEmpty || _userEmail == null) return;

    final now = DateTime.now();
    try {
      await _firestore.collection('todo').add({
        'text': text,
        'email': _userEmail,
        'timestamp': now,
        'status': 'pending',
        'created_by': _auth.currentUser?.uid,
      });

      _todoController.clear();
    } catch (e, stack) {
      debugPrint('Error creating todo: $e');
      debugPrint('$stack');
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  // ignore: unused_element
  DateTime _dateOnly(DateTime dateTime) {
    return DateTime(dateTime.year, dateTime.month, dateTime.day);
  }

  Future<void> _reloadFromDatabase() async {
    if (_userEmail == null || _isReloading) return;
    setState(() => _isReloading = true);
    try {
      await Future.wait([
        _pendingKey.currentState?.refreshFromDatabase(showSpinner: true) ??
            TodoCacheService.instance.fetchAndCacheTodos(_userEmail!),
        _doneKey.currentState?.refreshFromDatabase(showSpinner: true) ??
            Future.value([]),
      ]);
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text('Tasks updated from database'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text('Failed to reload: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isReloading = false);
    }
  }

  Future<void> _toggleStatus(String docId, Map<String, dynamic> data) async {
    final currentStatus = data['status'] ?? 'pending';
    if (currentStatus == 'done') {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('Completed tasks cannot be changed.')),
        );
      }
      return;
    }

    final newStatus = 'done';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark as Done?'),
        content:
            const Text('Are you sure you want to mark this todo as done? Completed tasks cannot be edited or reverted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.green),
            child: const Text('Yes'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: TextButton.styleFrom(foregroundColor: Colors.blue),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    // Cancel the notification using the same ID calculation from todoform.dart
    try {
      final notificationId = docId.hashCode & 0x7FFFFFFF;
      await AwesomeNotifications().cancel(notificationId);
    } catch (e) {
      debugPrint('Warning: Failed to cancel todo notification: $e');
    }

    await _firestore.collection('todo').doc(docId).update({
      'status': newStatus,
      'timestamp': Timestamp.now(),
    });

    if (_userEmail != null) {
      await TodoCacheService.instance
          .updateLocalTodoStatus(_userEmail!, docId, newStatus);
      _pendingKey.currentState?.reloadFromLocalCache();
      _doneKey.currentState?.reloadFromLocalCache();
    }
  }

  Future<void> _postponeTodo(String docId, DateTime newReminder) async {
    await _firestore.collection('todo').doc(docId).update({
      'reminder': newReminder.toIso8601String(),
    });

    if (_userEmail != null) {
      await TodoCacheService.instance
          .updateLocalReminder(_userEmail!, docId, newReminder);
      _pendingKey.currentState?.reloadFromLocalCache();
      _doneKey.currentState?.reloadFromLocalCache();
    }
  }

  Future<void> _deleteTodo(String docId) async {
    if (_userEmail != null) {
      final cached = await TodoCacheService.instance.getCachedTodos(_userEmail!);
      final match = cached.where((t) => t.id == docId).firstOrNull;
      if (match?.status == 'done') {
        if (mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            const SnackBar(content: Text('Completed tasks cannot be deleted.')),
          );
        }
        return;
      }
    }

    // Cancel the notification using the same ID calculation from todoform.dart
    try {
      final notificationId = docId.hashCode & 0x7FFFFFFF;
      await AwesomeNotifications().cancel(notificationId);
    } catch (e) {
      debugPrint('Warning: Failed to cancel todo notification: $e');
    }
    
    await _firestore.collection('todo').doc(docId).delete();

    if (_userEmail != null) {
      await TodoCacheService.instance.removeLocalTodo(_userEmail!, docId);
      _pendingKey.currentState?.reloadFromLocalCache();
      _doneKey.currentState?.reloadFromLocalCache();
    }
  }

  Future<void> _clearAllTodos() async {
    if (_userEmail == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Pending Tasks?'),
        content: const Text(
            'Are you sure you want to delete all your pending tasks? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear All', style: TextStyle(color: Colors.red)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      final batch = _firestore.batch();
      final snapshot = await _firestore
          .collection('todo')
          .where('email', isEqualTo: _userEmail)
          .where('status', isEqualTo: 'pending')
          .get();
      for (var doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      await TodoCacheService.instance.clearPendingTodos(_userEmail!);
      _pendingKey.currentState?.reloadFromLocalCache();
      _doneKey.currentState?.reloadFromLocalCache();
    }
  }

  Future<String> _getUsernameByEmail(String email) async {
    final userSnap = await _firestore
        .collection('users')
        .where('email', isEqualTo: email)
        .limit(1)
        .get();
    if (userSnap.docs.isNotEmpty) {
      return userSnap.docs.first.data()['username'] ?? email;
    }
    return email;
  }
}
