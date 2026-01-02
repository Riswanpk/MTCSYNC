import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'todoform.dart';
import 'report_todo.dart'; // Import the new report page
import 'package:provider/provider.dart';
import '../Misc/theme_notifier.dart';
import 'package:flutter_slidable/flutter_slidable.dart'; // Add this import at the top
import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../widgets/todo_widget_updater.dart';

const Color primaryBlue = Color(0xFF005BAC);
const Color primaryGreen = Color(0xFF8CC63F);

class TaskDetailPage extends StatelessWidget {
  final Map<String, dynamic> data;
  final String dateStr;

  const TaskDetailPage({
    Key? key,
    required this.data,
    required this.dateStr,
  }) : super(key: key);

  bool get isAssignedByManager => data['assigned_by_name'] != null;

  Color getPriorityColor(String priority) {
    switch (priority) {
      case 'High':
        return Colors.red;
      case 'Medium':
        return Colors.amber;
      case 'Low':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  Color getPriorityBgColor(String priority, bool isDark) {
    if (isDark) {
      switch (priority) {
        case 'High':
          return const Color(0xFF3B2323); // Dark red shade
        case 'Medium':
          return const Color(0xFF39321A); // Dark amber shade
        case 'Low':
          return const Color(0xFF1B3223); // Dark green shade
        default:
          return Colors.grey.shade800;
      }
    } else {
      switch (priority) {
        case 'High':
          return const Color(0xFFFFEBEE); // Light red
        case 'Medium':
          return const Color(0xFFFFF8E1); // Light amber/yellow
        case 'Low':
          return const Color(0xFFE8F5E9); // Light green
        default:
          return Colors.grey.shade100;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final priority = data['priority'] ?? 'High';

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF181A20) : const Color(0xFFF6F7FB),
      appBar: AppBar(
        title: const Text('Task Details'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          FutureBuilder<DocumentSnapshot>(
            future: FirebaseFirestore.instance.collection('users').doc(FirebaseAuth.instance.currentUser!.uid).get(),
            builder: (context, userSnapshot) {
              if (!userSnapshot.hasData) return const SizedBox.shrink();
 
              final currentUserData = userSnapshot.data!.data() as Map<String, dynamic>;
              final currentUserRole = currentUserData['role'];
              final currentUserId = FirebaseAuth.instance.currentUser!.uid;
 
              // Conditions to show the edit button:
              // 1. User is a manager AND they are the one who assigned the task.
              // 2. The task was NOT assigned by a manager (i.e., it's a self-created task).
              final bool canEdit = (currentUserRole == 'manager' && data['assigned_by'] == currentUserId) || !isAssignedByManager;
 
              return Row(
                children: [
                  if (canEdit)
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.white),
                      tooltip: 'Edit Task',
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => TodoFormPage(docId: data['docId'])),
                        );
                      },
                    ),
                  if (data['status'] != 'done')
                    Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: TextButton(
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Mark as Done?'),
                              content: const Text('Are you sure you want to mark this task as done?'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(false),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(true),
                                  child: const Text('Yes', style: TextStyle(color: Colors.green)),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true && data['docId'] != null) {
                            await FirebaseFirestore.instance.collection('todo').doc(data['docId']).update({
                              'status': 'done',
                              'timestamp': Timestamp.now(),
                            });
                            // Optionally pop back to the list page
                            if (Navigator.canPop(context)) {
                              Navigator.pop(context);
                            }
                          }
                        },
                        child: const Text('DONE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ),
                ],
              );
            },
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            Text(
              data['title'] ?? '',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 12),
            // Date
            Row(
              children: [
                Icon(Icons.calendar_today, size: 18, color: isDark ? Colors.white70 : Colors.black54),
                const SizedBox(width: 8),
                Text(
                  dateStr,
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black54,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            // Priority
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: getPriorityBgColor(priority, isDark),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.flag, color: getPriorityColor(priority), size: 18),
                  const SizedBox(width: 8),
                  Text(
                    priority,
                    style: TextStyle(
                      color: getPriorityColor(priority),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Description
            Text(
              'Description',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              data['description'] ?? '',
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black87,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 24),
            // Status
            Row(
              children: [
                Icon(
                  data['status'] == 'done' ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: data['status'] == 'done' ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 8),
                Text(
                  data['status'] == 'done' ? 'Completed' : 'Pending',
                  style: TextStyle(
                    color: data['status'] == 'done' ? Colors.green : Colors.orange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class TaskDetailPageFromId extends StatelessWidget {
  final String docId;
  const TaskDetailPageFromId({Key? key, required this.docId}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('todo').doc(docId).get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final data = snapshot.data!.data() as Map<String, dynamic>?;
        if (data == null) {
          return const Scaffold(body: Center(child: Text('Task not found')));
        }
        // Add docId to data map for TaskDetailPage
        data['docId'] = docId;

        final timestamp = data['timestamp'] as Timestamp?;
        String dateStr = '';
        if (timestamp is Timestamp) {
          dateStr = timestamp.toDate().toLocal().toString().split(' ')[0];
        }
        return TaskDetailPage(data: data, dateStr: dateStr);
      },
    );
  }
}

class TodoPage extends StatefulWidget {
  const TodoPage({Key? key}) : super(key: key);

  @override
  State<TodoPage> createState() => _TodoPageState();
}

class _TodoPageState extends State<TodoPage> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
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
    final doc = await _firestore.collection('users').doc(user.uid).get();
    _userEmail = doc.data()?['email'] ?? 'unknown@example.com';
    _userRole = doc.data()?['role'] ?? 'sales';
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

    await _localNotifications!.initialize(initSettings);

    // Create notification channel with custom sound
    const AndroidNotificationChannel assignmentChannel = AndroidNotificationChannel(
      'assignment_channel',
      'Assignment Notifications',
      description: 'Channel for assignment notifications',
      importance: Importance.max,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('assignment'), // <-- custom sound
    );

    await _localNotifications!
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
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
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'assignment_channel',
      'Assignment Notifications',
      channelDescription: 'Channel for assignment notifications',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('assignment'), // <-- custom sound
    );
    const NotificationDetails platformDetails =
        NotificationDetails(android: androidDetails);

    await _localNotifications?.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      'New Task Assigned',
      'You have been assigned: $taskTitle',
      platformDetails,
    );
  }

  @override
  didChangeDependencies() {
    super.didChangeDependencies();
    _setupAssignmentListener();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FutureBuilder<void>(
      future: _userInfoFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final isManager = _userRole == 'manager';
        final tabCount = isManager ? 3 : 2;

        _tabController ??= TabController(length: tabCount, vsync: this);

        return Theme(
          data: theme.copyWith(
            appBarTheme: const AppBarTheme(
              backgroundColor: primaryBlue,
              foregroundColor: Colors.white,
              iconTheme: IconThemeData(color: Colors.white),
              titleTextStyle: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
              elevation: 8,
            ),
            tabBarTheme: const TabBarThemeData(
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              indicator: BoxDecoration(),
              labelStyle: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          child: DefaultTabController(
            length: tabCount,
            child: Scaffold(
              resizeToAvoidBottomInset: true,
              appBar: AppBar(
                title: const Text('Todo List'),
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                backgroundColor: const Color.fromARGB(255, 15, 110, 205), // Or your preferred color
                foregroundColor: Colors.white,
                elevation: 0,
                actions: [
                  if (_userRole == 'admin')
                    IconButton(
                      icon: const Icon(Icons.bar_chart_rounded, color: Colors.white),
                      tooltip: 'Todo Report',
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const ReportTodoPage()),
                        );
                      },
                    ),
                  IconButton(
                    icon: const Icon(Icons.delete_sweep_rounded, color: Colors.white),
                    tooltip: 'Clear All Tasks',
                    onPressed: _clearAllTodos,
                  ),
                ],
                bottom: TabBar(
                  controller: _tabController,
                  tabs: isManager
                      ? const [
                          Tab(icon: Icon(Icons.pending_actions), text: 'Pending'),
                          Tab(icon: Icon(Icons.check_circle), text: 'Completed'),
                          Tab(icon: Icon(Icons.group), text: 'Others'),
                        ]
                      : const [
                          Tab(icon: Icon(Icons.pending_actions), text: 'Pending'),
                          Tab(icon: Icon(Icons.check_circle), text: 'Completed'),
                        ],
                ),
              ),
              body: TabBarView(
                controller: _tabController,
                children: isManager
                    ? [
                        _buildTodoList('pending', onlySelf: true),
                        _buildTodoList('done', onlySelf: true),
                        _buildSalesTodosForManagerTab(),
                      ]
                    : [
                        _buildTodoList('pending'),
                        _buildTodoList('done'),
                      ],
              ),
              floatingActionButton: FloatingActionButton(
                backgroundColor: primaryBlue,
                foregroundColor: Colors.white,
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const TodoFormPage(),
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
          content: const Text('Are you sure you want to mark this todo as done?'),
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
      await updateTodoWidgetFromFirestore(); // <-- Add this line
    } else {
      await _firestore.collection('todo').doc(doc.id).update({
        'status': newStatus,
        'timestamp': FieldValue.serverTimestamp(),
      });
      await updateTodoWidgetFromFirestore(); // <-- Add this line
    }
  }


  Widget _buildTodoList(String status, {bool onlySelf = false}) {
    if (_userEmail == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final user = _auth.currentUser;
    if (user == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return FutureBuilder<DocumentSnapshot>(
      future: _firestore.collection('users').doc(user.uid).get(),
      builder: (context, userSnapshot) {
        if (!userSnapshot.hasData) return const Center(child: CircularProgressIndicator());
        final role = userSnapshot.data!.get('role');
        final uid = user.uid;

        // For manager, show only their own todos in Pending/Completed tabs
        if (role == 'manager' && onlySelf) {
          return StreamBuilder<QuerySnapshot>(
            stream: _firestore
                .collection('todo')
                .where('email', isEqualTo: _userEmail)
                .where('status', isEqualTo: status)
                .orderBy('timestamp', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) return const Center(child: Text('Error loading todos'));
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final todos = snapshot.data?.docs ?? [];

              if (todos.isEmpty) {
                return Center(
                  child: Text(
                    status == 'pending' ? 'No pending tasks' : 'No completed tasks',
                    style: const TextStyle(fontSize: 16, color: Color.fromARGB(255, 70, 164, 57)),
                  ),
                );
              }

              final isDark = Theme.of(context).brightness == Brightness.dark;

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                itemCount: todos.length,
                itemBuilder: (context, index) {
                  final doc = todos[index];
                  final data = doc.data() as Map<String, dynamic>;
                  final title = data['title'] ?? 'No title';
                  final description = data['description'] ?? '';
                  final priority = data['priority'] ?? 'High';
                  final timestamp = data['timestamp'] as Timestamp?;
                  final timeStr = timestamp != null
                      ? TimeOfDay.fromDateTime(timestamp.toDate().toLocal()).format(context)
                      : '...';

                  Color priorityColor;
                  Color priorityBgColor;
                  if (isDark) {
                    switch (priority) {
                      case 'High':
                        priorityColor = Colors.red;
                        priorityBgColor = const Color(0xFF3B2323); // Dark red shade
                        break;
                      case 'Medium':
                        priorityColor = Colors.amber;
                        priorityBgColor = const Color(0xFF39321A); // Dark amber shade
                        break;
                      case 'Low':
                        priorityColor = Colors.green;
                        priorityBgColor = const Color(0xFF1B3223); // Dark green shade
                        break;
                      default:
                        priorityColor = Colors.grey;
                        priorityBgColor = Colors.grey.shade800;
                    }
                  } else {
                    switch (priority) {
                      case 'High':
                        priorityColor = Colors.red;
                        priorityBgColor = const Color(0xFFFFEBEE); // Light red
                        break;
                      case 'Medium':
                        priorityColor = Colors.amber;
                        priorityBgColor = const Color(0xFFFFF8E1); // Light amber/yellow
                        break;
                      case 'Low':
                        priorityColor = Colors.green;
                        priorityBgColor = const Color(0xFFE8F5E9); // Light green
                        break;
                      default:
                        priorityColor = Colors.grey;
                        priorityBgColor = Colors.grey.shade100;
                    }
                  }

                  return Slidable(
                    key: ValueKey(doc.id),
                    startActionPane: ActionPane(
                      motion: const DrawerMotion(),
                      extentRatio: 0.28,
                      children: [
                        SlidableAction(
                          onPressed: (context) async {
                            await _toggleStatus(doc);
                          },
                          backgroundColor: data['status'] == 'pending'
                              ? Colors.green.shade400
                              : Colors.orange.shade400,
                          foregroundColor: Colors.white,
                          icon: data['status'] == 'pending'
                              ? Icons.check_circle
                              : Icons.refresh,
                          label: data['status'] == 'pending'
                              ? 'Done'
                              : 'Pending',
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ],
                    ),
                    endActionPane: ActionPane(
                      motion: const DrawerMotion(),
                      extentRatio: 0.25,
                      children: [
                        SlidableAction(
                          onPressed: (context) async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Delete Task?'),
                                content: const Text('Are you sure you want to delete this task?'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.of(context).pop(true),
                                    child: const Text('Delete', style: TextStyle(color: Color.fromARGB(255, 0, 0, 0))),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.of(context).pop(false),
                                    child: const Text('Cancel'),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              await _firestore.collection('todo').doc(doc.id).delete();
                              await updateTodoWidgetFromFirestore(); // <-- Add this line
                            }
                          },
                          backgroundColor: Colors.red.shade400,
                          foregroundColor: Colors.white,
                          icon: Icons.delete,
                          label: 'Delete',
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ],
                    ),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: priorityBgColor,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Theme.of(context).shadowColor.withOpacity(0.15),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        leading: Container(
                          width: 5,
                          height: double.infinity,
                          decoration: BoxDecoration(
                            color: priorityColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        title: Text(
                          title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: data['status'] == 'done'
                                ? Theme.of(context).disabledColor
                                : Theme.of(context).textTheme.bodyLarge?.color,
                            decoration: data['status'] == 'done' ? TextDecoration.lineThrough : null,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    timeStr,
                                    style: TextStyle(
                                      color: Theme.of(context).hintColor,
                                      fontSize: 14,
                                    ),
                                  ),
                                  if (description.isNotEmpty)
                                    Flexible(
                                      child: Text(
                                        description,
                                        style: TextStyle(
                                          color: Theme.of(context).textTheme.bodySmall?.color,
                                          fontSize: 13,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            if (data['email'] != null)
                              FutureBuilder<String>(
                                future: _getUsernameByEmail(data['email'] ?? ''),
                                builder: (context, snapshot) {
                                  if (!snapshot.hasData) return const SizedBox.shrink();
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      'Assigned to: ${snapshot.data}',
                                      style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => TaskDetailPage(
                                data: {
                                  ...data,
                                  'docId': doc.id, // Ensure docId is passed
                                },
                                dateStr: timestamp != null
                                    ? timestamp.toDate().toLocal().toString().split(' ')[0]
                                    : '',
                              ),
                            ),
                          );
                        },
                      ),
                    ));
                },
              );
            },
          );
        } else {
          // Sales user: show as before
          return StreamBuilder<QuerySnapshot>(
            stream: _firestore
                .collection('todo')
                .where('email', isEqualTo: _userEmail)
                .where('status', isEqualTo: status)
                .orderBy('timestamp', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) return const Center(child: Text('Error loading todos'));
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final todos = snapshot.data?.docs ?? [];

              if (todos.isEmpty) {
                return Center(
                  child: Text(
                    status == 'pending' ? 'No pending tasks' : 'No completed tasks',
                    style: const TextStyle(fontSize: 16, color: Color.fromARGB(255, 70, 164, 57)),
                  ),
                );
              }

              final isDark = Theme.of(context).brightness == Brightness.dark;

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                itemCount: todos.length,
                itemBuilder: (context, index) {
                  final doc = todos[index];
                  final data = doc.data() as Map<String, dynamic>;
                  final title = data['title'] ?? 'No title';
                  final description = data['description'] ?? '';
                  final priority = data['priority'] ?? 'High';
                  final timestamp = data['timestamp'] as Timestamp?;
                  final timeStr = timestamp != null
                      ? TimeOfDay.fromDateTime(timestamp.toDate().toLocal()).format(context)
                      : '...';

                  Color priorityColor;
                  Color priorityBgColor;
                  if (isDark) {
                    switch (priority) {
                      case 'High':
                        priorityColor = Colors.red;
                        priorityBgColor = const Color(0xFF3B2323); // Dark red shade
                        break;
                      case 'Medium':
                        priorityColor = Colors.amber;
                        priorityBgColor = const Color(0xFF39321A); // Dark amber shade
                        break;
                      case 'Low':
                        priorityColor = Colors.green;
                        priorityBgColor = const Color(0xFF1B3223); // Dark green shade
                        break;
                      default:
                        priorityColor = Colors.grey;
                        priorityBgColor = Colors.grey.shade800;
                    }
                  } else {
                    switch (priority) {
                      case 'High':
                        priorityColor = Colors.red;
                        priorityBgColor = const Color(0xFFFFEBEE); // Light red
                        break;
                      case 'Medium':
                        priorityColor = Colors.amber;
                        priorityBgColor = const Color(0xFFFFF8E1); // Light amber/yellow
                        break;
                      case 'Low':
                        priorityColor = Colors.green;
                        priorityBgColor = const Color(0xFFE8F5E9); // Light green
                        break;
                      default:
                        priorityColor = Colors.grey;
                        priorityBgColor = Colors.grey.shade100;
                    }
                  }

                  return Slidable(
                    key: ValueKey(doc.id),
                    startActionPane: ActionPane(
                      motion: const DrawerMotion(),
                      extentRatio: 0.28,
                      children: [
                        SlidableAction(
                          onPressed: (context) async {
                            await _toggleStatus(doc);
                          },
                          backgroundColor: data['status'] == 'pending'
                              ? Colors.green.shade400
                              : Colors.orange.shade400,
                          foregroundColor: Colors.white,
                          icon: data['status'] == 'pending'
                              ? Icons.check_circle
                              : Icons.refresh,
                          label: data['status'] == 'pending'
                              ? 'Done'
                              : 'Pending',
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ],
                    ),
                    endActionPane: ActionPane(
                      motion: const DrawerMotion(),
                      extentRatio: 0.25,
                      children: [
                        SlidableAction(
                          onPressed: (context) async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Delete Task?'),
                                content: const Text('Are you sure you want to delete this task?'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.of(context).pop(true),
                                    child: const Text('Delete', style: TextStyle(color: Color.fromARGB(255, 0, 0, 0))),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.of(context).pop(false),
                                    child: const Text('Cancel'),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              final data = doc.data() as Map<String, dynamic>;
                              final timestamp = data['timestamp'] as Timestamp?;
                              final userId = data['userId'] ?? _auth.currentUser?.uid;
                              if (timestamp != null && userId != null) {
                                final created = timestamp.toDate();
                                final hour = created.hour;
                                // Only write daily_report if created between 12pm-11:59pm or 12am-11:59am
                                if ((hour >= 12 && hour <= 23) || (hour >= 0 && hour < 12)) {
                                  await FirebaseFirestore.instance.collection('daily_report').add({
                                    'timestamp': created,
                                    'userId': userId,
                                    'documentId': doc.id,
                                    'type': 'todo',
                                  });
                                }
                              }
                              await _firestore.collection('todo').doc(doc.id).delete();
                              await updateTodoWidgetFromFirestore(); // <-- Add this line
                            }
                          },
                          backgroundColor: Colors.red.shade400,
                          foregroundColor: Colors.white,
                          icon: Icons.delete,
                          label: 'Delete',
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ],
                    ),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: priorityBgColor,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Theme.of(context).shadowColor.withOpacity(0.15),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        leading: Container(
                          width: 5,
                          height: double.infinity,
                          decoration: BoxDecoration(
                            color: priorityColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        title: Text(
                          title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: data['status'] == 'done'
                                ? Theme.of(context).disabledColor
                                : Theme.of(context).textTheme.bodyLarge?.color,
                            decoration: data['status'] == 'done' ? TextDecoration.lineThrough : null,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    timeStr,
                                    style: TextStyle(
                                      color: Theme.of(context).hintColor,
                                      fontSize: 14,
                                    ),
                                  ),
                                  if (description.isNotEmpty)
                                    Flexible(
                                      child: Text(
                                        description,
                                        style: TextStyle(
                                          color: Theme.of(context).textTheme.bodySmall?.color,
                                          fontSize: 13,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            // Assignment info
                            if (data['assigned_to_name'] != null && data['assigned_by_name'] == null)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  'Assigned to: ${data['assigned_to_name']}',
                                  style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
                                ),
                              )
                            else if (data['assigned_by_name'] != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  'Assigned by: Manager',
                                  style: const TextStyle(fontSize: 12, color: Colors.deepPurple),
                                ),
                              ),
                          ],
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => TaskDetailPage(
                                data: {
                                  ...data,
                                  'docId': doc.id, // Ensure docId is passed
                                },
                                dateStr: timestamp != null
                                    ? timestamp.toDate().toLocal().toString().split(' ')[0]
                                    : '',
                              ),
                            ),
                          );
                        },
                      ),
                    ));
                },
              );
            },
          );
        }
      },
    );
  }

  Future<void> _clearAllTodos() async {
    if (_userEmail == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Tasks?'),
        content: const Text('Are you sure you want to delete all your tasks? This cannot be undone.'),
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
      await updateTodoWidgetFromFirestore(); // <-- Add this line
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

  // This method builds the "Others" tab for managers, showing todos not assigned to the current user
  Widget _buildSalesTodosForManagerTab() {
    if (_userEmail == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return FutureBuilder<DocumentSnapshot>(
      future: _firestore.collection('users').doc(_auth.currentUser!.uid).get(),
      builder: (context, userSnapshot) {
        if (!userSnapshot.hasData) return const Center(child: CircularProgressIndicator());
        final managerBranch = userSnapshot.data!.get('branch');
        final managerEmail = userSnapshot.data!.get('email');

        return FutureBuilder<QuerySnapshot>(
          future: _firestore
              .collection('users')
              .get(),
          builder: (context, usersSnapshot) {
            if (!usersSnapshot.hasData) return const Center(child: CircularProgressIndicator());
            final salesUsers = usersSnapshot.data!.docs
                .map((doc) => {
                      'email': doc['email'] as String?,
                      'username': doc['username'] as String? ?? doc['email'] as String?,
                    })
                .where((user) => user['email'] != managerEmail)
                .toList();

            if (salesUsers.isEmpty) {
              return const Center(child: Text('No sales users found.'));
            }

            // Pagination variables
            const int pageSize = 10;
            int _currentPage = 0;
            String? _selectedUsername;

            return StatefulBuilder(
              builder: (context, setState) {
                // Filtering logic
                List<Map<String, String?>> filteredUsers = salesUsers;
                if (_selectedUsername != null && _selectedUsername != 'All') {
                  filteredUsers = salesUsers
                      .where((user) => user['username'] == _selectedUsername)
                      .toList();
                }

                // Get the emails for the current page
                final int start = _currentPage * pageSize;
                final int end = ((start + pageSize) > filteredUsers.length) ? filteredUsers.length : (start + pageSize);
                final List<String> pageEmails = filteredUsers.sublist(start, end).map((u) => u['email']!).toList();

                // Username dropdown options
                final usernames = ['All', ...{for (var u in salesUsers) u['username'] ?? u['email']}];

                return Column(
                  children: [
                    // Username filter dropdown
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          const Text('Filter by user:', style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButton<String>(
                              value: _selectedUsername ?? 'All',
                              isExpanded: true,
                              items: usernames
                                  .map((username) => DropdownMenuItem(
                                        value: username,
                                        child: Text(username ?? ''),
                                      ))
                                  .toList(),
                              onChanged: (value) {
                                setState(() {
                                  _selectedUsername = value;
                                  _currentPage = 0; // Reset to first page on filter change
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: StreamBuilder<QuerySnapshot>(
                        stream: _firestore
                            .collection('todo')
                            .where('email', whereIn: pageEmails.isEmpty ? ['dummy'] : pageEmails)
                            .orderBy('timestamp', descending: true)
                            .snapshots(),
                        builder: (context, todosSnapshot) {
                          if (todosSnapshot.hasError) return const Center(child: Text('Error loading todos'));
                          if (todosSnapshot.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          final todos = todosSnapshot.data?.docs ?? [];
                          if (todos.isEmpty) {
                            return const Center(
                              child: Text('No tasks from others', style: TextStyle(fontSize: 16, color: Color.fromARGB(255, 70, 164, 57))),
                            );
                          }
                          final isDark = Theme.of(context).brightness == Brightness.dark;
                          return ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            itemCount: todos.length,
                            itemBuilder: (context, index) {
                              final doc = todos[index];
                              final data = doc.data() as Map<String, dynamic>;
                              final title = data['title'] ?? 'No title';
                              final description = data['description'] ?? '';
                              final priority = data['priority'] ?? 'High';
                              final timestamp = data['timestamp'] as Timestamp?;
                              final timeStr = timestamp != null
                                  ? TimeOfDay.fromDateTime(timestamp.toDate().toLocal()).format(context)
                                  : '...';

                              Color priorityColor;
                              Color priorityBgColor;
                              if (isDark) {
                                switch (priority) {
                                  case 'High':
                                    priorityColor = Colors.red;
                                    priorityBgColor = const Color(0xFF3B2323);
                                    break;
                                  case 'Medium':
                                    priorityColor = Colors.amber;
                                    priorityBgColor = const Color(0xFF39321A);
                                    break;
                                  case 'Low':
                                    priorityColor = Colors.green;
                                    priorityBgColor = const Color(0xFF1B3223);
                                    break;
                                  default:
                                    priorityColor = Colors.grey;
                                    priorityBgColor = Colors.grey.shade800;
                                }
                              } else {
                                switch (priority) {
                                  case 'High':
                                    priorityColor = Colors.red;
                                    priorityBgColor = const Color(0xFFFFEBEE);
                                    break;
                                  case 'Medium':
                                    priorityColor = Colors.amber;
                                    priorityBgColor = const Color(0xFFFFF8E1);
                                    break;
                                  case 'Low':
                                    priorityColor = Colors.green;
                                    priorityBgColor = const Color(0xFFE8F5E9);
                                    break;
                                  default:
                                    priorityColor = Colors.grey;
                                    priorityBgColor = Colors.grey.shade100;
                                }
                              }

                              return Container(
                                margin: const EdgeInsets.only(bottom: 16),
                                decoration: BoxDecoration(
                                  color: priorityBgColor,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Theme.of(context).shadowColor.withOpacity(0.15),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  leading: Container(
                                    width: 5,
                                    height: double.infinity,
                                    decoration: BoxDecoration(
                                      color: priorityColor,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  title: Text(
                                    title,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: data['status'] == 'done'
                                          ? Theme.of(context).disabledColor
                                          : Theme.of(context).textTheme.bodyLarge?.color,
                                      decoration: data['status'] == 'done' ? TextDecoration.lineThrough : null,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              timeStr,
                                              style: TextStyle(
                                                color: Theme.of(context).hintColor,
                                                fontSize: 14,
                                              ),
                                            ),
                                            if (description.isNotEmpty)
                                              Flexible(
                                                child: Text(
                                                  description,
                                                  style: TextStyle(
                                                    color: Theme.of(context).textTheme.bodySmall?.color,
                                                    fontSize: 13,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      if (data['email'] != null)
                                        FutureBuilder<String>(
                                          future: _getUsernameByEmail(data['email'] ?? ''),
                                          builder: (context, snapshot) {
                                            if (!snapshot.hasData) return const SizedBox.shrink();
                                            return Padding(
                                              padding: const EdgeInsets.only(top: 2),
                                              child: Text(
                                                'Assigned to: ${snapshot.data}',
                                                style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
                                              ),
                                            );
                                          },
                                        ),
                                    ],
                                  ),
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => TaskDetailPage(
                                          data: {
                                            ...data,
                                            'docId': doc.id, // Ensure docId is passed
                                          },
                                          dateStr: timestamp != null
                                              ? timestamp.toDate().toLocal().toString().split(' ')[0]
                                              : '',
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                    // Pagination controls
                    if (filteredUsers.length > pageSize)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_back),
                              onPressed: _currentPage > 0
                                  ? () => setState(() => _currentPage--)
                                  : null,
                            ),
                            Text('Page ${_currentPage + 1} of ${((filteredUsers.length - 1) ~/ pageSize) + 1}'),
                            IconButton(
                              icon: const Icon(Icons.arrow_forward),
                              onPressed: end < filteredUsers.length
                                  ? () => setState(() => _currentPage++)
                                  : null,
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}
