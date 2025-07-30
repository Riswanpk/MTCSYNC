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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Daily Form Entry'),
        backgroundColor: colorScheme.primary,
        elevation: 1,
      ),
      backgroundColor: colorScheme.background,
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Step 1: Branch Dropdown
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: DropdownButtonFormField<String>(
                key: ValueKey('branch-$selectedBranch'),
                value: selectedBranch,
                items: branches
                    .map((b) => DropdownMenuItem<String>(
                          value: b['branch'],
                          child: Text(b['branch'], style: theme.textTheme.bodyLarge),
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
                decoration: InputDecoration(
                  labelText: 'Select Branch',
                  filled: true,
                  fillColor: colorScheme.surface,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Step 2: User Dropdown
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: selectedBranch == null
                  ? const SizedBox.shrink()
                  : DropdownButtonFormField<String>(
                      key: ValueKey('user-$selectedUserId'),
                      value: selectedUserId,
                      items: users
                          .map((u) => DropdownMenuItem<String>(
                                value: u['id'],
                                child: Text(u['username'], style: theme.textTheme.bodyLarge),
                              ))
                          .toList(),
                      onChanged: (val) {
                        setState(() {
                          selectedUserId = val;
                          selectedDocId = null;
                        });
                        if (val != null) fetchFormsForUser(val);
                      },
                      decoration: InputDecoration(
                        labelText: 'Select User',
                        filled: true,
                        fillColor: colorScheme.surface,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
            ),
            const SizedBox(height: 12),
            // Step 3: Date Dropdown
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: (selectedUserId == null || forms.isEmpty)
                  ? const SizedBox.shrink()
                  : DropdownButtonFormField<String>(
                      key: ValueKey('date-$selectedDocId'),
                      value: selectedDocId,
                      items: forms
                          .map((form) {
                            final date = (form['timestamp'] as Timestamp?)?.toDate();
                            final dateStr = date != null
                                ? "${date.day}/${date.month}/${date.year}"
                                : 'Unknown';
                            return DropdownMenuItem<String>(
                              value: form['docId'],
                              child: Text(dateStr, style: theme.textTheme.bodyLarge),
                            );
                          })
                          .toList(),
                      onChanged: (val) {
                        setState(() {
                          selectedDocId = val;
                        });
                      },
                      decoration: InputDecoration(
                        labelText: 'Select Date',
                        filled: true,
                        fillColor: colorScheme.surface,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
            ),
            const SizedBox(height: 18),
            if (selectedDocId != null)
              Expanded(
                child: Card(
                  color: colorScheme.surface,
                  elevation: 3,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: _AdminEditForm(
                      form: forms.firstWhere((f) => f['docId'] == selectedDocId),
                      docId: selectedDocId!,
                      onSaved: () async {
                        // Refresh after save
                        if (selectedUserId != null) await fetchFormsForUser(selectedUserId!);
                      },
                    ),
                  ),
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isApprovedLeave = attendanceStatus == 'approved';
    final isUnapprovedLeave = attendanceStatus == 'notApproved';

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Attendance (never disable these)
            Text(
              'Attendance',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.secondary, // Green from theme
              ),
            ),
            RadioListTile<String>(
              title: const Text('Punching time'),
              value: 'punching',
              groupValue: attendanceStatus,
              onChanged: (val) => setState(() => attendanceStatus = val!),
              activeColor: colorScheme.primary,
            ),
            RadioListTile<String>(
              title: const Text('Late time'),
              value: 'late',
              groupValue: attendanceStatus,
              onChanged: (val) => setState(() => attendanceStatus = val!),
              activeColor: colorScheme.primary,
            ),
            RadioListTile<String>(
              title: const Text('Approved leave'),
              value: 'approved',
              groupValue: attendanceStatus,
              onChanged: (val) => setState(() => attendanceStatus = val!),
              activeColor: colorScheme.primary,
            ),
            RadioListTile<String>(
              title: const Text('Not Approved'),
              value: 'notApproved',
              groupValue: attendanceStatus,
              onChanged: (val) => setState(() => attendanceStatus = val!),
              activeColor: colorScheme.primary,
            ),
            Divider(color: theme.dividerColor),
            // Dress Code
            Text(
              'Dress Code',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.secondary, // Green from theme
              ),
            ),
            CheckboxListTile(
              title: const Text('Wear clean uniform'),
              value: cleanUniform,
              onChanged: (isApprovedLeave || isUnapprovedLeave)
                  ? null
                  : (val) => setState(() => cleanUniform = val!),
              activeColor: colorScheme.primary,
            ),
            CheckboxListTile(
              title: const Text('Keep inside'),
              value: keepInside,
              onChanged: (isApprovedLeave || isUnapprovedLeave)
                  ? null
                  : (val) => setState(() => keepInside = val!),
              activeColor: colorScheme.primary,
            ),
            CheckboxListTile(
              title: const Text('Keep your hair neat'),
              value: neatHair,
              onChanged: (isApprovedLeave || isUnapprovedLeave)
                  ? null
                  : (val) => setState(() => neatHair = val!),
              activeColor: colorScheme.primary,
            ),
            Divider(color: theme.dividerColor),
            // Attitude
            Text(
              'Attitude',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.secondary, // Green from theme
              ),
            ),
            CheckboxListTile(
              title: const Text('Greet with a warm smile'),
              value: greetSmile,
              onChanged: (isApprovedLeave || isUnapprovedLeave)
                  ? null
                  : (val) => setState(() => greetSmile = val!),
              activeColor: colorScheme.primary,
            ),
            CheckboxListTile(
              title: const Text('Ask about their needs'),
              value: askNeeds,
              onChanged: (isApprovedLeave || isUnapprovedLeave)
                  ? null
                  : (val) => setState(() => askNeeds = val!),
              activeColor: colorScheme.primary,
            ),
            CheckboxListTile(
              title: const Text('Help find the right product'),
              value: helpFindProduct,
              onChanged: (isApprovedLeave || isUnapprovedLeave)
                  ? null
                  : (val) => setState(() => helpFindProduct = val!),
              activeColor: colorScheme.primary,
            ),
            CheckboxListTile(
              title: const Text('Confirm the purchase'),
              value: confirmPurchase,
              onChanged: (isApprovedLeave || isUnapprovedLeave)
                  ? null
                  : (val) => setState(() => confirmPurchase = val!),
              activeColor: colorScheme.primary,
            ),
            CheckboxListTile(
              title: const Text('Offer carry or delivery help'),
              value: offerHelp,
              onChanged: (isApprovedLeave || isUnapprovedLeave)
                  ? null
                  : (val) => setState(() => offerHelp = val!),
              activeColor: colorScheme.primary,
            ),
            Divider(color: theme.dividerColor),
            // Meeting
            Text(
              'Meeting',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.secondary, // Green from theme
              ),
            ),
            CheckboxListTile(
              title: const Text('Attended'),
              value: meetingAttended,
              onChanged: (isApprovedLeave || isUnapprovedLeave)
                  ? null
                  : (val) => setState(() => meetingAttended = val!),
              activeColor: colorScheme.primary,
            ),
            Divider(color: theme.dividerColor),
            // Performance
            Text('Performance (End of Month Only)', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            AbsorbPointer(
              absorbing: isApprovedLeave || !_isEndOfMonth(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CheckboxListTile(
                    title: const Text('Target Achieved'),
                    value: targetAchieved ?? false,
                    onChanged: (val) => setState(() => targetAchieved = val),
                    activeColor: colorScheme.primary,
                  ),
                  CheckboxListTile(
                    title: const Text('Other Performance'),
                    value: otherPerformance ?? false,
                    onChanged: (val) => setState(() => otherPerformance = val),
                    activeColor: colorScheme.primary,
                  ),
                  if (!_isEndOfMonth())
                    Padding(
                      padding: const EdgeInsets.only(left: 16.0, top: 4),
                      child: Text(
                        "Performance can be filled only at the end of the month.",
                        style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.error),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
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