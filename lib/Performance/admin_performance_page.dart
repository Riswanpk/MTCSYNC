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
  int? selectedMonth;
  DateTime? selectedDate;
  List<Map<String, dynamic>> branches = [];
  List<Map<String, dynamic>> users = [];
  List<Map<String, dynamic>> forms = [];
  List<DateTime> availableDates = [];
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
      selectedMonth = null;
      selectedDate = null;
      availableDates = [];
    });
    final formsSnap = await FirebaseFirestore.instance
        .collection('dailyform')
        .where('userId', isEqualTo: userId)
        .orderBy('timestamp', descending: true)
        .get();
    forms = formsSnap.docs
        .map((doc) => {
              ...doc.data(),
              'docId': doc.id,
            })
        .toList();

    // Extract available months and dates
    final monthsSet = <int>{};
    final datesSet = <DateTime>{};
    for (var form in forms) {
      final ts = form['timestamp'] as Timestamp?;
      if (ts != null) {
        final date = ts.toDate();
        monthsSet.add(date.month);
        datesSet.add(DateTime(date.year, date.month, date.day));
      }
    }
    setState(() {
      isLoading = false;
      selectedMonth = monthsSet.isNotEmpty ? monthsSet.first : null;
      availableDates = datesSet.where((d) => selectedMonth == null || d.month == selectedMonth).toList()
        ..sort((a, b) => b.compareTo(a));
      selectedDate = null; // Don't auto-select date
      selectedDocId = null;
    });
  }

  void updateAvailableDates() {
    if (selectedMonth == null) {
      setState(() {
        availableDates = [];
        selectedDate = null;
        selectedDocId = null;
      });
      return;
    }
    availableDates = forms
        .map((f) => (f['timestamp'] as Timestamp?)?.toDate())
        .where((d) => d != null && d.month == selectedMonth)
        .map((d) => DateTime(d!.year, d.month, d.day))
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));
    setState(() {
      selectedDate = null;
      selectedDocId = null;
    });
  }

  void updateSelectedDocId() {
    if (selectedDate != null) {
      final doc = forms.firstWhere(
        (f) {
          final ts = f['timestamp'] as Timestamp?;
          final date = ts?.toDate();
          return date != null &&
              date.year == selectedDate!.year &&
              date.month == selectedDate!.month &&
              date.day == selectedDate!.day;
        },
        orElse: () => {},
      );
      setState(() {
        selectedDocId = doc['docId'];
      });
    } else {
      setState(() {
        selectedDocId = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Get all months present in forms
    final monthsList = forms
        .map((f) => (f['timestamp'] as Timestamp?)?.toDate())
        .where((d) => d != null)
        .map((d) => d!.month)
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));

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
            // --- First row: Branch & User ---
            Row(
              children: [
                Expanded(
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
                        selectedMonth = null;
                        selectedDate = null;
                        availableDates = [];
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
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
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
                        selectedMonth = null;
                        selectedDate = null;
                        availableDates = [];
                        forms = [];
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
              ],
            ),
            const SizedBox(height: 12),
            // --- Second row: Month & Date ---
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    key: ValueKey('month-$selectedMonth'),
                    value: selectedMonth,
                    items: monthsList
                        .map((m) => DropdownMenuItem<int>(
                              value: m,
                              child: Text(
                                "${m.toString().padLeft(2, '0')}",
                                style: theme.textTheme.bodyLarge,
                              ),
                            ))
                        .toList(),
                    onChanged: (val) {
                      setState(() {
                        selectedMonth = val;
                      });
                      updateAvailableDates();
                    },
                    decoration: InputDecoration(
                      labelText: 'Select Month',
                      filled: true,
                      fillColor: colorScheme.surface,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<DateTime>(
                    key: ValueKey('date-$selectedDate'),
                    value: selectedDate,
                    items: availableDates
                        .map((d) => DropdownMenuItem<DateTime>(
                              value: d,
                              child: Text(
                                "${d.day}", // Only show day number
                                style: theme.textTheme.bodyLarge,
                              ),
                            ))
                        .toList(),
                    onChanged: (val) {
                      setState(() {
                        selectedDate = val;
                        // Always update selectedDocId and force rebuild
                        updateSelectedDocId();
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
              ],
            ),
            const SizedBox(height: 18),
            if (selectedDocId != null)
              Expanded(
                key: ValueKey(selectedDocId), // <-- Add key to force rebuild when docId changes
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
  // REMOVE performance fields
  // late bool? targetAchieved;
  // late bool? otherPerformance;

  // Add these fields:
  late String? greetSmileLevel;
  late String? askNeedsLevel;
  late String? helpFindProductLevel;
  late String? confirmPurchaseLevel;
  late String? offerHelpLevel;
  late TextEditingController greetSmileReasonController;
  late TextEditingController askNeedsReasonController;
  late TextEditingController helpFindProductReasonController;
  late TextEditingController confirmPurchaseReasonController;
  late TextEditingController offerHelpReasonController;

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
    greetSmileLevel = f['attitude']?['greetSmileLevel'];
    askNeeds = f['attitude']?['askNeeds'] ?? false;
    askNeedsLevel = f['attitude']?['askNeedsLevel'];
    helpFindProduct = f['attitude']?['helpFindProduct'] ?? false;
    helpFindProductLevel = f['attitude']?['helpFindProductLevel'];
    confirmPurchase = f['attitude']?['confirmPurchase'] ?? false;
    confirmPurchaseLevel = f['attitude']?['confirmPurchaseLevel'];
    offerHelp = f['attitude']?['offerHelp'] ?? false;
    offerHelpLevel = f['attitude']?['offerHelpLevel'];
    meetingAttended = f['meeting']?['attended'] ?? false;
    // REMOVE performance fields
    // targetAchieved = f['performance']?['target'];
    // otherPerformance = f['performance']?['otherPerformance'];
    greetSmileReasonController = TextEditingController(text: f['attitude']?['greetSmileReason'] ?? '');
    askNeedsReasonController = TextEditingController(text: f['attitude']?['askNeedsReason'] ?? '');
    helpFindProductReasonController = TextEditingController(text: f['attitude']?['helpFindProductReason'] ?? '');
    confirmPurchaseReasonController = TextEditingController(text: f['attitude']?['confirmPurchaseReason'] ?? '');
    offerHelpReasonController = TextEditingController(text: f['attitude']?['offerHelpReason'] ?? '');
  }

  @override
  void dispose() {
    greetSmileReasonController.dispose();
    askNeedsReasonController.dispose();
    helpFindProductReasonController.dispose();
    confirmPurchaseReasonController.dispose();
    offerHelpReasonController.dispose();
    super.dispose();
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
        'greetSmileLevel': greetSmileLevel,
        'greetSmileReason': greetSmileReasonController.text,
        'askNeeds': askNeeds,
        'askNeedsLevel': askNeedsLevel,
        'askNeedsReason': askNeedsReasonController.text,
        'helpFindProduct': helpFindProduct,
        'helpFindProductLevel': helpFindProductLevel,
        'helpFindProductReason': helpFindProductReasonController.text,
        'confirmPurchase': confirmPurchase,
        'confirmPurchaseLevel': confirmPurchaseLevel,
        'confirmPurchaseReason': confirmPurchaseReasonController.text,
        'offerHelp': offerHelp,
        'offerHelpLevel': offerHelpLevel,
        'offerHelpReason': offerHelpReasonController.text,
      },
      'meeting': {
        'attended': meetingAttended,
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
                color: theme.colorScheme.secondary,
              ),
            ),
            _attitudeAdminRow(
              label: 'Greet with a warm smile',
              value: greetSmile,
              level: greetSmileLevel,
              onChanged: (val, level) => setState(() {
                greetSmile = val;
                greetSmileLevel = level;
              }),
              enabled: !(isApprovedLeave || isUnapprovedLeave),
            ),
            TextFormField(
              controller: greetSmileReasonController,
              decoration: InputDecoration(labelText: 'Reason'),
            ),
            _attitudeAdminRow(
              label: 'Ask about their needs',
              value: askNeeds,
              level: askNeedsLevel,
              onChanged: (val, level) => setState(() {
                askNeeds = val;
                askNeedsLevel = level;
              }),
              enabled: !(isApprovedLeave || isUnapprovedLeave),
            ),
            TextFormField(
              controller: askNeedsReasonController,
              decoration: InputDecoration(labelText: 'Reason'),
            ),
            _attitudeAdminRow(
              label: 'Help find the right product',
              value: helpFindProduct,
              level: helpFindProductLevel,
              onChanged: (val, level) => setState(() {
                helpFindProduct = val;
                helpFindProductLevel = level;
              }),
              enabled: !(isApprovedLeave || isUnapprovedLeave),
            ),
            TextFormField(
              controller: helpFindProductReasonController,
              decoration: InputDecoration(labelText: 'Reason'),
            ),
            _attitudeAdminRow(
              label: 'Confirm the purchase',
              value: confirmPurchase,
              level: confirmPurchaseLevel,
              onChanged: (val, level) => setState(() {
                confirmPurchase = val;
                confirmPurchaseLevel = level;
              }),
              enabled: !(isApprovedLeave || isUnapprovedLeave),
            ),
            TextFormField(
              controller: confirmPurchaseReasonController,
              decoration: InputDecoration(labelText: 'Reason'),
            ),
            _attitudeAdminRow(
              label: 'Offer carry or delivery help',
              value: offerHelp,
              level: offerHelpLevel,
              onChanged: (val, level) => setState(() {
                offerHelp = val;
                offerHelpLevel = level;
              }),
              enabled: !(isApprovedLeave || isUnapprovedLeave),
            ),
            TextFormField(
              controller: offerHelpReasonController,
              decoration: InputDecoration(labelText: 'Reason'),
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
            // REMOVE Performance section from UI
            // Text('Performance (End of Month Only)', ...),
            // AbsorbPointer(...),
            // const SizedBox(height: 16),
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

  Widget _attitudeAdminRow({
    required String label,
    required bool value,
    required String? level,
    required Function(bool, String?) onChanged,
    required bool enabled,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(label),
          ),
          Expanded(
            child: Column(
              children: [
                Text('Excellent', style: TextStyle(fontSize: 12)),
                Checkbox(
                  value: level == 'excellent',
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  onChanged: enabled
                      ? (val) {
                          if (val == true) {
                            onChanged(true, 'excellent');
                          } else {
                            onChanged(false, null);
                          }
                        }
                      : null,
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Text('Average', style: TextStyle(fontSize: 12)),
                Checkbox(
                  value: level == 'average',
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  onChanged: enabled
                      ? (val) {
                          if (val == true) {
                            onChanged(true, 'average');
                          } else {
                            onChanged(false, null);
                          }
                        }
                      : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}