import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PerformanceForm extends StatefulWidget {
  @override
  _PerformanceFormState createState() => _PerformanceFormState();
}

class _PerformanceFormState extends State<PerformanceForm> {
  // Attendance
  String? attendanceStatus; // values: 'punching', 'late', 'approved', 'notApproved'

  // Dress Code
  bool cleanUniform = false;
  bool keepInside = false;
  bool neatHair = false;

  // Attitude
  bool greetSmile = false;
  bool askNeeds = false;
  bool helpFindProduct = false;
  bool confirmPurchase = false;
  bool offerHelp = false;

  // Meeting
  bool meetingAttended = false;

  // 1. Add state variables for performance
  bool? targetAchieved; // null = not selected, true/false = selected
  bool? otherPerformance; // null = not selected, true/false = selected

  String? selectedUserId;
  String? selectedUserName;
  List<Map<String, dynamic>> branchUsers = [];
  bool isLoadingUsers = true;

  @override
  void initState() {
    super.initState();
    fetchBranchUsers();
  }

  Future<void> fetchBranchUsers() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final userDoc = await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).get();
    final branch = userDoc.data()?['branch'];

    if (branch == null) return;

    // Get today's date range
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));

    // Fetch users of the same branch
    final usersSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('branch', isEqualTo: branch)
        .get();

    // Fetch dailyform entries by this manager for today
    final dailyFormSnapshot = await FirebaseFirestore.instance
        .collection('dailyform')
        .where('managerId', isEqualTo: currentUser.uid)
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart))
        .where('timestamp', isLessThan: Timestamp.fromDate(todayEnd))
        .get();

    // Get userIds already filled today by this manager
    final filledUserIds = dailyFormSnapshot.docs.map((doc) => doc['userId'] as String).toSet();

    setState(() {
      branchUsers = usersSnapshot.docs
          .where((doc) => doc.id != currentUser.uid) // Exclude self
          .where((doc) => !filledUserIds.contains(doc.id)) // Exclude already filled users
          .map((doc) => {
                'id': doc.id,
                'username': doc.data()['username'] ?? doc.data()['email'] ?? 'User',
              })
          .toList();
      isLoadingUsers = false;
    });
  }

  bool _isEndOfMonth() {
    final now = DateTime.now();
    final lastDay = DateTime(now.year, now.month + 1, 0).day;
    return now.day >= lastDay - 2; // Allow last 3 days of month
  }

  Future<void> submitForm() async {
    if (selectedUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please select a user')),
      );
      return;
    }

    // Check again before submit (in case of race condition)
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));
    final currentUser = FirebaseAuth.instance.currentUser;

    final alreadyFilled = await FirebaseFirestore.instance
        .collection('dailyform')
        .where('managerId', isEqualTo: currentUser!.uid)
        .where('userId', isEqualTo: selectedUserId)
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart))
        .where('timestamp', isLessThan: Timestamp.fromDate(todayEnd))
        .get();

    if (alreadyFilled.docs.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('You have already filled the form for this user today.')),
      );
      return;
    }

    final managerDoc = await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).get();
    final managerName = managerDoc.data()?['username'] ?? managerDoc.data()?['email'] ?? 'Manager';

    await FirebaseFirestore.instance.collection('dailyform').add({
      'userId': selectedUserId,
      'userName': selectedUserName,
      'managerId': currentUser.uid,
      'managerName': managerName,
      'timestamp': FieldValue.serverTimestamp(),
      'attendance': attendanceStatus,
      'dressCode': {
        'cleanUniform': cleanUniform,
        'keepInside': keepInside,
        'neatHair': neatHair,
      },
      'attitude': {
        'greetSmile': greetSmile,
        'askNeeds': askNeeds,
        'helpFindProduct': helpFindProduct,
        'confirmPurchase': confirmPurchase,
        'offerHelp': offerHelp,
      },
      'meeting': {
        'attended': meetingAttended,
      },
      // 4. In your submitForm(), add to Firestore:
      'performance': _isEndOfMonth()
          ? {
              'target': targetAchieved ?? false,
              'otherPerformance': otherPerformance ?? false,
            }
          : null,
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Form submitted!')),
    );
    setState(() {
      // Reset form
      attendanceStatus = null;
      cleanUniform = false;
      keepInside = false;
      neatHair = false;  
      greetSmile = false;
      askNeeds = false;
      helpFindProduct = false;
      confirmPurchase = false;
      offerHelp = false;
      meetingAttended = false;
      selectedUserId = null;
      selectedUserName = null;
      isLoadingUsers = true;
      // 5. In setState after submit, reset:
      targetAchieved = null;
      otherPerformance = null;
    });
    // Refresh user list to remove the just-filled user
    fetchBranchUsers();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Performance Form')),
      body: isLoadingUsers
          ? Center(child: CircularProgressIndicator())
          : branchUsers.isEmpty
              ? Center(
                  child: Text(
                    'All users have been filled for today!',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                )
              : SingleChildScrollView(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Select User', style: TextStyle(fontWeight: FontWeight.bold)),
                      DropdownButtonFormField<String>(
                        value: selectedUserId,
                        items: branchUsers
                            .map((user) => DropdownMenuItem<String>(
                                  value: user['id'],
                                  child: Text(user['username']),
                                ))
                            .toList(),
                        onChanged: (val) {
                          setState(() {
                            selectedUserId = val;
                            selectedUserName = branchUsers.firstWhere((u) => u['id'] == val)['username'];
                          });
                        },
                        decoration: InputDecoration(
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        hint: Text('Choose user'),
                      ),
                      SizedBox(height: 16),
                      Text('1) Attendance', style: TextStyle(fontWeight: FontWeight.bold)),
                      RadioListTile<String>(
                        title: Text('Punching time'),
                        value: 'punching',
                        groupValue: attendanceStatus,
                        onChanged: (val) => setState(() => attendanceStatus = val),
                      ),
                      RadioListTile<String>(
                        title: Text('Late time'),
                        value: 'late',
                        groupValue: attendanceStatus,
                        onChanged: (val) => setState(() => attendanceStatus = val),
                      ),
                      RadioListTile<String>(
                        title: Text('Approved leave'),
                        value: 'approved',
                        groupValue: attendanceStatus,
                        onChanged: (val) => setState(() => attendanceStatus = val),
                      ),
                      RadioListTile<String>(
                        title: Text('Not Approved'),
                        value: 'notApproved',
                        groupValue: attendanceStatus,
                        onChanged: (val) => setState(() => attendanceStatus = val),
                      ),
                      Divider(),

                      Text('2) Dress Code', style: TextStyle(fontWeight: FontWeight.bold)),
                      CheckboxListTile(
                        title: Text('Wear clean uniform'),
                        value: cleanUniform,
                        onChanged: (val) => setState(() => cleanUniform = val!),
                      ),
                      CheckboxListTile(
                        title: Text('Keep inside'),
                        value: keepInside,
                        onChanged: (val) => setState(() => keepInside = val!),
                      ),
                      CheckboxListTile(
                        title: Text('Keep your hair neat'),
                        value: neatHair,
                        onChanged: (val) => setState(() => neatHair = val!),
                      ),
                      Divider(),

                      Text('3) Attitude', style: TextStyle(fontWeight: FontWeight.bold)),
                      CheckboxListTile(
                        title: Text('Greet with a warm smile'),
                        value: greetSmile,
                        onChanged: (val) => setState(() => greetSmile = val!),
                      ),
                      CheckboxListTile(
                        title: Text('Ask about their needs'),
                        value: askNeeds,
                        onChanged: (val) => setState(() => askNeeds = val!),
                      ),
                      CheckboxListTile(
                        title: Text('Help find the right product'),
                        value: helpFindProduct,
                        onChanged: (val) => setState(() => helpFindProduct = val!),
                      ),
                      CheckboxListTile(
                        title: Text('Confirm the purchase'),
                        value: confirmPurchase,
                        onChanged: (val) => setState(() => confirmPurchase = val!),
                      ),
                      CheckboxListTile(
                        title: Text('Offer carry or delivery help'),
                        value: offerHelp,
                        onChanged: (val) => setState(() => offerHelp = val!),
                      ),
                      Divider(),

                      Text('4) Meeting', style: TextStyle(fontWeight: FontWeight.bold)),
                      CheckboxListTile(
                        title: Text('Attended'),
                        value: meetingAttended,
                        onChanged: (val) => setState(() => meetingAttended = val!),
                      ),
                      Divider(),

                      Text('5) Performance (End of Month Only)', style: TextStyle(fontWeight: FontWeight.bold)),
                      AbsorbPointer(
                        absorbing: !_isEndOfMonth(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CheckboxListTile(
                              title: Text('Target Achieved '),
                              value: targetAchieved ?? false,
                              onChanged: (val) => setState(() => targetAchieved = val),
                            ),
                            CheckboxListTile(
                              title: Text('Other Performance '),
                              value: otherPerformance ?? false,
                              onChanged: (val) => setState(() => otherPerformance = val),
                            ),
                            if (!_isEndOfMonth())
                              Padding(
                                padding: const EdgeInsets.only(left: 16.0, top: 4),
                                child: Text(
                                  "Performance can be filled only at the end of the month.",
                                  style: TextStyle(color: Colors.red, fontSize: 13),
                                ),
                              ),
                          ],
                        ),
                      ),
                      SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: selectedUserId == null ? null : submitForm,
                        child: Text('Submit'),
                      ),
                    ],
                  ),
                ),
    );
  }
}