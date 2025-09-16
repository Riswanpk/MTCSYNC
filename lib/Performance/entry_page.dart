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

  Future<void> savePerformanceMark(String userId, int score) async {
    final now = DateTime.now();
    final month = now.month;
    final year = now.year;

    // Only allow marks <= 30
    if (score > 30) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mark cannot be greater than 30')),
      );
      return;
    }

    final query = await FirebaseFirestore.instance
        .collection('performance_mark')
        .where('userId', isEqualTo: userId)
        .where('month', isEqualTo: month)
        .where('year', isEqualTo: year)
        .get();

    if (query.docs.isNotEmpty) {
      // Update existing entry for this month
      final docId = query.docs.first.id;
      await FirebaseFirestore.instance
          .collection('performance_mark')
          .doc(docId)
          .update({'score': score});
    } else {
      // Create new entry for new month
      await FirebaseFirestore.instance.collection('performance_mark').add({
        'userId': userId,
        'score': score,
        'month': month,
        'year': year,
        'timestamp': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> saveMarks() async {
    for (var user in users) {
      final uid = user['id'];
      final username = user['username'];
      final markStr = controllers[uid]?.text ?? '';
      if (markStr.isEmpty) continue;
      final mark = int.tryParse(markStr);
      if (mark == null || mark > 30) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Mark for $username must be 0-30')),
        );
        continue;
      }
      await savePerformanceMark(uid, mark);
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