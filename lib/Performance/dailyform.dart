import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

/// App brand colors
const Color primaryBlue = Color(0xFF005BAC);
const Color primaryGreen = Color(0xFF8CC63F);

class PerformanceForm extends StatefulWidget {
  @override
  _PerformanceFormState createState() => _PerformanceFormState();
}

class _PerformanceFormState extends State<PerformanceForm> {
    // Additional questions
    String? timeTakenOtherTasks;
    bool? oldStockOfferGiven;
    bool? crossSellingUpselling;
    bool? productComplaints;
    bool? achievedDailyTarget;
  // Date selection
  DateTime selectedDate = DateTime.now();
  List<DateTime> allowedDates = [];

  // Attendance
  String?
      attendanceStatus; // values: 'punching', 'late', 'approved', 'notApproved'

  // Dress Code
  bool cleanUniform = false;
  bool keepInside = false;
  bool neatHair = false;

  // Attitude
  bool? greetSmile; // null = unselected, true = Excellent, false = Average
  bool? askNeeds; // null = unselected, true = Excellent, false = Average
  bool? helpFindProduct; // null = unselected, true = Excellent, false = Average
  bool? confirmPurchase; // null = unselected, true = Excellent, false = Average
  bool? offerHelp; // null = unselected, true = Excellent, false = Average
  bool attitudeExcellent = false;
  bool attitudeAverage = false;
  String? greetSmileLevel;
  String? askNeedsLevel;
  String? helpFindProductLevel;
  String? confirmPurchaseLevel;
  String? offerHelpLevel;

  // Meeting
  bool meetingAttended = false;
  bool meetingNoMeeting = false;

  String? selectedUserId;
  String? selectedUserName;
  List<Map<String, dynamic>> branchUsers = [];
  bool isLoadingUsers = true;

  // Reasons for attitude selections
  Map<String, String> attitudeReasons = {
    'greetSmile': '',
    'askNeeds': '',
    'helpFindProduct': '',
    'confirmPurchase': '',
    'offerHelp': '',
  };

  @override
  void initState() {
    super.initState();
    _initAllowedDates();
    fetchBranchUsers();
  }

