import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Helper service for managing the "marks" Firestore structure:
/// marks (collection)
///   -> {month} (doc e.g., 'Jan', 'Feb', etc.)
///     -> branches (sub-collection)
///       -> {branch} (doc e.g., 'TRR', 'PMN', etc.)
///         -> yupass_ids (sub-collection)
///           -> {yupass_id} (doc containing 'Todo' and 'Customer Calling')
class MarksFirestoreService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Sets or updates mark details for a specific month, branch, and yupass_id.
  /// 
  /// Firestore Hierarchy:
  /// `marks/{month}/branches/{branch}/yupass_ids/{yupassId}`
  /// Document fields:
  /// - `Todo`
  /// - `Customer Calling`
  static Future<void> setMarkData({
    required String month,
    required String branch,
    required String yupassId,
    dynamic todoData,
    dynamic customerCallingData,
  }) async {
    final docRef = _firestore
        .collection('marks')
        .doc(month)
        .collection('branches')
        .doc(branch)
        .collection('yupass_ids')
        .doc(yupassId);

    final Map<String, dynamic> data = {
      'Todo': todoData,
      'Customer Calling': customerCallingData,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    await docRef.set(data, SetOptions(merge: true));
  }

  /// Fetches mark details for a given month, branch, and yupass_id.
  static Future<DocumentSnapshot<Map<String, dynamic>>> getMarkData({
    required String month,
    required String branch,
    required String yupassId,
  }) async {
    return await _firestore
        .collection('marks')
        .doc(month)
        .collection('branches')
        .doc(branch)
        .collection('yupass_ids')
        .doc(yupassId)
        .get();
  }

  /// Streams all mark documents under a given month and branch.
  static Stream<QuerySnapshot<Map<String, dynamic>>> streamBranchMarks({
    required String month,
    required String branch,
  }) {
    return _firestore
        .collection('marks')
        .doc(month)
        .collection('branches')
        .doc(branch)
        .collection('yupass_ids')
        .snapshots();
  }
}

class YupulseSyncPage extends StatefulWidget {
  const YupulseSyncPage({super.key});

  @override
  State<YupulseSyncPage> createState() => _YupulseSyncPageState();
}

class _YupulseSyncPageState extends State<YupulseSyncPage> {
  static const Color primaryGreen = Color(0xFF8CC63F);

  final List<String> _months = const [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];

  late String _selectedMonth;
  List<String> _branches = [];
  String _selectedBranch = 'All Branches';
  bool _loadingBranches = true;
  bool _loadingUsers = false;
  bool _saving = false;

  // Each user item contains:
  // username, yupass_id, email, branch,
  // calculatedTodoPct (String), calculatedCallingPct (String),
  // todoController (TextEditingController), callingController (TextEditingController)
  List<Map<String, dynamic>> _userMarkItems = [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = _months[now.month - 1];
    _fetchBranches();
  }

  @override
  void dispose() {
    for (final item in _userMarkItems) {
      (item['todoController'] as TextEditingController).dispose();
      (item['callingController'] as TextEditingController).dispose();
    }
    super.dispose();
  }

