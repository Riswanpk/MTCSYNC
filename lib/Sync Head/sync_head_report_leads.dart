import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:intl/intl.dart';

const Color _primaryBlue = Color(0xFF005BAC);
const Color _primaryGreen = Color(0xFF8CC63F);

class SyncHeadReportLeadsPage extends StatefulWidget {
  const SyncHeadReportLeadsPage({super.key});

  @override
  State<SyncHeadReportLeadsPage> createState() =>
      _SyncHeadReportLeadsPageState();
}

class _SyncHeadReportLeadsPageState extends State<SyncHeadReportLeadsPage> {
  List<String> _branches = [];
  String? _selectedBranch;
  DateTimeRange? _selectedRange;
  bool _branchesLoading = true;
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    _fetchBranches();
    final now = DateTime.now();
    _selectedRange = DateTimeRange(
      start: DateTime(now.year, now.month, 1),
      end: DateTime(now.year, now.month + 1, 0, 23, 59, 59),
    );
  }

  Future<void> _fetchBranches() async {
    final snap = await FirebaseFirestore.instance.collection('users').get();
    final branches = snap.docs
        .map((d) => d.data()['branch'] as String?)
        .where((b) => b != null && b.isNotEmpty && b.toLowerCase() != 'admin')
        .toSet()
        .cast<String>()
        .toList()
      ..sort();
    setState(() {
      _branches = ['All Branches', ...branches];
      _branchesLoading = false;
    });
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023, 1, 1),
      lastDate: DateTime(2100),
      initialDateRange: _selectedRange,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: _primaryBlue,
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _selectedRange = picked);
    }
  }

  String _formatDate(DateTime d) => DateFormat('dd MMM yyyy').format(d);

  /// Fetches lead stats for all users in the selected branch & date range,
  /// then generates and shares an Excel report.
  Future<void> _generateReport() async {
    if (_selectedBranch == null || _selectedRange == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please select a branch and date range.')),
      );
      return;
    }

    setState(() => _isGenerating = true);
    // Capture messenger so snackbars work even if user navigates away
    final messenger = ScaffoldMessenger.of(context);

    try {
      final rangeStart = _selectedRange!.start;
      final rangeEnd = DateTime(
        _selectedRange!.end.year,
        _selectedRange!.end.month,
        _selectedRange!.end.day,
        23,
        59,
        59,
      );

      // ── 1. Fetch users in branch or all branches ─────────────────────
      Query usersQuery = FirebaseFirestore.instance.collection('users');
      if (_selectedBranch != 'All Branches') {
        usersQuery = usersQuery.where('branch', isEqualTo: _selectedBranch);
      } else {
        usersQuery = usersQuery.where('branch', isNotEqualTo: 'admin');
      }
      final usersSnap = await usersQuery.get();

      final users = usersSnap.docs
          .map((d) {
            final data = d.data() as Map<String, dynamic>?;
            return {
              'uid': d.id,
              'username': data?['username'] ?? 'Unknown',
              'role': data?['role'] ?? 'sales',
              'branch': data?['branch'] ?? '',
            };
          })
          .where((u) => u['role'] != 'admin' && u['role'] != 'sync_head' && (u['branch'] as String).toLowerCase() != 'admin')
          .toList();

      if (users.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('No users found in this branch.')),
        );
        if (mounted) setState(() => _isGenerating = false);
        return;
      }

      // ── 2. Fetch stats per user (parallel) ─────────────────────────────
        final List<Map<String, dynamic>> stats = [];
        await Future.wait(users.map((user) async {
        final uid = user['uid'] as String;
        final userBranch = user['branch'] as String? ?? '';
        final branchForQuery = _selectedBranch == 'All Branches' ? userBranch : _selectedBranch;

        final results = await Future.wait([
          // Created in range
          FirebaseFirestore.instance
            .collection('follow_ups')
            .where('created_by', isEqualTo: uid)
            .where('branch', isEqualTo: branchForQuery)
            .where('created_at',
              isGreaterThanOrEqualTo: Timestamp.fromDate(rangeStart))
            .where('created_at',
              isLessThanOrEqualTo: Timestamp.fromDate(rangeEnd))
            .get(),
          // Sale in range
          FirebaseFirestore.instance
            .collection('follow_ups')
            .where('created_by', isEqualTo: uid)
            .where('branch', isEqualTo: branchForQuery)
            .where('status', isEqualTo: 'Sale')
            .where('completed_at',
              isGreaterThanOrEqualTo: Timestamp.fromDate(rangeStart))
            .where('completed_at',
              isLessThanOrEqualTo: Timestamp.fromDate(rangeEnd))
            .get(),
          // Cancelled in range
          FirebaseFirestore.instance
            .collection('follow_ups')
            .where('created_by', isEqualTo: uid)
            .where('branch', isEqualTo: branchForQuery)
            .where('status', isEqualTo: 'Cancelled')
            .where('completed_at',
              isGreaterThanOrEqualTo: Timestamp.fromDate(rangeStart))
            .where('completed_at',
              isLessThanOrEqualTo: Timestamp.fromDate(rangeEnd))
            .get(),
        ]);

        stats.add({
          'username': user['username'],
          'role': user['role'],
          'branch': userBranch,
          'created': (results[0] as QuerySnapshot).size,
          'sale': (results[1] as QuerySnapshot).size,
          'cancelled': (results[2] as QuerySnapshot).size,
        });
        }));

      if (_selectedBranch == 'All Branches') {
        // Group users by branch
        final Map<String, List<Map<String, dynamic>>> branchMap = {};
        for (final user in stats) {
          final branch = (user['branch'] ?? 'Unknown').toString();
          branchMap.putIfAbsent(branch, () => []).add(user);
        }
        final sortedBranches = branchMap.keys.toList()..sort();
        final xlsio.Workbook workbook = xlsio.Workbook();
        int sheetIdx = 0;
        for (final branch in sortedBranches) {
          final usersForBranch = branchMap[branch]!;
          // Sort by created ascending, managers at the bottom
          usersForBranch.sort((a, b) {
            final aIsManager = (a['role'] as String).toLowerCase() == 'manager';
            final bIsManager = (b['role'] as String).toLowerCase() == 'manager';
            if (aIsManager && !bIsManager) return 1;
            if (!aIsManager && bIsManager) return -1;
            return (a['created'] as int).compareTo(b['created'] as int);
          });
          // First sheet already exists; add new sheets for subsequent branches
          final xlsio.Worksheet sheet = sheetIdx == 0
              ? workbook.worksheets[0]
              : workbook.worksheets.addWithName(branch);
          sheet.name = branch; // always set name
          sheetIdx++;

          // Title row
          final titleRange = sheet.getRangeByName('A1:E1');
          titleRange.merge();
          titleRange.setText(
              'Leads Report — $branch  (${_formatDate(rangeStart)} → ${_formatDate(rangeEnd)})');
          titleRange.cellStyle.bold = true;
          titleRange.cellStyle.fontSize = 14;
          titleRange.cellStyle.hAlign = xlsio.HAlignType.center;
          titleRange.cellStyle.backColor = '#005BAC';
          titleRange.cellStyle.fontColor = '#FFFFFF';
          sheet.getRangeByName('A1').rowHeight = 30;

          // Header row — unique style name per sheet to avoid collision
          const headers = ['User', 'Role', 'Created', 'Sale', 'Cancelled'];
          final headerStyle = workbook.styles.add('header_$sheetIdx');
          headerStyle.bold = true;
          headerStyle.fontSize = 11;
          headerStyle.backColor = '#8CC63F';
          headerStyle.fontColor = '#FFFFFF';
          headerStyle.hAlign = xlsio.HAlignType.center;
          headerStyle.borders.bottom.lineStyle = xlsio.LineStyle.thin;

          for (int c = 0; c < headers.length; c++) {
            final cell = sheet.getRangeByIndex(2, c + 1);
            cell.setText(headers[c]);
            cell.cellStyle = headerStyle;
          }

          // Data rows
          int totalCreated = 0, totalSale = 0, totalCancelled = 0;

          final dataStyle = workbook.styles.add('data_$sheetIdx');
          dataStyle.fontSize = 11;
          dataStyle.hAlign = xlsio.HAlignType.center;

          final nameStyle = workbook.styles.add('nameStyle_$sheetIdx');
          nameStyle.fontSize = 11;
          nameStyle.hAlign = xlsio.HAlignType.left;

          final altStyle = workbook.styles.add('altData_$sheetIdx');
          altStyle.fontSize = 11;
          altStyle.hAlign = xlsio.HAlignType.center;
          altStyle.backColor = '#F0F5FF';

          final altNameStyle = workbook.styles.add('altNameStyle_$sheetIdx');
          altNameStyle.fontSize = 11;
          altNameStyle.hAlign = xlsio.HAlignType.left;
          altNameStyle.backColor = '#F0F5FF';

          for (int i = 0; i < usersForBranch.length; i++) {
            final row = i + 3;
            final s = usersForBranch[i];
            final created = s['created'] as int;
            final sale = s['sale'] as int;
            final cancelled = s['cancelled'] as int;
            totalCreated += created;
            totalSale += sale;
            totalCancelled += cancelled;

            final isAlt = i % 2 == 1;
            final currentNameStyle = isAlt ? altNameStyle : nameStyle;
            final currentDataStyle = isAlt ? altStyle : dataStyle;

            final cellA = sheet.getRangeByIndex(row, 1);
            cellA.setText(s['username'] as String);
            cellA.cellStyle = currentNameStyle;

            final cellB = sheet.getRangeByIndex(row, 2);
            final role = s['role'] as String;
            cellB.setText(
                role.isNotEmpty ? role[0].toUpperCase() + role.substring(1) : role);
            cellB.cellStyle = currentDataStyle;

            final cellC = sheet.getRangeByIndex(row, 3);
            cellC.setNumber(created.toDouble());
            cellC.cellStyle = currentDataStyle;

            final cellD = sheet.getRangeByIndex(row, 4);
            cellD.setNumber(sale.toDouble());
            cellD.cellStyle = currentDataStyle;

            final cellE = sheet.getRangeByIndex(row, 5);
            cellE.setNumber(cancelled.toDouble());
            cellE.cellStyle = currentDataStyle;
          }

          // Totals row
          final totalsRow = usersForBranch.length + 3;
          final totalsStyle = workbook.styles.add('totals_$sheetIdx');
          totalsStyle.bold = true;
          totalsStyle.fontSize = 12;
          totalsStyle.hAlign = xlsio.HAlignType.center;
          totalsStyle.backColor = '#005BAC';
          totalsStyle.fontColor = '#FFFFFF';
          totalsStyle.borders.top.lineStyle = xlsio.LineStyle.medium;

          final totalsNameStyle = workbook.styles.add('totalsName_$sheetIdx');
          totalsNameStyle.bold = true;
          totalsNameStyle.fontSize = 12;
          totalsNameStyle.hAlign = xlsio.HAlignType.left;
          totalsNameStyle.backColor = '#005BAC';
          totalsNameStyle.fontColor = '#FFFFFF';
          totalsNameStyle.borders.top.lineStyle = xlsio.LineStyle.medium;

          final tA = sheet.getRangeByIndex(totalsRow, 1);
          tA.setText('TOTAL');
          tA.cellStyle = totalsNameStyle;

          final tB = sheet.getRangeByIndex(totalsRow, 2);
          tB.setText('');
          tB.cellStyle = totalsStyle;

          final tC = sheet.getRangeByIndex(totalsRow, 3);
          tC.setNumber(totalCreated.toDouble());
          tC.cellStyle = totalsStyle;

          final tD = sheet.getRangeByIndex(totalsRow, 4);
          tD.setNumber(totalSale.toDouble());
          tD.cellStyle = totalsStyle;

          final tE = sheet.getRangeByIndex(totalsRow, 5);
          tE.setNumber(totalCancelled.toDouble());
          tE.cellStyle = totalsStyle;

          // Column widths
          sheet.getRangeByIndex(1, 1).columnWidth = 25;
          sheet.getRangeByIndex(1, 2).columnWidth = 15;
          sheet.getRangeByIndex(1, 3).columnWidth = 14;
          sheet.getRangeByIndex(1, 4).columnWidth = 14;
          sheet.getRangeByIndex(1, 5).columnWidth = 14;
        }
        // Save & send email (moved below)
        final List<int> bytes = workbook.saveAsStream();
        workbook.dispose();

        final directory = await getTemporaryDirectory();
        final String fileName =
            '${directory.path}/Leads_Report_AllBranches_${DateFormat('yyyyMMdd').format(rangeStart)}_${DateFormat('yyyyMMdd').format(rangeEnd)}.xlsx';
        final File file = File(fileName);
        await file.writeAsBytes(bytes, flush: true);

        // --- Send email with attachment ---
        final smtpServer = gmail('crmmalabar@gmail.com', 'rhmo laoh qara qrnd');
        final message = Message()
          ..from = Address('crmmalabar@gmail.com', 'MTC Sync')
          ..recipients.addAll(['crmmalabar@gmail.com','performancemtc@gmail.com'])
          ..subject = 'Leads Report — All Branches'
          ..text = 'Please find attached the leads report for all branches.'
          ..attachments = [FileAttachment(file)];

        try {
          await send(message, smtpServer);
          messenger.showSnackBar(
            const SnackBar(content: Text('Email sent to crmmalabar@gmail.com')),
          );
        } on MailerException catch (e) {
          messenger.showSnackBar(
            SnackBar(content: Text('Failed to send email: ${e.toString()}')),
          );
        }
        return;
      }

      // (else: single branch, original logic)
      final xlsio.Workbook workbook = xlsio.Workbook();
      final xlsio.Worksheet sheet = workbook.worksheets[0];
      sheet.name = _selectedBranch ?? 'Report';

      // Title row
      final titleRange = sheet.getRangeByName('A1:E1');
      titleRange.merge();
      titleRange.setText(
          'Leads Report — $_selectedBranch  (${_formatDate(rangeStart)} → ${_formatDate(rangeEnd)})');
      titleRange.cellStyle.bold = true;
      titleRange.cellStyle.fontSize = 14;
      titleRange.cellStyle.hAlign = xlsio.HAlignType.center;
      titleRange.cellStyle.backColor = '#005BAC';
      titleRange.cellStyle.fontColor = '#FFFFFF';
      sheet.getRangeByName('A1').rowHeight = 30;

      // Header row
      const headers = ['User', 'Role', 'Created', 'Sale', 'Cancelled'];
      final headerStyle = workbook.styles.add('header');
      headerStyle.bold = true;
      headerStyle.fontSize = 11;
      headerStyle.backColor = '#8CC63F';
      headerStyle.fontColor = '#FFFFFF';
      headerStyle.hAlign = xlsio.HAlignType.center;
      headerStyle.borders.bottom.lineStyle = xlsio.LineStyle.thin;

      for (int c = 0; c < headers.length; c++) {
        final cell = sheet.getRangeByIndex(2, c + 1);
        cell.setText(headers[c]);
        cell.cellStyle = headerStyle;
      }

      // Data rows
      int totalCreated = 0, totalSale = 0, totalCancelled = 0;

      final dataStyle = workbook.styles.add('data');
      dataStyle.fontSize = 11;
      dataStyle.hAlign = xlsio.HAlignType.center;

      final nameStyle = workbook.styles.add('nameStyle');
      nameStyle.fontSize = 11;
      nameStyle.hAlign = xlsio.HAlignType.left;

      final altStyle = workbook.styles.add('altData');
      altStyle.fontSize = 11;
      altStyle.hAlign = xlsio.HAlignType.center;
      altStyle.backColor = '#F0F5FF';

      final altNameStyle = workbook.styles.add('altNameStyle');
      altNameStyle.fontSize = 11;
      altNameStyle.hAlign = xlsio.HAlignType.left;
      altNameStyle.backColor = '#F0F5FF';

      for (int i = 0; i < stats.length; i++) {
        final row = i + 3;
        final s = stats[i];
        final created = s['created'] as int;
        final sale = s['sale'] as int;
        final cancelled = s['cancelled'] as int;
        totalCreated += created;
        totalSale += sale;
        totalCancelled += cancelled;

        final isAlt = i % 2 == 1;
        final currentNameStyle = isAlt ? altNameStyle : nameStyle;
        final currentDataStyle = isAlt ? altStyle : dataStyle;

        final cellA = sheet.getRangeByIndex(row, 1);
        cellA.setText(s['username'] as String);
        cellA.cellStyle = currentNameStyle;

        final cellB = sheet.getRangeByIndex(row, 2);
        final role = s['role'] as String;
        cellB.setText(
            role.isNotEmpty ? role[0].toUpperCase() + role.substring(1) : role);
        cellB.cellStyle = currentDataStyle;

        final cellC = sheet.getRangeByIndex(row, 3);
        cellC.setNumber(created.toDouble());
        cellC.cellStyle = currentDataStyle;

        final cellD = sheet.getRangeByIndex(row, 4);
        cellD.setNumber(sale.toDouble());
        cellD.cellStyle = currentDataStyle;

        final cellE = sheet.getRangeByIndex(row, 5);
        cellE.setNumber(cancelled.toDouble());
        cellE.cellStyle = currentDataStyle;
      }

      // Totals row
      final totalsRow = stats.length + 3;
      final totalsStyle = workbook.styles.add('totals');
      totalsStyle.bold = true;
      totalsStyle.fontSize = 12;
      totalsStyle.hAlign = xlsio.HAlignType.center;
      totalsStyle.backColor = '#005BAC';
      totalsStyle.fontColor = '#FFFFFF';
      totalsStyle.borders.top.lineStyle = xlsio.LineStyle.medium;

      final totalsNameStyle = workbook.styles.add('totalsName');
      totalsNameStyle.bold = true;
      totalsNameStyle.fontSize = 12;
      totalsNameStyle.hAlign = xlsio.HAlignType.left;
      totalsNameStyle.backColor = '#005BAC';
      totalsNameStyle.fontColor = '#FFFFFF';
      totalsNameStyle.borders.top.lineStyle = xlsio.LineStyle.medium;

      final tA = sheet.getRangeByIndex(totalsRow, 1);
      tA.setText('TOTAL');
      tA.cellStyle = totalsNameStyle;

      final tB = sheet.getRangeByIndex(totalsRow, 2);
      tB.setText('');
      tB.cellStyle = totalsStyle;

      final tC = sheet.getRangeByIndex(totalsRow, 3);
      tC.setNumber(totalCreated.toDouble());
      tC.cellStyle = totalsStyle;

      final tD = sheet.getRangeByIndex(totalsRow, 4);
      tD.setNumber(totalSale.toDouble());
      tD.cellStyle = totalsStyle;

      final tE = sheet.getRangeByIndex(totalsRow, 5);
      tE.setNumber(totalCancelled.toDouble());
      tE.cellStyle = totalsStyle;

      // Column widths
      sheet.getRangeByIndex(1, 1).columnWidth = 25;
      sheet.getRangeByIndex(1, 2).columnWidth = 15;
      sheet.getRangeByIndex(1, 3).columnWidth = 14;
      sheet.getRangeByIndex(1, 4).columnWidth = 14;
      sheet.getRangeByIndex(1, 5).columnWidth = 14;

      // ── 4. Save & send email ─────────────────────────────────────────
      final List<int> bytes = workbook.saveAsStream();
      workbook.dispose();

      final directory = await getTemporaryDirectory();
      final String fileName =
          '${directory.path}/Leads_Report_${_selectedBranch}_${DateFormat('yyyyMMdd').format(rangeStart)}_${DateFormat('yyyyMMdd').format(rangeEnd)}.xlsx';
      final File file = File(fileName);
      await file.writeAsBytes(bytes, flush: true);

      // --- Send email with attachment ---
      final smtpServer = gmail('crmmalabar@gmail.com', 'rhmo laoh qara qrnd');
      final message = Message()
        ..from = Address('crmmalabar@gmail.com', 'MTC Sync')
        ..recipients.addAll(['crmmalabar@gmail.com'])
        ..subject = 'Leads Report — $_selectedBranch'
        ..text = 'Please find attached the leads report for $_selectedBranch.'
        ..attachments = [FileAttachment(file)];

      try {
        await send(message, smtpServer);
        messenger.showSnackBar(
          const SnackBar(content: Text('Email sent to crmmalabar@gmail.com')),
        );
      } on MailerException catch (e) {
        messenger.showSnackBar(
          SnackBar(content: Text('Failed to send email: ${e.toString()}')),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to generate report: $e')),
      );
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0A1628) : const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Leads Excel Report'),
        backgroundColor: _primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Date range picker ──────────────────────────────────────
            InkWell(
              onTap: _pickDateRange,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  border:
                      Border.all(color: _primaryBlue.withOpacity(0.4)),
                  borderRadius: BorderRadius.circular(10),
                  color: isDark
                      ? const Color(0xFF162236)
                      : const Color(0xFFF0F5FF),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.date_range_rounded,
                        color: _primaryBlue, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _selectedRange == null
                            ? 'Select Date Range'
                            : '${_formatDate(_selectedRange!.start)}  →  ${_formatDate(_selectedRange!.end)}',
                        style: TextStyle(
                          color: isDark ? Colors.white : _primaryBlue,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Icon(Icons.arrow_drop_down_rounded,
                        color: isDark ? Colors.white54 : _primaryBlue),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Branch dropdown ────────────────────────────────────────
            _branchesLoading
                ? const LinearProgressIndicator()
                : DropdownButtonFormField<String>(
                    value: _selectedBranch,
                    decoration: InputDecoration(
                      labelText: 'Branch',
                      labelStyle:
                          const TextStyle(color: _primaryBlue),
                      prefixIcon: const Icon(
                          Icons.location_city_rounded,
                          color: _primaryBlue,
                          size: 20),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                            color: _primaryBlue.withOpacity(0.4)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                            color: _primaryBlue.withOpacity(0.4)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                            color: _primaryBlue, width: 1.5),
                      ),
                      filled: true,
                      fillColor: isDark
                          ? const Color(0xFF162236)
                          : const Color(0xFFF0F5FF),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                    dropdownColor: isDark
                        ? const Color(0xFF162236)
                        : Colors.white,
                    style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                        fontSize: 14),
                    items: _branches
                        .map((b) =>
                            DropdownMenuItem(value: b, child: Text(b)))
                        .toList(),
                    onChanged: (val) =>
                        setState(() => _selectedBranch = val),
                  ),

            const SizedBox(height: 32),

            // ── Generate button ────────────────────────────────────────
            ElevatedButton.icon(
              onPressed: _isGenerating ? null : _generateReport,
              icon: _isGenerating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.download_rounded),
              label: Text(_isGenerating
                  ? 'Generating...'
                  : 'Generate & Share Excel'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),

            const SizedBox(height: 24),

            // ── Info card ──────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF0D2137)
                    : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: _primaryBlue.withOpacity(0.15)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline_rounded,
                          color: _primaryBlue.withOpacity(0.7),
                          size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Report Contents',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : _primaryBlue,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _infoLine(Icons.person_rounded, 'User name & role',
                      isDark),
                  _infoLine(
                      Icons.add_circle_outline_rounded,
                      'Leads created in date range',
                      isDark),
                  _infoLine(Icons.handshake_rounded,
                      'Leads converted to Sale', isDark),
                  _infoLine(Icons.cancel_rounded,
                      'Leads marked Cancelled', isDark),
                  _infoLine(Icons.functions_rounded,
                      'Branch totals row', isDark),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoLine(IconData icon, String text, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon,
              size: 16,
              color: isDark ? Colors.white38 : Colors.black38),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white60 : Colors.black54,
            ),
          ),
        ],
      ),
    );
  }
}
