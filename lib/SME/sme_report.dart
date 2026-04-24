import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;
import '../Navigation/user_cache_service.dart';

const Color _primaryBlue = Color(0xFF005BAC);
const Color _primaryGreen = Color(0xFF8CC63F);

class SmeReportPage extends StatefulWidget {
  const SmeReportPage({super.key});

  @override
  State<SmeReportPage> createState() => _SmeReportPageState();
}

class _SmeReportPageState extends State<SmeReportPage> {
  List<String> _branches = [];
  String? _selectedBranch;
  DateTimeRange? _selectedRange;
  bool _branchesLoading = true;
  bool _isGenerating = false;
  bool _detailedReport = false;
  String _statusFilter = 'All';

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
    final allBranches = await UserCacheService.instance.getBranches();
    final branches = allBranches.where((b) => b.toLowerCase() != 'admin').toList();
    if (mounted) {
      setState(() {
        _branches = ['All Branches', ...branches];
        _branchesLoading = false;
      });
    }
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
    if (picked != null) setState(() => _selectedRange = picked);
  }

  String _formatDate(DateTime d) => DateFormat('dd MMM yyyy').format(d);

  Future<void> _generateReport() async {
    if (_selectedBranch == null || _selectedRange == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a branch and date range.')),
      );
      return;
    }

    setState(() => _isGenerating = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final rangeStart = _selectedRange!.start;
      final rangeEnd = DateTime(
        _selectedRange!.end.year,
        _selectedRange!.end.month,
        _selectedRange!.end.day,
        23, 59, 59,
      );

      // -- Fetch all SME leads for selected branch(es) and date range --
      Query leadsQuery = FirebaseFirestore.instance.collection('follow_ups')
          .where('source', isEqualTo: 'sme')
          .where('created_at', isGreaterThanOrEqualTo: Timestamp.fromDate(rangeStart))
          .where('created_at', isLessThanOrEqualTo: Timestamp.fromDate(rangeEnd));

      if (_selectedBranch != 'All Branches') {
        leadsQuery = leadsQuery.where('branch', isEqualTo: _selectedBranch);
      }

      final leadsSnap = await leadsQuery.get();

      if (leadsSnap.docs.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('No SME leads found for this selection.')),
        );
        if (mounted) setState(() => _isGenerating = false);
        return;
      }

      // -- 3. Build Excel -----------------------------------------------
      if (_selectedBranch == 'All Branches') {
        await _buildAllBranchesExcel(leadsSnap.docs, rangeStart, rangeEnd, messenger);
      } else {
        await _buildSingleBranchExcel(
            leadsSnap.docs, _selectedBranch!, rangeStart, rangeEnd, messenger);
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to generate report: $e')),
      );
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  // -- Excel helpers ------------------------------------------------------------

  void _writeSummarySheetDirect({
    required xlsio.Workbook workbook,
    required xlsio.Worksheet sheet,
    required String title,
    required int total,
    required int inProgress,
    required int sale,
    required int cancelled,
    required int sheetIdx,
  }) {
    const headers = ['Status', 'Count'];

    final titleRange = sheet.getRangeByName('A1:B1');
    titleRange.merge();
    titleRange.setText(title);
    titleRange.cellStyle.bold = true;
    titleRange.cellStyle.fontSize = 14;
    titleRange.cellStyle.hAlign = xlsio.HAlignType.center;
    titleRange.cellStyle.backColor = '#005BAC';
    titleRange.cellStyle.fontColor = '#FFFFFF';
    sheet.getRangeByName('A1').rowHeight = 30;

    final headerStyle = workbook.styles.add('smeHdr_$sheetIdx');
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

    final dataStyle = workbook.styles.add('smeData_$sheetIdx');
    dataStyle.fontSize = 11;
    dataStyle.hAlign = xlsio.HAlignType.left;

    final numStyle = workbook.styles.add('smeNum_$sheetIdx');
    numStyle.fontSize = 11;
    numStyle.hAlign = xlsio.HAlignType.center;

    final statuses = [
      ('Total', total),
      ('In Progress', inProgress),
      ('Sale', sale),
      ('Cancelled', cancelled),
    ];

    for (int i = 0; i < statuses.length; i++) {
      final row = i + 3;
      sheet.getRangeByIndex(row, 1).setText(statuses[i].$1);
      sheet.getRangeByIndex(row, 1).cellStyle = dataStyle;
      sheet.getRangeByIndex(row, 2).setNumber(statuses[i].$2.toDouble());
      sheet.getRangeByIndex(row, 2).cellStyle = numStyle;
    }

    sheet.getRangeByIndex(1, 1).columnWidth = 22;
    sheet.getRangeByIndex(1, 2).columnWidth = 15;
  }

  void _writeDetailSheetDirect({
    required xlsio.Workbook workbook,
    required xlsio.Worksheet sheet,
    required String title,
    required Map<String, List<QueryDocumentSnapshot>> leadsByUser,
    required int sheetIdx,
  }) {
    final titleRange = sheet.getRangeByName('A1:J1');
    titleRange.merge();
    titleRange.setText(title);
    titleRange.cellStyle.bold = true;
    titleRange.cellStyle.fontSize = 14;
    titleRange.cellStyle.hAlign = xlsio.HAlignType.center;
    titleRange.cellStyle.backColor = '#005BAC';
    titleRange.cellStyle.fontColor = '#FFFFFF';
    sheet.getRangeByName('A1').rowHeight = 30;

    sheet.getRangeByIndex(1, 1).columnWidth = 24;
    sheet.getRangeByIndex(1, 2).columnWidth = 16;
    sheet.getRangeByIndex(1, 3).columnWidth = 22;
    sheet.getRangeByIndex(1, 4).columnWidth = 14;
    sheet.getRangeByIndex(1, 5).columnWidth = 14;
    sheet.getRangeByIndex(1, 6).columnWidth = 12;
    sheet.getRangeByIndex(1, 7).columnWidth = 32;
    sheet.getRangeByIndex(1, 8).columnWidth = 20;
    sheet.getRangeByIndex(1, 9).columnWidth = 18;
    sheet.getRangeByIndex(1, 10).columnWidth = 20;

    final userHdrSt = workbook.styles.add('smeDetUserHdr_$sheetIdx');
    userHdrSt.bold = true;
    userHdrSt.fontSize = 11;
    userHdrSt.backColor = '#005BAC';
    userHdrSt.fontColor = '#FFFFFF';
    userHdrSt.hAlign = xlsio.HAlignType.left;

    final colHdrSt = workbook.styles.add('smeDetColHdr_$sheetIdx');
    colHdrSt.bold = true;
    colHdrSt.fontSize = 10;
    colHdrSt.backColor = '#8CC63F';
    colHdrSt.fontColor = '#FFFFFF';
    colHdrSt.hAlign = xlsio.HAlignType.center;

    final dataSt = workbook.styles.add('smeDetData_$sheetIdx');
    dataSt.fontSize = 10;
    dataSt.hAlign = xlsio.HAlignType.left;

    final altSt = workbook.styles.add('smeDetAlt_$sheetIdx');
    altSt.fontSize = 10;
    altSt.hAlign = xlsio.HAlignType.left;
    altSt.backColor = '#F0F5FF';

    const detailHeaders = ['Customer Name', 'Phone', 'Address', 'Platform', 'Status', 'Priority', 'Comments', 'Assigned To', 'Created Date', 'Reminder'];

    int detailRow = 2;

    for (final entry in leadsByUser.entries) {
      final user = entry.key;
      final userLeads = entry.value;

      final userHdrRange = sheet.getRangeByIndex(detailRow, 1, detailRow, detailHeaders.length);
      userHdrRange.merge();
      userHdrRange.setText(user);
      userHdrRange.cellStyle = userHdrSt;
      detailRow++;

      for (int c = 0; c < detailHeaders.length; c++) {
        final cell = sheet.getRangeByIndex(detailRow, c + 1);
        cell.setText(detailHeaders[c]);
        cell.cellStyle = colHdrSt;
      }
      detailRow++;

      for (int leadIdx = 0; leadIdx < userLeads.length; leadIdx++) {
        final leadDoc = userLeads[leadIdx];
        final d = leadDoc.data() as Map<String, dynamic>;

        final createdAt = d['created_at'];
        final createdDateStr = createdAt is Timestamp
            ? DateFormat('dd MMM yyyy').format(createdAt.toDate())
            : '';

        final isAlt = leadIdx % 2 == 1;
        final statusVal = d['status'] ?? '';
        final statusLabel = statusVal == 'Sale' ? 'Sold' : statusVal == 'Cancelled' ? 'Cancelled' : 'In Progress';
        final st = isAlt ? altSt : dataSt;

        void writeCell(int col, String value) {
          sheet.getRangeByIndex(detailRow, col).setText(value);
          sheet.getRangeByIndex(detailRow, col).cellStyle = st;
        }

        writeCell(1, d['name'] ?? '');
        writeCell(2, d['phone'] ?? '');
        writeCell(3, d['address'] ?? '');
        writeCell(4, d['platform'] ?? '');
        writeCell(5, statusLabel);
        writeCell(6, d['priority'] ?? '');
        writeCell(7, d['comments'] ?? '');
        writeCell(8, d['assigned_to_name'] ?? '');
        writeCell(9, createdDateStr);
        writeCell(10, d['reminder'] ?? '');

        detailRow++;
      }
      detailRow++;
    }
  }

  Future<void> _buildSingleBranchExcel(List<QueryDocumentSnapshot> leads, String branch, DateTime rangeStart, DateTime rangeEnd, ScaffoldMessengerState messenger) async {
    final inProgressLeads = leads.where((l) => (l['status'] ?? '') == 'In Progress').toList();
    final saleLeads = leads.where((l) => (l['status'] ?? '') == 'Sale').toList();
    final cancelledLeads = leads.where((l) => (l['status'] ?? '') == 'Cancelled').toList();

    final Map<String, List<QueryDocumentSnapshot>> leadsByUser = {};
    for (final lead in leads) {
      final assignedTo = lead['assigned_to_name'] ?? 'Unknown';
      leadsByUser.putIfAbsent(assignedTo, () => []).add(lead);
    }

    final statusText = _statusFilter == 'All' ? '' : ' [$_statusFilter]';
    final title = 'SME Leads Report — $branch$statusText  (${_formatDate(rangeStart)} → ${_formatDate(rangeEnd)})';

    final workbook = xlsio.Workbook();
    final sheet = workbook.worksheets[0];
    sheet.name = branch;

    if (!_detailedReport) {
      _writeSummarySheetDirect(workbook: workbook, sheet: sheet, title: title, total: leads.length, inProgress: inProgressLeads.length, sale: saleLeads.length, cancelled: cancelledLeads.length, sheetIdx: 1);
    } else {
      _writeDetailSheetDirect(workbook: workbook, sheet: sheet, title: title, leadsByUser: leadsByUser, sheetIdx: 1);
    }

    await _saveAndShare(workbook: workbook, fileName: 'SME_Leads_Report_${branch}_${_statusFilter == 'All' ? 'All' : _statusFilter.replaceAll(' ', '_')}_${DateFormat('yyyyMMdd').format(rangeStart)}_${DateFormat('yyyyMMdd').format(rangeEnd)}', messenger: messenger);
  }

  Future<void> _buildAllBranchesExcel(List<QueryDocumentSnapshot> leads, DateTime rangeStart, DateTime rangeEnd, ScaffoldMessengerState messenger) async {
    final Map<String, List<QueryDocumentSnapshot>> leadsByBranch = {};
    for (final lead in leads) {
      final branch = (lead['branch'] ?? 'Unknown').toString();
      leadsByBranch.putIfAbsent(branch, () => []).add(lead);
    }

    final sortedBranches = leadsByBranch.keys.toList()..sort();
    final workbook = xlsio.Workbook();
    int sheetIdx = 0;

    for (final branch in sortedBranches) {
      final branchLeads = leadsByBranch[branch]!;
      final inProgressLeads = branchLeads.where((l) => (l['status'] ?? '') == 'In Progress').toList();
      final saleLeads = branchLeads.where((l) => (l['status'] ?? '') == 'Sale').toList();
      final cancelledLeads = branchLeads.where((l) => (l['status'] ?? '') == 'Cancelled').toList();

      final Map<String, List<QueryDocumentSnapshot>> leadsByUser = {};
      for (final lead in branchLeads) {
        final assignedTo = lead['assigned_to_name'] ?? 'Unknown';
        leadsByUser.putIfAbsent(assignedTo, () => []).add(lead);
      }

      final sheet = sheetIdx == 0 ? workbook.worksheets[0] : workbook.worksheets.addWithName(branch);
      sheet.name = branch;
      sheetIdx++;

      final statusText = _statusFilter == 'All' ? '' : ' [$_statusFilter]';
      final title = 'SME Leads Report — $branch$statusText  (${_formatDate(rangeStart)} → ${_formatDate(rangeEnd)})';

      if (!_detailedReport) {
        _writeSummarySheetDirect(workbook: workbook, sheet: sheet, title: title, total: branchLeads.length, inProgress: inProgressLeads.length, sale: saleLeads.length, cancelled: cancelledLeads.length, sheetIdx: sheetIdx);
      } else {
        _writeDetailSheetDirect(workbook: workbook, sheet: sheet, title: title, leadsByUser: leadsByUser, sheetIdx: sheetIdx);
      }
    }

    await _saveAndShare(workbook: workbook, fileName: 'SME_Leads_Report_AllBranches_${_statusFilter == 'All' ? 'All' : _statusFilter.replaceAll(' ', '_')}_${DateFormat('yyyyMMdd').format(rangeStart)}_${DateFormat('yyyyMMdd').format(rangeEnd)}', messenger: messenger);
  }

  Future<void> _saveAndShare({required xlsio.Workbook workbook, required String fileName, required ScaffoldMessengerState messenger}) async {
    final bytes = workbook.saveAsStream();
    workbook.dispose();
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/$fileName.xlsx');
    await file.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles([XFile(file.path)], text: 'SME Leads Report');
  }

  InputDecoration _fieldDecoration({required String label, required IconData icon, bool isDark = false}) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: _primaryBlue),
      prefixIcon: Icon(icon, color: _primaryBlue, size: 20),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _primaryBlue.withValues(alpha: 0.4))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _primaryBlue.withValues(alpha: 0.4))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _primaryBlue, width: 1.5)),
      filled: true,
      fillColor: isDark ? const Color(0xFF162236) : const Color(0xFFF0F5FF),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A1628) : const Color(0xFFF5F7FA),
      appBar: AppBar(title: const Text('SME Leads Report'), backgroundColor: _primaryBlue, foregroundColor: Colors.white, elevation: 0),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          InkWell(
            onTap: _pickDateRange,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(border: Border.all(color: _primaryBlue.withValues(alpha: 0.4)), borderRadius: BorderRadius.circular(10), color: isDark ? const Color(0xFF162236) : const Color(0xFFF0F5FF)),
              child: Row(children: [
                const Icon(Icons.date_range_rounded, color: _primaryBlue, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text(_selectedRange == null ? 'Select Date Range' : '${_formatDate(_selectedRange!.start)}  →  ${_formatDate(_selectedRange!.end)}', style: TextStyle(color: isDark ? Colors.white : _primaryBlue, fontWeight: FontWeight.w600, fontSize: 14))),
                Icon(Icons.arrow_drop_down_rounded, color: isDark ? Colors.white54 : _primaryBlue),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          _branchesLoading ? const LinearProgressIndicator() : DropdownButtonFormField<String>(initialValue: _selectedBranch, decoration: _fieldDecoration(label: 'Branch', icon: Icons.location_city_rounded, isDark: isDark), dropdownColor: isDark ? const Color(0xFF162236) : Colors.white, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14), items: _branches.map((b) => DropdownMenuItem(value: b, child: Text(b))).toList(), onChanged: (val) => setState(() => _selectedBranch = val)),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(initialValue: _statusFilter, decoration: _fieldDecoration(label: 'Filter by Status', icon: Icons.filter_list_rounded, isDark: isDark), dropdownColor: isDark ? const Color(0xFF162236) : Colors.white, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14), items: const [DropdownMenuItem(value: 'All', child: Text('All leads')), DropdownMenuItem(value: 'Created in this Interval', child: Text('Created in this Interval'))], onChanged: (val) => setState(() => _statusFilter = val ?? 'All')),
          const SizedBox(height: 12),
          Row(children: [Checkbox(value: _detailedReport, activeColor: _primaryBlue, onChanged: (val) => setState(() => _detailedReport = val ?? false)), const Text('Detailed Report', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)), const SizedBox(width: 6), Tooltip(message: 'Detailed includes: customer name, phone, address,\nplatform, status, priority, comments, assigned to,\ncreated date & reminder for every lead.', child: Icon(Icons.info_outline, size: 18, color: isDark ? Colors.white54 : Colors.black38))]),
          const SizedBox(height: 16),
          ElevatedButton.icon(onPressed: _isGenerating ? null : _generateReport, icon: _isGenerating ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.download_rounded), label: Text(_isGenerating ? 'Generating�' : 'Generate & Share Excel'), style: ElevatedButton.styleFrom(backgroundColor: _primaryGreen, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
          const SizedBox(height: 24),
          Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: isDark ? const Color(0xFF0D2137) : Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: _primaryBlue.withValues(alpha: 0.15))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Report Summary', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isDark ? Colors.white70 : _primaryBlue)), const SizedBox(height: 8), _infoLine(Icons.summarize_rounded, 'Non-detailed: user summary with counts', isDark), _infoLine(Icons.list_alt_rounded, 'Detailed: full lead info per user', isDark), _infoLine(Icons.filter_alt_rounded, 'Source filtered to SME leads only', isDark), _infoLine(Icons.share_rounded, 'Report shared as .xlsx file', isDark)]))
        ]),
      ),
    );
  }

  Widget _infoLine(IconData icon, String text, bool isDark) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(children: [Icon(icon, size: 16, color: isDark ? Colors.white38 : Colors.black38), const SizedBox(width: 8), Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: isDark ? Colors.white60 : Colors.black54)))]));
  }
}
