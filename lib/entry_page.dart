import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class EntryPage extends StatefulWidget {
  @override
  State<EntryPage> createState() => _EntryPageState();
}

class _EntryPageState extends State<EntryPage> {
  String? selectedBranch;
  List<Map<String, dynamic>> branches = [];
  List<Map<String, dynamic>> users = [];
  Map<String, TextEditingController> controllers = {};
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    fetchBranches();
  }

  Future<void> fetchBranches() async {
    final usersSnap = await FirebaseFirestore.instance.collection('users').get();
    final branchSet = <String>{};
    for (var doc in usersSnap.docs) {
      final branch = doc.data()['branch'];
      if (branch != null) branchSet.add(branch);
    }
    setState(() {
      branches = branchSet.map((b) => {'branch': b}).toList();
      if (branches.isNotEmpty) selectedBranch = branches.first['branch'];
    });
    fetchUsersForBranch(selectedBranch);
  }

  Future<void> fetchUsersForBranch(String? branch) async {
    if (branch == null) return;
    setState(() {
      isLoading = true;
      users = [];
      controllers.clear();
    });
    final usersSnap = await FirebaseFirestore.instance
        .collection('users')
        .where('branch', isEqualTo: branch)
        .get();
    setState(() {
      users = usersSnap.docs
          .map((doc) => {
                'id': doc.id,
                'username': doc.data()['username'] ?? doc.data()['email'] ?? 'User',
              })
          .toList();
      for (var user in users) {
        controllers[user['id']] = TextEditingController();
      }
      isLoading = false;
    });
  }

  Future<void> saveMarks() async {
    for (var user in users) {
      final uid = user['id'];
      final username = user['username'];
      final markStr = controllers[uid]?.text ?? '';
      if (markStr.isEmpty) continue;
      final mark = int.tryParse(markStr);
      if (mark == null) continue;

      // Save to Firestore: collection "performance_mark"
      await FirebaseFirestore.instance
          .collection('performance_mark')
          .doc(uid)
          .set({
        'userId': uid,
        'username': username,
        'branch': selectedBranch,
        'score': mark,
        'timestamp': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Performance marks saved!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Performance Entry'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              value: selectedBranch,
              items: branches
                  .map((b) => DropdownMenuItem<String>(
                        value: b['branch'] as String,
                        child: Text(b['branch'] as String),
                      ))
                  .toList(),
              onChanged: (val) {
                setState(() {
                  selectedBranch = val;
                });
                fetchUsersForBranch(val);
              },
              decoration: const InputDecoration(labelText: 'Select Branch'),
            ),
            const SizedBox(height: 16),
            isLoading
                ? const CircularProgressIndicator()
                : Expanded(
                    child: ListView.builder(
                      itemCount: users.length,
                      itemBuilder: (context, idx) {
                        final user = users[idx];
                        return ListTile(
                          title: Text(user['username']),
                          subtitle: TextField(
                            controller: controllers[user['id']],
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Performance Mark',
                              hintText: 'Enter score (0-30)',
                            ),
                          ),
                        );
                      },
                    ),
                  ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: saveMarks,
              child: const Text('Save Marks'),
            ),
          ],
        ),
      ),
    );
  }
}