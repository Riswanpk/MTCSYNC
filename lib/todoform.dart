import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'dart:async';

const Color primaryBlue = Color(0xFF005BAC);
const Color primaryGreen = Color(0xFF8CC63F);

class TodoFormPage extends StatefulWidget {
  const TodoFormPage({Key? key}) : super(key: key);

  @override
  State<TodoFormPage> createState() => _TodoFormPageState();
}

class _TodoFormPageState extends State<TodoFormPage> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  String _priority = 'High';
  bool _isSaving = false;

  // For manager assignment
  String? _currentUserRole;
  String? _currentUserBranch;
  List<Map<String, dynamic>> _salesUsers = [];
  String? _selectedSalesUserId;

  @override
  void initState() {
    super.initState();
    _fetchCurrentUserRoleAndBranch();
  }

  Future<void> _fetchCurrentUserRoleAndBranch() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    setState(() {
      _currentUserRole = userDoc.data()?['role'];
      _currentUserBranch = userDoc.data()?['branch'];
    });
    if (_currentUserRole == 'manager') {
      _fetchSalesUsers();
    }
  }

  Future<void> _fetchSalesUsers() async {
    if (_currentUserBranch == null) return;
    final query = await FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'sales')
        .where('branch', isEqualTo: _currentUserBranch)
        .get();
    setState(() {
      _salesUsers = query.docs.map((doc) {
        final data = doc.data();
        return {
          'uid': doc.id,
          'name': data['name'] ?? data['email'] ?? 'Unknown',
          'email': data['email'] ?? 'unknown@example.com',
        };
      }).toList();
    });
  }

  Future<void> _saveTodo() async {
    final title = _titleController.text.trim();
    final desc = _descController.text.trim();
    if (title.isEmpty || desc.isEmpty || _priority.isEmpty) return;

    setState(() => _isSaving = true);

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User not logged in')),
      );
      return;
    }

    // If manager, assign to selected sales user
    String createdBy = user.uid;
    String email = '';
    if (_currentUserRole == 'manager' && _selectedSalesUserId != null) {
      createdBy = _selectedSalesUserId!;
      // Get the email of the assigned sales user
      final salesUser = _salesUsers.firstWhere((u) => u['uid'] == _selectedSalesUserId, orElse: () => {});
      email = salesUser['email'] ?? '';
    } else {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      email = userDoc.data()?['email'] ?? user.email ?? 'unknown@example.com';
    }

    await FirebaseFirestore.instance.collection('todo').add({
      'title': title,
      'description': desc,
      'priority': _priority,
      'status': 'pending',
      'timestamp': FieldValue.serverTimestamp(),
      'email': email,
      'created_by': createdBy,
    });

    setState(() => _isSaving = false);
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Widget _priorityDot(String priority) {
    Color color;
    switch (priority) {
      case 'High':
        color = Colors.red;
        break;
      case 'Medium':
        color = Colors.amber;
        break;
      case 'Low':
        color = Colors.green;
        break;
      default:
        color = Colors.grey;
    }
    return Container(
      width: 10,
      height: 10,
      margin: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inputFillColor = isDark ? const Color(0xFF23262F) : Colors.white;
    final inputTextColor = isDark ? Colors.white : Colors.black;
    final labelColor = isDark ? Colors.white70 : Colors.black87;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF181A20) : const Color(0xFFF6F7FB),
      appBar: AppBar(
        title: const Text('Add Task'),
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: AbsorbPointer(
          absorbing: _isSaving,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Title', style: TextStyle(color: labelColor, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              TextField(
                controller: _titleController,
                style: TextStyle(color: inputTextColor),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: inputFillColor,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  hintText: 'Enter task title',
                  hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey),
                ),
              ),
              const SizedBox(height: 18),
              Text('Description', style: TextStyle(color: labelColor, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              TextField(
                controller: _descController,
                style: TextStyle(color: inputTextColor),
                maxLines: 3,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: inputFillColor,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  hintText: 'Enter task description',
                  hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey),
                ),
              ),
              if (_currentUserRole == 'manager')
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 18),
                    const Text('Assign To', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: _selectedSalesUserId,
                      items: _salesUsers
                          .map<DropdownMenuItem<String>>((user) => DropdownMenuItem<String>(
                                value: user['uid'] as String,
                                child: Text(user['name'] as String),
                              ))
                          .toList(),
                      onChanged: (val) => setState(() => _selectedSalesUserId = val),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Select Sales User',
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 18),
              Text('Priority', style: TextStyle(color: labelColor, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _priority,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: inputFillColor,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                dropdownColor: inputFillColor,
                style: TextStyle(color: inputTextColor),
                items: [
                  DropdownMenuItem(
                    value: 'High',
                    child: Row(
                      children: [
                        _priorityDot('High'),
                        const Text('High'),
                      ],
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'Medium',
                    child: Row(
                      children: [
                        _priorityDot('Medium'),
                        const Text('Medium'),
                      ],
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'Low',
                    child: Row(
                      children: [
                        _priorityDot('Low'),
                        const Text('Low'),
                      ],
                    ),
                  ),
                ],
                onChanged: (val) => setState(() => _priority = val!),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveTodo,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Save Task', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}