import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../Navigation/user_cache_service.dart';
import 'marks_firestore_service.dart';
import 'yupulse_mark_model.dart';
import 'yupulse_ui_helpers.dart';
import 'yupulse_user_card.dart';

class YupulseSyncPage extends StatefulWidget {
  const YupulseSyncPage({super.key});

  @override
  State<YupulseSyncPage> createState() => _YupulseSyncPageState();
}

class _YupulseSyncPageState extends State<YupulseSyncPage> {
  static const Color primaryGreen = YupulseUiHelpers.primaryGreen;

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
  String? _selectedBranch;
  bool _loadingBranches = true;
  bool _loadingUsers = false;
  bool _saving = false;

  List<YupulseUserCardItem> _userMarkItems = [];

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
      item.dispose();
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
          _branches = list;
          _selectedBranch = null;
          _loadingBranches = false;
        });
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
    if (_selectedBranch == null) {
      setState(() {
        _userMarkItems = [];
      });
      return;
    }

    setState(() {
      _loadingUsers = true;
    });

    try {
      final usersSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('branch', isEqualTo: _selectedBranch)
          .get();

      final currentYear = DateTime.now().year;
      final monthYearStr = "$_selectedMonth $currentYear";
      final monthIndex = _months.indexOf(_selectedMonth) + 1;
      final periodStr = "$currentYear-${monthIndex.toString().padLeft(2, '0')}";

      final startOfMonth = DateTime(currentYear, monthIndex, 1);

      final List<YupulseUserCardItem> items = [];

      for (final userDoc in usersSnap.docs) {
        final uData = userDoc.data();
        final username = (uData['username'] ?? uData['email'] ?? 'Unknown User').toString();
        final rawYupulseId = (uData['YuPulseID'] ?? uData['yupass_id'] ?? uData['yupassId'] ?? uData['yupulse_id'] ?? '').toString().trim();
        final email = (uData['email'] ?? '').toString().toLowerCase().trim();

        // Check if this user was already submitted for this month period
        bool isAlreadySubmitted = false;
        if (rawYupulseId.isNotEmpty) {
          isAlreadySubmitted = await MarksFirestoreService.isUserSubmitted(
            period: periodStr,
            yupulseId: rawYupulseId,
          );
        }

        // 1. Calculate auto Todo days done (matches monthly.dart logic)
        int autoTodoDoneCount = 0;
        try {
          final userId = userDoc.id;
          final nextMonthDate = (monthIndex == 12)
              ? DateTime(currentYear + 1, 1, 1)
              : DateTime(currentYear, monthIndex + 1, 1);
          final today = DateTime.now();
          final int lastDay = (nextMonthDate.isAfter(today)
              ? today
              : nextMonthDate.subtract(const Duration(days: 1))).day;

          final dailySnap = await FirebaseFirestore.instance
              .collection('daily_report')
              .where('userId', isEqualTo: userId)
              .where('type', isEqualTo: 'todo')
              .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth.subtract(const Duration(days: 2))))
              .where('timestamp', isLessThan: Timestamp.fromDate(nextMonthDate.add(const Duration(hours: 12))))
              .get();

          final Set<DateTime> todoDates = {};
          for (final dDoc in dailySnap.docs) {
            final ts = dDoc.data()['timestamp'];
            if (ts is Timestamp) {
              todoDates.add(ts.toDate());
            } else if (ts is String) {
              final parsed = DateTime.tryParse(ts);
              if (parsed != null) todoDates.add(parsed);
            }
          }

          for (int i = 0; i < lastDay; i++) {
            final date = startOfMonth.add(Duration(days: i));
            if (date.weekday == DateTime.sunday) continue;

            final dayStart = DateTime(date.year, date.month, date.day);
            DateTime windowStart;
            if (dayStart.weekday == DateTime.monday) {
              windowStart = dayStart.subtract(const Duration(days: 2)).add(const Duration(hours: 12));
            } else {
              windowStart = dayStart.subtract(const Duration(days: 1)).add(const Duration(hours: 12));
            }
            final windowEnd = dayStart.add(const Duration(hours: 12));

            final bool isDone = todoDates.any((todoDate) =>
                todoDate.isAfter(windowStart) && todoDate.isBefore(windowEnd));

            if (isDone) {
              autoTodoDoneCount++;
            }
          }
        } catch (_) {}

        // 2. Calculate auto Customer Calling target & done counts
        int autoCallTargetCount = 0;
        int autoCallDoneCount = 0;
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
              autoCallTargetCount = customers.length;

              for (final c in customers) {
                if (c is Map) {
                  final status = (c['status'] ?? '').toString().toLowerCase();
                  final remarks = (c['remarks'] ?? '').toString().trim();
                  if (status == 'done' || status == 'completed' || remarks.isNotEmpty) {
                    autoCallDoneCount++;
                  }
                }
              }
            }
          } catch (_) {}
        }

        // 3. Fetch existing document from yupulse_bda_marks if available
        int? savedTodoDoneCount;
        int? savedCallTargetCount;
        int? savedCallDoneCount;
        String savedReason = '';
        bool hasSavedDoc = false;

        if (rawYupulseId.isNotEmpty) {
          final markDoc = await MarksFirestoreService.getMarkData(
            period: periodStr,
            yupulseId: rawYupulseId,
          );

          if (markDoc.exists && markDoc.data() != null) {
            hasSavedDoc = true;
            final mData = markDoc.data()!;
            final answers = mData['answers'] as Map<String, dynamic>? ?? {};

            if (answers['todoDoneCount'] != null) {
              savedTodoDoneCount = int.tryParse(answers['todoDoneCount'].toString());
            }
            if (answers['callTargetCount'] != null) {
              savedCallTargetCount = int.tryParse(answers['callTargetCount'].toString());
            }
            if (answers['callDoneCount'] != null) {
              savedCallDoneCount = int.tryParse(answers['callDoneCount'].toString());
            }
            if (answers['callReason'] != null) {
              savedReason = answers['callReason'].toString();
            }
          }
        }

        final int initialTodoDone = savedTodoDoneCount ?? autoTodoDoneCount;
        final int initialCallTarget = savedCallTargetCount ?? autoCallTargetCount;
        final int initialCallDone = savedCallDoneCount ?? autoCallDoneCount;

        bool useAutoTodo = true;
        bool useAutoCalling = true;

        if (hasSavedDoc) {
          if (savedTodoDoneCount != null && savedTodoDoneCount != autoTodoDoneCount) {
            useAutoTodo = false;
          }
          if ((savedCallTargetCount != null && savedCallTargetCount != autoCallTargetCount) ||
              (savedCallDoneCount != null && savedCallDoneCount != autoCallDoneCount)) {
            useAutoCalling = false;
          }
        }

        final todoController = TextEditingController(text: initialTodoDone.toString());
        final callTargetController = TextEditingController(text: initialCallTarget.toString());
        final callDoneController = TextEditingController(text: initialCallDone.toString());
        final reasonController = TextEditingController(text: savedReason);

        items.add(YupulseUserCardItem(
          username: username,
          yupulseId: rawYupulseId,
          email: email,
          branch: _selectedBranch!,
          period: periodStr,
          isSubmitted: isAlreadySubmitted,
          isSelected: !isAlreadySubmitted,
          autoTodoDoneCount: autoTodoDoneCount,
          autoCallTargetCount: autoCallTargetCount,
          autoCallDoneCount: autoCallDoneCount,
          useAutoTodo: useAutoTodo,
          useAutoCalling: useAutoCalling,
          todoController: todoController,
          callTargetController: callTargetController,
          callDoneController: callDoneController,
          reasonController: reasonController,
        ));
      }

      if (mounted) {
        setState(() {
          for (final item in _userMarkItems) {
            item.dispose();
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
    if (_userMarkItems.isEmpty || _selectedBranch == null) return;

    final selectedItems = _userMarkItems
        .where((item) => item.isSelected && !item.isSubmitted)
        .toList();

    if (selectedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one unsubmitted user to save marks.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final missingUsers = selectedItems
        .where((item) => item.yupulseId.isEmpty)
        .map((item) => item.username)
        .toList();

    if (missingUsers.isNotEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Missing Yupulse ID'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Cannot submit marks. The following selected user(s) do not have a Yupulse ID:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              ...missingUsers.map(
                (u) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2.0),
                  child: Text('• $u', style: const TextStyle(color: Colors.red)),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Tip: You can unselect users without a Yupulse ID by clicking the circle next to their name to save marks for others.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
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

    final invalidCallingUsers = <String>[];
    for (final item in selectedItems) {
      if (!item.useAutoCalling) {
        final target = int.tryParse(item.callTargetController.text.trim()) ?? 0;
        final done = int.tryParse(item.callDoneController.text.trim()) ?? 0;
        if (done > target) {
          invalidCallingUsers.add('${item.username} (Target: $target, Called: $done)');
        }
      }
    }

    if (invalidCallingUsers.isNotEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Invalid Called Count'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Called count cannot be greater than Total Target for the following user(s):',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              ...invalidCallingUsers.map(
                (u) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2.0),
                  child: Text('• $u', style: const TextStyle(color: Colors.red)),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Please correct the numbers before saving.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
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

    final invalidReasonUsers = <String>[];
    for (final item in selectedItems) {
      if (!item.useAutoTodo || !item.useAutoCalling) {
        final reason = item.reasonController.text.trim();
        if (reason.length < 15) {
          invalidReasonUsers.add('${item.username} (${reason.length}/15 chars)');
        }
      }
    }

    if (invalidReasonUsers.isNotEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Reason Too Short'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'A minimum of 15 characters is required in the reason field for the following user(s):',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              ...invalidReasonUsers.map(
                (u) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2.0),
                  child: Text('• $u', style: const TextStyle(color: Colors.red)),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Please provide a detailed reason before submitting.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
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

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 24),
            SizedBox(width: 8),
            Text('Confirm Submission', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to submit marks for ${selectedItems.length} user(s) in $_selectedBranch for $_selectedMonth?',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.lock_rounded, color: Colors.red.shade700, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Important: Once submitted, marks cannot be edited or submitted again for this month.',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.red.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Confirm & Submit', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _saving = true;
    });

    try {
      await UserCacheService.instance.ensureLoaded();
      final currentSyncHeadUser = UserCacheService.instance.username ??
          FirebaseAuth.instance.currentUser?.displayName ??
          FirebaseAuth.instance.currentUser?.email ??
          'SyncHead';

      final currentBranch = _selectedBranch!;

      for (final item in selectedItems) {
        final yupulseId = item.yupulseId;
        final period = item.period;
        final employeeName = item.username;
        final useAutoTodo = item.useAutoTodo;
        final useAutoCalling = item.useAutoCalling;

        final autoTodoDone = item.autoTodoDoneCount;
        final autoCallTarget = item.autoCallTargetCount;
        final autoCallDone = item.autoCallDoneCount;

        final todoDoneCount = useAutoTodo
            ? autoTodoDone
            : (int.tryParse(item.todoController.text.trim()) ?? 0);

        final callTargetCount = useAutoCalling
            ? autoCallTarget
            : (int.tryParse(item.callTargetController.text.trim()) ?? 0);

        final callDoneCount = useAutoCalling
            ? autoCallDone
            : (int.tryParse(item.callDoneController.text.trim()) ?? 0);

        final callReason = (!useAutoTodo || !useAutoCalling)
            ? item.reasonController.text.trim()
            : '';

        await MarksFirestoreService.setMarkData(
          period: period,
          yupulseId: yupulseId,
          employeeName: employeeName,
          currentSyncHeadUser: currentSyncHeadUser,
          callTargetCount: callTargetCount,
          callDoneCount: callDoneCount,
          callReason: callReason,
          todoDoneCount: todoDoneCount,
        );

        await MarksFirestoreService.recordSubmissionLock(
          period: period,
          yupulseId: yupulseId,
          branch: currentBranch,
          employeeName: employeeName,
          currentSyncHeadUser: currentSyncHeadUser,
        );

        item.isSubmitted = true;
        item.isSelected = false;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Marks submitted for ${selectedItems.length} user(s) successfully! (Locked)'),
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

    final unsubmittedItems = _userMarkItems.where((i) => !i.isSubmitted).toList();
    final selectedCount = _userMarkItems.where((i) => i.isSelected && !i.isSubmitted).length;
    final submittedCount = _userMarkItems.where((i) => i.isSubmitted).length;

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
                              hint: Text(
                                'Select Branch',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: isDark ? Colors.white54 : Colors.grey.shade600,
                                ),
                              ),
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
                // Selection stats header if users loaded
                if (_userMarkItems.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 20, right: 20, top: 12, bottom: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          unsubmittedItems.isEmpty
                              ? 'All ${_userMarkItems.length} users submitted (Locked)'
                              : 'Selected: $selectedCount of ${unsubmittedItems.length} unsubmitted ($submittedCount submitted)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white70 : Colors.grey.shade700,
                          ),
                        ),
                        if (unsubmittedItems.isNotEmpty)
                          InkWell(
                            onTap: () {
                              final allUnsubmittedSelected = selectedCount == unsubmittedItems.length;
                              setState(() {
                                for (final item in _userMarkItems) {
                                  if (!item.isSubmitted) {
                                    item.isSelected = !allUnsubmittedSelected;
                                  }
                                }
                              });
                            },
                            child: Text(
                              selectedCount == unsubmittedItems.length ? 'Deselect All' : 'Select All',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: primaryGreen,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                // Main Content List
                Expanded(
                  child: _selectedBranch == null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.touch_app_rounded, size: 56, color: primaryGreen.withValues(alpha: 0.6)),
                              const SizedBox(height: 12),
                              Text(
                                'Select a Branch to view users',
                                style: TextStyle(
                                  fontSize: 16,
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
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  itemCount: _userMarkItems.length,
                                  itemBuilder: (context, index) {
                                    final item = _userMarkItems[index];

                                    return YupulseUserCard(
                                      item: item,
                                      selectedBranch: _selectedBranch!,
                                      isDark: isDark,
                                      cardColor: cardColor,
                                      onToggleSelected: () {
                                        setState(() {
                                          item.isSelected = !item.isSelected;
                                        });
                                      },
                                      onToggleAutoTodo: (useAuto) {
                                        setState(() {
                                          item.useAutoTodo = useAuto;
                                          if (useAuto) {
                                            item.todoController.text = item.autoTodoDoneCount.toString();
                                          }
                                        });
                                      },
                                      onToggleAutoCalling: (useAuto) {
                                        setState(() {
                                          item.useAutoCalling = useAuto;
                                          if (useAuto) {
                                            item.callTargetController.text = item.autoCallTargetCount.toString();
                                            item.callDoneController.text = item.autoCallDoneCount.toString();
                                          }
                                        });
                                      },
                                      onReasonChanged: () {
                                        setState(() {});
                                      },
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
                      onPressed: (_saving || unsubmittedItems.isEmpty || selectedCount == 0) ? null : _sendMarksToFirestore,
                      icon: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : Icon(
                              unsubmittedItems.isEmpty ? Icons.lock_outline_rounded : Icons.cloud_upload_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                      label: Text(
                        _saving
                            ? 'Submitting Marks...'
                            : unsubmittedItems.isEmpty
                                ? 'All Users Submitted for $_selectedMonth'
                                : selectedCount == unsubmittedItems.length
                                    ? 'Submit Marks for All ($selectedCount)'
                                    : 'Submit Marks for $selectedCount User(s)',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.3,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: unsubmittedItems.isEmpty ? Colors.grey : primaryGreen,
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
}
