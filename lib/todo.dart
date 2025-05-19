import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class TodoPage extends StatefulWidget {
  const TodoPage({Key? key}) : super(key: key);

  @override
  State<TodoPage> createState() => _TodoPageState();
}

class _TodoPageState extends State<TodoPage> {
  final TextEditingController _todoController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? _userEmail;

  @override
  void initState() {
    super.initState();
    _loadUserEmail();
  }

  Future<void> _loadUserEmail() async {
    final user = _auth.currentUser;
    if (user == null) {
      // User not logged in
      setState(() => _userEmail = null);
      return;
    }
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

  Future<void> _toggleStatus(DocumentSnapshot todoDoc) async {
    final currentStatus = todoDoc['status'] as String? ?? 'pending';
    final newStatus = currentStatus == 'pending' ? 'done' : 'pending';

    await _firestore.collection('todo').doc(todoDoc.id).update({
      'status': newStatus,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Todo List'),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('todo')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error loading todos'));
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator());
                }

                final todos = snapshot.data?.docs ?? [];

                if (todos.isEmpty) {
                  return Center(child: Text('No todos yet'));
                }

                return ListView.builder(
                  reverse: true,
                  itemCount: todos.length,
                  itemBuilder: (context, index) {
                    final doc = todos[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final status = data['status'] ?? 'pending';
                    final text = data['text'] ?? '';
                    final email = data['email'] ?? '';
                    final timestamp = data['timestamp'] as Timestamp?;
                    final timeStr = timestamp != null
                        ? DateTime.fromMillisecondsSinceEpoch(timestamp.millisecondsSinceEpoch)
                            .toLocal()
                            .toString()
                        : '...';

                    return ListTile(
                      title: Text(
                        text,
                        style: TextStyle(
                          decoration: status == 'done' ? TextDecoration.lineThrough : null,
                          color: status == 'done' ? Colors.grey : Colors.black,
                        ),
                      ),
                      subtitle: Text('$email\n$timeStr'),
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
            ),
          ),
          _buildInputBar(),
        ],
      ),
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
                  hintText: 'Type your todo',
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
                  color: Colors.green,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.send,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
