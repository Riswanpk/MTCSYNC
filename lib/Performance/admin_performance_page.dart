import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../Misc/user_cache_service.dart';

// Theme colors (matching dashboard)
const Color _primaryBlue = Color(0xFF005BAC);
const Color _primaryGreen = Color(0xFF8CC63F);

class AdminPerformancePage extends StatefulWidget {
  const AdminPerformancePage({Key? key}) : super(key: key);

  @override
  State<AdminPerformancePage> createState() => _AdminPerformancePageState();
}

class _AdminPerformancePageState extends State<AdminPerformancePage>
    with SingleTickerProviderStateMixin {
  String? selectedBranch;
  String? selectedUserId;
  String? selectedDocId;
  int? selectedMonth;
  DateTime? selectedDate;
  List<Map<String, dynamic>> branches = [];
  List<Map<String, dynamic>> users = [];
  List<Map<String, dynamic>> forms = [];
  List<DateTime> availableDates = [];
  int selectedYear = DateTime.now().year;
  bool isLoading = false;
  bool isLoadingBranches = true;
  bool isLoadingUsers = false;
  late AnimationController _animController;
  late Animation<double> _fadeIn;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeIn = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    fetchBranches();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> fetchBranches() async {
    setState(() => isLoadingBranches = true);
    final branchList = await UserCacheService.instance.getBranches();
    setState(() {
      branches = branchList.map((b) => {'branch': b}).toList();
      isLoadingBranches = false;
    });
    _animController.forward();
  }

  Future<void> fetchUsersForBranch(String branch) async {
    setState(() {
      isLoadingUsers = true;
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
      isLoadingUsers = false;
      // No auto-selection
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
      selectedMonth = monthsSet.isNotEmpty ? monthsSet.first : DateTime.now().month;
      final _m = selectedMonth!;
      final _daysInMonth = DateTime(selectedYear, _m + 1, 0).day;
      // Exclude Sundays from availableDates
      availableDates = List.generate(_daysInMonth, (i) => DateTime(selectedYear, _m, i + 1))
        .where((d) => d.weekday != DateTime.sunday)
        .toList()
        .reversed
        .toList();
      selectedDate = null;
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
    final daysInMonth = DateTime(selectedYear, selectedMonth! + 1, 0).day;
    // Exclude Sundays from availableDates
    setState(() {
      availableDates = List.generate(daysInMonth, (i) => DateTime(selectedYear, selectedMonth!, i + 1))
        .where((d) => d.weekday != DateTime.sunday)
        .toList()
        .reversed
        .toList();
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

  static const _monthNames = [
    '', 'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  Widget _buildStyledDropdown<T>({
    required T? value,
    required String hint,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
    required bool isDark,
    required Color cardColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: (isDark ? Colors.white : _primaryBlue).withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: (isDark ? Colors.white : _primaryBlue).withOpacity(0.12),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          hint: Text(
            hint,
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          borderRadius: BorderRadius.circular(14),
          dropdownColor: cardColor,
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: isDark ? Colors.white54 : _primaryBlue,
          ),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.white : const Color(0xFF1A1B22),
          ),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildDropdownLabel(String text, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white54 : Colors.black45,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? const Color(0xFF1A1B22) : const Color(0xFFF5F7FA);
    final cardColor = isDark ? const Color(0xFF23242B) : Colors.white;

    // Show all months of the year (Jan–Dec, descending)
    final monthsList = List<int>.generate(12, (i) => 12 - i);

    if (isLoadingBranches) {
      return Scaffold(
        backgroundColor: surfaceColor,
        body: const Center(
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }

    return Scaffold(
      backgroundColor: surfaceColor,
      body: FadeTransition(
        opacity: _fadeIn,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // ── Sliver App Bar ──
            SliverAppBar(
              expandedHeight: 120,
              floating: false,
              pinned: true,
              elevation: 0,
              backgroundColor: isDark ? const Color(0xFF1A1B22) : Colors.white,
              surfaceTintColor: Colors.transparent,
              leading: IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: (isDark ? Colors.white : _primaryBlue).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: isDark ? Colors.white70 : _primaryBlue,
                    size: 18,
                  ),
                ),
                onPressed: () => Navigator.pop(context),
              ),
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: const EdgeInsets.only(left: 60, bottom: 16),
                title: Text(
                  'Edit Daily Form',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF1A1B22),
                    letterSpacing: -0.3,
                  ),
                ),
                background: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isDark
                          ? [const Color(0xFF1A1B22), const Color(0xFF23242B)]
                          : [Colors.white, const Color(0xFFF0F4FF)],
                    ),
                  ),
                ),
              ),
            ),

            // ── Body ──
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  const SizedBox(height: 8),

                  // ── Filter Card ──
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: isDark ? Colors.black26 : Colors.black.withOpacity(0.06),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Section header
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: _primaryBlue.withOpacity(isDark ? 0.2 : 0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.filter_list_rounded,
                                color: isDark ? Colors.white70 : _primaryBlue,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Select Entry',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: isDark ? Colors.white : const Color(0xFF1A1B22),
                                letterSpacing: -0.2,
                              ),
                            ),
                            // Delete button if a form is selected
                            if (selectedDocId != null && selectedDate != null)
                              Spacer(),
                            if (selectedDocId != null && selectedDate != null)
                              IconButton(
                                icon: Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                                tooltip: 'Delete Entry',
                                onPressed: () async {
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('Delete Entry'),
                                      content: const Text('Are you sure you want to delete this entry?'),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.of(ctx).pop(false),
                                          child: const Text('Cancel'),
                                        ),
                                        TextButton(
                                          onPressed: () => Navigator.of(ctx).pop(true),
                                          child: const Text('Delete', style: TextStyle(color: Colors.red)),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirm == true) {
                                    try {
                                      await FirebaseFirestore.instance
                                          .collection('dailyform')
                                          .doc(selectedDocId)
                                          .delete();
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Entry deleted!')),
                                      );
                                      // Refresh forms for user
                                      if (selectedUserId != null) {
                                        await fetchFormsForUser(selectedUserId!);
                                        setState(() {
                                          selectedDate = null;
                                          selectedDocId = null;
                                        });
                                      }
                                    } catch (e) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Failed to delete entry: $e')),
                                      );
                                    }
                                  }
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // Branch & User row
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildDropdownLabel('Branch', isDark),
                                  _buildStyledDropdown<String>(
                                    value: selectedBranch,
                                    hint: 'Select Branch',
                                    isDark: isDark,
                                    cardColor: cardColor,
                                    items: branches
                                        .map((b) => DropdownMenuItem<String>(
                                              value: b['branch'],
                                              child: Row(
                                                children: [
                                                  Container(
                                                    padding: const EdgeInsets.all(6),
                                                    decoration: BoxDecoration(
                                                      color: _primaryBlue.withOpacity(0.12),
                                                      borderRadius: BorderRadius.circular(8),
                                                    ),
                                                    child: Icon(Icons.store_rounded, size: 16, color: _primaryBlue),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Text(b['branch']),
                                                ],
                                              ),
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
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildDropdownLabel('Employee', isDark),
                                  if (isLoadingUsers)
                                    const Padding(
                                      padding: EdgeInsets.all(12),
                                      child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
                                    )
                                  else
                                    _buildStyledDropdown<String>(
                                      value: selectedUserId,
                                      hint: 'Select User',
                                      isDark: isDark,
                                      cardColor: cardColor,
                                      items: users
                                          .map((u) => DropdownMenuItem<String>(
                                                value: u['id'],
                                                child: Row(
                                                  children: [
                                                    CircleAvatar(
                                                      radius: 14,
                                                      backgroundColor: _primaryGreen.withOpacity(0.15),
                                                      child: Text(
                                                        (u['username'] ?? 'U').substring(0, 1).toUpperCase(),
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          fontWeight: FontWeight.w700,
                                                          color: _primaryGreen,
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 10),
                                                    Flexible(child: Text(u['username'] ?? u['id'])),
                                                  ],
                                                ),
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
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        // Month & Date row
                        if (selectedUserId != null) ...[
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildDropdownLabel('Month', isDark),
                                    _buildStyledDropdown<int>(
                                      value: selectedMonth,
                                      hint: 'Select Month',
                                      isDark: isDark,
                                      cardColor: cardColor,
                                      items: monthsList
                                          .map((m) => DropdownMenuItem<int>(
                                                value: m,
                                                child: Row(
                                                  children: [
                                                    Container(
                                                      padding: const EdgeInsets.all(6),
                                                      decoration: BoxDecoration(
                                                        color: _primaryGreen.withOpacity(0.12),
                                                        borderRadius: BorderRadius.circular(8),
                                                      ),
                                                      child: Icon(Icons.calendar_month_rounded, size: 16, color: _primaryGreen),
                                                    ),
                                                    const SizedBox(width: 10),
                                                    Text(_monthNames[m]),
                                                  ],
                                                ),
                                              ))
                                          .toList(),
                                      onChanged: (val) {
                                        setState(() {
                                          selectedMonth = val;
                                        });
                                        updateAvailableDates();
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildDropdownLabel('Date', isDark),
                                    _buildStyledDropdown<DateTime>(
                                      value: selectedDate,
                                      hint: 'Select Date',
                                      isDark: isDark,
                                      cardColor: cardColor,
                                      items: availableDates
                                          .map((d) {
                                            final hasForm = forms.any((f) {
                                              final ts = f['timestamp'] as Timestamp?;
                                              final fd = ts?.toDate();
                                              return fd != null &&
                                                  fd.year == d.year &&
                                                  fd.month == d.month &&
                                                  fd.day == d.day;
                                            });
                                            return DropdownMenuItem<DateTime>(
                                              value: d,
                                              child: Row(
                                                children: [
                                                  Container(
                                                    padding: const EdgeInsets.all(6),
                                                    decoration: BoxDecoration(
                                                      color: (hasForm ? _primaryGreen : _primaryBlue).withOpacity(0.12),
                                                      borderRadius: BorderRadius.circular(8),
                                                    ),
                                                    child: Icon(
                                                      hasForm ? Icons.edit_rounded : Icons.add_rounded,
                                                      size: 16,
                                                      color: hasForm ? _primaryGreen : _primaryBlue,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Text('${d.day}/${d.month < 10 ? '0' : ''}${d.month}'),
                                                  if (hasForm) ...[
                                                    const SizedBox(width: 6),
                                                    Container(
                                                      width: 6,
                                                      height: 6,
                                                      decoration: const BoxDecoration(
                                                        color: _primaryGreen,
                                                        shape: BoxShape.circle,
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            );
                                          })
                                          .toList(),
                                      onChanged: (val) {
                                        setState(() {
                                          selectedDate = val;
                                        });
                                        updateSelectedDocId();
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── Form Section ──
                  if (selectedDate != null)
                    Container(
                      key: ValueKey('${selectedDate?.toIso8601String()}_$selectedDocId'),
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: isDark ? Colors.black26 : Colors.black.withOpacity(0.06),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: _AdminEditForm(
                          form: selectedDocId != null
                              ? forms.firstWhere((f) => f['docId'] == selectedDocId)
                              : {},
                          docId: selectedDocId,
                          userId: selectedUserId!,
                          userName: users.firstWhere(
                            (u) => u['id'] == selectedUserId,
                            orElse: () => {'username': 'Unknown'},
                          )['username'] ?? 'Unknown',
                          selectedDate: selectedDate!,
                          onSaved: () async {
                            if (selectedUserId != null) {
                              final prevDate = selectedDate;
                              await fetchFormsForUser(selectedUserId!);
                              if (prevDate != null) {
                                final daysInMonth = DateTime(selectedYear, prevDate.month + 1, 0).day;
                                setState(() {
                                  selectedMonth = prevDate.month;
                                  availableDates = List.generate(daysInMonth, (i) => DateTime(selectedYear, prevDate.month, i + 1)).reversed.toList();
                                  selectedDate = prevDate;
                                });
                                updateSelectedDocId();
                              }
                            }
                          },
                        ),
                      ),
                    ),

                  const SizedBox(height: 32),
                ]),
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
  final String? docId;
  final String userId;
  final String userName;
  final DateTime selectedDate;
  final VoidCallback onSaved;

  const _AdminEditForm({
    required this.form,
    required this.docId,
    required this.userId,
    required this.userName,
    required this.selectedDate,
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
  late bool meetingNoMeeting;

  // New questions (5-9)
  late bool timeTakenOtherTasks;
  late TextEditingController timeTakenOtherTasksController;
  late TextEditingController timeTakenOtherTasksDescriptionController;
  late bool oldStockOfferGiven;
  late TextEditingController oldStockOfferDescriptionController;
  late bool crossSellingUpselling;
  late TextEditingController crossSellingUpsellingDescriptionController;
  late bool productComplaints;
  late TextEditingController productComplaintsDescriptionController;
  late bool achievedDailyTarget;
  late TextEditingController achievedDailyTargetDescriptionController;

  // Attitude levels and reasons
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

  bool _parseBool(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is String) {
      return value.toLowerCase() == 'true';
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    final f = widget.form;
    attendance = f['attendance']?.toString() ?? '';
    attendanceStatus = f['attendance']?.toString() ?? '';
    cleanUniform = _parseBool(f['dressCode']?['cleanUniform']);
    keepInside = _parseBool(f['dressCode']?['keepInside']);
    neatHair = _parseBool(f['dressCode']?['neatHair']);
    greetSmile = _parseBool(f['attitude']?['greetSmile']);
    greetSmileLevel = f['attitude']?['greetSmileLevel'];
    askNeeds = _parseBool(f['attitude']?['askNeeds']);
    askNeedsLevel = f['attitude']?['askNeedsLevel'];
    helpFindProduct = _parseBool(f['attitude']?['helpFindProduct']);
    helpFindProductLevel = f['attitude']?['helpFindProductLevel'];
    confirmPurchase = _parseBool(f['attitude']?['confirmPurchase']);
    confirmPurchaseLevel = f['attitude']?['confirmPurchaseLevel'];
    offerHelp = _parseBool(f['attitude']?['offerHelp']);
    offerHelpLevel = f['attitude']?['offerHelpLevel'];
    meetingAttended = _parseBool(f['meeting']?['attended']);
    meetingNoMeeting = _parseBool(f['meeting']?['noMeeting']);

    // New questions (5-9)
    timeTakenOtherTasks = _parseBool(f['timeTakenOtherTasks']);
    timeTakenOtherTasksController = TextEditingController(text: (f['timeTakenOtherTasksTime'] ?? '').toString());
    timeTakenOtherTasksDescriptionController = TextEditingController(text: (f['timeTakenOtherTasksDescription'] ?? '').toString());
    oldStockOfferGiven = _parseBool(f['oldStockOfferGiven']);
    oldStockOfferDescriptionController = TextEditingController(text: (f['oldStockOfferDescription'] ?? '').toString());
    crossSellingUpselling = _parseBool(f['crossSellingUpselling']);
    crossSellingUpsellingDescriptionController = TextEditingController(text: (f['crossSellingUpsellingDescription'] ?? '').toString());
    productComplaints = _parseBool(f['productComplaints']);
    productComplaintsDescriptionController = TextEditingController(text: (f['productComplaintsDescription'] ?? '').toString());
    achievedDailyTarget = _parseBool(f['achievedDailyTarget']);
    achievedDailyTargetDescriptionController = TextEditingController(text: (f['achievedDailyTargetDescription'] ?? '').toString());

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
    timeTakenOtherTasksController.dispose();
    timeTakenOtherTasksDescriptionController.dispose();
    oldStockOfferDescriptionController.dispose();
    crossSellingUpsellingDescriptionController.dispose();
    productComplaintsDescriptionController.dispose();
    achievedDailyTargetDescriptionController.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final data = <String, dynamic>{
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
        'noMeeting': meetingNoMeeting,
      },
      // New questions (5-9)
      'timeTakenOtherTasks': timeTakenOtherTasks,
      'timeTakenOtherTasksTime': timeTakenOtherTasksController.text,
      'timeTakenOtherTasksDescription': timeTakenOtherTasks ? timeTakenOtherTasksDescriptionController.text : null,
      'oldStockOfferGiven': oldStockOfferGiven,
      'oldStockOfferDescription': oldStockOfferGiven ? oldStockOfferDescriptionController.text : null,
      'crossSellingUpselling': crossSellingUpselling,
      'crossSellingUpsellingDescription': crossSellingUpselling ? crossSellingUpsellingDescriptionController.text : null,
      'productComplaints': productComplaints,
      'productComplaintsDescription': productComplaints ? productComplaintsDescriptionController.text : null,
      'achievedDailyTarget': achievedDailyTarget,
      'achievedDailyTargetDescription': achievedDailyTarget ? achievedDailyTargetDescriptionController.text : null,
    };

    if (widget.docId != null) {
      await FirebaseFirestore.instance
          .collection('dailyform')
          .doc(widget.docId)
          .update(data);
    } else {
      final now = DateTime.now();
      final submissionTimestamp = DateTime(
        widget.selectedDate.year,
        widget.selectedDate.month,
        widget.selectedDate.day,
        now.hour,
        now.minute,
        now.second,
      );
      data['userId'] = widget.userId;
      data['userName'] = widget.userName;
      data['timestamp'] = Timestamp.fromDate(submissionTimestamp);
      await FirebaseFirestore.instance.collection('dailyform').add(data);
    }

    widget.onSaved();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.docId != null ? 'Entry updated!' : 'Entry created!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isApprovedLeave = attendanceStatus == 'approved';
    final isUnapprovedLeave = attendanceStatus == 'notApproved';

    Widget sectionHeader(String title, IconData icon, Color accentColor) {
      return Container(
        margin: const EdgeInsets.only(top: 8, bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [accentColor.withOpacity(0.15), Colors.transparent]
                : [accentColor.withOpacity(0.08), Colors.transparent],
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: accentColor, size: 18),
            ),
            const SizedBox(width: 10),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: isDark ? Colors.white : const Color(0xFF1A1B22),
                letterSpacing: -0.1,
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Attendance
            sectionHeader('Attendance', Icons.access_time_rounded, const Color(0xFF4A90D9)),
            RadioListTile<String>(
              title: const Text('Punching time'),
              value: 'punching',
              groupValue: attendanceStatus,
              onChanged: (val) => setState(() => attendanceStatus = val!),
              activeColor: _primaryBlue,
            ),
            RadioListTile<String>(
              title: const Text('Late time'),
              value: 'late',
              groupValue: attendanceStatus,
              onChanged: (val) => setState(() => attendanceStatus = val!),
              activeColor: _primaryBlue,
            ),
            RadioListTile<String>(
              title: const Text('Approved leave'),
              value: 'approved',
              groupValue: attendanceStatus,
              onChanged: (val) => setState(() => attendanceStatus = val!),
              activeColor: _primaryBlue,
            ),
            RadioListTile<String>(
              title: const Text('Not Approved'),
              value: 'notApproved',
              groupValue: attendanceStatus,
              onChanged: (val) => setState(() => attendanceStatus = val!),
              activeColor: _primaryBlue,
            ),

            // Dress Code
            sectionHeader('Dress Code', Icons.checkroom_rounded, _primaryGreen),
            CheckboxListTile(
              title: const Text('Wear clean uniform'),
              value: cleanUniform,
              onChanged: (isApprovedLeave || isUnapprovedLeave)
                  ? null
                  : (val) => setState(() => cleanUniform = val!),
              activeColor: _primaryGreen,
            ),
            CheckboxListTile(
              title: const Text('Keep inside'),
              value: keepInside,
              onChanged: (isApprovedLeave || isUnapprovedLeave)
                  ? null
                  : (val) => setState(() => keepInside = val!),
              activeColor: _primaryGreen,
            ),
            CheckboxListTile(
              title: const Text('Keep your hair neat'),
              value: neatHair,
              onChanged: (isApprovedLeave || isUnapprovedLeave)
                  ? null
                  : (val) => setState(() => neatHair = val!),
              activeColor: _primaryGreen,
            ),

            // Attitude
            sectionHeader('Attitude', Icons.emoji_emotions_rounded, const Color(0xFFFFA726)),
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
              decoration: const InputDecoration(labelText: 'Reason'),
            ),

            // Meeting
            sectionHeader('Meeting', Icons.groups_rounded, const Color(0xFFEF5350)),
            Row(
              children: [
                Checkbox(
                  value: meetingAttended && !meetingNoMeeting,
                  onChanged: (isApprovedLeave || isUnapprovedLeave)
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
                  activeColor: _primaryBlue,
                ),
                const Text('Attended'),
                const SizedBox(width: 24),
                Checkbox(
                  value: meetingNoMeeting,
                  onChanged: (isApprovedLeave || isUnapprovedLeave)
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
                  activeColor: _primaryBlue,
                ),
                const Text('No meeting conducted'),
              ],
            ),
            Divider(color: isDark ? Colors.white12 : Colors.black12),
            // New questions
            sectionHeader('Additional Questions', Icons.list_alt_rounded, _primaryBlue),
            TextFormField(
              controller: timeTakenOtherTasksController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: 'Minutes'),
            ),
            CheckboxListTile(
              title: const Text('Old Stock Offer Given?'),
              value: oldStockOfferGiven,
              onChanged: (isApprovedLeave || isUnapprovedLeave)
                  ? null
                  : (val) => setState(() => oldStockOfferGiven = val ?? false),
              activeColor: _primaryGreen,
            ),
            if (oldStockOfferGiven)
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
                child: TextFormField(
                  controller: oldStockOfferDescriptionController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Describe the old stock offer',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            CheckboxListTile(
              title: const Text('Cross-selling & Upselling?'),
              value: crossSellingUpselling,
              onChanged: (isApprovedLeave || isUnapprovedLeave)
                  ? null
                  : (val) => setState(() => crossSellingUpselling = val ?? false),
              activeColor: _primaryGreen,
            ),
            CheckboxListTile(
              title: const Text('Product Complaints?'),
              value: productComplaints,
              onChanged: (isApprovedLeave || isUnapprovedLeave)
                  ? null
                  : (val) => setState(() => productComplaints = val ?? false),
              activeColor: _primaryGreen,
            ),
            CheckboxListTile(
              title: const Text('Achieved Daily Target?'),
              value: achievedDailyTarget,
              onChanged: (isApprovedLeave || isUnapprovedLeave)
                  ? null
                  : (val) => setState(() => achievedDailyTarget = val ?? false),
              activeColor: _primaryGreen,
            ),
            const SizedBox(height: 16),
            Center(
              child: Container(
                width: double.infinity,
                height: 50,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF66BB6A), Color(0xFF2E7D32)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: _primaryGreen.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: save,
                  child: Text(
                    widget.docId != null ? 'Save Changes' : 'Create Form',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
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
                Text('Good', style: TextStyle(fontSize: 12)),
                Checkbox(
                  value: level == 'good',
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  onChanged: enabled
                      ? (val) {
                          if (val == true) {
                            onChanged(true, 'good');
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