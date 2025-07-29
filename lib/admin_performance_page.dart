import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminPerformancePage extends StatefulWidget {
  const AdminPerformancePage({Key? key}) : super(key: key);

  @override
  State<AdminPerformancePage> createState() => _AdminPerformancePageState();
}

class _AdminPerformancePageState extends State<AdminPerformancePage> {
  String? selectedBranch;
  String? selectedUserId;
  String? selectedDocId;
  List<Map<String, dynamic>> branches = [];
  List<Map<String, dynamic>> users = [];
  List<Map<String, dynamic>> forms = [];
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
    });
  }

  Future<void> fetchUsersForBranch(String branch) async {
    setState(() {
      users = [];
      selectedUserId = null;
      forms = [];
      selectedDocId = null;
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
    });
  }

  Future<void> fetchFormsForUser(String userId) async {
    setState(() {
      forms = [];
      isLoading = true;
      selectedDocId = null;
    });
    final formsSnap = await FirebaseFirestore.instance
        .collection('dailyform')
        .where('userId', isEqualTo: userId)
        .orderBy('timestamp', descending: true)
        .get();
    setState(() {
      forms = formsSnap.docs
          .map((doc) => {
                ...doc.data(),
                'docId': doc.id,
              })
          .toList();
      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Daily Form Entry'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Branch Dropdown
            DropdownButtonFormField<String>(
              value: selectedBranch,
              items: branches
                  .map((b) => DropdownMenuItem<String>(
                        value: b['branch'],
                        child: Text(b['branch']),
                      ))
                  .toList(),
              onChanged: (val) {
                setState(() {
                  selectedBranch = val;
                  selectedUserId = null;
                  forms = [];
                  selectedDocId = null;
                });
                if (val != null) fetchUsersForBranch(val);
              },
              decoration: const InputDecoration(labelText: 'Select Branch'),
            ),
            const SizedBox(height: 12),
            // User Dropdown
            DropdownButtonFormField<String>(
              value: selectedUserId,
              items: users
                  .map((u) => DropdownMenuItem<String>(
                        value: u['id'],
                        child: Text(u['username']),
                      ))
                  .toList(),
              onChanged: (val) {
                setState(() {
                  selectedUserId = val;
                  selectedDocId = null;
                });
                if (val != null) fetchFormsForUser(val);
              },
              decoration: const InputDecoration(labelText: 'Select User'),
            ),
            const SizedBox(height: 12),
            // Date Dropdown
            if (forms.isNotEmpty)
              DropdownButtonFormField<String>(
                value: selectedDocId,
                items: forms
                    .map((form) {
                      final date = (form['timestamp'] as Timestamp?)?.toDate();
                      final dateStr = date != null
                          ? "${date.day}/${date.month}/${date.year}"
                          : 'Unknown';
                      return DropdownMenuItem<String>(
                        value: form['docId'],
                        child: Text(dateStr),
                      );
                    })
                    .toList(),
                onChanged: (val) {
                  setState(() {
                    selectedDocId = val;
                  });
                },
                decoration: const InputDecoration(labelText: 'Select Date'),
              ),
            const SizedBox(height: 18),
            if (selectedDocId != null)
              Expanded(
                child: _AdminEditForm(
                  form: forms.firstWhere((f) => f['docId'] == selectedDocId),
                  docId: selectedDocId!,
                  onSaved: () async {
                    // Refresh after save
                    if (selectedUserId != null) await fetchFormsForUser(selectedUserId!);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AdminEditForm extends StatefulWidget {
  final Map<String, dynamic> form;
  final String docId;
  final VoidCallback onSaved;

  const _AdminEditForm({
    required this.form,
    required this.docId,
    required this.onSaved,
  });

  @override
  State<_AdminEditForm> createState() => _AdminEditFormState();
}

class _AdminEditFormState extends State<_AdminEditForm> {
  late String attendance;
  late String attendanceStatus;
  late bool cleanUniform;
  late bool keepInside;
  late bool neatHair;
  late bool greetSmile;
  late bool askNeeds;
  late bool helpFindProduct;
  late bool confirmPurchase;
  late bool offerHelp;
  late bool meetingAttended;
  late bool? targetAchieved;
  late bool? otherPerformance;

  @override
  void initState() {
    super.initState();
    final f = widget.form;
    attendance = f['attendance']?.toString() ?? '';
    attendanceStatus = f['attendance']?.toString() ?? '';
    cleanUniform = f['dressCode']?['cleanUniform'] ?? false;
    keepInside = f['dressCode']?['keepInside'] ?? false;
    neatHair = f['dressCode']?['neatHair'] ?? false;
    greetSmile = f['attitude']?['greetSmile'] ?? false;
    askNeeds = f['attitude']?['askNeeds'] ?? false;
    helpFindProduct = f['attitude']?['helpFindProduct'] ?? false;
    confirmPurchase = f['attitude']?['confirmPurchase'] ?? false;
    offerHelp = f['attitude']?['offerHelp'] ?? false;
    meetingAttended = f['meeting']?['attended'] ?? false;
    targetAchieved = f['performance']?['target'];
    otherPerformance = f['performance']?['otherPerformance'];
  }

  Future<void> save() async {
    await FirebaseFirestore.instance.collection('dailyform').doc(widget.docId).update({
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
      'performance': {
        'target': targetAchieved,
        'otherPerformance': otherPerformance,
      },
    });
    widget.onSaved();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Entry updated!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isApprovedLeave = attendanceStatus == 'approved';
    final isUnapprovedLeave = attendanceStatus == 'notApproved';

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Attendance (never disable these)
            const Text('Attendance', style: TextStyle(fontWeight: FontWeight.bold)),
            RadioListTile<String>(
              title: const Text('Punching time'),
              value: 'punching',
              groupValue: attendanceStatus,
              onChanged: (val) => setState(() => attendanceStatus = val!),
            ),
            RadioListTile<String>(
              title: const Text('Late time'),
              value: 'late',
              groupValue: attendanceStatus,
              onChanged: (val) => setState(() => attendanceStatus = val!),
            ),
            RadioListTile<String>(
              title: const Text('Approved leave'),
              value: 'approved',
              groupValue: attendanceStatus,
              onChanged: (val) => setState(() => attendanceStatus = val!),
            ),
            RadioListTile<String>(
              title: const Text('Not Approved'),
              value: 'notApproved',
              groupValue: attendanceStatus,
              onChanged: (val) => setState(() => attendanceStatus = val!),
            ),
            const Divider(),
            // Dress Code
            const Text('Dress Code', style: TextStyle(fontWeight: FontWeight.bold)),
            CheckboxListTile(
              title: const Text('Wear clean uniform'),
              value: cleanUniform,
              onChanged: (attendanceStatus == 'approved' || attendanceStatus == 'notApproved')
                  ? null
                  : (val) => setState(() => cleanUniform = val!),
            ),
            CheckboxListTile(
              title: const Text('Keep inside'),
              value: keepInside,
              onChanged: (attendanceStatus == 'approved' || attendanceStatus == 'notApproved')
                  ? null
                  : (val) => setState(() => keepInside = val!),
            ),
            CheckboxListTile(
              title: const Text('Keep your hair neat'),
              value: neatHair,
              onChanged: (attendanceStatus == 'approved' || attendanceStatus == 'notApproved')
                  ? null
                  : (val) => setState(() => neatHair = val!),
            ),
            const Divider(),
            // Attitude
            const Text('Attitude', style: TextStyle(fontWeight: FontWeight.bold)),
            CheckboxListTile(
              title: const Text('Greet with a warm smile'),
              value: greetSmile,
              onChanged: (attendanceStatus == 'approved' || attendanceStatus == 'notApproved')
                  ? null
                  : (val) => setState(() => greetSmile = val!),
            ),
            CheckboxListTile(
              title: const Text('Ask about their needs'),
              value: askNeeds,
              onChanged: (attendanceStatus == 'approved' || attendanceStatus == 'notApproved')
                  ? null
                  : (val) => setState(() => askNeeds = val!),
            ),
            CheckboxListTile(
              title: const Text('Help find the right product'),
              value: helpFindProduct,
              onChanged: (attendanceStatus == 'approved' || attendanceStatus == 'notApproved')
                  ? null
                  : (val) => setState(() => helpFindProduct = val!),
            ),
            CheckboxListTile(
              title: const Text('Confirm the purchase'),
              value: confirmPurchase,
              onChanged: (attendanceStatus == 'approved' || attendanceStatus == 'notApproved')
                  ? null
                  : (val) => setState(() => confirmPurchase = val!),
            ),
            CheckboxListTile(
              title: const Text('Offer carry or delivery help'),
              value: offerHelp,
              onChanged: (attendanceStatus == 'approved' || attendanceStatus == 'notApproved')
                  ? null
                  : (val) => setState(() => offerHelp = val!),
            ),
            const Divider(),
            // Meeting
            const Text('Meeting', style: TextStyle(fontWeight: FontWeight.bold)),
            CheckboxListTile(
              title: const Text('Attended'),
              value: meetingAttended,
              onChanged: (attendanceStatus == 'approved' || attendanceStatus == 'notApproved')
                  ? null
                  : (val) => setState(() => meetingAttended = val!),
            ),
            const Divider(),
            // Performance
            const Text('Performance (End of Month Only)', style: TextStyle(fontWeight: FontWeight.bold)),
            AbsorbPointer(
              absorbing: isApprovedLeave || !_isEndOfMonth(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CheckboxListTile(
                    title: const Text('Target Achieved'),
                    value: targetAchieved ?? false,
                    onChanged: (val) => setState(() => targetAchieved = val),
                  ),
                  CheckboxListTile(
                    title: const Text('Other Performance'),
                    value: otherPerformance ?? false,
                    onChanged: (val) => setState(() => otherPerformance = val),
                  ),
                  if (!_isEndOfMonth())
                    const Padding(
                      padding: EdgeInsets.only(left: 16.0, top: 4),
                      child: Text(
                        "Performance can be filled only at the end of the month.",
                        style: TextStyle(color: Colors.red, fontSize: 13),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: ElevatedButton(
                onPressed: save,
                child: const Text('Save Changes'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isEndOfMonth() {
    final now = DateTime.now();
    final lastDay = DateTime(now.year, now.month + 1, 0).day;
    return now.day >= lastDay - 2; // Allow last 3 days of month
  }
}