  void _initAllowedDates() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    allowedDates = [today, yesterday];
    selectedDate = today;
  }

  Future<void> fetchBranchUsers() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser.uid)
        .get();
    final branch = userDoc.data()?['branch'];

    if (branch == null) return;

    // Get selected date range
    final dateStart =
        DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
    final dateEnd = dateStart.add(const Duration(days: 1));

    // Fetch users of the same branch
    final usersSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('branch', isEqualTo: branch)
        .get();

    // Fetch dailyform entries by this manager for selected date
    final dailyFormSnapshot = await FirebaseFirestore.instance
        .collection('dailyform')
        .where('managerId', isEqualTo: currentUser.uid)
        .where('timestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(dateStart))
        .where('timestamp', isLessThan: Timestamp.fromDate(dateEnd))
        .get();

    // Get userIds already filled for selected date by this manager
    final filledUserIds =
        dailyFormSnapshot.docs.map((doc) => doc['userId'] as String).toSet();

    setState(() {
      branchUsers = usersSnapshot.docs
          .where((doc) => doc.id != currentUser.uid) // Exclude self
          .where((doc) =>
              !filledUserIds.contains(doc.id)) // Exclude already filled users
          .map((doc) => {
                'id': doc.id,
                'username':
                    doc.data()['username'] ?? doc.data()['email'] ?? 'User',
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
    final dateStart =
        DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
    final dateEnd = dateStart.add(const Duration(days: 1));
    final currentUser = FirebaseAuth.instance.currentUser;

    final alreadyFilled = await FirebaseFirestore.instance
        .collection('dailyform')
        .where('managerId', isEqualTo: currentUser!.uid)
        .where('userId', isEqualTo: selectedUserId)
        .where('timestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(dateStart))
        .where('timestamp', isLessThan: Timestamp.fromDate(dateEnd))
        .get();

    if (alreadyFilled.docs.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'You have already filled the form for this user on this date.')),
      );
      return;
    }

    final managerDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser.uid)
        .get();
    final managerName = managerDoc.data()?['username'] ??
        managerDoc.data()?['email'] ??
        'Manager';

    // If leave, set all other fields to true
    bool isLeave =
        attendanceStatus == 'approved' || attendanceStatus == 'notApproved';

    // Create timestamp for the selected date with current time
    final now = DateTime.now();
    final submissionTimestamp = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      now.hour,
      now.minute,
      now.second,
    );

    await FirebaseFirestore.instance.collection('dailyform').add({
      'userId': selectedUserId,
      'userName': selectedUserName,
      'managerId': currentUser.uid,
      'managerName': managerName,
      'timestamp': Timestamp.fromDate(submissionTimestamp),
      'attendance': attendanceStatus,
      'dressCode': {
        'cleanUniform': isLeave ? true : cleanUniform,
        'keepInside': isLeave ? true : keepInside,
        'neatHair': isLeave ? true : neatHair,
      },
      'attitude': {
        'greetSmile': isLeave ? true : (greetSmile != null ? true : false),
        'greetSmileLevel': isLeave ? 'excellent' : greetSmileLevel,
        'greetSmileReason': attitudeReasons['greetSmile'] ?? '',
        'askNeeds': isLeave ? true : (askNeeds != null ? true : false),
        'askNeedsLevel': isLeave ? 'excellent' : askNeedsLevel,
        'askNeedsReason': attitudeReasons['askNeeds'] ?? '',
        'helpFindProduct':
            isLeave ? true : (helpFindProduct != null ? true : false),
        'helpFindProductLevel': isLeave ? 'excellent' : helpFindProductLevel,
        'helpFindProductReason': attitudeReasons['helpFindProduct'] ?? '',
        'confirmPurchase':
            isLeave ? true : (confirmPurchase != null ? true : false),
        'confirmPurchaseLevel': isLeave ? 'excellent' : confirmPurchaseLevel,
        'confirmPurchaseReason': attitudeReasons['confirmPurchase'] ?? '',
        'offerHelp': isLeave ? true : (offerHelp != null ? true : false),
        'offerHelpLevel': isLeave ? 'excellent' : offerHelpLevel,
        'offerHelpReason': attitudeReasons['offerHelp'] ?? '',
      },
      'meeting': {
        'attended': isLeave ? true : meetingAttended,
        'noMeeting': isLeave ? false : meetingNoMeeting,
        'meetingComment':
            isLeave ? '' : (meetingNoMeeting ? 'No meeting conducted' : ''),
      },
      // Additional questions
      'timeTakenOtherTasks': timeTakenOtherTasks,
      'oldStockOfferGiven': oldStockOfferGiven,
      'crossSellingUpselling': crossSellingUpselling,
      'productComplaints': productComplaints,
      'achievedDailyTarget': achievedDailyTarget,
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
      greetSmile = null;
      askNeeds = null;
      helpFindProduct = null;
      confirmPurchase = null;
      offerHelp = null;
      greetSmileLevel = null;
      askNeedsLevel = null;
      helpFindProductLevel = null;
      confirmPurchaseLevel = null;
      offerHelpLevel = null;
      meetingAttended = false;
      selectedUserId = null;
      selectedUserName = null;
      attitudeReasons = {
        'greetSmile': '',
        'askNeeds': '',
        'helpFindProduct': '',
        'confirmPurchase': '',
        'offerHelp': '',
      };
      isLoadingUsers = true;
      timeTakenOtherTasks = null;
      oldStockOfferGiven = null;
      crossSellingUpselling = null;
      productComplaints = null;
      achievedDailyTarget = null;
    });
    // Refresh user list to remove the just-filled user
    fetchBranchUsers();
  }

  @override
  Widget build(BuildContext context) {
    // 2. Add this variable to control enabled/disabled state
    bool isApprovedLeave = attendanceStatus == 'approved';
    bool isUnapprovedLeave = attendanceStatus == 'notApproved';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Performance Form',
            style: TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? [
                    const Color(0xFF0A1628),
                    const Color(0xFF0D2137),
                    const Color(0xFF0A1628),
                  ]
                : [
                    primaryBlue.withOpacity(0.05),
                    Colors.white,
                    primaryGreen.withOpacity(0.08),
                  ],
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
        child: isLoadingUsers
            ? Center(child: CircularProgressIndicator(color: primaryBlue))
            : branchUsers.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Date picker even when no users
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Container(
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withOpacity(0.05)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: primaryBlue.withOpacity(0.1),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: DropdownButtonFormField<DateTime>(
                              value: selectedDate,
                              items: allowedDates
                                  .map((date) => DropdownMenuItem<DateTime>(
                                        value: date,
                                        child: Text(_formatDate(date)),
                                      ))
                                  .toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() {
                                    selectedDate = val;
                                    isLoadingUsers = true;
                                  });
                                  fetchBranchUsers();
                                }
                              },
                              decoration: InputDecoration(
                                labelText: 'Select Date',
                                labelStyle: TextStyle(color: primaryBlue),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16)),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide(
                                      color: primaryBlue.withOpacity(0.3)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide:
                                      BorderSide(color: primaryBlue, width: 2),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(20),
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: primaryGreen.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: primaryGreen.withOpacity(0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle,
                                  color: primaryGreen, size: 28),
                              const SizedBox(width: 12),
                              Flexible(
                                child: Text(
                                  'All users have been filled for ${_formatDate(selectedDate)}!',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color:
                                          isDark ? Colors.white : primaryBlue),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Date Picker
                        _buildSectionCard(
                          isDark: isDark,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Select Date',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: primaryBlue,
                                      fontSize: 14)),
                              const SizedBox(height: 8),
                              DropdownButtonFormField<DateTime>(
                                value: selectedDate,
                                items: allowedDates
                                    .map((date) => DropdownMenuItem<DateTime>(
                                          value: date,
                                          child: Text(_formatDate(date)),
                                        ))
                                    .toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() {
                                      selectedDate = val;
                                      selectedUserId = null;
                                      selectedUserName = null;
                                      isLoadingUsers = true;
                                    });
                                    fetchBranchUsers();
                                  }
                                },
                                decoration: _inputDecoration(''),
                              ),
                              const SizedBox(height: 16),
                              Text('Select User',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: primaryBlue,
                                      fontSize: 14)),
                              const SizedBox(height: 8),
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
                                    selectedUserName = branchUsers.firstWhere(
                                        (u) => u['id'] == val)['username'];
                                  });
                                },
                                decoration: _inputDecoration(''),
                                hint: const Text('Choose user'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildSectionHeader(
                            '1) Attendance', Icons.access_time_rounded),
                        _buildSectionCard(
                          isDark: isDark,
                          child: Column(
                            children: [
                              _buildRadioTile(
                                  'Punching time',
                                  'punching',
                                  attendanceStatus,
                                  (val) =>
                                      setState(() => attendanceStatus = val)),
                              _buildRadioTile(
                                  'Late time',
                                  'late',
                                  attendanceStatus,
                                  (val) =>
                                      setState(() => attendanceStatus = val)),
                              _buildRadioTile(
                                  'Approved leave',
                                  'approved',
                                  attendanceStatus,
                                  (val) =>
                                      setState(() => attendanceStatus = val)),
                              _buildRadioTile(
                                  'Not Approved',
                                  'notApproved',
                                  attendanceStatus,
                                  (val) =>
                                      setState(() => attendanceStatus = val)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildSectionHeader(
                            '2) Dress Code', Icons.checkroom_rounded),
                        _buildSectionCard(
                          isDark: isDark,
                          child: Column(
                            children: [
                              _buildCheckboxTile(
                                  'Wear clean uniform',
                                  cleanUniform,
                                  (isApprovedLeave || isUnapprovedLeave)
                                      ? null
                                      : (val) =>
                                          setState(() => cleanUniform = val!)),
                              _buildCheckboxTile(
                                  'Keep inside',
                                  keepInside,
                                  (isApprovedLeave || isUnapprovedLeave)
                                      ? null
                                      : (val) =>
                                          setState(() => keepInside = val!)),
                              _buildCheckboxTile(
                                  'Keep your hair neat',
                                  neatHair,
                                  (isApprovedLeave || isUnapprovedLeave)
                                      ? null
                                      : (val) =>
                                          setState(() => neatHair = val!)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        _buildSectionHeader(
                            '3) Attitude', Icons.emoji_emotions_rounded),
                        _buildSectionCard(
                          isDark: isDark,
                          child: Column(
                            children: [
                              _attitudeCheckboxRow(
                                label: 'Greet with a warm smile',
                                value: greetSmile,
                                onChanged: (val) {
                                  setState(() {
                                    greetSmile = val;
                                    greetSmileLevel = val == true
                                        ? 'excellent'
                                        : val == false
                                            ? 'average'
                                            : null;
                                  });
                                },
                                enabled:
                                    !(isApprovedLeave || isUnapprovedLeave),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                child: TextFormField(
                                  decoration: _inputDecoration('Reason'),
                                  onChanged: (val) {
                                    attitudeReasons['greetSmile'] = val;
                                  },
                                ),
                              ),
                              const Divider(height: 24),
                              _attitudeCheckboxRow(
                                label: 'Ask about their needs',
                                value: askNeeds,
                                onChanged: (val) {
                                  setState(() {
                                    askNeeds = val;
                                    askNeedsLevel = val == true
                                        ? 'excellent'
                                        : val == false
                                            ? 'average'
                                            : null;
                                  });
                                },
                                enabled:
                                    !(isApprovedLeave || isUnapprovedLeave),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                child: TextFormField(
                                  decoration: _inputDecoration('Reason'),
                                  onChanged: (val) {
                                    attitudeReasons['askNeeds'] = val;
                                  },
                                ),
                              ),
                              const Divider(height: 24),
                              _attitudeCheckboxRow(
                                label: 'Help find the right product',
                                value: helpFindProduct,
                                onChanged: (val) {
                                  setState(() {
                                    helpFindProduct = val;
                                    helpFindProductLevel = val == true
                                        ? 'excellent'
                                        : val == false
                                            ? 'average'
                                            : null;
                                  });
                                },
                                enabled:
                                    !(isApprovedLeave || isUnapprovedLeave),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                child: TextFormField(
                                  decoration: _inputDecoration('Reason'),
                                  onChanged: (val) {
                                    attitudeReasons['helpFindProduct'] = val;
                                  },
                                ),
                              ),
                              const Divider(height: 24),
                              _attitudeCheckboxRow(
                                label: 'Confirm the purchase',
                                value: confirmPurchase,
                                onChanged: (val) {
                                  setState(() {
                                    confirmPurchase = val;
                                    confirmPurchaseLevel = val == true
                                        ? 'excellent'
                                        : val == false
                                            ? 'average'
                                            : null;
                                  });
                                },
                                enabled:
                                    !(isApprovedLeave || isUnapprovedLeave),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                child: TextFormField(
                                  decoration: _inputDecoration('Reason'),
                                  onChanged: (val) {
                                    attitudeReasons['confirmPurchase'] = val;
                                  },
                                ),
                              ),
                              const Divider(height: 24),
                              _attitudeCheckboxRow(
                                label: 'Offer carry or delivery help',
                                value: offerHelp,
                                onChanged: (val) {
                                  setState(() {
                                    offerHelp = val;
                                    offerHelpLevel = val == true
                                        ? 'excellent'
                                        : val == false
                                            ? 'average'
                                            : null;
                                  });
                                },
                                enabled:
                                    !(isApprovedLeave || isUnapprovedLeave),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                child: TextFormField(
                                  decoration: _inputDecoration('Reason'),
                                  onChanged: (val) {
                                    attitudeReasons['offerHelp'] = val;
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildSectionHeader('4) Meeting', Icons.groups_rounded),
                        _buildSectionCard(
                          isDark: isDark,
                          child: Row(
                            children: [
                              Expanded(
                                child: _buildCheckboxTile(
                                  'Attended',
                                  meetingAttended && !meetingNoMeeting,
                                  (isApprovedLeave || isUnapprovedLeave)
                                      ? null
                                      : (val) {
                                          setState(() {
                                            if (val == true) {
                                              meetingAttended = true;
                                              meetingNoMeeting = false;
                                            } else {
                                              meetingAttended = false;
                                              meetingNoMeeting = false;
                                            }
                                          });
                                        },
                                ),
                              ),
                              Expanded(
                                child: _buildCheckboxTile(
                                  'No meeting',
                                  meetingNoMeeting,
                                  (isApprovedLeave || isUnapprovedLeave)
                                      ? null
                                      : (val) {
                                          setState(() {
                                            if (val == true) {
                                              meetingNoMeeting = true;
                                              meetingAttended = true;
                                            } else {
                                              meetingNoMeeting = false;
                                              meetingAttended = false;
                                            }
                                          });
                                        },
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                                                // 5) Time taken to complete other tasks?
                                                _buildSectionHeader('5) Time taken to complete other tasks?', Icons.timer_outlined),
                                                _buildSectionCard(
                                                  isDark: isDark,
                                                  child: TextFormField(
                                                    keyboardType: TextInputType.number,
                                                    decoration: _inputDecoration('Enter time in minutes'),
                                                    onChanged: (val) {
                                                      setState(() {
                                                        timeTakenOtherTasks = val;
                                                      });
                                                    },
                                                  ),
                                                ),
                                                const SizedBox(height: 16),

                                                // 6) Old stock offer given to customers? (yes or no)
                                                _buildSectionHeader('6) Old stock offer given to customers?', Icons.local_offer_outlined),
                                                _buildSectionCard(
                                                  isDark: isDark,
                                                  child: Row(
                                                    children: [
                                                      Expanded(
                                                        child: RadioListTile<bool>(
                                                          title: const Text('Yes'),
                                                          value: true,
                                                          groupValue: oldStockOfferGiven,
                                                          onChanged: (val) {
                                                            setState(() {
                                                              oldStockOfferGiven = val;
                                                            });
                                                          },
                                                        ),
                                                      ),
                                                      Expanded(
                                                        child: RadioListTile<bool>(
                                                          title: const Text('No'),
                                                          value: false,
                                                          groupValue: oldStockOfferGiven,
                                                          onChanged: (val) {
                                                            setState(() {
                                                              oldStockOfferGiven = val;
                                                            });
                                                          },
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(height: 16),

                                                // 7) Cross-selling and upselling? (yes or no)
                                                _buildSectionHeader('7) Cross-selling and upselling?', Icons.swap_horiz),
                                                _buildSectionCard(
                                                  isDark: isDark,
                                                  child: Row(
                                                    children: [
                                                      Expanded(
                                                        child: RadioListTile<bool>(
                                                          title: const Text('Yes'),
                                                          value: true,
                                                          groupValue: crossSellingUpselling,
                                                          onChanged: (val) {
                                                            setState(() {
                                                              crossSellingUpselling = val;
                                                            });
                                                          },
                                                        ),
                                                      ),
                                                      Expanded(
                                                        child: RadioListTile<bool>(
                                                          title: const Text('No'),
                                                          value: false,
                                                          groupValue: crossSellingUpselling,
                                                          onChanged: (val) {
                                                            setState(() {
                                                              crossSellingUpselling = val;
                                                            });
                                                          },
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(height: 16),

                                                // 8) Are there any product complaints? (yes or no)
                                                _buildSectionHeader('8) Are there any product complaints?', Icons.report_problem_outlined),
                                                _buildSectionCard(
                                                  isDark: isDark,
                                                  child: Row(
                                                    children: [
                                                      Expanded(
                                                        child: RadioListTile<bool>(
                                                          title: const Text('Yes'),
                                                          value: true,
                                                          groupValue: productComplaints,
                                                          onChanged: (val) {
                                                            setState(() {
                                                              productComplaints = val;
                                                            });
                                                          },
                                                        ),
                                                      ),
                                                      Expanded(
                                                        child: RadioListTile<bool>(
                                                          title: const Text('No'),
                                                          value: false,
                                                          groupValue: productComplaints,
                                                          onChanged: (val) {
                                                            setState(() {
                                                              productComplaints = val;
                                                            });
                                                          },
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(height: 16),

                                                // 9) Achieved the daily target? (yes or no)
                                                _buildSectionHeader('9) Achieved the daily target?', Icons.verified_outlined),
                                                _buildSectionCard(
                                                  isDark: isDark,
                                                  child: Row(
                                                    children: [
                                                      Expanded(
                                                        child: RadioListTile<bool>(
                                                          title: const Text('Yes'),
                                                          value: true,
                                                          groupValue: achievedDailyTarget,
                                                          onChanged: (val) {
                                                            setState(() {
                                                              achievedDailyTarget = val;
                                                            });
                                                          },
                                                        ),
                                                      ),
                                                      Expanded(
                                                        child: RadioListTile<bool>(
                                                          title: const Text('No'),
                                                          value: false,
                                                          groupValue: achievedDailyTarget,
                                                          onChanged: (val) {
                                                            setState(() {
                                                              achievedDailyTarget = val;
                                                            });
                                                          },
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(height: 24),
                        // Submit Button
                        Container(
                          width: double.infinity,
                          height: 56,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: selectedUserId == null
                                  ? [Colors.grey.shade400, Colors.grey.shade500]
                                  : [
                                      Color.lerp(
                                          primaryGreen, Colors.white, 0.1)!,
                                      primaryGreen,
                                      Color.lerp(
                                          primaryGreen, Colors.black, 0.12)!,
                                    ],
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: selectedUserId == null
                                ? []
                                : [
                                    BoxShadow(
                                      color: primaryGreen.withOpacity(0.4),
                                      offset: const Offset(0, 8),
                                      blurRadius: 16,
                                    ),
                                  ],
                          ),
                          child: ElevatedButton(
                            onPressed:
                                selectedUserId == null ? null : submitForm,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                            ),
                            child: const Text(
                              'Submit',
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
      ),
    );
  }

  // Helper for section headers
  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: primaryBlue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: primaryBlue, size: 20),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 16, color: primaryBlue),
          ),
        ],
      ),
    );
  }

  // Helper for section cards
  Widget _buildSectionCard({required bool isDark, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: primaryBlue.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: primaryBlue.withOpacity(0.1)),
      ),
      child: child,
    );
  }

  // Helper for input decoration
  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label.isNotEmpty ? label : null,
      labelStyle: TextStyle(color: primaryBlue.withOpacity(0.7)),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: primaryBlue.withOpacity(0.2)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primaryBlue, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }

  // Helper for radio tiles
  Widget _buildRadioTile(String title, String value, String? groupValue,
      ValueChanged<String?> onChanged) {
    final isSelected = groupValue == value;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: isSelected ? primaryBlue.withOpacity(0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border:
            isSelected ? Border.all(color: primaryBlue.withOpacity(0.3)) : null,
      ),
      child: RadioListTile<String>(
        title: Text(title,
            style: TextStyle(
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal)),
        value: value,
        groupValue: groupValue,
        activeColor: primaryBlue,
        onChanged: onChanged,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      ),
    );
  }

  // Helper for checkbox tiles
  Widget _buildCheckboxTile(
      String title, bool value, ValueChanged<bool?>? onChanged) {
    return CheckboxListTile(
      title: Text(title),
      value: value,
      activeColor: primaryGreen,
      checkColor: Colors.white,
      onChanged: onChanged,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    if (date == today) {
      return 'Today (${DateFormat('dd MMM yyyy').format(date)})';
    } else if (date == yesterday) {
      return 'Yesterday (${DateFormat('dd MMM yyyy').format(date)})';
    }
    return DateFormat('dd MMM yyyy').format(date);
  }

  // Helper widget for attitude items
  Widget _attitudeCheckboxRow({
    required String label,
    required bool?
        value, // null = unselected, true = Excellent/Good, false = Average
    required ValueChanged<bool?> onChanged,
    required bool enabled,
  }) {
    String? level;
    if (label == 'Greet with a warm smile') level = greetSmileLevel;
    if (label == 'Ask about their needs') level = askNeedsLevel;
    if (label == 'Help find the right product') level = helpFindProductLevel;
    if (label == 'Confirm the purchase') level = confirmPurchaseLevel;
    if (label == 'Offer carry or delivery help') level = offerHelpLevel;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text(label)),
          Expanded(
            child: Column(
              children: [
                Text('Excellent',
                    style: TextStyle(
                        fontSize: 12,
                        color: primaryGreen,
                        fontWeight: FontWeight.w600)),
                Checkbox(
                  value: level == 'excellent',
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4)),
                  onChanged: enabled
                      ? (val) {
                          if (val == true) {
                            onChanged(true);
                            setState(() {
                              if (label == 'Greet with a warm smile')
                                greetSmileLevel = 'excellent';
                              if (label == 'Ask about their needs')
                                askNeedsLevel = 'excellent';
                              if (label == 'Help find the right product')
                                helpFindProductLevel = 'excellent';
                              if (label == 'Confirm the purchase')
                                confirmPurchaseLevel = 'excellent';
                              if (label == 'Offer carry or delivery help')
                                offerHelpLevel = 'excellent';
                            });
                          } else {
                            onChanged(null);
                            setState(() {
                              if (label == 'Greet with a warm smile')
                                greetSmileLevel = null;
                              if (label == 'Ask about their needs')
                                askNeedsLevel = null;
                              if (label == 'Help find the right product')
                                helpFindProductLevel = null;
                              if (label == 'Confirm the purchase')
                                confirmPurchaseLevel = null;
                              if (label == 'Offer carry or delivery help')
                                offerHelpLevel = null;
                            });
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
                  Text('Good', style: TextStyle(fontSize: 12, color: primaryBlue)),
                Checkbox(
                  value: level == 'good',
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4)),
                  onChanged: enabled
                      ? (val) {
                          if (val == true) {
                            onChanged(true);
                            setState(() {
                              if (label == 'Greet with a warm smile')
                                greetSmileLevel = 'good';
                              if (label == 'Ask about their needs')
                                askNeedsLevel = 'good';
                              if (label == 'Help find the right product')
                                helpFindProductLevel = 'good';
                              if (label == 'Confirm the purchase')
                                confirmPurchaseLevel = 'good';
                              if (label == 'Offer carry or delivery help')
                                offerHelpLevel = 'good';
                            });
                          } else {
                            onChanged(null);
                            setState(() {
                              if (label == 'Greet with a warm smile')
                                greetSmileLevel = null;
                              if (label == 'Ask about their needs')
                                askNeedsLevel = null;
                              if (label == 'Help find the right product')
                                helpFindProductLevel = null;
                              if (label == 'Confirm the purchase')
                                confirmPurchaseLevel = null;
                              if (label == 'Offer carry or delivery help')
                                offerHelpLevel = null;
                            });
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
                  Text('Average', style: TextStyle(fontSize: 12, color: Colors.orange)),
                Checkbox(
                  value: level == 'average',
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4)),
                  onChanged: enabled
                      ? (val) {
                          if (val == true) {
                            onChanged(false);
                            setState(() {
                              if (label == 'Greet with a warm smile')
                                greetSmileLevel = 'average';
                              if (label == 'Ask about their needs')
                                askNeedsLevel = 'average';
                              if (label == 'Help find the right product')
                                helpFindProductLevel = 'average';
                              if (label == 'Confirm the purchase')
                                confirmPurchaseLevel = 'average';
                              if (label == 'Offer carry or delivery help')
                                offerHelpLevel = 'average';
                            });
                          } else {
                            onChanged(null);
                            setState(() {
                              if (label == 'Greet with a warm smile')
                                greetSmileLevel = null;
                              if (label == 'Ask about their needs')
                                askNeedsLevel = null;
                              if (label == 'Help find the right product')
                                helpFindProductLevel = null;
                              if (label == 'Confirm the purchase')
                                confirmPurchaseLevel = null;
                              if (label == 'Offer carry or delivery help')
                                offerHelpLevel = null;
                            });
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
