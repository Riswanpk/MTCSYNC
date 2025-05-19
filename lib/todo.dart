import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ToDoPage extends StatefulWidget {
  const ToDoPage({super.key});

  @override
  State<ToDoPage> createState() => _ToDoPageState();
}

class _ToDoPageState extends State<ToDoPage> {
  final TextEditingController _controller = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const Color primaryBlue = Color(0xFF005BAC);
  static const Color primaryGreen = Color(0xFF8CC63F);

  late String _today;
  late String _uid;

  final List<String> statusOptions = ['Pending', 'In Progress', 'Completed'];

  bool showPending = true;
  bool showCompleted = true;

  @override
  void initState() {
    super.initState();
    final user = _auth.currentUser;
    if (user != null) {
      _uid = user.uid;
    } else {
      // Force logout or redirect to login
      Navigator.of(context).pushReplacementNamed('/login');
    }

    final now = DateTime.now();
    _today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> _addTask(String text) async {
    if (text.trim().isEmpty || _uid.isEmpty) return;
    await _firestore.collection('todo').add({
      'text': text.trim(),
      'done': false,
      'status': 'Pending',
      'userId': _uid,
      'date': _today,
      'timestamp': FieldValue.serverTimestamp(),
    });
    _controller.clear();
  }

  Future<void> _toggleDone(DocumentSnapshot doc) async {
    final currentDone = (doc['done'] as bool?) ?? false;
    await doc.reference.update({
      'done': !currentDone,
      'status': !currentDone ? 'Completed' : 'Pending',
    });
  }

  Future<void> _updateStatus(DocumentSnapshot doc, String newStatus) async {
    await doc.reference.update({
      'status': newStatus,
      'done': newStatus == 'Completed',
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE8ECF4),
      appBar: AppBar(
        backgroundColor: primaryBlue,
        elevation: 0,
        title: const Text('ToDo List'),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(25),
              color: Colors.white.withOpacity(0.95),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              children: [
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: _firestore
                        .collection('todo')
                        .where('userId', isEqualTo: _uid)
                        .orderBy('timestamp', descending: true)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final tasks = snapshot.data?.docs ?? [];

                      final completed = tasks
                          .where((t) =>
                              (t.data() as Map<String, dynamic>)['done'] == true)
                          .toList();

                      final notCompleted = tasks
                          .where((t) =>
                              (t.data() as Map<String, dynamic>)['done'] != true)
                          .toList();

                      return ListView(
                        children: [
                          sectionHeader(
                            title: 'Pending Tasks',
                            expanded: showPending,
                            onTap: () => setState(() => showPending = !showPending),
                          ),
                          if (showPending) ...notCompleted.map(buildTaskTile),
                          sectionHeader(
                            title: "Completed Tasks",
                            expanded: showCompleted,
                            onTap: () => setState(() => showCompleted = !showCompleted),
                          ),
                          if (showCompleted) ...completed.map(buildTaskTile),
                        ],
                      );
                    },
                  ),
                ),
                // Add Task Field
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          decoration: InputDecoration(
                            labelText: 'Add new task',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            focusedBorder: const OutlineInputBorder(
                              borderSide: BorderSide(color: primaryGreen, width: 2),
                            ),
                          ),
                          onSubmitted: (value) {
                            _addTask(value);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      FloatingActionButton(
                        mini: true,
                        backgroundColor: primaryBlue,
                        child: const Icon(Icons.add, color: Colors.white),
                        onPressed: () {
                          _addTask(_controller.text);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget sectionHeader({
    required String title,
    required bool expanded,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(width: 8),
            Icon(
              expanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  Widget buildTaskTile(DocumentSnapshot doc) {
    final task = doc.data() as Map<String, dynamic>;
    return ListTile(
      leading: Checkbox(
        activeColor: primaryGreen,
        value: task['done'] ?? false,
        onChanged: (_) => _toggleDone(doc),
      ),
      title: Text(
        task['text'] ?? '',
        style: task['done'] == true
            ? TextStyle(
                decoration: TextDecoration.lineThrough,
                color: Colors.grey.withOpacity(0.7),
              )
            : null,
      ),
      trailing: DropdownButton<String>(
        value: task['status'] ?? (task['done'] == true ? 'Completed' : 'Pending'),
        items: statusOptions.map((status) {
          return DropdownMenuItem<String>(
            value: status,
            child: Text(status),
          );
        }).toList(),
        onChanged: (value) {
          if (value != null) _updateStatus(doc, value);
        },
      ),
    );
  }
}
