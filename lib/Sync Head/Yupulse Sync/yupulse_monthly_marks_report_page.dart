import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;
import '../../Navigation/user_cache_service.dart';

const Color _primaryGreen = Color(0xFF8CC63F);
const Color _primaryBlue = Color(0xFF005BAC);

class YupulseMonthlyMarksReportPage extends StatefulWidget {
  final String? initialBranch;
  final int? initialMonth;
  final int? initialYear;

  const YupulseMonthlyMarksReportPage({
    super.key,
    this.initialBranch,
    this.initialMonth,
    this.initialYear,
  });

  @override
  State<YupulseMonthlyMarksReportPage> createState() =>
      _YupulseMonthlyMarksReportPageState();
}

class _YupulseMonthlyMarksReportPageState
    extends State<YupulseMonthlyMarksReportPage> {
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
  late int _selectedYear;
  List<String> _branches = [];
  String? _selectedBranch;

  bool _loadingBranches = true;
  bool _loadingReport = false;
  bool _isExporting = false;
  String _searchQuery = '';
  String _statusFilter = 'all'; // 'all', 'submitted', 'pending'

  List<_UserMarkReportItem> _reportItems = [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = widget.initialMonth != null
        ? _months[(widget.initialMonth! - 1).clamp(0, 11)]
        : _months[now.month - 1];
    _selectedYear = widget.initialYear ?? now.year;
    _selectedBranch = widget.initialBranch;
    _fetchBranches();
  }

  String get _periodStr {
    final monthIndex = _months.indexOf(_selectedMonth) + 1;
    return '$_selectedYear-${monthIndex.toString().padLeft(2, '0')}';
  }

  Future<void> _fetchBranches() async {
    try {
      final cache = UserCacheService.instance;
      await cache.ensureLoaded();
      final allBranches = await cache.getBranches();
      final branchSet = <String>{};

      for (final b in allBranches) {
        if (b.isNotEmpty && b.toLowerCase() != 'admin') {
          branchSet.add(b);
        }
      }

      // Also ensure any branch stored in users is available
      final usersSnap =
          await FirebaseFirestore.instance.collection('users').get();
      for (final doc in usersSnap.docs) {
        final b = (doc.data()['branch'] ?? '').toString().trim();
        if (b.isNotEmpty && b.toLowerCase() != 'admin') {
          branchSet.add(b);
        }
      }

      final sorted = branchSet.toList()..sort();
      if (mounted) {
        setState(() {
          _branches = sorted;
          if (_selectedBranch == null && sorted.isNotEmpty) {
            _selectedBranch = sorted.first;
          }
          _loadingBranches = false;
        });
        _loadReportData();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingBranches = false);
      }
    }
  }

  Future<void> _loadReportData() async {
    if (_selectedBranch == null) {
      setState(() => _reportItems = []);
      return;
    }

    setState(() => _loadingReport = true);

    try {
      final currentBranch = _selectedBranch!;
      final period = _periodStr;

      // 1. Fetch users for this branch
      final usersSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('branch', isEqualTo: currentBranch)
          .get();

      // 2. Fetch marks & submissions in parallel for the period
      final results = await Future.wait([
        FirebaseFirestore.instance
            .collection('yupulse_bda_marks')
            .where('period', isEqualTo: period)
            .get(),
        FirebaseFirestore.instance
            .collection('yupulse_bda_submissions')
            .where('period', isEqualTo: period)
            .get(),
      ]);

      final marksSnap = results[0];
      final submissionsSnap = results[1];

      final Map<String, Map<String, dynamic>> marksMap = {};
      for (final doc in marksSnap.docs) {
        final data = doc.data();
        final empId = (data['employeeId'] ?? '').toString().trim();
        if (empId.isNotEmpty) {
          marksMap[empId] = data;
        }
      }

      final Map<String, Map<String, dynamic>> submissionsMap = {};
      for (final doc in submissionsSnap.docs) {
        final data = doc.data();
        final empId = (data['employeeId'] ?? '').toString().trim();
        if (empId.isNotEmpty) {
          submissionsMap[empId] = data;
        }
      }

      final List<_UserMarkReportItem> items = [];

      for (final uDoc in usersSnap.docs) {
        final uData = uDoc.data();
        final role = (uData['role'] ?? '').toString().toLowerCase().trim();
        if (role == 'admin' || role == 'sync_head') continue;

        final username =
            (uData['username'] ?? uData['email'] ?? 'Unknown User').toString();
        final rawYupulseId = (uData['YuPulseID'] ??
                uData['yupass_id'] ??
                uData['yupassId'] ??
                uData['yupulse_id'] ??
                '')
            .toString()
            .trim();
        final email = (uData['email'] ?? '').toString().trim();

        final markData = rawYupulseId.isNotEmpty ? marksMap[rawYupulseId] : null;
        final subData =
            rawYupulseId.isNotEmpty ? submissionsMap[rawYupulseId] : null;

        final bool isSubmitted = subData != null;
        final answers = markData?['answers'] as Map<String, dynamic>? ?? {};

        final int todoDone =
            int.tryParse('${answers['todoDoneCount']}') ?? 0;
        final int callTarget =
            int.tryParse('${answers['callTargetCount']}') ?? 0;
        final int callDone =
            int.tryParse('${answers['callDoneCount']}') ?? 0;
        final int supersaleTotal =
            int.tryParse('${answers['supersaleTotal']}') ?? 0;
        final int supersaleTaken =
            int.tryParse('${answers['supersaleTaken']}') ?? 0;
        final int ccLeads =
            int.tryParse('${answers['ccLeadsCreated']}') ?? 0;
        final int salesLeads =
            int.tryParse('${answers['salesLeadsCreated']}') ?? 0;

        final String todoReason = (answers['todoReason'] ?? '').toString().trim();
        final String callReason = (answers['callReason'] ?? '').toString().trim();
        final String supersaleReason =
            (answers['supersaleReason'] ?? '').toString().trim();
        final String leadsReason =
            (answers['leadsReason'] ?? '').toString().trim();

        DateTime? submittedAt;
        final subAtRaw = subData?['submittedAt'] ?? markData?['updatedAt'];
        if (subAtRaw is Timestamp) {
          submittedAt = subAtRaw.toDate();
        }

        final String submittedBy = (subData?['submittedBy'] ??
                markData?['updatedBy'] ??
                markData?['createdBy'] ??
                '')
            .toString()
            .trim();

        items.add(
          _UserMarkReportItem(
            uid: uDoc.id,
            username: username,
            email: email,
            yupulseId: rawYupulseId,
            branch: currentBranch,
            role: role,
            period: period,
            isSubmitted: isSubmitted,
            hasSavedMarks: markData != null,
            todoDoneCount: todoDone,
            callTargetCount: callTarget,
            callDoneCount: callDone,
            supersaleTotal: supersaleTotal,
            supersaleTaken: supersaleTaken,
            ccLeadsCreated: ccLeads,
            salesLeadsCreated: salesLeads,
            todoReason: todoReason,
            callReason: callReason,
            supersaleReason: supersaleReason,
            leadsReason: leadsReason,
            submittedAt: submittedAt,
            submittedBy: submittedBy,
          ),
        );
      }

      // Sort by username
      items.sort((a, b) => a.username.toLowerCase().compareTo(b.username.toLowerCase()));

      if (mounted) {
        setState(() {
          _reportItems = items;
          _loadingReport = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingReport = false);
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text('Failed to load marks report: $e')),
        );
      }
    }
  }

  Future<void> _exportToExcel() async {
    if (_reportItems.isEmpty || _isExporting) return;

    setState(() => _isExporting = true);

    try {
      final xlsio.Workbook workbook = xlsio.Workbook();
      final xlsio.Worksheet sheet = workbook.worksheets[0];
      final monthLabel = '$_selectedMonth $_selectedYear';
      sheet.name = 'Marks Report';

      // Title
      sheet.getRangeByIndex(1, 1).setText(
          'YUPULSE MONTHLY MARKS REPORT — $_selectedBranch — $monthLabel');
      sheet.getRangeByIndex(1, 1).cellStyle.bold = true;
      sheet.getRangeByIndex(1, 1).cellStyle.fontSize = 14;
      sheet.getRangeByIndex(1, 1, 1, 12).merge();

      final headers = [
        'Sl.No',
        'Employee Name',
        'YuPulse ID',
        'Role',
        'Status',
        'Todo Days',
        'Calling Target',
        'Calling Done',
        'Supersale Total',
        'Supersale Taken',
        'CC Leads',
        'Sales Leads',
        'Reasons / Notes',
        'Submitted By',
      ];

      for (int c = 0; c < headers.length; c++) {
        final cell = sheet.getRangeByIndex(3, c + 1);
        cell.setText(headers[c]);
        cell.cellStyle.bold = true;
        cell.cellStyle.backColor = '#D9E1F2';
        cell.cellStyle.hAlign = xlsio.HAlignType.center;
      }

      int row = 4;
      int sl = 1;

      for (final item in _reportItems) {
        sheet.getRangeByIndex(row, 1).setNumber(sl.toDouble());
        sheet.getRangeByIndex(row, 2).setText(item.username);
        sheet.getRangeByIndex(row, 3).setText(
            item.yupulseId.isNotEmpty ? item.yupulseId : 'MISSING ID');
        sheet.getRangeByIndex(row, 4).setText(item.formattedRole);
        sheet.getRangeByIndex(row, 5).setText(
            item.isSubmitted ? 'Submitted (Locked)' : (item.hasSavedMarks ? 'Draft' : 'Not Submitted'));
        sheet.getRangeByIndex(row, 6).setNumber(item.todoDoneCount.toDouble());
        sheet.getRangeByIndex(row, 7).setNumber(item.callTargetCount.toDouble());
        sheet.getRangeByIndex(row, 8).setNumber(item.callDoneCount.toDouble());
        sheet.getRangeByIndex(row, 9).setNumber(item.supersaleTotal.toDouble());
        sheet.getRangeByIndex(row, 10).setNumber(item.supersaleTaken.toDouble());
        sheet.getRangeByIndex(row, 11).setNumber(item.ccLeadsCreated.toDouble());
        sheet.getRangeByIndex(row, 12).setNumber(item.salesLeadsCreated.toDouble());

        final notes = [
          if (item.todoReason.isNotEmpty) 'Todo: ${item.todoReason}',
          if (item.callReason.isNotEmpty) 'Calling: ${item.callReason}',
          if (item.supersaleReason.isNotEmpty) 'Supersale: ${item.supersaleReason}',
          if (item.leadsReason.isNotEmpty) 'Leads: ${item.leadsReason}',
        ].join(' | ');

        sheet.getRangeByIndex(row, 13).setText(notes);
        sheet.getRangeByIndex(row, 14).setText(item.submittedBy);

        if (!item.isSubmitted) {
          for (int c = 1; c <= headers.length; c++) {
            sheet.getRangeByIndex(row, c).cellStyle.backColor = '#FFF2CC';
          }
        }

        sl++;
        row++;
      }

      for (int c = 1; c <= headers.length; c++) {
        sheet.autoFitColumn(c);
      }

      final List<int> bytes = workbook.saveAsStream();
      workbook.dispose();

      final Directory directory = await getTemporaryDirectory();
      final fileName =
          'Yupulse_Marks_${_selectedBranch}_${_selectedMonth}_${_selectedYear}_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';
      final File file = File('${directory.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Yupulse Monthly Marks Report — $_selectedBranch ($monthLabel)',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text('Failed to export Excel: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor =
        isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9);
    final cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;

    final filteredItems = _reportItems.where((i) {
      if (_statusFilter == 'submitted' && !i.isSubmitted) return false;
      if (_statusFilter == 'pending' && i.isSubmitted) return false;
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        if (!i.username.toLowerCase().contains(q) &&
            !i.yupulseId.toLowerCase().contains(q) &&
            !i.email.toLowerCase().contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();

    final submittedCount = _reportItems.where((i) => i.isSubmitted).length;
    final totalUsers = _reportItems.length;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.assessment_rounded, color: Colors.white, size: 24),
            SizedBox(width: 8),
            Text(
              'Monthly Marks Report',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 19,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
        backgroundColor: _primaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: _isExporting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.download_rounded),
            tooltip: 'Export Excel Report',
            onPressed: (_loadingReport || _reportItems.isEmpty || _isExporting)
                ? null
                : _exportToExcel,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _loadingReport ? null : _loadReportData,
          ),
        ],
      ),
      body: _loadingBranches
          ? const Center(child: CircularProgressIndicator(color: _primaryGreen))
          : Column(
              children: [
                // Top Selection Bar (Month, Year, Branch)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16.0, vertical: 14.0),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius:
                        const BorderRadius.vertical(bottom: Radius.circular(20)),
                    boxShadow: [
                      BoxShadow(
                        color:
                            Colors.black.withValues(alpha: isDark ? 0.4 : 0.06),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          // Month Selector
                          Expanded(
                            flex: 3,
                            child: DropdownButtonFormField<String>(
                              initialValue: _selectedMonth,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color:
                                    isDark ? Colors.white : Colors.grey.shade900,
                              ),
                              dropdownColor: isDark
                                  ? const Color(0xFF1E293B)
                                  : Colors.white,
                              decoration: InputDecoration(
                                labelText: 'Month',
                                prefixIcon: const Icon(
                                    Icons.calendar_month_rounded,
                                    color: _primaryGreen,
                                    size: 18),
                                filled: true,
                                fillColor: isDark
                                    ? const Color(0xFF334155)
                                    : const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 8),
                              ),
                              items: _months.map((m) {
                                return DropdownMenuItem(
                                  value: m,
                                  child: Text(m,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600)),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null && val != _selectedMonth) {
                                  setState(() => _selectedMonth = val);
                                  _loadReportData();
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Year Selector
                          Expanded(
                            flex: 2,
                            child: DropdownButtonFormField<int>(
                              initialValue: _selectedYear,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color:
                                    isDark ? Colors.white : Colors.grey.shade900,
                              ),
                              dropdownColor: isDark
                                  ? const Color(0xFF1E293B)
                                  : Colors.white,
                              decoration: InputDecoration(
                                labelText: 'Year',
                                filled: true,
                                fillColor: isDark
                                    ? const Color(0xFF334155)
                                    : const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 8),
                              ),
                              items: List.generate(5, (i) {
                                final y = DateTime.now().year - 2 + i;
                                return DropdownMenuItem(
                                  value: y,
                                  child: Text('$y',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600)),
                                );
                              }),
                              onChanged: (val) {
                                if (val != null && val != _selectedYear) {
                                  setState(() => _selectedYear = val);
                                  _loadReportData();
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Branch Selector
                          Expanded(
                            flex: 4,
                            child: DropdownButtonFormField<String>(
                              initialValue: _selectedBranch,
                              hint: const Text('Branch',
                                  style: TextStyle(fontSize: 12)),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color:
                                    isDark ? Colors.white : Colors.grey.shade900,
                              ),
                              dropdownColor: isDark
                                  ? const Color(0xFF1E293B)
                                  : Colors.white,
                              decoration: InputDecoration(
                                labelText: 'Branch',
                                prefixIcon: const Icon(
                                    Icons.location_city_rounded,
                                    color: _primaryGreen,
                                    size: 18),
                                filled: true,
                                fillColor: isDark
                                    ? const Color(0xFF334155)
                                    : const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 8),
                              ),
                              items: _branches.map((b) {
                                return DropdownMenuItem(
                                  value: b,
                                  child: Text(b,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600)),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null && val != _selectedBranch) {
                                  setState(() => _selectedBranch = val);
                                  _loadReportData();
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // Search and filter chips
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 36,
                              child: TextField(
                                onChanged: (val) =>
                                    setState(() => _searchQuery = val.trim()),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Search employee name or ID...',
                                  prefixIcon:
                                      const Icon(Icons.search_rounded, size: 16),
                                  filled: true,
                                  fillColor: isDark
                                      ? const Color(0xFF0F172A)
                                      : Colors.grey.shade100,
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 0),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _buildFilterChoiceChip('All', 'all', isDark),
                          const SizedBox(width: 4),
                          _buildFilterChoiceChip(
                              'Submitted', 'submitted', isDark),
                          const SizedBox(width: 4),
                          _buildFilterChoiceChip('Pending', 'pending', isDark),
                        ],
                      ),
                    ],
                  ),
                ),

                // Submissions status summary bar
                if (!_loadingReport && _selectedBranch != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    color: isDark
                        ? const Color(0xFF1E293B)
                        : _primaryGreen.withValues(alpha: 0.1),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '$_selectedBranch • $_selectedMonth $_selectedYear',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white70 : _primaryBlue,
                          ),
                        ),
                        Text(
                          'Submitted: $submittedCount / $totalUsers',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: submittedCount == totalUsers && totalUsers > 0
                                ? _primaryGreen
                                : Colors.orange.shade800,
                          ),
                        ),
                      ],
                    ),
                  ),

                Expanded(
                  child: _loadingReport
                      ? const Center(
                          child: CircularProgressIndicator(color: _primaryGreen),
                        )
                      : _selectedBranch == null
                          ? const Center(
                              child: Text('Please select a branch to view marks'),
                            )
                          : filteredItems.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.assignment_late_rounded,
                                          size: 48,
                                          color: Colors.grey.shade400),
                                      const SizedBox(height: 10),
                                      Text(
                                        'No user mark records found for this criteria.',
                                        style: TextStyle(
                                          color: isDark
                                              ? Colors.white60
                                              : Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : ListView.builder(
                                  padding: const EdgeInsets.all(16),
                                  itemCount: filteredItems.length,
                                  itemBuilder: (context, index) {
                                    final item = filteredItems[index];
                                    return _buildUserMarkCard(
                                        item, isDark, cardColor);
                                  },
                                ),
                ),
              ],
            ),
    );
  }

  Widget _buildFilterChoiceChip(String label, String value, bool isDark) {
    final isSelected = _statusFilter == value;
    return InkWell(
      onTap: () => setState(() => _statusFilter = value),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? _primaryGreen
              : (isDark ? const Color(0xFF0F172A) : Colors.grey.shade200),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected
                ? Colors.white
                : (isDark ? Colors.white70 : Colors.black87),
          ),
        ),
      ),
    );
  }

  Widget _buildUserMarkCard(
      _UserMarkReportItem item, bool isDark, Color cardColor) {
    final bool isSubmitted = item.isSubmitted;
    final bool hasId = item.yupulseId.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isSubmitted
            ? (isDark ? const Color(0xFF0D2818) : const Color(0xFFF0FDF4))
            : cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSubmitted
              ? _primaryGreen.withValues(alpha: isDark ? 0.6 : 0.4)
              : (isDark ? Colors.grey.shade800 : Colors.grey.shade200),
          width: isSubmitted ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: User details & status
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: isSubmitted
                      ? _primaryGreen
                      : (isDark ? const Color(0xFF334155) : Colors.grey.shade300),
                  child: Text(
                    item.username.isNotEmpty
                        ? item.username[0].toUpperCase()
                        : 'U',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.username,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Wrap(
                        spacing: 6,
                        runSpacing: 2,
                        children: [
                          Text(
                            item.formattedRole,
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? Colors.white54 : Colors.grey.shade600,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: hasId
                                  ? _primaryGreen.withValues(alpha: 0.12)
                                  : Colors.red.shade50,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              hasId ? 'ID: ${item.yupulseId}' : 'No YuPulse ID',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: hasId
                                    ? _primaryGreen
                                    : Colors.red.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isSubmitted
                        ? _primaryGreen.withValues(alpha: 0.15)
                        : (item.hasSavedMarks
                            ? Colors.orange.withValues(alpha: 0.15)
                            : Colors.grey.withValues(alpha: 0.15)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isSubmitted
                            ? Icons.check_circle_rounded
                            : (item.hasSavedMarks
                                ? Icons.edit_note_rounded
                                : Icons.hourglass_empty_rounded),
                        size: 13,
                        color: isSubmitted
                            ? _primaryGreen
                            : (item.hasSavedMarks
                                ? Colors.orange.shade800
                                : Colors.grey.shade600),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isSubmitted
                            ? 'Submitted (Locked)'
                            : (item.hasSavedMarks ? 'Draft' : 'Pending'),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isSubmitted
                              ? _primaryGreen
                              : (item.hasSavedMarks
                                  ? Colors.orange.shade800
                                  : Colors.grey.shade600),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),

            // Metrics Grid (Todo, Calling, Supersale, Leads)
            Row(
              children: [
                _buildMetricBox(
                  title: 'Todo Mark',
                  value: '${item.todoDoneCount} days',
                  icon: Icons.checklist_rounded,
                  color: _primaryGreen,
                  isDark: isDark,
                  hasReason: item.todoReason.isNotEmpty,
                ),
                const SizedBox(width: 8),
                _buildMetricBox(
                  title: 'Calling',
                  value: '${item.callDoneCount} / ${item.callTargetCount}',
                  icon: Icons.phone_in_talk_rounded,
                  color: _primaryBlue,
                  isDark: isDark,
                  hasReason: item.callReason.isNotEmpty,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildMetricBox(
                  title: 'Supersale',
                  value: '${item.supersaleTaken} / ${item.supersaleTotal}',
                  icon: Icons.local_offer_rounded,
                  color: Colors.purple,
                  isDark: isDark,
                  hasReason: item.supersaleReason.isNotEmpty,
                ),
                const SizedBox(width: 8),
                _buildMetricBox(
                  title: 'Leads Created',
                  value: 'CC: ${item.ccLeadsCreated} | S: ${item.salesLeadsCreated}',
                  icon: Icons.person_add_alt_1_rounded,
                  color: Colors.deepOrange,
                  isDark: isDark,
                  hasReason: item.leadsReason.isNotEmpty,
                ),
              ],
            ),

            // Notes / Override Reasons if any
            if (item.todoReason.isNotEmpty ||
                item.callReason.isNotEmpty ||
                item.supersaleReason.isNotEmpty ||
                item.leadsReason.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: isDark ? 0.12 : 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark
                        ? Colors.amber.shade800
                        : Colors.amber.shade300,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline_rounded,
                            size: 13,
                            color: isDark
                                ? Colors.amber.shade300
                                : Colors.amber.shade900),
                        const SizedBox(width: 4),
                        Text(
                          'Override Reasons:',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? Colors.amber.shade300
                                : Colors.amber.shade900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (item.todoReason.isNotEmpty)
                      Text('• Todo: ${item.todoReason}',
                          style: const TextStyle(fontSize: 11)),
                    if (item.callReason.isNotEmpty)
                      Text('• Calling: ${item.callReason}',
                          style: const TextStyle(fontSize: 11)),
                    if (item.supersaleReason.isNotEmpty)
                      Text('• Supersale: ${item.supersaleReason}',
                          style: const TextStyle(fontSize: 11)),
                    if (item.leadsReason.isNotEmpty)
                      Text('• Leads: ${item.leadsReason}',
                          style: const TextStyle(fontSize: 11)),
                  ],
                ),
              ),
            ],

            if (item.submittedBy.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Submitted by: ${item.submittedBy}',
                    style: TextStyle(
                      fontSize: 10,
                      color: isDark ? Colors.white38 : Colors.grey.shade600,
                    ),
                  ),
                  if (item.submittedAt != null)
                    Text(
                      DateFormat('dd MMM yy, hh:mm a').format(item.submittedAt!),
                      style: TextStyle(
                        fontSize: 10,
                        color: isDark ? Colors.white38 : Colors.grey.shade600,
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMetricBox({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required bool isDark,
    required bool hasReason,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: isDark ? 0.12 : 0.07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: hasReason
                ? Colors.amber.shade600
                : color.withValues(alpha: 0.2),
            width: hasReason ? 1.2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white54 : Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (hasReason)
              Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: Colors.amber,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.edit, size: 8, color: Colors.white),
              ),
          ],
        ),
      ),
    );
  }
}

