import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import '../Navigation/user_cache_service.dart';

const Color _primaryGreen = Color(0xFF8CC63F);

class SyncHeadReportTodoPage extends StatefulWidget {
  const SyncHeadReportTodoPage({super.key});

  @override
  State<SyncHeadReportTodoPage> createState() => _SyncHeadReportTodoPageState();
}

class _SyncHeadReportTodoPageState extends State<SyncHeadReportTodoPage> {
  List<String> _branches = [];
  String _selectedBranch = 'All Branches';
  DateTimeRange? _selectedRange;
  bool _isDetailed = false;
  bool _branchesLoading = true;
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    _fetchBranches();
    final now = DateTime.now();
    _selectedRange = DateTimeRange(
      start: DateTime(now.year, now.month, 1),
      end: DateTime(now.year, now.month, now.day, 23, 59, 59),
    );
  }

  Future<void> _fetchBranches() async {
    final allBranches = await UserCacheService.instance.getBranches();
    final branches = allBranches
        .where((b) => b.toLowerCase() != 'admin')
        .toList();
    setState(() {
      _branches = ['All Branches', ...branches];
      _branchesLoading = false;
    });
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023, 1, 1),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: _selectedRange,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: _primaryGreen,
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      // Ensure end of day covers until 23:59:59
      final endOfDay = DateTime(
        picked.end.year,
        picked.end.month,
        picked.end.day,
        23,
        59,
        59,
      );
      setState(() {
        _selectedRange = DateTimeRange(start: picked.start, end: endOfDay);
      });
    }
  }

  String _formatDate(DateTime d) => DateFormat('dd MMM yyyy').format(d);

  Future<void> _generateReport() async {
    if (_selectedRange == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a date range.')),
      );
      return;
    }

    setState(() => _isGenerating = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final rangeStart = _selectedRange!.start;
      final rangeEnd = _selectedRange!.end;

      // 1. Determine list of target branches
      List<String> targetBranches = [];
      if (_selectedBranch == 'All Branches') {
        targetBranches = _branches.where((b) => b != 'All Branches').toList();
      } else {
        targetBranches = [_selectedBranch];
      }

      // 2. Fetch users in target branches excluding admin & sync_head
      final usersSnap = await FirebaseFirestore.instance
          .collection('users')
          .get();

      final allUsers = usersSnap.docs
          .map((d) {
            final data = d.data();
            return {
              'uid': d.id,
              'username': data['username'] ?? 'Unknown',
              'email': data['email'] ?? '',
              'role': (data['role'] ?? 'sales').toString(),
              'branch': (data['branch'] ?? '').toString(),
            };
          })
          .where((u) {
            final role = u['role'].toLowerCase();
            final branch = u['branch'];
            if (role == 'admin' || role == 'sync_head') return false;
            if (branch.toLowerCase() == 'admin') return false;
            return targetBranches.contains(branch);
          })
          .toList();

      // Sort users by branch, then role (managers first), then username
      allUsers.sort((a, b) {
        final bComp = a['branch'].compareTo(b['branch']);
        if (bComp != 0) return bComp;
        final roleA = a['role'];
        final roleB = b['role'];
        if (roleA != roleB) {
          if (roleA == 'manager' || roleA == 'asst_manager') return -1;
          if (roleB == 'manager' || roleB == 'asst_manager') return 1;
        }
        return a['username'].compareTo(b['username']);
      });

      // 3. Fetch pending todos for each user within the selected date range
      List<Map<String, dynamic>> userPendingTodos = [];
      int totalCreatedOverall = 0;
      int totalPendingOverall = 0;

      await Future.wait(allUsers.map((user) async {
        final email = user['email'] as String;
        if (email.isEmpty) return;

        final snap = await FirebaseFirestore.instance
            .collection('todo')
            .where('email', isEqualTo: email)
            .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(rangeStart))
            .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(rangeEnd))
            .get();

        final allDocs = snap.docs.map((d) => {...d.data(), 'id': d.id}).toList();
        final createdCount = allDocs.length;

        // Pending todos are those where status != 'done' && status != 'completed'
        final pendingDocs = allDocs.where((todo) {
          final st = (todo['status'] ?? 'pending').toString().toLowerCase();
          return st != 'done' && st != 'completed';
        }).toList();

        // Sort pending todos by timestamp ascending
        pendingDocs.sort((a, b) {
          final tsA = a['timestamp'];
          final tsB = b['timestamp'];
          DateTime dtA = tsA is Timestamp ? tsA.toDate() : DateTime(1970);
          DateTime dtB = tsB is Timestamp ? tsB.toDate() : DateTime(1970);
          return dtA.compareTo(dtB);
        });

        userPendingTodos.add({
          'username': user['username'],
          'role': user['role'],
          'email': email,
          'branch': user['branch'],
          'created': createdCount,
          'pendingCount': pendingDocs.length,
          'pendingTodos': pendingDocs,
        });
      }));

      // Re-sort userPendingTodos using allUsers ordering
      final userOrderMap = {for (int i = 0; i < allUsers.length; i++) allUsers[i]['email']: i};
      userPendingTodos.sort((a, b) {
        final orderA = userOrderMap[a['email']] ?? 9999;
        final orderB = userOrderMap[b['email']] ?? 9999;
        return orderA.compareTo(orderB);
      });

      for (var u in userPendingTodos) {
        totalCreatedOverall += (u['created'] as int);
        totalPendingOverall += (u['pendingCount'] as int);
      }

      // 4. Create Excel workbook
      final xlsio.Workbook workbook = xlsio.Workbook();
      final xlsio.Worksheet sheet = workbook.worksheets[0];
      sheet.name = 'Pending Todos';
      sheet.showGridlines = true;

      // Title row
      final dateSubtitle = '(${_formatDate(rangeStart)} → ${_formatDate(rangeEnd)})';
      final titleRange = sheet.getRangeByName('A1:C1');
      titleRange.merge();
      titleRange.setText('Pending ToDos Report — $_selectedBranch  $dateSubtitle');
      titleRange.cellStyle.bold = true;
      titleRange.cellStyle.fontSize = 14;
      titleRange.cellStyle.hAlign = xlsio.HAlignType.center;
      titleRange.cellStyle.backColor = '#005BAC';
      titleRange.cellStyle.fontColor = '#FFFFFF';
      sheet.getRangeByName('A1').rowHeight = 28;

      // Table Header row (Username, Created, Pending)
      final headerStyle = workbook.styles.add('headerStyle');
      headerStyle.bold = true;
      headerStyle.fontSize = 11;
      headerStyle.backColor = '#8CC63F';
      headerStyle.fontColor = '#FFFFFF';
      headerStyle.hAlign = xlsio.HAlignType.center;

      final nameHeaderStyle = workbook.styles.add('nameHeaderStyle');
      nameHeaderStyle.bold = true;
      nameHeaderStyle.fontSize = 11;
      nameHeaderStyle.backColor = '#8CC63F';
      nameHeaderStyle.fontColor = '#FFFFFF';
      nameHeaderStyle.hAlign = xlsio.HAlignType.left;

      final cellHdrA = sheet.getRangeByIndex(2, 1);
      cellHdrA.setText('username');
      cellHdrA.cellStyle = nameHeaderStyle;

      final cellHdrB = sheet.getRangeByIndex(2, 2);
      cellHdrB.setText('created');
      cellHdrB.cellStyle = headerStyle;

      final cellHdrC = sheet.getRangeByIndex(2, 3);
      cellHdrC.setText('Pending');
      cellHdrC.cellStyle = headerStyle;

      // Data Rows
      final dataStyle = workbook.styles.add('dataStyle');
      dataStyle.fontSize = 10;
      dataStyle.hAlign = xlsio.HAlignType.center;

      final nameStyle = workbook.styles.add('nameStyle');
      nameStyle.fontSize = 10;
      nameStyle.hAlign = xlsio.HAlignType.left;

      final altDataStyle = workbook.styles.add('altDataStyle');
      altDataStyle.fontSize = 10;
      altDataStyle.hAlign = xlsio.HAlignType.center;
      altDataStyle.backColor = '#F0F5FF';

      final altNameStyle = workbook.styles.add('altNameStyle');
      altNameStyle.fontSize = 10;
      altNameStyle.hAlign = xlsio.HAlignType.left;
      altNameStyle.backColor = '#F0F5FF';

      int currentRow = 3;
      for (int i = 0; i < userPendingTodos.length; i++) {
        final item = userPendingTodos[i];
        final isAlt = i % 2 == 1;
        final curNameStyle = isAlt ? altNameStyle : nameStyle;
        final curDataStyle = isAlt ? altDataStyle : dataStyle;

        final cA = sheet.getRangeByIndex(currentRow, 1);
        cA.setText((item['username'] as String).toUpperCase());
        cA.cellStyle = curNameStyle;

        final cB = sheet.getRangeByIndex(currentRow, 2);
        cB.setNumber((item['created'] as int).toDouble());
        cB.cellStyle = curDataStyle;

        final cC = sheet.getRangeByIndex(currentRow, 3);
        cC.setNumber((item['pendingCount'] as int).toDouble());
        cC.cellStyle = curDataStyle;

        currentRow++;
      }

      // Totals Row
      final totalsStyle = workbook.styles.add('totalsStyle');
      totalsStyle.bold = true;
      totalsStyle.fontSize = 11;
      totalsStyle.hAlign = xlsio.HAlignType.center;
      totalsStyle.backColor = '#005BAC';
      totalsStyle.fontColor = '#FFFFFF';

      final totalsNameStyle = workbook.styles.add('totalsNameStyle');
      totalsNameStyle.bold = true;
      totalsNameStyle.fontSize = 11;
      totalsNameStyle.hAlign = xlsio.HAlignType.left;
      totalsNameStyle.backColor = '#005BAC';
      totalsNameStyle.fontColor = '#FFFFFF';

      final tA = sheet.getRangeByIndex(currentRow, 1);
      tA.setText('TOTAL');
      tA.cellStyle = totalsNameStyle;

      final tB = sheet.getRangeByIndex(currentRow, 2);
      tB.setNumber(totalCreatedOverall.toDouble());
      tB.cellStyle = totalsStyle;

      final tC = sheet.getRangeByIndex(currentRow, 3);
      tC.setNumber(totalPendingOverall.toDouble());
      tC.cellStyle = totalsStyle;

      currentRow += 2; // Blank row separator before detailed section

      // 5. Add Detailed Section below if _isDetailed is true
      if (_isDetailed) {
        final detailUserHdrSt = workbook.styles.add('detailUserHdr');
        detailUserHdrSt.bold = true;
        detailUserHdrSt.fontSize = 11;
        detailUserHdrSt.backColor = '#005BAC';
        detailUserHdrSt.fontColor = '#FFFFFF';
        detailUserHdrSt.hAlign = xlsio.HAlignType.left;

        final detailColHdrSt = workbook.styles.add('detailColHdr');
        detailColHdrSt.bold = true;
        detailColHdrSt.fontSize = 10;
        detailColHdrSt.backColor = '#8CC63F';
        detailColHdrSt.fontColor = '#FFFFFF';
        detailColHdrSt.hAlign = xlsio.HAlignType.left;

        final detailColHdrCenterSt = workbook.styles.add('detailColHdrCenter');
        detailColHdrCenterSt.bold = true;
        detailColHdrCenterSt.fontSize = 10;
        detailColHdrCenterSt.backColor = '#8CC63F';
        detailColHdrCenterSt.fontColor = '#FFFFFF';
        detailColHdrCenterSt.hAlign = xlsio.HAlignType.center;

        final detailDataSt = workbook.styles.add('detailData');
        detailDataSt.fontSize = 10;
        detailDataSt.hAlign = xlsio.HAlignType.left;

        final detailDataCenterSt = workbook.styles.add('detailDataCenter');
        detailDataCenterSt.fontSize = 10;
        detailDataCenterSt.hAlign = xlsio.HAlignType.center;

        final detailAltSt = workbook.styles.add('detailAlt');
        detailAltSt.fontSize = 10;
        detailAltSt.hAlign = xlsio.HAlignType.left;
        detailAltSt.backColor = '#F0F5FF';

        final detailAltCenterSt = workbook.styles.add('detailAltCenter');
        detailAltCenterSt.fontSize = 10;
        detailAltCenterSt.hAlign = xlsio.HAlignType.center;
        detailAltCenterSt.backColor = '#F0F5FF';

        for (final userItem in userPendingTodos) {
          final pendingTodos = userItem['pendingTodos'] as List<dynamic>;
          if (pendingTodos.isEmpty) continue;

          final userName = (userItem['username'] as String).toUpperCase();
          final userBranch = userItem['branch'] as String;

          // User Title Header
          final uHdrRange = sheet.getRangeByIndex(currentRow, 1, currentRow, 3);
          uHdrRange.merge();
          uHdrRange.setText('$userName ($userBranch)');
          uHdrRange.cellStyle = detailUserHdrSt;
          currentRow++;

          // Table subheaders
          final col1 = sheet.getRangeByIndex(currentRow, 1);
          col1.setText('Created Date');
          col1.cellStyle = detailColHdrCenterSt;

          final col2 = sheet.getRangeByIndex(currentRow, 2);
          col2.setText('Title / Priority');
          col2.cellStyle = detailColHdrSt;

          final col3 = sheet.getRangeByIndex(currentRow, 3);
          col3.setText('Description');
          col3.cellStyle = detailColHdrSt;
          currentRow++;

          for (int tIdx = 0; tIdx < pendingTodos.length; tIdx++) {
            final todo = pendingTodos[tIdx];
            final isAlt = tIdx % 2 == 1;
            final curSt = isAlt ? detailAltSt : detailDataSt;
            final curCenterSt = isAlt ? detailAltCenterSt : detailDataCenterSt;

            final ts = todo['timestamp'];
            DateTime? dt;
            if (ts is Timestamp) dt = ts.toDate();
            final dateStr = dt != null ? DateFormat('dd MMM yyyy, hh:mm a').format(dt) : 'N/A';

            final title = (todo['title'] ?? 'Untitled').toString();
            final priority = (todo['priority'] ?? '').toString();
            final titlePrioStr = priority.isNotEmpty ? '$title [$priority]' : title;
            final description = (todo['description'] ?? '').toString();

            final dCellA = sheet.getRangeByIndex(currentRow, 1);
            dCellA.setText(dateStr);
            dCellA.cellStyle = curCenterSt;

            final dCellB = sheet.getRangeByIndex(currentRow, 2);
            dCellB.setText(titlePrioStr);
            dCellB.cellStyle = curSt;

            final dCellC = sheet.getRangeByIndex(currentRow, 3);
            dCellC.setText(description);
            dCellC.cellStyle = curSt;

            currentRow++;
          }

          currentRow++; // Space between users
        }
      }

      // Adjust column widths
      sheet.getRangeByIndex(1, 1).columnWidth = 26;
      sheet.getRangeByIndex(1, 2).columnWidth = 30;
      sheet.getRangeByIndex(1, 3).columnWidth = 45;

      // 6. Save & Share file
      final List<int> bytes = workbook.saveAsStream();
      workbook.dispose();

      final directory = await getTemporaryDirectory();
      final branchClean = _selectedBranch.replaceAll(' ', '_');
      final modeClean = _isDetailed ? 'Detailed' : 'Summary';
      final dateClean = '${DateFormat('dd-MM').format(rangeStart)}_to_${DateFormat('dd-MM').format(rangeEnd)}';
      final fileName = '${directory.path}/Pending_Todos_${branchClean}_${modeClean}_$dateClean.xlsx';
      final File file = File(fileName);
      await file.writeAsBytes(bytes, flush: true);

      await Share.shareXFiles(
        [XFile(fileName)],
        text: 'Pending ToDos Report — $_selectedBranch (${_isDetailed ? 'Detailed' : 'Summary'}) $dateSubtitle',
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to generate report: $e')),
      );
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  void _showBranchSelector() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF162236) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Select Branch',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _branches.length,
                    itemBuilder: (context, index) {
                      final branch = _branches[index];
                      final isSelected = branch == _selectedBranch;
                      return ListTile(
                        leading: Icon(
                          isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                          color: isSelected ? _primaryGreen : (isDark ? Colors.white54 : Colors.black45),
                        ),
                        title: Text(
                          branch,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected
                                ? _primaryGreen
                                : (isDark ? Colors.white : Colors.black87),
                          ),
                        ),
                        onTap: () {
                          setState(() {
                            _selectedBranch = branch;
                          });
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A1628) : const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Export Pending ToDos'),
        backgroundColor: _primaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF162236) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _primaryGreen.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.file_download_outlined, color: _primaryGreen, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Download Pending ToDos',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Export pending todos across branches (excluding Admin).',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Date Range Picker Tile Header
            Text(
              'Date Range',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : const Color.fromARGB(255, 56, 56, 56),
              ),
            ),
            const SizedBox(height: 8),

            // Date Range Selector Tile
            InkWell(
              onTap: _pickDateRange,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF162236) : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _primaryGreen.withValues(alpha: 0.4),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_rounded, color: _primaryGreen, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _selectedRange == null
                            ? 'Select date range'
                            : '${_formatDate(_selectedRange!.start)}  →  ${_formatDate(_selectedRange!.end)}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                    const Icon(Icons.edit_calendar_rounded, color: _primaryGreen, size: 20),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Branch Selector Header
            Text(
              'Select Branch',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : const Color.fromARGB(255, 56, 56, 56),
              ),
            ),
            const SizedBox(height: 8),

            // Custom Styled Branch Picker Tile
            InkWell(
              onTap: _branchesLoading ? null : _showBranchSelector,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF162236) : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _primaryGreen.withValues(alpha: 0.4),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.business_rounded, color: _primaryGreen, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _branchesLoading ? 'Loading branches...' : _selectedBranch,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                    const Icon(Icons.keyboard_arrow_down_rounded, color: _primaryGreen, size: 24),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Detailed Checkbox / Switch Option Card
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF162236) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _isDetailed
                      ? _primaryGreen
                      : (isDark ? Colors.white12 : Colors.black12),
                  width: 1.5,
                ),
              ),
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeColor: _primaryGreen,
                title: Text(
                  'Include Detailed Pending List',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                subtitle: Text(
                  _isDetailed
                      ? 'Detailed breakdown per user will be added below the summary table'
                      : 'Only summary table (username, created, pending) will be exported',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
                value: _isDetailed,
                onChanged: (val) {
                  setState(() => _isDetailed = val);
                },
              ),
            ),

            const Spacer(),

            // Download Button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _isGenerating || _branchesLoading ? null : _generateReport,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 2,
                ),
                icon: _isGenerating
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.download_rounded),
                label: Text(
                  _isGenerating ? 'Generating Excel...' : 'Download Excel Report',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
