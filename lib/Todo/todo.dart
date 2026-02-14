import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'todoform.dart' as todoform;
import 'report_todo.dart';
import '../Misc/user_cache_service.dart';
import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'todo_widget_updater.dart';
import 'todo_widgets.dart' as todowidgets;
import 'todo_list_body.dart';
import 'todo_manager_tab.dart';

// Re-export so existing imports of TaskDetailPage/TaskDetailPageFromId keep working
export 'task_detail_widgets.dart';

class TodoPage extends StatefulWidget {
  const TodoPage({Key? key}) : super(key: key);

  @override
  State<TodoPage> createState() => _TodoPageState();
}

class _TodoPageState extends State<TodoPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _todoController = TextEditingController();
  String? _userEmail;
  String? _userRole;
  late Future<void> _userInfoFuture;

  TabController? _tabController;
  StreamSubscription<QuerySnapshot>? _assignmentListener;
  FlutterLocalNotificationsPlugin? _localNotifications;

  @override
  void initState() {
    super.initState();
    _userInfoFuture = _loadUserInfo().then((_) {
      _deleteOldTasks();
      _initLocalNotifications();
      _setupAssignmentListener();
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
    _assignmentListener?.cancel();
    _tabController?.dispose();
    _todoController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _initLocalNotifications() async {
    _localNotifications = FlutterLocalNotificationsPlugin();

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initSettings =
        InitializationSettings(android: androidSettings);

    await _localNotifications!.initialize(settings: initSettings);

    // Create notification channel with custom sound
    const AndroidNotificationChannel assignmentChannel =
        AndroidNotificationChannel(
      'assignment_channel',
      'Assignment Notifications',
      description: 'Channel for assignment notifications',
      importance: Importance.max,
      playSound: true,
      sound:
          RawResourceAndroidNotificationSound('assignment'), // <-- custom sound
    );

    await _localNotifications!
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(assignmentChannel);
  }

  void _setupAssignmentListener() async {
    await _userInfoFuture;
    if (_userRole != 'sales' || _userEmail == null) return;

    await _assignmentListener?.cancel();

    _assignmentListener = FirebaseFirestore.instance
        .collection('todo')
        .where('email', isEqualTo: _userEmail)
        .where('assigned_by_name', isNotEqualTo: null)
        .where('assignment_seen', isEqualTo: false)
        .snapshots()
        .listen((snapshot) {
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final title = data['title'] ?? 'New Task Assigned';
        _showAssignmentNotification(title);
        doc.reference.update({'assignment_seen': true});
      }
    });
  }

  Future<void> _showAssignmentNotification(String taskTitle) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'assignment_channel',
      'Assignment Notifications',
      channelDescription: 'Channel for assignment notifications',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      sound:
          RawResourceAndroidNotificationSound('assignment'), // <-- custom sound
    );
    const NotificationDetails platformDetails =
        NotificationDetails(android: androidDetails);

    await _localNotifications?.show(
      id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title: 'New Task Assigned',
      body: 'You have been assigned: $taskTitle',
      notificationDetails: platformDetails,
    );
  }

  @override
  didChangeDependencies() {
    super.didChangeDependencies();
    _setupAssignmentListener();
  }

  // ==================== Helper Widgets ====================

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

        final isManager = _userRole == 'manager';
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
                color: Colors.white.withOpacity(0.2),
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
                          todowidgets.primaryBlue.withOpacity(0.9),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: todowidgets.primaryBlue.withOpacity(0.3),
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
                            color: Colors.white.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(25),
                          ),
                          child: TabBar(
                            controller: _tabController,
                            indicatorSize: TabBarIndicatorSize.tab,
                            dividerColor: Colors.transparent,
                            indicatorPadding: const EdgeInsets.all(4),
                            indicator: BoxDecoration(
                              borderRadius: BorderRadius.circular(22),
                              color: Colors.white.withOpacity(0.25),
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
                            status: 'pending',
                            onlySelf: true,
                            userEmail: _userEmail,
                            firestore: _firestore,
                            auth: _auth,
                            onToggleStatus: _toggleStatus,
                            onDelete: _deleteTodo,
                            getUsernameByEmail: _getUsernameByEmail,
                          ),
                          TodoListBody(
                            status: 'done',
                            onlySelf: true,
                            userEmail: _userEmail,
                            firestore: _firestore,
                            auth: _auth,
                            onToggleStatus: _toggleStatus,
                            onDelete: _deleteTodo,
                            getUsernameByEmail: _getUsernameByEmail,
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
                            status: 'pending',
                            userEmail: _userEmail,
                            firestore: _firestore,
                            auth: _auth,
                            onToggleStatus: _toggleStatus,
                            onDelete: _deleteTodo,
                            getUsernameByEmail: _getUsernameByEmail,
                          ),
                          TodoListBody(
                            status: 'done',
                            userEmail: _userEmail,
                            firestore: _firestore,
                            auth: _auth,
                            onToggleStatus: _toggleStatus,
                            onDelete: _deleteTodo,
                            getUsernameByEmail: _getUsernameByEmail,
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
                  child: const Icon(Icons.add_rounded, size: 28),
                  tooltip: 'Add New Task',
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

    // Get all completed todos for this user
    final snapshot = await _firestore
        .collection('todo')
        .where('email', isEqualTo: _userEmail)
        .where('status', isEqualTo: 'done') // Only completed todos
        .get();

    final batch = _firestore.batch();

    for (var doc in snapshot.docs) {
      final data = doc.data();
      final timestamp = data['timestamp'];
      if (timestamp is Timestamp) {
        final todoTime = timestamp.toDate();
        final difference = now.difference(todoTime);
        // Change from 24 hours to 30 days (about 1 month)
        if (difference.inDays >= 30) {
          batch.delete(doc.reference);
          // Do NOT update daily_report here!
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

  Future<void> _sendTodo() async {
    final text = _todoController.text.trim();
    if (text.isEmpty || _userEmail == null) return;

    final now = DateTime.now();
    try {
      final docRef = await _firestore.collection('todo').add({
        'text': text,
        'email': _userEmail,
        'timestamp': now,
        'status': 'pending',
        'userId': _auth.currentUser?.uid,
      });

      _todoController.clear();
    } catch (e, stack) {
      print('Error creating todo: $e');
      print(stack);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  DateTime _dateOnly(DateTime dateTime) {
    return DateTime(dateTime.year, dateTime.month, dateTime.day);
  }

  Future<void> _toggleStatus(DocumentSnapshot doc) async {
    final currentStatus = doc['status'] ?? 'pending';
    final newStatus = currentStatus == 'pending' ? 'done' : 'pending';

    if (newStatus == 'done') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Mark as Done?'),
          content:
              const Text('Are you sure you want to mark this todo as done?'),
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

      final today = _dateOnly(DateTime.now());
      await _firestore.collection('todo').doc(doc.id).update({
        'status': newStatus,
        'timestamp': Timestamp.now(),
      });
      await updateTodoWidgetFromFirestore();
    } else {
      await _firestore.collection('todo').doc(doc.id).update({
        'status': newStatus,
        'timestamp': FieldValue.serverTimestamp(),
      });
      await updateTodoWidgetFromFirestore();
    }
  }

  Future<void> _deleteTodo(String docId) async {
    await _firestore.collection('todo').doc(docId).delete();
    await updateTodoWidgetFromFirestore();
  }

  Future<void> _clearAllTodos() async {
    if (_userEmail == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Tasks?'),
        content: const Text(
            'Are you sure you want to delete all your tasks? This cannot be undone.'),
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
          .get();
      for (var doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      await updateTodoWidgetFromFirestore();
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
