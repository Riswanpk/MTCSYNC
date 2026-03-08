import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../Misc/user_cache_service.dart';

const Color _primaryBlue = Color(0xFF005BAC);
const Color _primaryGreen = Color(0xFF8CC63F);

class EntryPage extends StatefulWidget {
  @override
  State<EntryPage> createState() => _EntryPageState();
}

class _EntryPageState extends State<EntryPage> {
  String? selectedBranch;
  List<Map<String, dynamic>> branches = [];
  List<Map<String, dynamic>> users = [];
  Map<String, TextEditingController> controllers = {};
  Map<String, TextEditingController> bdaControllers = {};
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    fetchBranches();
  }

  Future<void> fetchBranches() async {
    final cachedUsers = await UserCacheService.instance.getAllUsers();
    final branchSet = <String>{};
    for (var u in cachedUsers) {
      final branch = u['branch'];
      if (branch != null && branch.toString().isNotEmpty) branchSet.add(branch);
    }
    final sortedBranches = branchSet.toList()..sort();
    setState(() {
      branches = sortedBranches.map((b) => {'branch': b}).toList();
    });
  }

  String _monthName(int month) {
    const months = ['January','February','March','April','May','June','July','August','September','October','November','December'];
    return months[month - 1];
  }

  Future<void> fetchUsersForBranch(String? branch) async {
    if (branch == null) return;
    setState(() {
      isLoading = true;
      users = [];
      controllers.clear();
      bdaControllers.clear();
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
        bdaControllers[user['id']] = TextEditingController();
      }
    });

    // Load existing marks for this branch/month
    // Marks entered this month are for the previous month's performance
    final now = DateTime.now();
    final prevMonth = now.month == 1 ? 12 : now.month - 1;
    final prevYear = now.month == 1 ? now.year - 1 : now.year;
    final monthYear = "${_monthName(prevMonth)} $prevYear";
    final branchDoc = await FirebaseFirestore.instance
        .collection('performance_mark')
        .doc(monthYear)
        .collection('branches')
        .doc(branch)
        .get();
    if (branchDoc.exists && branchDoc.data()?['users'] != null) {
      final usersMap = Map<String, dynamic>.from(branchDoc.data()!['users']);
      for (var user in users) {
        final uid = user['id'];
        if (usersMap.containsKey(uid)) {
          final userData = Map<String, dynamic>.from(usersMap[uid]);
          controllers[uid]?.text = (userData['score'] ?? '').toString();
          bdaControllers[uid]?.text = (userData['bdaScore'] ?? '').toString();
        }
      }
    }

    setState(() {
      isLoading = false;
    });
  }

  Future<void> saveMarks() async {
    // Marks entered this month are for the previous month's performance
    final now = DateTime.now();
    final prevMonth = now.month == 1 ? 12 : now.month - 1;
    final prevYear = now.month == 1 ? now.year - 1 : now.year;
    final monthYear = "${_monthName(prevMonth)} $prevYear";

    Map<String, dynamic> usersData = {};
    for (var user in users) {
      final uid = user['id'];
      final username = user['username'];
      final markStr = controllers[uid]?.text ?? '';
      final bdaStr = bdaControllers[uid]?.text ?? '';
      if (markStr.isEmpty && bdaStr.isEmpty) continue;
      final mark = markStr.isNotEmpty ? int.tryParse(markStr) : null;
      final bdaMark = bdaStr.isNotEmpty ? int.tryParse(bdaStr) : null;
      if (mark != null && mark > 30) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Performance mark for $username must be 0-30')),
        );
        return;
      }
      if (bdaMark != null && bdaMark > 20) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('BDA mark for $username must be 0-20')),
        );
        return;
      }
      final userData = <String, dynamic>{'username': username};
      if (mark != null) userData['score'] = mark;
      if (bdaMark != null) userData['bdaScore'] = bdaMark;
      usersData[uid] = userData;
    }

    if (usersData.isEmpty) return;

    final docRef = FirebaseFirestore.instance
        .collection('performance_mark')
        .doc(monthYear)
        .collection('branches')
        .doc(selectedBranch);

    await docRef.set({'users': usersData}, SetOptions(merge: true));

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Performance marks saved!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final now = DateTime.now();
    final prevMonth = now.month == 1 ? 12 : now.month - 1;
    final prevYear = now.month == 1 ? now.year - 1 : now.year;
    final monthLabel = '${_monthName(prevMonth)} $prevYear';

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF181A20) : Colors.white,
      appBar: AppBar(
        title: Text('Performance Entry - $monthLabel'),
        backgroundColor: _primaryBlue,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              value: selectedBranch,
              hint: const Text('Select Branch'),
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
              decoration: InputDecoration(
                labelText: 'Select Branch',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _primaryBlue.withOpacity(0.3)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _primaryBlue, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (selectedBranch == null)
              Expanded(
                child: Center(
                  child: Text(
                    'Select a branch to enter marks',
                    style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600]),
                  ),
                ),
              )
            else if (isLoading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else
              Expanded(
                child: ListView.builder(
                  itemCount: users.length,
                  itemBuilder: (context, idx) {
                    final user = users[idx];
                    return Card(
                      color: isDark ? Colors.grey[900] : Colors.white,
                      elevation: 2,
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(user['username'], style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDark ? Colors.white : _primaryBlue)),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: controllers[user['id']],
                                    keyboardType: TextInputType.number,
                                    decoration: InputDecoration(
                                      labelText: 'Performance Mark',
                                      hintText: '0-30',
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: BorderSide(color: _primaryBlue.withOpacity(0.2)),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: const BorderSide(color: _primaryBlue, width: 2),
                                      ),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextField(
                                    controller: bdaControllers[user['id']],
                                    keyboardType: TextInputType.number,
                                    decoration: InputDecoration(
                                      labelText: 'BDA Marks',
                                      hintText: '0-20',
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: BorderSide(color: _primaryGreen.withOpacity(0.2)),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: const BorderSide(color: _primaryGreen, width: 2),
                                      ),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 16),
            if (selectedBranch != null && !isLoading)
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: saveMarks,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Save Marks', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}