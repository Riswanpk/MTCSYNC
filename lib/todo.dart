import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'todoform.dart';
import 'package:provider/provider.dart';
import 'theme_notifier.dart';
import 'package:flutter_slidable/flutter_slidable.dart'; // Add this import at the top

const Color primaryBlue = Color(0xFF005BAC);
const Color primaryGreen = Color(0xFF8CC63F);

class TaskDetailPage extends StatelessWidget {
  final Map<String, dynamic> data;
  final String dateStr;

  const TaskDetailPage({Key? key, required this.data, required this.dateStr}) : super(key: key);

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

class TodoPage extends StatefulWidget {
  const TodoPage({Key? key}) : super(key: key);

  @override
  State<TodoPage> createState() => _TodoPageState();
}

class _TodoPageState extends State<TodoPage> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final TextEditingController _todoController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String? _userEmail;

  late TabController _tabController;

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeNotifier>(context).currentTheme;

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
        tabBarTheme: const TabBarTheme(
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicator: BoxDecoration(), // No highlight
          labelStyle: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          resizeToAvoidBottomInset: true,
          appBar: AppBar(
            title: const Text('Todo List'),
            actions: [
              IconButton(
                icon: const Icon(Icons.delete_sweep_rounded, color: Colors.white),
                tooltip: 'Clear All Tasks',
                onPressed: _clearAllTodos,
              ),
            ],
            bottom: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(icon: Icon(Icons.pending_actions), text: 'Pending'),
                Tab(icon: Icon(Icons.check_circle), text: 'Completed'),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildTodoList('pending'),
              _buildTodoList('done'),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            backgroundColor: primaryBlue, // Make the + button blue
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
  }

  @override
  void initState() {
    super.initState();
    _loadUserEmail();
    _tabController = TabController(length: 2, vsync: this);

    // Add observer to detect app lifecycle changes
    WidgetsBinding.instance.addObserver(this);

    // Call the function to delete old tasks when the app starts
    _deleteOldTasks();
  }

  Future<void> _deleteOldTasks() async {
    if (_userEmail == null) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final snapshot = await _firestore
        .collection('todo')
        .where('email', isEqualTo: _userEmail)
        .where('status', isEqualTo: 'done')
        .get();
    for (var doc in snapshot.docs) {
      final data = doc.data();
      final timestamp = data['timestamp'];
      if (timestamp is Timestamp) {
        final taskDate = DateTime(timestamp.toDate().year, timestamp.toDate().month, timestamp.toDate().day);
        if (taskDate.isBefore(today)) {
          await _firestore.collection('todo').doc(doc.id).delete();
        }
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    WidgetsBinding.instance.removeObserver(this); // Remove observer
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // App is active, check for old tasks
      _deleteOldTasks();
    }
  }

  Future<void> _loadUserEmail() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final doc = await _firestore.collection('users').doc(user.uid).get();
    setState(() {
      _userEmail = doc.data()?['email'] ?? 'unknown@example.com';
    });
  }

  Future<void> _sendTodo() async {
    final text = _todoController.text.trim();
    if (text.isEmpty || _userEmail == null) return;

    await _firestore.collection('todo').add({
      'text': text,
      'email': _userEmail,
      'timestamp': FieldValue.serverTimestamp(),
      'status': 'pending',
    });

    _todoController.clear();
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
              style: TextButton.styleFrom(foregroundColor: Colors.green), // Green for "Yes"
              child: const Text('Yes'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(foregroundColor: Colors.blue), // Blue for "Cancel"
              child: const Text('Cancel'),
            ),
          ],
        ),
      );
      if (confirm != true) return;

      final today = _dateOnly(DateTime.now());
      await _firestore.collection('todo').doc(doc.id).update({
        'status': newStatus,
        'timestamp': Timestamp.fromDate(today),
      });
    } else {
      await _firestore.collection('todo').doc(doc.id).update({
        'status': newStatus,
        'timestamp': FieldValue.serverTimestamp(),
      });
    }
  }

  Widget _buildTodoList(String status) {
    if (_userEmail == null) {
      return const Center(child: CircularProgressIndicator());
    }

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
                  color: priorityBgColor, // <-- background color by priority
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
                  subtitle: Padding(
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
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => TaskDetailPage(
                          data: data,
                          dateStr: timestamp != null
                              ? timestamp.toDate().toLocal().toString().split(' ')[0]
                              : '',
                        ),
                      ),
                    );
                  },
                ),
              ),
            );
          },
        );
        // Ensure a widget is always returned
        // (This line is technically unreachable, but required for Dart's analysis)
        // ignore: dead_code
        // return SizedBox.shrink();
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
    }
  }

  Widget _buildInputBar() {
    // Remove the input bar entirely, as per your request
    return const SizedBox.shrink();
  }

}