class _UserMarkReportItem {
  final String uid;
  final String username;
  final String email;
  final String yupulseId;
  final String branch;
  final String role;
  final String period;
  final bool isSubmitted;
  final bool hasSavedMarks;
  final int todoDoneCount;
  final int callTargetCount;
  final int callDoneCount;
  final int supersaleTotal;
  final int supersaleTaken;
  final int ccLeadsCreated;
  final int salesLeadsCreated;
  final String todoReason;
  final String callReason;
  final String supersaleReason;
  final String leadsReason;
  final DateTime? submittedAt;
  final String submittedBy;

  const _UserMarkReportItem({
    required this.uid,
    required this.username,
    required this.email,
    required this.yupulseId,
    required this.branch,
    required this.role,
    required this.period,
    required this.isSubmitted,
    required this.hasSavedMarks,
    required this.todoDoneCount,
    required this.callTargetCount,
    required this.callDoneCount,
    required this.supersaleTotal,
    required this.supersaleTaken,
    required this.ccLeadsCreated,
    required this.salesLeadsCreated,
    required this.todoReason,
    required this.callReason,
    required this.supersaleReason,
    required this.leadsReason,
    this.submittedAt,
    required this.submittedBy,
  });

  String get formattedRole {
    switch (role.toLowerCase()) {
      case 'manager':
        return 'Manager';
      case 'asst_manager':
        return 'Asst. Manager';
      case 'sales':
        return 'Sales';
      default:
        return role;
    }
  }
}

