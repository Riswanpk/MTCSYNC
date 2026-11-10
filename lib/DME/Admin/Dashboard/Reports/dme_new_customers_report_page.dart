import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

import '../../../Misc/dme_constants.dart';
import '../../../Misc/dme_config.dart';

const Color _primaryBlue = Color(0xFF005BAC);
const Color _primaryGreen = Color(0xFF8CC63F);

class DmeNewCustomerReportItem {
  final int customerId;
  final String name;
  final String phone;
  final String address;
  final String categoryName;
  final String customerTypeName;
  final List<DateTime> purchaseDates;
  final String branchName;
  final int branchId;

  DmeNewCustomerReportItem({
    required this.customerId,
    required this.name,
    required this.phone,
    required this.address,
    required this.categoryName,
    required this.customerTypeName,
    required this.purchaseDates,
    required this.branchName,
    required this.branchId,
  });

  String get purchaseDatesFormatted {
    if (purchaseDates.isEmpty) return 'N/A';
    final sorted = List<DateTime>.from(purchaseDates)..sort();
    return sorted.map((d) => DateFormat('dd-MM-yyyy').format(d)).join(', ');
  }
}

class DmeNewCustomersReportPage extends StatefulWidget {
  final List<int>? userAssignedBranches;
  final DateTime? initialStartDate;
  final DateTime? initialEndDate;
  final int? initialBranchId;

  const DmeNewCustomersReportPage({
    super.key,
    this.userAssignedBranches,
    this.initialStartDate,
    this.initialEndDate,
    this.initialBranchId,
  });

  @override
  State<DmeNewCustomersReportPage> createState() => _DmeNewCustomersReportPageState();
}

class _DmeNewCustomersReportPageState extends State<DmeNewCustomersReportPage> {
  DateTime? _startDate;
  DateTime? _endDate;

  int? _selectedBranchId; // null means 'All Allowed Branches'
  List<int> _assignedBranches = [];

  bool _isLoading = false;
  bool _isExporting = false;
  String _searchQuery = '';
  Timer? _searchDebounce;

  // View mode: 'detailed' | 'summary' | 'branchwise'
  String _viewMode = 'detailed';
  // Summary/Branchwise grouping mode: 'category' or 'type'
  String _summaryGroupBy = 'category'; // 'category' | 'type'

  List<DmeNewCustomerReportItem> _reportItems = [];

