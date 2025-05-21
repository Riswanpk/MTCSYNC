import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'todoform.dart';

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
        return Colors.yellow[700]!;
      case 'Low':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final priority = data['priority'] ?? 'High';
    return Theme(
      data: ThemeData(
        colorScheme: ColorScheme.light(
          primary: primaryBlue,
          secondary: primaryGreen,
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F6FA),
        appBarTheme: const AppBarTheme(
          backgroundColor: primaryBlue,
          foregroundColor: Colors.white,
        ),
      ),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Task Details'),
        ),
        body: Center(
          child: Card(
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: getPriorityColor(priority),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        priority,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: getPriorityColor(priority),
                          fontSize: 16,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        dateStr,
                        style: const TextStyle(color: Colors.grey, fontSize: 14),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    data['title'] ?? 'No Title',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    data['description'] ?? 'No Description',
                    style: const TextStyle(fontSize: 16),
                  ),
                ],
              ),
            ),
          ),
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
              style: const TextStyle(fontSize: 16, color: Color.fromARGB(255, 76, 175, 158)),
            ),
          );
        }

        return ListView.builder(
          itemCount: todos.length,
          itemBuilder: (context, index) {
            final doc = todos[index];
            final data = doc.data() as Map<String, dynamic>;
            final title = data['title'] ?? data['text'] ?? 'No title';
            final description = data['description'] ?? '';
            final priority = data['priority'] ?? 'High';
            final timestamp = data['timestamp'] as Timestamp?;
            final dateStr = timestamp != null
                ? timestamp.toDate().toLocal().toString().split(' ')[0]
                : '...';

            Color priorityColor;
            switch (priority) {
              case 'High':
                priorityColor = Colors.red;
                break;
              case 'Medium':
                priorityColor = Colors.yellow[700]!;
                break;
              case 'Low':
                priorityColor = Colors.green;
                break;
              default:
                priorityColor = Colors.grey;
            }

            return ListTile(
              title: Text(
                title,
                style: TextStyle(
                  decoration: status == 'done' ? TextDecoration.lineThrough : null,
                  color: status == 'done' ? Colors.grey : Colors.black,
                ),
              ),
              subtitle: Text(dateStr),
              isThreeLine: false,
              leading: GestureDetector(
                onTap: () async {
                  // Only ask to mark as done when the circle is tapped
                  await _toggleStatus(doc);
                },
                child: Icon(
                  status == 'pending' ? Icons.circle_outlined : Icons.check_circle,
                  color: status == 'pending'
                      ? priorityColor
                      : Colors.green,
                ),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Delete Task?'),
                      content: const Text('Are you sure you want to delete this task?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text('Delete', style: TextStyle(color: Colors.red)),
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
              ),
              onTap: () {
                // Open detail page when tapping anywhere except the circle
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => TaskDetailPage(data: data, dateStr: dateStr),
                  ),
                );
              },
            );
          },
        );
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

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData(
        colorScheme: ColorScheme.light(
          primary: primaryBlue,
          secondary: primaryGreen,
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F6FA),
        appBarTheme: const AppBarTheme(
          backgroundColor: primaryBlue,
          foregroundColor: Colors.white,
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: primaryGreen,
          foregroundColor: Colors.white,
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
                icon: const Icon(Icons.delete_sweep, color: Colors.red),
                tooltip: 'Clear All Tasks',
                onPressed: _clearAllTodos,
              ),
            ],
            bottom: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Pending'),
                Tab(text: 'Completed'),
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
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const TodoFormPage()),
              );
            },
            child: const Icon(Icons.add),
            tooltip: 'Add New Task',
          ),
        ),
      ),
    );
  }
}
