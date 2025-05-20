import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

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
            final text = data['text'] ?? 'No text';
            final timestamp = data['timestamp'] as Timestamp?;
            final dateStr = timestamp != null
                ? timestamp.toDate().toLocal().toString().split(' ')[0]
                : '...';

            return ListTile(
              title: Text(
                text,
                style: TextStyle(
                  decoration: status == 'done' ? TextDecoration.lineThrough : null,
                  color: status == 'done' ? Colors.grey : Colors.black,
                ),
              ),
              subtitle: Text('$_userEmail\n$dateStr'),
              isThreeLine: true,
              trailing: Icon(
                status == 'pending' ? Icons.circle_outlined : Icons.check_circle,
                color: status == 'pending' ? Colors.red : Colors.green,
              ),
              onTap: () => _toggleStatus(doc),
            );
          },
        );
      },
    );
  }

  Widget _buildInputBar() {
    return SafeArea(
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        color: Colors.grey.shade200,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _todoController,
                decoration: InputDecoration(
                  hintText: "Enter Today's Task",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ),
            SizedBox(width: 8),
            GestureDetector(
              onTap: _sendTodo,
              child: Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color.fromARGB(255, 51, 131, 199),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.send,
                  color: const Color.fromARGB(255, 76, 175, 80),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteOldTasks() async {
    print('Running _deleteOldTasks...');
    final today = _dateOnly(DateTime.now());

    final querySnapshot = await _firestore
        .collection('todo')
        .where('status', isEqualTo: 'done')
        .get();

    for (var doc in querySnapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final timestamp = data['timestamp'] as Timestamp?;
      if (timestamp != null) {
        final todoDate = _dateOnly(timestamp.toDate());
        if (todoDate.isBefore(today)) {
          await _firestore.collection('todo').doc(doc.id).delete();
          print('Deleted task: ${doc.id}');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Todo List'),
          bottom: TabBar(
            controller: _tabController,
            tabs: [
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
        bottomNavigationBar: _buildInputBar(),
      ),
    );
  }
}