  @override
  void initState() {
    super.initState();
    _startDate = widget.initialStartDate;
    _endDate = widget.initialEndDate;
    _selectedBranchId = widget.initialBranchId;
    _initBranchAccess();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _initBranchAccess() async {
    if (widget.userAssignedBranches != null) {
      _assignedBranches = widget.userAssignedBranches!;
    } else {
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
          if (!mounted) return;
          final data = doc.data();
          final role = data?['role']?.toString();
          if (role == 'dme_user' && data?['assigned_branches'] is List) {
            _assignedBranches = (data!['assigned_branches'] as List)
                .map((e) => int.tryParse(e.toString()) ?? 0)
                .where((e) => e > 0)
                .toList();
          }
        }
      } catch (e) {
        debugPrint('Error loading user assigned branches: $e');
      }
    }
    if (!mounted) return;
    // Only load automatically if date range was explicitly provided
    if (_startDate != null && _endDate != null) {
      _fetchReportData();
    }
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final initialRange = (_startDate != null && _endDate != null)
        ? DateTimeRange(start: _startDate!, end: _endDate!)
        : DateTimeRange(
            start: DateTime(now.year, now.month, 1),
            end: now,
          );

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: initialRange,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: _primaryBlue,
              onPrimary: Colors.white,
              onSurface: Colors.black87,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      if (mounted) { setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      }); }
      _fetchReportData();
    }
  }

  Future<void> _fetchReportData() async {
    if (_startDate == null || _endDate == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Please select a date range first.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final client = await DmeConfig.getClient();
    if (client == null) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('Supabase is not configured.')),
        );
      }
      return;
    }

    setState(() => _isLoading = true);

    try {
      final startStr = DateFormat('yyyy-MM-dd').format(_startDate!);
      final endStr = DateFormat('yyyy-MM-dd').format(_endDate!);

      final startIso =
          DateTime(_startDate!.year, _startDate!.month, _startDate!.day, 0, 0, 0)
              .toIso8601String();
      final endIso =
          DateTime(_endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59, 999)
              .toIso8601String();

      // 1. Fetch Customers created in the date interval (checking creation_date with fallback to created_at)
      final List<dynamic> custList = [];
      int custOffset = 0;
      const int pageSize = 1000;
      bool hasMoreCusts = true;

      while (hasMoreCusts) {
        final custQuery = client
            .from('dme_customers')
            .select('id, name, phone, address, salesman, created_at, creation_date, primary_branch')
            .or('and(creation_date.gte.$startStr,creation_date.lte.$endStr),and(creation_date.is.null,created_at.gte.$startIso,created_at.lte.$endIso)')
            .range(custOffset, custOffset + pageSize - 1);

        final custBatch = await custQuery;
        final list = custBatch as List<dynamic>;
        custList.addAll(list);

        if (list.length < pageSize) {
          hasMoreCusts = false;
        } else {
          custOffset += pageSize;
        }
      }

      if (custList.isEmpty) {
        if (mounted) {
          setState(() {
            _reportItems = [];
            _isLoading = false;
          });
        }
        return;
      }

      final List<int> customerIds = custList
          .map((c) => int.tryParse(c['id']?.toString() ?? ''))
          .whereType<int>()
          .toList();

      // 2. Fetch Customer Branches for these new customers
      final Map<int, List<Map<String, dynamic>>> customerBranchesMap = {};
      const int batchSize = 100;
      for (var i = 0; i < customerIds.length; i += batchSize) {
        final chunk = customerIds.sublist(
          i,
          i + batchSize > customerIds.length ? customerIds.length : i + batchSize,
        );
        final branchRes = await client
            .from('dme_customer_branches')
            .select('customer_id, branch_id, category_id, customer_type_id')
            .inFilter('customer_id', chunk);

        for (var b in (branchRes as List<dynamic>)) {
          final cId = b['customer_id'] as int?;
          if (cId != null) {
            customerBranchesMap.putIfAbsent(cId, () => []).add(b);
          }
        }
      }

      // 3. Fetch Sales made by these customers in the date interval
      final Map<int, List<DateTime>> customerPurchaseDatesMap = {};
      for (var i = 0; i < customerIds.length; i += batchSize) {
        final chunk = customerIds.sublist(
          i,
          i + batchSize > customerIds.length ? customerIds.length : i + batchSize,
        );
        var salesQuery = client
            .from('dme_sales')
            .select('customer_id, date, purchased_branch')
            .inFilter('customer_id', chunk)
            .gte('date', startStr)
            .lte('date', endStr);

        if (_selectedBranchId != null) {
          salesQuery = salesQuery.eq('purchased_branch', _selectedBranchId!);
        } else if (_assignedBranches.isNotEmpty) {
          salesQuery = salesQuery.inFilter('purchased_branch', _assignedBranches);
        }

        final salesRes = await salesQuery;
        for (var s in (salesRes as List<dynamic>)) {
          final cId = s['customer_id'] as int?;
          final dStr = s['date']?.toString();
          if (cId != null && dStr != null) {
            final dt = DateTime.tryParse(dStr);
            if (dt != null) {
              customerPurchaseDatesMap.putIfAbsent(cId, () => []).add(dt);
            }
          }
        }
      }

      // 4. Build Report Items
      final List<DmeNewCustomerReportItem> items = [];

      for (var c in custList) {
        final cId = c['id'] as int;
        final name = (c['name'] ?? '').toString().trim();
        final phone = (c['phone'] ?? '').toString().trim();
        final address = (c['address'] ?? '').toString().trim();

        final branches = customerBranchesMap[cId] ?? [];

        // Primary branch (first purchased branch)
        int? primaryBranchId = c['primary_branch'] as int?;
        if (primaryBranchId == null && branches.isNotEmpty) {
          primaryBranchId = branches.first['branch_id'] as int?;
        }

        // Branchwise filter:
        // - If a specific branch is selected, include customer ONLY for their primary/first purchased branch
        // - If All Branches is selected, customer is listed once under their primary branch
        if (_selectedBranchId != null) {
          if (primaryBranchId != _selectedBranchId) continue;
        } else if (_assignedBranches.isNotEmpty) {
          if (primaryBranchId == null || !_assignedBranches.contains(primaryBranchId)) {
            continue;
          }
        }

        // Branch-specific category and type from primary branch
        Map<String, dynamic>? branchData;
        if (primaryBranchId != null) {
          branchData = branches.firstWhere(
            (b) => b['branch_id'] == primaryBranchId,
            orElse: () => branches.isNotEmpty ? branches.first : <String, dynamic>{},
          );
        } else if (branches.isNotEmpty) {
          branchData = branches.first;
        }

        final categoryId = branchData?['category_id'] as int?;
        final typeId = branchData?['customer_type_id'] as int?;

        final branchName = primaryBranchId != null
            ? DmeConstants.getBranchName(primaryBranchId)
            : 'Unknown';
        final categoryName = categoryId != null
            ? DmeConstants.getCategoryName(categoryId)
            : 'N/A';
        final typeName = typeId != null
            ? DmeConstants.getCustomerTypeName(typeId)
            : 'Regular';

        final pDates = customerPurchaseDatesMap[cId] ?? [];
        if (pDates.isEmpty) {
          final cDateStr = c['creation_date']?.toString() ?? c['created_at']?.toString();
          if (cDateStr != null) {
            final cd = DateTime.tryParse(cDateStr);
            if (cd != null) {
              pDates.add(cd);
            }
          }
        }

        items.add(DmeNewCustomerReportItem(
          customerId: cId,
          name: name.isNotEmpty ? name : 'Unknown Customer',
          phone: phone,
          address: address,
          categoryName: categoryName,
          customerTypeName: typeName,
          purchaseDates: pDates,
          branchName: branchName,
          branchId: primaryBranchId ?? 0,
        ));
      }

      if (mounted) {
        setState(() {
          _reportItems = items;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching new customer report: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text('Error loading report: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _generateAndShareExcel() async {
    if (_reportItems.isEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('No report data available to export.')),
      );
      return;
    }

    setState(() => _isExporting = true);

    try {
      final filteredList = _getFilteredItems();
      final xlsio.Workbook workbook = xlsio.Workbook();
      final xlsio.Worksheet sheet = workbook.worksheets[0];
      sheet.name = 'New Customers';

      // 1. Title Banner
      final String branchTitle = _selectedBranchId != null
          ? DmeConstants.getBranchName(_selectedBranchId!)
          : 'All Branches';
      final String dateIntervalTitle = (_startDate != null && _endDate != null)
          ? '${DateFormat('dd MMM yyyy').format(_startDate!)} to ${DateFormat('dd MMM yyyy').format(_endDate!)}'
          : 'All Time';

      final String groupLabel = _summaryGroupBy == 'category' ? 'Category' : 'Customer Type';
      final String sheetSubtitle = _viewMode == 'detailed'
          ? 'Date Interval: $dateIntervalTitle  |  Total New Customers: ${_reportItems.length}'
          : _viewMode == 'summary'
              ? 'Date Interval: $dateIntervalTitle  |  Summary by $groupLabel  |  Total New Customers: ${_reportItems.length}'
              : 'Date Interval: $dateIntervalTitle  |  Branchwise Distribution by $groupLabel  |  Total New Customers: ${_reportItems.length}';

      final String sheetTitle = _viewMode == 'detailed'
          ? 'NEW CUSTOMERS REPORT - $branchTitle'
          : _viewMode == 'summary'
              ? 'NEW CUSTOMERS SUMMARY REPORT - $branchTitle'
              : 'NEW CUSTOMERS BRANCHWISE REPORT - $branchTitle';

      sheet.getRangeByName('A1:H1').merge();
      final xlsio.Range titleRange = sheet.getRangeByName('A1');
      titleRange.setText(sheetTitle);
      titleRange.cellStyle.fontSize = 14;
      titleRange.cellStyle.bold = true;
      titleRange.cellStyle.fontColor = '#FFFFFF';
      titleRange.cellStyle.backColor = '#005BAC';
      titleRange.cellStyle.hAlign = xlsio.HAlignType.center;
      titleRange.cellStyle.vAlign = xlsio.VAlignType.center;
      sheet.setRowHeightInPixels(1, 32);

      sheet.getRangeByName('A2:H2').merge();
      final xlsio.Range subTitleRange = sheet.getRangeByName('A2');
      subTitleRange.setText(sheetSubtitle);
      subTitleRange.cellStyle.fontSize = 11;
      subTitleRange.cellStyle.bold = true;
      subTitleRange.cellStyle.fontColor = '#333333';
      subTitleRange.cellStyle.backColor = '#EAEAEA';
      subTitleRange.cellStyle.hAlign = xlsio.HAlignType.center;
      subTitleRange.cellStyle.vAlign = xlsio.VAlignType.center;
      sheet.setRowHeightInPixels(2, 24);

      if (_viewMode == 'branchwise') {
        // BRANCHWISE EXPORT
        final branchwiseData = _calculateBranchwiseDistribution();
        final totalCount = _getFilteredItems().length;
        int currentRow = 4;

        for (final entry in branchwiseData.entries) {
          final groupName = entry.key;
          final branches = entry.value;
          final groupTotal = branches.fold<int>(0, (acc, b) => acc + b.value);
          final groupPct = totalCount > 0 ? (groupTotal / totalCount) * 100 : 0.0;

          // Category/Type Section Header
          sheet.getRangeByIndex(currentRow, 1, currentRow, 4).merge();
          final groupHeaderCell = sheet.getRangeByIndex(currentRow, 1);
          groupHeaderCell.setText('$groupLabel: $groupName  (Total: $groupTotal | ${groupPct.toStringAsFixed(1)}%)');
          groupHeaderCell.cellStyle.bold = true;
          groupHeaderCell.cellStyle.fontSize = 11;
          groupHeaderCell.cellStyle.fontColor = '#FFFFFF';
          groupHeaderCell.cellStyle.backColor = '#005BAC';
          groupHeaderCell.cellStyle.vAlign = xlsio.VAlignType.center;
          sheet.setRowHeightInPixels(currentRow, 26);
          currentRow++;

          // Table Columns Header
          final List<String> bHeaders = ['SL NO', 'BRANCH NAME', 'CUSTOMER COUNT', '% OF GROUP'];
          for (int c = 0; c < bHeaders.length; c++) {
            final cell = sheet.getRangeByIndex(currentRow, c + 1);
            cell.setText(bHeaders[c]);
            cell.cellStyle.bold = true;
            cell.cellStyle.fontSize = 10;
            cell.cellStyle.fontColor = '#005BAC';
            cell.cellStyle.backColor = '#E6F0FA';
            cell.cellStyle.hAlign = xlsio.HAlignType.center;
            cell.cellStyle.vAlign = xlsio.VAlignType.center;
            cell.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
            cell.cellStyle.borders.all.color = '#B9D5F2';
          }
          sheet.setRowHeightInPixels(currentRow, 22);
          currentRow++;

          // Branch rows
          for (int bIdx = 0; bIdx < branches.length; bIdx++) {
            final bEntry = branches[bIdx];
            final bCount = bEntry.value;
            final bPct = groupTotal > 0 ? (bCount / groupTotal) * 100 : 0.0;
            final isEven = bIdx % 2 == 0;
            final String rowBg = isEven ? '#FFFFFF' : '#F9FBFD';

            // SL NO
            final slCell = sheet.getRangeByIndex(currentRow, 1);
            slCell.setNumber((bIdx + 1).toDouble());
            slCell.cellStyle.hAlign = xlsio.HAlignType.center;

            // Branch Name
            final branchNameCell = sheet.getRangeByIndex(currentRow, 2);
            branchNameCell.setText(bEntry.key);

            // Count
            final countCell = sheet.getRangeByIndex(currentRow, 3);
            countCell.setNumber(bCount.toDouble());
            countCell.cellStyle.hAlign = xlsio.HAlignType.center;

            // % of group
            final pctCell = sheet.getRangeByIndex(currentRow, 4);
            pctCell.setText('${bPct.toStringAsFixed(1)}%');
            pctCell.cellStyle.hAlign = xlsio.HAlignType.center;

            for (int col = 1; col <= 4; col++) {
              final cell = sheet.getRangeByIndex(currentRow, col);
              cell.cellStyle.backColor = rowBg;
              cell.cellStyle.vAlign = xlsio.VAlignType.center;
              cell.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
              cell.cellStyle.borders.all.color = '#DDDDDD';
            }
            sheet.setRowHeightInPixels(currentRow, 20);
            currentRow++;
          }

          // Group Subtotal Row
          sheet.getRangeByIndex(currentRow, 1).setText('');
          final subtotalLabel = sheet.getRangeByIndex(currentRow, 2);
          subtotalLabel.setText('Subtotal - $groupName');
          subtotalLabel.cellStyle.bold = true;

          final subtotalCount = sheet.getRangeByIndex(currentRow, 3);
          subtotalCount.setNumber(groupTotal.toDouble());
          subtotalCount.cellStyle.bold = true;
          subtotalCount.cellStyle.hAlign = xlsio.HAlignType.center;

          final subtotalPct = sheet.getRangeByIndex(currentRow, 4);
          subtotalPct.setText('100.0%');
          subtotalPct.cellStyle.bold = true;
          subtotalPct.cellStyle.hAlign = xlsio.HAlignType.center;

          for (int col = 1; col <= 4; col++) {
            final cell = sheet.getRangeByIndex(currentRow, col);
            cell.cellStyle.backColor = '#F2F2F2';
            cell.cellStyle.vAlign = xlsio.VAlignType.center;
            cell.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
            cell.cellStyle.borders.all.color = '#CCCCCC';
          }
          sheet.setRowHeightInPixels(currentRow, 22);
          currentRow += 2; // Blank row between tables
        }

        sheet.setColumnWidthInPixels(1, 60);
        sheet.setColumnWidthInPixels(2, 220);
        sheet.setColumnWidthInPixels(3, 140);
        sheet.setColumnWidthInPixels(4, 120);
      } else if (_viewMode == 'summary') {
        // SUMMARY EXPORT
        final groupTitle = _summaryGroupBy == 'category' ? 'CATEGORY' : 'CUSTOMER TYPE';
        final List<String> summaryHeaders = ['SL NO', groupTitle, 'CUSTOMER COUNT', 'PERCENTAGE'];

        for (int i = 0; i < summaryHeaders.length; i++) {
          final cell = sheet.getRangeByIndex(4, i + 1);
          cell.setText(summaryHeaders[i]);
          cell.cellStyle.bold = true;
          cell.cellStyle.fontSize = 11;
          cell.cellStyle.fontColor = '#FFFFFF';
          cell.cellStyle.backColor = '#005BAC';
          cell.cellStyle.hAlign = xlsio.HAlignType.center;
          cell.cellStyle.vAlign = xlsio.VAlignType.center;
        }
        sheet.setRowHeightInPixels(4, 26);

        final summaryData = _calculateSummaryDistribution();
        final totalCount = _getFilteredItems().length;

        for (int r = 0; r < summaryData.length; r++) {
          final entry = summaryData[r];
          final int rowIndex = 5 + r;
          final pct = totalCount > 0 ? (entry.value / totalCount) * 100 : 0.0;
          final isEven = r % 2 == 0;
          final String rowBgColor = isEven ? '#FFFFFF' : '#F9FBFD';

          final slCell = sheet.getRangeByIndex(rowIndex, 1);
          slCell.setNumber((r + 1).toDouble());
          slCell.cellStyle.hAlign = xlsio.HAlignType.center;

          final nameCell = sheet.getRangeByIndex(rowIndex, 2);
          nameCell.setText(entry.key);
          nameCell.cellStyle.bold = true;

          final countCell = sheet.getRangeByIndex(rowIndex, 3);
          countCell.setNumber(entry.value.toDouble());
          countCell.cellStyle.hAlign = xlsio.HAlignType.center;

          final pctCell = sheet.getRangeByIndex(rowIndex, 4);
          pctCell.setText('${pct.toStringAsFixed(1)}%');
          pctCell.cellStyle.hAlign = xlsio.HAlignType.center;

          for (int c = 1; c <= 4; c++) {
            final cell = sheet.getRangeByIndex(rowIndex, c);
            cell.cellStyle.backColor = rowBgColor;
            cell.cellStyle.vAlign = xlsio.VAlignType.center;
            cell.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
            cell.cellStyle.borders.all.color = '#DDDDDD';
          }
          sheet.setRowHeightInPixels(rowIndex, 22);
        }

        // Total Row
        final int totalRowIndex = 5 + summaryData.length;
        sheet.getRangeByIndex(totalRowIndex, 1).setText('');
        final totalLabel = sheet.getRangeByIndex(totalRowIndex, 2);
        totalLabel.setText('TOTAL');
        totalLabel.cellStyle.bold = true;
        totalLabel.cellStyle.hAlign = xlsio.HAlignType.center;

        final totalCountCell = sheet.getRangeByIndex(totalRowIndex, 3);
        totalCountCell.setNumber(totalCount.toDouble());
        totalCountCell.cellStyle.bold = true;
        totalCountCell.cellStyle.hAlign = xlsio.HAlignType.center;

        final totalPctCell = sheet.getRangeByIndex(totalRowIndex, 4);
        totalPctCell.setText('100.0%');
        totalPctCell.cellStyle.bold = true;
        totalPctCell.cellStyle.hAlign = xlsio.HAlignType.center;

        for (int c = 1; c <= 4; c++) {
          final cell = sheet.getRangeByIndex(totalRowIndex, c);
          cell.cellStyle.backColor = '#EAEAEA';
          cell.cellStyle.vAlign = xlsio.VAlignType.center;
          cell.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
          cell.cellStyle.borders.all.color = '#CCCCCC';
        }
        sheet.setRowHeightInPixels(totalRowIndex, 24);

        sheet.setColumnWidthInPixels(1, 60);
        sheet.setColumnWidthInPixels(2, 220);
        sheet.setColumnWidthInPixels(3, 140);
        sheet.setColumnWidthInPixels(4, 120);
      } else {
        // DETAILED EXPORT
        // 2. Table Column Headers
        final List<String> headers = [
          'SL NO',
          'CUSTOMER NAME',
          'PHONE NUMBER',
          'PRIMARY BRANCH',
          'ADDRESS',
          'CATEGORY',
          'CUSTOMER TYPE',
          'PURCHASE DATE(S)',
        ];

        for (int i = 0; i < headers.length; i++) {
          final cell = sheet.getRangeByIndex(4, i + 1);
          cell.setText(headers[i]);
          cell.cellStyle.bold = true;
          cell.cellStyle.fontSize = 11;
          cell.cellStyle.fontColor = '#FFFFFF';
          cell.cellStyle.backColor = '#005BAC';
          cell.cellStyle.hAlign = xlsio.HAlignType.center;
          cell.cellStyle.vAlign = xlsio.VAlignType.center;
        }
        sheet.setRowHeightInPixels(4, 26);

        // 3. Populate Rows
        final filteredList = _getFilteredItems();
        for (int r = 0; r < filteredList.length; r++) {
          final item = filteredList[r];
          final int rowIndex = 5 + r;

          final isEven = r % 2 == 0;
          final String rowBgColor = isEven ? '#FFFFFF' : '#F9FBFD';

          // SL NO
          final slCell = sheet.getRangeByIndex(rowIndex, 1);
          slCell.setNumber((r + 1).toDouble());
          slCell.cellStyle.hAlign = xlsio.HAlignType.center;

          // Name
          final nameCell = sheet.getRangeByIndex(rowIndex, 2);
          nameCell.setText(item.name);
          nameCell.cellStyle.bold = true;

          // Phone
          final phoneCell = sheet.getRangeByIndex(rowIndex, 3);
          phoneCell.setText(item.phone);
          phoneCell.cellStyle.hAlign = xlsio.HAlignType.center;

          // Primary Branch
          final branchCell = sheet.getRangeByIndex(rowIndex, 4);
          branchCell.setText(item.branchName);
          branchCell.cellStyle.hAlign = xlsio.HAlignType.center;

          // Address
          final addrCell = sheet.getRangeByIndex(rowIndex, 5);
          addrCell.setText(item.address.isNotEmpty ? item.address : '-');

          // Category
          final catCell = sheet.getRangeByIndex(rowIndex, 6);
          catCell.setText(item.categoryName);
          catCell.cellStyle.hAlign = xlsio.HAlignType.center;

          // Customer Type
          final typeCell = sheet.getRangeByIndex(rowIndex, 7);
          typeCell.setText(item.customerTypeName);
          typeCell.cellStyle.hAlign = xlsio.HAlignType.center;

          // Purchase Date(s)
          final dateCell = sheet.getRangeByIndex(rowIndex, 8);
          dateCell.setText(item.purchaseDatesFormatted);
          dateCell.cellStyle.hAlign = xlsio.HAlignType.center;

          for (int c = 1; c <= 8; c++) {
            final cell = sheet.getRangeByIndex(rowIndex, c);
            cell.cellStyle.backColor = rowBgColor;
            cell.cellStyle.vAlign = xlsio.VAlignType.center;
            cell.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
            cell.cellStyle.borders.all.color = '#DDDDDD';
          }
          sheet.setRowHeightInPixels(rowIndex, 22);
        }

        // Column Widths
        sheet.setColumnWidthInPixels(1, 60);
        sheet.setColumnWidthInPixels(2, 200);
        sheet.setColumnWidthInPixels(3, 130);
        sheet.setColumnWidthInPixels(4, 150);
        sheet.setColumnWidthInPixels(5, 200);
        sheet.setColumnWidthInPixels(6, 140);
        sheet.setColumnWidthInPixels(7, 140);
        sheet.setColumnWidthInPixels(8, 220);
      }

      // 4. Save and Directly Share Excel File
      final List<int> bytes = workbook.saveAsStream();
      workbook.dispose();

      final tempDir = await getTemporaryDirectory();
      final String fileName =
          'New_Customers_Report_${DateFormat('ddMMyyyy_HHmm').format(DateTime.now())}.xlsx';
      final String filePath = '${tempDir.path}/$fileName';
      final File file = File(filePath);
      await file.writeAsBytes(bytes, flush: true);

      if (mounted) {
        setState(() => _isExporting = false);
        final xFile = XFile(filePath);
        await Share.shareXFiles(
          [xFile],
          subject: 'New Customers Report ($dateIntervalTitle)',
          text: 'DME New Customers Report for $branchTitle ($dateIntervalTitle). Total records: ${filteredList.length}',
        );
      }
    } catch (e) {
      debugPrint('Error generating Excel: $e');
      if (mounted) {
        setState(() => _isExporting = false);
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text('Failed to generate Excel: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  List<MapEntry<String, int>> _calculateSummaryDistribution() {
    final filtered = _getFilteredItems();
    final Map<String, int> counts = {};

    for (final item in filtered) {
      final key = _summaryGroupBy == 'category'
          ? (item.categoryName.isNotEmpty ? item.categoryName : 'N/A')
          : (item.customerTypeName.isNotEmpty ? item.customerTypeName : 'Regular');
      counts[key] = (counts[key] ?? 0) + 1;
    }

    final sortedEntries = counts.entries.toList()
      ..sort((a, b) {
        final cmp = b.value.compareTo(a.value);
        if (cmp != 0) return cmp;
        return a.key.compareTo(b.key);
      });

    return sortedEntries;
  }

  /// Groups items by primary grouping (_summaryGroupBy: category or customer type),
  /// and within each group provides the branchwise breakdown sorted by customer count descending.
  Map<String, List<MapEntry<String, int>>> _calculateBranchwiseDistribution() {
    final filtered = _getFilteredItems();
    final Map<String, Map<String, int>> groupToBranchCounts = {};

    for (final item in filtered) {
      final groupKey = _summaryGroupBy == 'category'
          ? (item.categoryName.isNotEmpty ? item.categoryName : 'N/A')
          : (item.customerTypeName.isNotEmpty ? item.customerTypeName : 'Regular');
      final branchKey = item.branchName.isNotEmpty ? item.branchName : 'Unknown';

      groupToBranchCounts.putIfAbsent(groupKey, () => {});
      groupToBranchCounts[groupKey]![branchKey] =
          (groupToBranchCounts[groupKey]![branchKey] ?? 0) + 1;
    }

    final Map<String, List<MapEntry<String, int>>> result = {};

    // Sort group keys by total customer count in that group descending
    final sortedGroupKeys = groupToBranchCounts.keys.toList()
      ..sort((a, b) {
        final totalA = groupToBranchCounts[a]!.values.fold<int>(0, (acc, c) => acc + c);
        final totalB = groupToBranchCounts[b]!.values.fold<int>(0, (acc, c) => acc + c);
        final cmp = totalB.compareTo(totalA);
        if (cmp != 0) return cmp;
        return a.compareTo(b);
      });

    for (final gk in sortedGroupKeys) {
      final branchCounts = groupToBranchCounts[gk]!;
      final sortedBranches = branchCounts.entries.toList()
        ..sort((a, b) {
          final cmp = b.value.compareTo(a.value);
          if (cmp != 0) return cmp;
          return a.key.compareTo(b.key);
        });
      result[gk] = sortedBranches;
    }

    return result;
  }

  List<DmeNewCustomerReportItem> _getFilteredItems() {
    if (_searchQuery.trim().isEmpty) return _reportItems;
    final q = _searchQuery.trim().toLowerCase();
    return _reportItems.where((item) {
      return item.name.toLowerCase().contains(q) ||
          item.phone.toLowerCase().contains(q) ||
          item.branchName.toLowerCase().contains(q) ||
          item.categoryName.toLowerCase().contains(q) ||
          item.customerTypeName.toLowerCase().contains(q) ||
          item.address.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filteredItems = _getFilteredItems();

    return Scaffold(
      appBar: AppBar(
        title: const Text('New Customers Report'),
        backgroundColor: _primaryBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Data',
            onPressed: _isLoading ? null : _fetchReportData,
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Header Card
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[900] : Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    // Date Interval Selector
                    Expanded(
                      flex: 3,
                      child: InkWell(
                        onTap: _pickDateRange,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: (_startDate != null && _endDate != null)
                                  ? _primaryBlue
                                  : Colors.grey.shade400,
                            ),
                            borderRadius: BorderRadius.circular(8),
                            color: (_startDate != null && _endDate != null)
                                ? _primaryBlue.withValues(alpha: 0.05)
                                : null,
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.date_range, size: 18, color: _primaryBlue),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  (_startDate != null && _endDate != null)
                                      ? '${DateFormat('dd-MM-yy').format(_startDate!)} to ${DateFormat('dd-MM-yy').format(_endDate!)}'
                                      : 'Select Date Range',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: (_startDate != null && _endDate != null)
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: (_startDate != null && _endDate != null)
                                        ? null
                                        : Colors.grey[600],
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Branch Selector Dropdown
                    Expanded(
                      flex: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade400),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<int?>(
                            isExpanded: true,
                            value: _selectedBranchId,
                            hint: const Text('All Branches', style: TextStyle(fontSize: 12)),
                            items: [
                              const DropdownMenuItem<int?>(
                                value: null,
                                child: Text('All Branches', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              ),
                              ...DmeConstants.branches
                                  .where((b) => _assignedBranches.isEmpty || _assignedBranches.contains(b.id))
                                  .map(
                                    (b) => DropdownMenuItem<int?>(
                                      value: b.id,
                                      child: Text(b.name, style: const TextStyle(fontSize: 12)),
                                    ),
                                  ),
                            ],
                            onChanged: (val) {
                              setState(() => _selectedBranchId = val);
                              if (_startDate != null && _endDate != null) {
                                _fetchReportData();
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Search Bar and Direct Share Button
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Search by customer, phone, category...',
                          prefixIcon: const Icon(Icons.search, size: 18),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          filled: true,
                          fillColor: isDark ? Colors.grey[850] : Colors.grey[100],
                        ),
                        onChanged: (val) {
                          _searchDebounce?.cancel();
                          _searchDebounce = Timer(const Duration(milliseconds: 250), () {
                            if (mounted) setState(() => _searchQuery = val);
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: (_isLoading || _isExporting || _reportItems.isEmpty)
                          ? null
                          : _generateAndShareExcel,
                      icon: _isExporting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.share, size: 18),
                      label: const Text('Share Excel', style: TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // View Mode (Detailed vs Summary vs Branchwise) & Grouping Toggle
                Row(
                  children: [
                    // Segmented Mode Selector
                    Container(
                      decoration: BoxDecoration(
                        color: isDark ? Colors.grey[850] : Colors.grey[200],
                        borderRadius: BorderRadius.circular(6),
                      ),
                      padding: const EdgeInsets.all(2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildModeTab(
                            title: 'Detailed',
                            icon: Icons.list_alt_rounded,
                            isSelected: _viewMode == 'detailed',
                            isDark: isDark,
                            onTap: () => setState(() => _viewMode = 'detailed'),
                          ),
                          _buildModeTab(
                            title: 'Summary',
                            icon: Icons.pie_chart_outline_rounded,
                            isSelected: _viewMode == 'summary',
                            isDark: isDark,
                            onTap: () => setState(() => _viewMode = 'summary'),
                          ),
                          _buildModeTab(
                            title: 'Branchwise',
                            icon: Icons.store_mall_directory_rounded,
                            isSelected: _viewMode == 'branchwise',
                            isDark: isDark,
                            onTap: () => setState(() => _viewMode = 'branchwise'),
                          ),
                        ],
                      ),
                    ),

                    const Spacer(),

                    // Category vs Type selector (Visible in summary or branchwise mode)
                    if (_viewMode != 'detailed')
                      Container(
                        decoration: BoxDecoration(
                          color: isDark ? Colors.grey[850] : Colors.grey[200],
                          borderRadius: BorderRadius.circular(6),
                        ),
                        padding: const EdgeInsets.all(2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildGroupTab(
                              title: 'Cat',
                              isSelected: _summaryGroupBy == 'category',
                              isDark: isDark,
                              onTap: () => setState(() => _summaryGroupBy = 'category'),
                            ),
                            _buildGroupTab(
                              title: 'Type',
                              isSelected: _summaryGroupBy == 'type',
                              isDark: isDark,
                              onTap: () => setState(() => _summaryGroupBy = 'type'),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // Total Count Banner (only shown when date range is selected)
          if (_startDate != null && _endDate != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: _primaryBlue.withValues(alpha: 0.08),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'New Customers Found: ${filteredItems.length}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _primaryBlue),
                  ),
                  if (_selectedBranchId != null)
                    Text(
                      'Branch: ${DmeConstants.getBranchName(_selectedBranchId!)}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                    ),
                ],
              ),
            ),

          // Customer Table / List View
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : (_startDate == null || _endDate == null)
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: _primaryBlue.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.date_range_rounded, size: 48, color: _primaryBlue),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Select Date Range',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Select a date interval above to fetch and view new customers.',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: _pickDateRange,
                                icon: const Icon(Icons.calendar_month_rounded, size: 18),
                                label: const Text('Choose Dates'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _primaryBlue,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : filteredItems.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.person_off_rounded, size: 48, color: Colors.grey[400]),
                                const SizedBox(height: 8),
                                Text(
                                  'No new customers found for this period.',
                                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                                ),
                              ],
                            ),
                          )
                    : _viewMode == 'branchwise'
                        ? _buildBranchwiseView(filteredItems, isDark)
                        : _viewMode == 'summary'
                            ? _buildSummaryView(filteredItems, isDark)
                            : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: filteredItems.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, idx) {
                          final item = filteredItems[idx];
                          return Card(
                            elevation: 1.5,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      CircleAvatar(
                                        radius: 16,
                                        backgroundColor: _primaryBlue.withValues(alpha: 0.15),
                                        foregroundColor: _primaryBlue,
                                        child: Text(
                                          '${idx + 1}',
                                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              item.name,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Row(
                                              children: [
                                                const Icon(Icons.phone, size: 12, color: Colors.grey),
                                                const SizedBox(width: 4),
                                                Text(
                                                  item.phone,
                                                  style: TextStyle(fontSize: 12, color: Colors.grey[800]),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: _primaryGreen.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: _primaryGreen.withValues(alpha: 0.5)),
                                        ),
                                        child: Text(
                                          item.branchName,
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.green[900],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Divider(height: 16),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Row(
                                          children: [
                                            const Icon(Icons.category_rounded, size: 13, color: Colors.grey),
                                            const SizedBox(width: 4),
                                            Flexible(
                                              child: Text(
                                                'Category: ${item.categoryName}',
                                                style: const TextStyle(fontSize: 11),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Expanded(
                                        child: Row(
                                          children: [
                                            const Icon(Icons.badge_rounded, size: 13, color: Colors.grey),
                                            const SizedBox(width: 4),
                                            Flexible(
                                              child: Text(
                                                'Type: ${item.customerTypeName}',
                                                style: const TextStyle(fontSize: 11),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Icon(Icons.calendar_month, size: 13, color: Colors.grey),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          'Purchase Dates: ${item.purchaseDatesFormatted}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.blue[900],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (item.address.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Icon(Icons.location_on, size: 13, color: Colors.grey),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            item.address,
                                            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryView(List<DmeNewCustomerReportItem> filteredItems, bool isDark) {
    final summaryData = _calculateSummaryDistribution();
    final totalCount = filteredItems.length;
    final isCategory = _summaryGroupBy == 'category';
    final groupLabel = isCategory ? 'Category' : 'Customer Type';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Summary Card
          Card(
            elevation: 1.5,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Distribution by $groupLabel',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Total Distinct Groups: ${summaryData.length}',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.grey[400] : Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: _primaryBlue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          children: [
                            const Text(
                              'TOTAL',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _primaryBlue),
                            ),
                            Text(
                              '$totalCount',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: _primaryBlue,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Distribution breakdown list
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: summaryData.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, idx) {
              final entry = summaryData[idx];
              final count = entry.value;
              final pct = totalCount > 0 ? (count / totalCount) : 0.0;
              final pctFormatted = (pct * 100).toStringAsFixed(1);

              return Card(
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 12,
                            backgroundColor: _primaryBlue.withValues(alpha: 0.12),
                            foregroundColor: _primaryBlue,
                            child: Text(
                              '${idx + 1}',
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              entry.key,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: _primaryBlue.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '$count ($pctFormatted%)',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: _primaryBlue,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Progress Bar
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: pct,
                          minHeight: 6,
                          backgroundColor: isDark ? Colors.grey[800] : Colors.grey[200],
                          valueColor: const AlwaysStoppedAnimation<Color>(_primaryGreen),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildModeTab({
    required String title,
    required IconData icon,
    required bool isSelected,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? _primaryBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 12,
              color: isSelected ? Colors.white : (isDark ? Colors.grey[400] : Colors.grey[700]),
            ),
            const SizedBox(width: 3),
            Text(
              title,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.white : (isDark ? Colors.grey[300] : Colors.grey[800]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupTab({
    required String title,
    required bool isSelected,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? _primaryBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Colors.white : (isDark ? Colors.grey[300] : Colors.grey[800]),
          ),
        ),
      ),
    );
  }

  Widget _buildBranchwiseView(List<DmeNewCustomerReportItem> filteredItems, bool isDark) {
    final branchwiseData = _calculateBranchwiseDistribution();
    final totalCount = filteredItems.length;
    final isCategory = _summaryGroupBy == 'category';
    final groupLabel = isCategory ? 'Category' : 'Customer Type';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Summary Card
          Card(
            elevation: 1.5,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Branchwise by $groupLabel',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Total Distinct ${groupLabel}s: ${branchwiseData.length}',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _primaryBlue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'TOTAL',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _primaryBlue),
                        ),
                        Text(
                          '$totalCount',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: _primaryBlue,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // For each category/type: render a separate table/card with branch distribution
          ...branchwiseData.entries.map((entry) {
            final groupName = entry.key;
            final branches = entry.value;
            final groupTotal = branches.fold<int>(0, (acc, b) => acc + b.value);
            final groupPct = totalCount > 0 ? (groupTotal / totalCount) * 100 : 0.0;

            return Card(
              elevation: 1.5,
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Category Header bar
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: _primaryBlue.withValues(alpha: 0.08),
                      border: Border(
                        bottom: BorderSide(color: _primaryBlue.withValues(alpha: 0.2)),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Icon(
                                isCategory ? Icons.category_rounded : Icons.badge_rounded,
                                size: 16,
                                color: _primaryBlue,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  groupName,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: _primaryBlue,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _primaryBlue,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '$groupTotal (${groupPct.toStringAsFixed(1)}%)',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Table of Branches for this category/type
                  Table(
                    border: TableBorder(
                      horizontalInside: BorderSide(
                        color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
                        width: 1,
                      ),
                    ),
                    columnWidths: const {
                      0: FlexColumnWidth(1),
                      1: FlexColumnWidth(4),
                      2: FlexColumnWidth(2),
                      3: FlexColumnWidth(2),
                    },
                    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                    children: [
                      // Header Row
                      TableRow(
                        decoration: BoxDecoration(
                          color: isDark ? Colors.grey[850] : Colors.grey[100],
                        ),
                        children: const [
                          Padding(
                            padding: EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                            child: Text(
                              '#',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                            child: Text(
                              'Branch',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                            child: Text(
                              'Count',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                            child: Text(
                              'Share',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),

                      // Branch Data Rows
                      ...branches.asMap().entries.map((bMapEntry) {
                        final bIdx = bMapEntry.key;
                        final bItem = bMapEntry.value;
                        final bPct = groupTotal > 0 ? (bItem.value / groupTotal) * 100 : 0.0;

                        return TableRow(
                          decoration: BoxDecoration(
                            color: bIdx % 2 == 1
                                ? (isDark ? Colors.grey[900]!.withValues(alpha: 0.5) : Colors.grey[50])
                                : null,
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 8),
                              child: Text(
                                '${bIdx + 1}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 8),
                              child: Text(
                                bItem.key,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 8),
                              child: Text(
                                '${bItem.value}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: _primaryBlue,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 8),
                              child: Text(
                                '${bPct.toStringAsFixed(1)}%',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark ? Colors.grey[300] : Colors.grey[700],
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        );
                      }),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
