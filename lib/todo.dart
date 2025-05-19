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
  final List<String> tabOptions = ['All', 'Work', 'Personal', 'Other'];
  int selectedTab = 0;

  bool showToday = true;
  bool showCompleted = true;

  @override
  void initState() {
    super.initState();
    _uid = _auth.currentUser?.uid ?? '';
    final now = DateTime.now();
    _today = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    // _cleanupOldTasks(); // Removed cleanup feature
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
      'category': tabOptions[selectedTab], // Save category for filtering
    });
    _controller.clear();
  }

  Future<void> _toggleDone(DocumentSnapshot doc) async {
    await doc.reference.update({
      'done': !(doc['done'] as bool),
      'status': !(doc['done'] as bool) ? 'Completed' : 'Pending',
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
      appBar: AppBar(
        title: const Text('Your Tasks', style: TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Colors.black),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          // Tabs
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: List.generate(tabOptions.length, (i) {
                final selected = selectedTab == i;
                return GestureDetector(
                  onTap: () => setState(() => selectedTab = i),
                  child: Container(
                    margin: const EdgeInsets.only(right: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          tabOptions[i],
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 16,
                            color: selected ? Colors.black : Colors.black54,
                          ),
                        ),
                        if (selected)
                          Container(
                            margin: const EdgeInsets.only(top: 2),
                            height: 2,
                            width: 28,
                            color: Colors.black,
                          ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
          const Divider(height: 1, thickness: 1),
          // Today Section
          sectionHeader(
            title: 'All Tasks',
            expanded: showToday,
            onTap: () => setState(() => showToday = !showToday),
          ),
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
                final filtered = selectedTab == 0
                    ? tasks
                    : tasks.where((t) => t['category'] == tabOptions[selectedTab]).toList();
                final completed = filtered.where((t) => t['done'] == true).toList();
                final notCompleted = filtered.where((t) => t['done'] == false).toList();

                return ListView(
                  children: [
                    if (showToday) ...notCompleted.map(buildTaskTile),
                    sectionHeader(
                      title: "Complited Task's",
                      expanded: showCompleted,
                      onTap: () => setState(() => showCompleted = !showCompleted),
                    ),
                    if (showCompleted) ...completed.map(buildTaskTile),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.black,
        child: const Icon(Icons.add, color: Colors.white),
        onPressed: () {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Add Task'),
              content: TextField(
                controller: _controller,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Task'),
                onSubmitted: (value) {
                  _addTask(value);
                  Navigator.pop(context);
                },
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    _addTask(_controller.text);
                    Navigator.pop(context);
                  },
                  child: const Text('Add'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget sectionHeader({required String title, required bool expanded, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
            ),
            const SizedBox(width: 8),
            Icon(
              expanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
              size: 24,
            ),
          ],
        ),
      ),
    );
  }

  Widget buildTaskTile(DocumentSnapshot doc) {
    return ListTile(
      leading: Checkbox(
        activeColor: primaryGreen,
        value: doc['done'],
        onChanged: (_) => _toggleDone(doc),
      ),
      title: Text(
        doc['text'],
        style: doc['done']
            ? TextStyle(
                decoration: TextDecoration.lineThrough,
                color: Colors.grey.withOpacity(0.7),
              )
            : null,
      ),
      trailing: DropdownButton<String>(
        value: doc['status'] ?? (doc['done'] ? 'Completed' : 'Pending'),
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
