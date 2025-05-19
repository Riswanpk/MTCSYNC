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

  DateTime _dateOnly(DateTime dateTime) {
    // Returns DateTime with time set to midnight (00:00:00)
    return DateTime(dateTime.year, dateTime.month, dateTime.day);
  }

  Future<void> _toggleStatus(DocumentSnapshot todoDoc) async {
    final currentStatus = todoDoc['status'] as String? ?? 'pending';
    final newStatus = currentStatus == 'pending' ? 'done' : 'pending';

    if (newStatus == 'done') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Center(
              child: Text(
                'Mark as Done?',
                style: TextStyle(
                  color: Color(0xFF0D47A1), // Blue color (#0D47A1)
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
            ),
            content: Text(
              'Are you sure you want to mark this todo as done?',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.black87,
                fontSize: 16,
              ),
            ),
            actionsPadding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            actions: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFF0D47A1), // Blue (#0D47A1)
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(
                    'Yes',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
              ),
              SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFF8BC34A), // Green (#8BC34A)
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      );

      if (confirm != true) {
        return;
      }

      final now = DateTime.now();
      final dateOnly = _dateOnly(now);
      await _firestore.collection('todo').doc(todoDoc.id).update({
        'status': newStatus,
        'timestamp': Timestamp.fromDate(dateOnly),
      });
    } else {
      await _firestore.collection('todo').doc(todoDoc.id).update({
        'status': newStatus,
        'timestamp': FieldValue.serverTimestamp(),
      });
    }
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
              stream: _userEmail == null
                  ? Stream.empty()
                  : _firestore
                      .collection('todo')
                      .where('email', isEqualTo: _userEmail)
                      //.orderBy('timestamp', descending: true) // add index if needed
                      .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error loading todos'));
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator());
                }

                final todos = snapshot.data?.docs ?? [];

                // Cleanup: delete todos that are 'done' and timestamp date is before today
                final today = _dateOnly(DateTime.now());
                for (var doc in todos) {
                  final data = doc.data() as Map<String, dynamic>;
                  final status = data['status'] ?? 'pending';
                  final timestamp = data['timestamp'] as Timestamp?;
                  if (status == 'done' && timestamp != null) {
                    final todoDate = _dateOnly(timestamp.toDate());
                    if (todoDate.isBefore(today)) {
                      // Delete document
                      _firestore.collection('todo').doc(doc.id).delete();
                    }
                  }
                }

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
                        ? timestamp.toDate().toLocal().toString().split(' ')[0] // Show only date YYYY-MM-DD
                        : '...';

                    return ListTile(
                      title: Text(
                        text,
                        style: TextStyle(
                          decoration:
                              status == 'done' ? TextDecoration.lineThrough : null,
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
