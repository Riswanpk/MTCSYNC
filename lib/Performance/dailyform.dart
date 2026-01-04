import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class PerformanceForm extends StatefulWidget {
  @override
  _PerformanceFormState createState() => _PerformanceFormState();
}

class _PerformanceFormState extends State<PerformanceForm> {
  // Date selection
  DateTime selectedDate = DateTime.now();
  List<DateTime> allowedDates = [];

  // Attendance
  String? attendanceStatus; // values: 'punching', 'late', 'approved', 'notApproved'

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

    final userDoc = await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).get();
    final branch = userDoc.data()?['branch'];

    if (branch == null) return;

    // Get selected date range
    final dateStart = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
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
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(dateStart))
        .where('timestamp', isLessThan: Timestamp.fromDate(dateEnd))
        .get();

    // Get userIds already filled for selected date by this manager
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
    final dateStart = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
    final dateEnd = dateStart.add(const Duration(days: 1));
    final currentUser = FirebaseAuth.instance.currentUser;

    final alreadyFilled = await FirebaseFirestore.instance
        .collection('dailyform')
        .where('managerId', isEqualTo: currentUser!.uid)
        .where('userId', isEqualTo: selectedUserId)
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(dateStart))
        .where('timestamp', isLessThan: Timestamp.fromDate(dateEnd))
        .get();

    if (alreadyFilled.docs.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('You have already filled the form for this user on this date.')),
      );
      return;
    }

    final managerDoc = await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).get();
    final managerName = managerDoc.data()?['username'] ?? managerDoc.data()?['email'] ?? 'Manager';

    // If leave, set all other fields to true
    bool isLeave = attendanceStatus == 'approved' || attendanceStatus == 'notApproved';

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
        'helpFindProduct': isLeave ? true : (helpFindProduct != null ? true : false),
        'helpFindProductLevel': isLeave ? 'excellent' : helpFindProductLevel,
        'helpFindProductReason': attitudeReasons['helpFindProduct'] ?? '',
        'confirmPurchase': isLeave ? true : (confirmPurchase != null ? true : false),
        'confirmPurchaseLevel': isLeave ? 'excellent' : confirmPurchaseLevel,
        'confirmPurchaseReason': attitudeReasons['confirmPurchase'] ?? '',
        'offerHelp': isLeave ? true : (offerHelp != null ? true : false),
        'offerHelpLevel': isLeave ? 'excellent' : offerHelpLevel,
        'offerHelpReason': attitudeReasons['offerHelp'] ?? '',
      },
      'meeting': {
        'attended': isLeave ? true : meetingAttended,
      },
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
    });
    // Refresh user list to remove the just-filled user
    fetchBranchUsers();
  }

  @override
  Widget build(BuildContext context) {
    // 2. Add this variable to control enabled/disabled state
    bool isApprovedLeave = attendanceStatus == 'approved';
    bool isUnapprovedLeave = attendanceStatus == 'notApproved';

    return Scaffold(
      appBar: AppBar(title: Text('Performance Form')),
      body: isLoadingUsers
          ? Center(child: CircularProgressIndicator())
          : branchUsers.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Date picker even when no users
                      Padding(
                        padding: const EdgeInsets.all(16.0),
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
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      Text(
                        'All users have been filled for ${_formatDate(selectedDate)}!',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Date Picker
                      Text('Select Date', style: TextStyle(fontWeight: FontWeight.bold)),
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
                        decoration: InputDecoration(
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                      ),
                      SizedBox(height: 16),
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
                        onChanged: (isApprovedLeave || isUnapprovedLeave) ? null : (val) => setState(() => cleanUniform = val!),
                      ),
                      CheckboxListTile(
                        title: Text('Keep inside'),
                        value: keepInside,
                        onChanged: (isApprovedLeave || isUnapprovedLeave) ? null : (val) => setState(() => keepInside = val!),
                      ),
                      CheckboxListTile(
                        title: Text('Keep your hair neat'),
                        value: neatHair,
                        onChanged: (isApprovedLeave || isUnapprovedLeave) ? null : (val) => setState(() => neatHair = val!),
                      ),
                      Divider(),

                      Text('3) Attitude', style: TextStyle(fontWeight: FontWeight.bold)),
                      _attitudeCheckboxRow(
                        label: 'Greet with a warm smile',
                        value: greetSmile,
                        onChanged: (val) {
                          setState(() {
                            greetSmile = val;
                            greetSmileLevel = val == true ? 'excellent' : val == false ? 'average' : null;
                          });
                        },
                        enabled: !(isApprovedLeave || isUnapprovedLeave),
                      ),
                      TextFormField(
                        decoration: InputDecoration(labelText: 'Reason'),
                        onChanged: (val) {
                          attitudeReasons['greetSmile'] = val;
                        },
                      ),
                      _attitudeCheckboxRow(
                        label: 'Ask about their needs',
                        value: askNeeds,
                        onChanged: (val) {
                          setState(() {
                            askNeeds = val;
                            askNeedsLevel = val == true ? 'excellent' : val == false ? 'average' : null;
                          });
                        },
                        enabled: !(isApprovedLeave || isUnapprovedLeave),
                      ),
                      TextFormField(
                        decoration: InputDecoration(labelText: 'Reason'),
                        onChanged: (val) {
                          attitudeReasons['askNeeds'] = val;
                        },
                      ),
                      _attitudeCheckboxRow(
                        label: 'Help find the right product',
                        value: helpFindProduct,
                        onChanged: (val) {
                          setState(() {
                            helpFindProduct = val;
                            helpFindProductLevel = val == true ? 'excellent' : val == false ? 'average' : null;
                          });
                        },
                        enabled: !(isApprovedLeave || isUnapprovedLeave),
                      ),
                      TextFormField(
                        decoration: InputDecoration(labelText: 'Reason'),
                        onChanged: (val) {
                          attitudeReasons['helpFindProduct'] = val;
                        },
                      ),
                      _attitudeCheckboxRow(
                        label: 'Confirm the purchase',
                        value: confirmPurchase,
                        onChanged: (val) {
                          setState(() {
                            confirmPurchase = val;
                            confirmPurchaseLevel = val == true ? 'excellent' : val == false ? 'average' : null;
                          });
                        },
                        enabled: !(isApprovedLeave || isUnapprovedLeave),
                      ),
                      TextFormField(
                        decoration: InputDecoration(labelText: 'Reason'),
                        onChanged: (val) {
                          attitudeReasons['confirmPurchase'] = val;
                        },
                      ),
                      _attitudeCheckboxRow(
                        label: 'Offer carry or delivery help',
                        value: offerHelp,
                        onChanged: (val) {
                          setState(() {
                            offerHelp = val;
                            offerHelpLevel = val == true ? 'excellent' : val == false ? 'average' : null;
                          });
                        },
                        enabled: !(isApprovedLeave || isUnapprovedLeave),
                      ),
                      TextFormField(
                        decoration: InputDecoration(labelText: 'Reason'),
                        onChanged: (val) {
                          attitudeReasons['offerHelp'] = val;
                        },
                      ),

                      Divider(),
                      Text('4) Meeting', style: TextStyle(fontWeight: FontWeight.bold)),
                      CheckboxListTile(
                        title: Text('Attended'),
                        value: meetingAttended,
                        onChanged: (isApprovedLeave || isUnapprovedLeave) ? null : (val) => setState(() => meetingAttended = val!),
                      ),
                      Divider(),

                      // REMOVE Performance section from UI
                      // Text('5) Performance (End of Month Only)', ...),
                      // AbsorbPointer(...),
                      // SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: selectedUserId == null ? null : submitForm,
                        child: Text('Submit'),
                      ),
                    ],
                  ),
                ),
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
    required bool? value, // null = unselected, true = Excellent/Good, false = Average
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
                Text('Excellent', style: TextStyle(fontSize: 12)),
                Checkbox(
                  value: level == 'excellent',
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  onChanged: enabled
                      ? (val) {
                          if (val == true) {
                            onChanged(true);
                            setState(() {
                              if (label == 'Greet with a warm smile') greetSmileLevel = 'excellent';
                              if (label == 'Ask about their needs') askNeedsLevel = 'excellent';
                              if (label == 'Help find the right product') helpFindProductLevel = 'excellent';
                              if (label == 'Confirm the purchase') confirmPurchaseLevel = 'excellent';
                              if (label == 'Offer carry or delivery help') offerHelpLevel = 'excellent';
                            });
                          } else {
                            onChanged(null);
                            setState(() {
                              if (label == 'Greet with a warm smile') greetSmileLevel = null;
                              if (label == 'Ask about their needs') askNeedsLevel = null;
                              if (label == 'Help find the right product') helpFindProductLevel = null;
                              if (label == 'Confirm the purchase') confirmPurchaseLevel = null;
                              if (label == 'Offer carry or delivery help') offerHelpLevel = null;
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
                Text('Good', style: TextStyle(fontSize: 12)),
                Checkbox(
                  value: level == 'good',
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  onChanged: enabled
                      ? (val) {
                          if (val == true) {
                            onChanged(true);
                            setState(() {
                              if (label == 'Greet with a warm smile') greetSmileLevel = 'good';
                              if (label == 'Ask about their needs') askNeedsLevel = 'good';
                              if (label == 'Help find the right product') helpFindProductLevel = 'good';
                              if (label == 'Confirm the purchase') confirmPurchaseLevel = 'good';
                              if (label == 'Offer carry or delivery help') offerHelpLevel = 'good';
                            });
                          } else {
                            onChanged(null);
                            setState(() {
                              if (label == 'Greet with a warm smile') greetSmileLevel = null;
                              if (label == 'Ask about their needs') askNeedsLevel = null;
                              if (label == 'Help find the right product') helpFindProductLevel = null;
                              if (label == 'Confirm the purchase') confirmPurchaseLevel = null;
                              if (label == 'Offer carry or delivery help') offerHelpLevel = null;
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
                Text('Average', style: TextStyle(fontSize: 12)),
                Checkbox(
                  value: level == 'average',
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  onChanged: enabled
                      ? (val) {
                          if (val == true) {
                            onChanged(false);
                            setState(() {
                              if (label == 'Greet with a warm smile') greetSmileLevel = 'average';
                              if (label == 'Ask about their needs') askNeedsLevel = 'average';
                              if (label == 'Help find the right product') helpFindProductLevel = 'average';
                              if (label == 'Confirm the purchase') confirmPurchaseLevel = 'average';
                              if (label == 'Offer carry or delivery help') offerHelpLevel = 'average';
                            });
                          } else {
                            onChanged(null);
                            setState(() {
                              if (label == 'Greet with a warm smile') greetSmileLevel = null;
                              if (label == 'Ask about their needs') askNeedsLevel = null;
                              if (label == 'Help find the right product') helpFindProductLevel = null;
                              if (label == 'Confirm the purchase') confirmPurchaseLevel = null;
                              if (label == 'Offer carry or delivery help') offerHelpLevel = null;
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