  Future<void> _fetchBranches() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('users').get();
      final set = <String>{};
      for (final doc in snap.docs) {
        final b = (doc.data()['branch'] ?? '').toString().trim();
        if (b.isNotEmpty && b.toLowerCase() != 'admin') {
          set.add(b);
        }
      }
      final list = set.toList()..sort();
      if (mounted) {
        setState(() {
          _branches = ['All Branches', ...list];
          if (_branches.length > 1) {
            _selectedBranch = _branches[1]; // default first actual branch
          }
          _loadingBranches = false;
        });
        if (_selectedBranch != 'All Branches') {
          _loadUserData();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingBranches = false;
        });
      }
    }
  }

  Future<void> _loadUserData() async {
    if (_selectedBranch == 'All Branches') {
      setState(() {
        _userMarkItems = [];
      });
      return;
    }

    setState(() {
      _loadingUsers = true;
    });

    try {
      // 1. Fetch users for the selected branch
      final usersSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('branch', isEqualTo: _selectedBranch)
          .get();

      final currentYear = DateTime.now().year;
      final monthYearStr = "$_selectedMonth $currentYear";
      final monthIndex = _months.indexOf(_selectedMonth) + 1;

      // Date range for the selected month in current year
      final startOfMonth = DateTime(currentYear, monthIndex, 1);
      final endOfMonth = (monthIndex < 12)
          ? DateTime(currentYear, monthIndex + 1, 1).subtract(const Duration(milliseconds: 1))
          : DateTime(currentYear + 1, 1, 1).subtract(const Duration(milliseconds: 1));

      final List<Map<String, dynamic>> items = [];

      for (final userDoc in usersSnap.docs) {
        final uData = userDoc.data();
        final username = uData['username'] ?? uData['email'] ?? 'Unknown User';
        final rawYupassId = (uData['yupass_id'] ?? uData['yupassId'] ?? '').toString().trim();
        final email = (uData['email'] ?? '').toString().toLowerCase().trim();

        // 2. Fetch existing marks from Firestore if available
        String existingTodoVal = '';
        String existingCallingVal = '';

        if (rawYupassId.isNotEmpty) {
          final markDoc = await FirebaseFirestore.instance
              .collection('marks')
              .doc(_selectedMonth)
              .collection('branches')
              .doc(_selectedBranch)
              .collection('yupass_ids')
              .doc(rawYupassId)
              .get();

          if (markDoc.exists && markDoc.data() != null) {
            final mData = markDoc.data()!;
            if (mData['Todo'] != null) {
              existingTodoVal = mData['Todo'].toString();
            }
            if (mData['Customer Calling'] != null) {
              existingCallingVal = mData['Customer Calling'].toString();
            }
          }
        }

        // 3. Calculate Todo Percentage using `daily_report` collection
        double todoPct = 0.0;
        try {
          final userId = userDoc.id;
          final dailySnap = await FirebaseFirestore.instance
              .collection('daily_report')
              .where('userId', isEqualTo: userId)
              .where('type', isEqualTo: 'todo')
              .get();

          int totalReportsInMonth = 0;
          for (final dDoc in dailySnap.docs) {
            final dData = dDoc.data();
            final ts = dData['timestamp'];
            DateTime? dDate;
            if (ts is Timestamp) {
              dDate = ts.toDate();
            } else if (ts is String) {
              dDate = DateTime.tryParse(ts);
            }

            if (dDate != null &&
                dDate.isAfter(startOfMonth.subtract(const Duration(seconds: 1))) &&
                dDate.isBefore(endOfMonth)) {
              totalReportsInMonth++;
            }
          }

          // Calculate percentage based on days in month or total entries
          final daysInMonth = DateTime(currentYear, monthIndex + 1, 0).day;
          if (daysInMonth > 0) {
            todoPct = (totalReportsInMonth / daysInMonth) * 100;
            if (todoPct > 100) todoPct = 100.0;
          }
        } catch (_) {}

        // 4. Calculate Customer Calling Percentage
        double callingPct = 0.0;
        if (email.isNotEmpty) {
          try {
            final callingDoc = await FirebaseFirestore.instance
                .collection('customer_target')
                .doc(monthYearStr)
                .collection('users')
                .doc(email)
                .get();

            if (callingDoc.exists && callingDoc.data() != null) {
              final customers = callingDoc.data()!['customers'] as List<dynamic>? ?? [];
              int totalCust = customers.length;
              int completedCust = 0;

              for (final c in customers) {
                if (c is Map) {
                  final status = (c['status'] ?? '').toString().toLowerCase();
                  final remarks = (c['remarks'] ?? '').toString().trim();
                  if (status == 'done' || status == 'completed' || remarks.isNotEmpty) {
                    completedCust++;
                  }
                }
              }

              if (totalCust > 0) {
                callingPct = (completedCust / totalCust) * 100;
              }
            }
          } catch (_) {}
        }

        final calcTodoStr = "${todoPct.toStringAsFixed(1)}%";
        final calcCallingStr = "${callingPct.toStringAsFixed(1)}%";

        final bool hasExistingTodo = existingTodoVal.isNotEmpty;
        final bool hasExistingCalling = existingCallingVal.isNotEmpty;

        final bool useAutoTodo = !hasExistingTodo;
        final bool useAutoCalling = !hasExistingCalling;

        final todoController = TextEditingController(
          text: hasExistingTodo ? existingTodoVal : calcTodoStr,
        );

        final callingController = TextEditingController(
          text: hasExistingCalling ? existingCallingVal : calcCallingStr,
        );

        items.add({
          'username': username,
          'yupass_id': rawYupassId,
          'email': email,
          'branch': _selectedBranch,
          'calculatedTodoPct': calcTodoStr,
          'calculatedCallingPct': calcCallingStr,
          'useAutoTodo': useAutoTodo,
          'useAutoCalling': useAutoCalling,
          'todoController': todoController,
          'callingController': callingController,
        });
      }

      if (mounted) {
        setState(() {
          for (final item in _userMarkItems) {
            (item['todoController'] as TextEditingController).dispose();
            (item['callingController'] as TextEditingController).dispose();
          }
          _userMarkItems = items;
          _loadingUsers = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading user data: $e')),
        );
        setState(() {
          _loadingUsers = false;
        });
      }
    }
  }

  Future<void> _sendMarksToFirestore() async {
    if (_userMarkItems.isEmpty) return;

    // Check if any user is missing a yupass_id
    final missingUsers = _userMarkItems
        .where((item) => (item['yupass_id'] as String).isEmpty)
        .map((item) => item['username'] as String)
        .toList();

    if (missingUsers.isNotEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Missing Yupass ID'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Cannot submit marks. The following user(s) do not have a Yupass ID:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              ...missingUsers.map(
                (u) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2.0),
                  child: Text('• $u', style: const TextStyle(color: Colors.red)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      for (final item in _userMarkItems) {
        final yupassId = item['yupass_id'] as String;
        final useAutoTodo = item['useAutoTodo'] as bool;
        final useAutoCalling = item['useAutoCalling'] as bool;

        final calcTodo = item['calculatedTodoPct'] as String;
        final calcCalling = item['calculatedCallingPct'] as String;

        final todoVal = useAutoTodo
            ? calcTodo
            : (item['todoController'] as TextEditingController).text.trim();
        final callingVal = useAutoCalling
            ? calcCalling
            : (item['callingController'] as TextEditingController).text.trim();

        await MarksFirestoreService.setMarkData(
          month: _selectedMonth,
          branch: _selectedBranch,
          yupassId: yupassId,
          todoData: todoVal,
          customerCallingData: callingVal,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Marks saved to Firestore successfully!'),
            backgroundColor: primaryGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save marks: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9);
    final cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.bolt_rounded, color: Colors.white, size: 26),
            SizedBox(width: 8),
            Text('Yupulse Sync', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, letterSpacing: 0.3)),
          ],
        ),
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loadingBranches
          ? const Center(child: CircularProgressIndicator(color: primaryGreen))
          : Column(
              children: [
                // Top Filter Header Container
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.06),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      // Month Selector Dropdown
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(left: 4, bottom: 6),
                              child: Text(
                                'SELECT MONTH',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                  color: isDark ? Colors.white60 : Colors.grey.shade600,
                                ),
                              ),
                            ),
                            DropdownButtonFormField<String>(
                              initialValue: _selectedMonth,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : Colors.grey.shade900,
                              ),
                              dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                              decoration: InputDecoration(
                                prefixIcon: const Icon(Icons.calendar_month_rounded, color: primaryGreen, size: 20),
                                filled: true,
                                fillColor: isDark ? const Color(0xFF334155) : const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide.none,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(color: isDark ? Colors.grey.shade700 : Colors.grey.shade200),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(color: primaryGreen, width: 2),
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                              ),
                              items: _months.map((m) {
                                return DropdownMenuItem(
                                  value: m,
                                  child: Text(m, style: const TextStyle(fontWeight: FontWeight.w600)),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null && val != _selectedMonth) {
                                  setState(() {
                                    _selectedMonth = val;
                                  });
                                  _loadUserData();
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Branch Selector Dropdown
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(left: 4, bottom: 6),
                              child: Text(
                                'SELECT BRANCH',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                  color: isDark ? Colors.white60 : Colors.grey.shade600,
                                ),
                              ),
                            ),
                            DropdownButtonFormField<String>(
                              initialValue: _selectedBranch,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : Colors.grey.shade900,
                              ),
                              dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                              decoration: InputDecoration(
                                prefixIcon: const Icon(Icons.location_city_rounded, color: primaryGreen, size: 20),
                                filled: true,
                                fillColor: isDark ? const Color(0xFF334155) : const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide.none,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(color: isDark ? Colors.grey.shade700 : Colors.grey.shade200),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(color: primaryGreen, width: 2),
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                              ),
                              items: _branches.map((b) {
                                return DropdownMenuItem(
                                  value: b,
                                  child: Text(b, style: const TextStyle(fontWeight: FontWeight.w600)),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null && val != _selectedBranch) {
                                  setState(() {
                                    _selectedBranch = val;
                                  });
                                  _loadUserData();
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // User List Content
                Expanded(
                  child: _selectedBranch == 'All Branches'
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: primaryGreen.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.filter_alt_rounded, size: 40, color: primaryGreen),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Select a branch to calculate & sync marks',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white70 : Colors.grey.shade700,
                                ),
                              ),
                            ],
                          ),
                        )
                      : _loadingUsers
                          ? const Center(child: CircularProgressIndicator(color: primaryGreen))
                          : _userMarkItems.isEmpty
                              ? Center(
                                  child: Text(
                                    'No users found for $_selectedBranch.',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                      color: isDark ? Colors.white70 : Colors.grey.shade600,
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                  itemCount: _userMarkItems.length,
                                  itemBuilder: (context, index) {
                                    final item = _userMarkItems[index];
                                    final username = item['username'] as String;
                                    final yupassId = item['yupass_id'] as String;
                                    final calcTodo = item['calculatedTodoPct'] as String;
                                    final calcCalling = item['calculatedCallingPct'] as String;
                                    final bool useAutoTodo = item['useAutoTodo'] as bool;
                                    final bool useAutoCalling = item['useAutoCalling'] as bool;
                                    final todoCtrl = item['todoController'] as TextEditingController;
                                    final callingCtrl = item['callingController'] as TextEditingController;
                                    final hasYupassId = yupassId.isNotEmpty;

                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 16),
                                      decoration: BoxDecoration(
                                        color: cardColor,
                                        borderRadius: BorderRadius.circular(18),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
                                            blurRadius: 10,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                        border: Border.all(
                                          color: hasYupassId
                                              ? (isDark ? Colors.grey.shade800 : Colors.grey.shade200)
                                              : Colors.red.shade400,
                                          width: hasYupassId ? 1 : 1.5,
                                        ),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.all(16.0),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            // User Header
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Expanded(
                                                  child: Row(
                                                    children: [
                                                      Container(
                                                        width: 38,
                                                        height: 38,
                                                        decoration: BoxDecoration(
                                                          gradient: LinearGradient(
                                                            colors: [
                                                              primaryGreen,
                                                              primaryGreen.withValues(alpha: 0.7),
                                                            ],
                                                            begin: Alignment.topLeft,
                                                            end: Alignment.bottomRight,
                                                          ),
                                                          borderRadius: BorderRadius.circular(12),
                                                        ),
                                                        child: Center(
                                                          child: Text(
                                                            username.isNotEmpty ? username[0].toUpperCase() : 'U',
                                                            style: const TextStyle(
                                                              color: Colors.white,
                                                              fontWeight: FontWeight.bold,
                                                              fontSize: 16,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 12),
                                                      Expanded(
                                                        child: Column(
                                                          crossAxisAlignment: CrossAxisAlignment.start,
                                                          children: [
                                                            Text(
                                                              username,
                                                              style: const TextStyle(
                                                                fontSize: 16,
                                                                fontWeight: FontWeight.bold,
                                                              ),
                                                              overflow: TextOverflow.ellipsis,
                                                            ),
                                                            Text(
                                                              'Branch: $_selectedBranch',
                                                              style: TextStyle(
                                                                fontSize: 11,
                                                                color: isDark ? Colors.white54 : Colors.grey.shade600,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                  decoration: BoxDecoration(
                                                    color: hasYupassId
                                                        ? primaryGreen.withValues(alpha: 0.12)
                                                        : Colors.red.shade50,
                                                    borderRadius: BorderRadius.circular(20),
                                                    border: Border.all(
                                                      color: hasYupassId
                                                          ? primaryGreen.withValues(alpha: 0.3)
                                                          : Colors.red.shade300,
                                                    ),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(
                                                        hasYupassId ? Icons.verified_user_rounded : Icons.warning_amber_rounded,
                                                        size: 14,
                                                        color: hasYupassId ? primaryGreen : Colors.red.shade700,
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        hasYupassId ? 'ID: $yupassId' : 'Missing Yupass ID',
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          color: hasYupassId ? primaryGreen : Colors.red.shade700,
                                                          fontWeight: FontWeight.w700,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 16),
                                            Divider(height: 1, color: isDark ? Colors.grey.shade800 : Colors.grey.shade200),
                                            const SizedBox(height: 16),
                                            // Marks Control Grid
                                            Row(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                // Todo Column
                                                Expanded(
                                                  child: _buildMarkSection(
                                                    title: 'Todo Mark',
                                                    icon: Icons.checklist_rounded,
                                                    autoValue: calcTodo,
                                                    useAuto: useAutoTodo,
                                                    controller: todoCtrl,
                                                    isDark: isDark,
                                                    onCheckboxChanged: (val) {
                                                      setState(() {
                                                        item['useAutoTodo'] = val ?? true;
                                                        if (item['useAutoTodo'] == true) {
                                                          todoCtrl.text = calcTodo;
                                                        }
                                                      });
                                                    },
                                                  ),
                                                ),
                                                const SizedBox(width: 14),
                                                // Customer Calling Column
                                                Expanded(
                                                  child: _buildMarkSection(
                                                    title: 'Customer Calling',
                                                    icon: Icons.phone_in_talk_rounded,
                                                    autoValue: calcCalling,
                                                    useAuto: useAutoCalling,
                                                    controller: callingCtrl,
                                                    isDark: isDark,
                                                    onCheckboxChanged: (val) {
                                                      setState(() {
                                                        item['useAutoCalling'] = val ?? true;
                                                        if (item['useAutoCalling'] == true) {
                                                          callingCtrl.text = calcCalling;
                                                        }
                                                      });
                                                    },
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
                // Bottom Submit Bar
                if (_selectedBranch != 'All Branches' && _userMarkItems.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cardColor,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.08),
                          blurRadius: 16,
                          offset: const Offset(0, -4),
                        ),
                      ],
                    ),
                    child: ElevatedButton.icon(
                      onPressed: _saving ? null : _sendMarksToFirestore,
                      icon: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Icon(Icons.cloud_upload_rounded, color: Colors.white, size: 20),
                      label: Text(
                        _saving ? 'Saving Marks...' : 'Send Marks to Firestore',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.3,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryGreen,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        elevation: 3,
                        shadowColor: primaryGreen.withValues(alpha: 0.4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildMarkSection({
    required String title,
    required IconData icon,
    required String autoValue,
    required bool useAuto,
    required TextEditingController controller,
    required bool isDark,
    required ValueChanged<bool?> onCheckboxChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: primaryGreen),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Auto Value Pill Display
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: primaryGreen.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: primaryGreen.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.auto_awesome_rounded, size: 12, color: primaryGreen),
                    SizedBox(width: 4),
                    Text(
                      'Auto Val:',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: primaryGreen,
                      ),
                    ),
                  ],
                ),
                Text(
                  autoValue,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: primaryGreen,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Checkbox toggle
          InkWell(
            onTap: () => onCheckboxChanged(!useAuto),
            borderRadius: BorderRadius.circular(6),
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: Checkbox(
                    value: useAuto,
                    activeColor: primaryGreen,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    onChanged: onCheckboxChanged,
                  ),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Use Auto Value',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Input Box Below
          TextField(
            controller: controller,
            enabled: !useAuto,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: useAuto
                  ? (isDark ? Colors.white38 : Colors.grey.shade500)
                  : (isDark ? Colors.white : Colors.grey.shade900),
            ),
            decoration: InputDecoration(
              labelText: useAuto ? 'Auto Applied' : 'Enter Custom Mark',
              labelStyle: TextStyle(
                fontSize: 11,
                color: useAuto ? (isDark ? Colors.white38 : Colors.grey.shade500) : primaryGreen,
              ),
              filled: true,
              fillColor: useAuto
                  ? (isDark ? const Color(0xFF1E293B) : Colors.grey.shade200)
                  : (isDark ? const Color(0xFF1E293B) : Colors.white),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: isDark ? Colors.grey.shade700 : Colors.grey.shade300),
              ),
              disabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: isDark ? Colors.grey.shade800 : Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: primaryGreen, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }
}

