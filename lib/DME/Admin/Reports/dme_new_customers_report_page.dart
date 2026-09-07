import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

import '../../dme_constants.dart';
import '../../dme_config.dart';

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

  const DmeNewCustomersReportPage({super.key, this.userAssignedBranches});

  @override
  State<DmeNewCustomersReportPage> createState() => _DmeNewCustomersReportPageState();
}

class _DmeNewCustomersReportPageState extends State<DmeNewCustomersReportPage> {
  DateTime _startDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _endDate = DateTime.now();

  int? _selectedBranchId; // null means 'All Allowed Branches'
  List<int> _assignedBranches = [];

  bool _isLoading = false;
  bool _isExporting = false;
  String _searchQuery = '';

  List<DmeNewCustomerReportItem> _reportItems = [];

  @override
  void initState() {
    super.initState();
    _initBranchAccess();
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
    _fetchReportData();
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
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
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _fetchReportData();
    }
  }

  Future<void> _fetchReportData() async {
    final client = await DmeConfig.getClient();
    if (client == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Supabase is not configured.')),
        );
      }
      return;
    }

    setState(() => _isLoading = true);

    try {
      final startStr = DateFormat('yyyy-MM-dd').format(_startDate);
      final endStr = DateFormat('yyyy-MM-dd').format(_endDate);

      // 1. Fetch Customers created in the date interval
      var custQuery = client
          .from('dme_customers')
          .select('id, name, phone, address, salesman, created_at')
          .gte('created_at', '${startStr}T00:00:00')
          .lte('created_at', '${endStr}T23:59:59');

      final custRes = await custQuery;
      final List<dynamic> custList = custRes as List<dynamic>;

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
        if (_selectedBranchId != null) {
          final hasBranch = branches.any((b) => b['branch_id'] == _selectedBranchId);
          if (!hasBranch) continue;
        } else if (_assignedBranches.isNotEmpty) {
          final hasAllowedBranch = branches.any((b) => _assignedBranches.contains(b['branch_id']));
          if (!hasAllowedBranch) continue;
        }

        int? primaryBranchId;
        int? categoryId;
        int? typeId;

        if (_selectedBranchId != null) {
          final matched = branches.firstWhere(
            (b) => b['branch_id'] == _selectedBranchId,
            orElse: () => branches.isNotEmpty ? branches.first : {},
          );
          primaryBranchId = matched['branch_id'] as int?;
          categoryId = matched['category_id'] as int?;
          typeId = matched['customer_type_id'] as int?;
        } else if (branches.isNotEmpty) {
          final first = branches.first;
          primaryBranchId = first['branch_id'] as int?;
          categoryId = first['category_id'] as int?;
          typeId = first['customer_type_id'] as int?;
        }

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
          final createdDateStr = c['created_at']?.toString();
          if (createdDateStr != null) {
            final cd = DateTime.tryParse(createdDateStr);
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading report: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _generateAndShareExcel() async {
    if (_reportItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No report data available to export.')),
      );
      return;
    }

    setState(() => _isExporting = true);

    try {
      final xlsio.Workbook workbook = xlsio.Workbook();
      final xlsio.Worksheet sheet = workbook.worksheets[0];
      sheet.name = 'New Customers';

      // 1. Title Banner
      final String branchTitle = _selectedBranchId != null
          ? DmeConstants.getBranchName(_selectedBranchId!)
          : 'All Branches';
      final String dateIntervalTitle =
          '${DateFormat('dd MMM yyyy').format(_startDate)} to ${DateFormat('dd MMM yyyy').format(_endDate)}';

      sheet.getRangeByName('A1:G1').merge();
      final xlsio.Range titleRange = sheet.getRangeByName('A1');
      titleRange.setText('NEW CUSTOMERS REPORT - $branchTitle');
      titleRange.cellStyle.fontSize = 14;
      titleRange.cellStyle.bold = true;
      titleRange.cellStyle.fontColor = '#FFFFFF';
      titleRange.cellStyle.backColor = '#005BAC';
      titleRange.cellStyle.hAlign = xlsio.HAlignType.center;
      titleRange.cellStyle.vAlign = xlsio.VAlignType.center;
      sheet.setRowHeightInPixels(1, 32);

      sheet.getRangeByName('A2:G2').merge();
      final xlsio.Range subTitleRange = sheet.getRangeByName('A2');
      subTitleRange.setText('Date Interval: $dateIntervalTitle  |  Total New Customers: ${_reportItems.length}');
      subTitleRange.cellStyle.fontSize = 11;
      subTitleRange.cellStyle.bold = true;
      subTitleRange.cellStyle.fontColor = '#333333';
      subTitleRange.cellStyle.backColor = '#EAEAEA';
      subTitleRange.cellStyle.hAlign = xlsio.HAlignType.center;
      subTitleRange.cellStyle.vAlign = xlsio.VAlignType.center;
      sheet.setRowHeightInPixels(2, 24);

      // 2. Table Column Headers
      final List<String> headers = [
        'SL NO',
        'CUSTOMER NAME',
        'PHONE NUMBER',
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

        // Address
        final addrCell = sheet.getRangeByIndex(rowIndex, 4);
        addrCell.setText(item.address.isNotEmpty ? item.address : '-');

        // Category
        final catCell = sheet.getRangeByIndex(rowIndex, 5);
        catCell.setText(item.categoryName);
        catCell.cellStyle.hAlign = xlsio.HAlignType.center;

        // Customer Type
        final typeCell = sheet.getRangeByIndex(rowIndex, 6);
        typeCell.setText(item.customerTypeName);
        typeCell.cellStyle.hAlign = xlsio.HAlignType.center;

        // Purchase Date(s)
        final dateCell = sheet.getRangeByIndex(rowIndex, 7);
        dateCell.setText(item.purchaseDatesFormatted);
        dateCell.cellStyle.hAlign = xlsio.HAlignType.center;

        for (int c = 1; c <= 7; c++) {
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
      sheet.setColumnWidthInPixels(3, 140);
      sheet.setColumnWidthInPixels(4, 220);
      sheet.setColumnWidthInPixels(5, 140);
      sheet.setColumnWidthInPixels(6, 140);
      sheet.setColumnWidthInPixels(7, 240);

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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate Excel: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  List<DmeNewCustomerReportItem> _getFilteredItems() {
    if (_searchQuery.trim().isEmpty) return _reportItems;
    final q = _searchQuery.trim().toLowerCase();
    return _reportItems.where((item) {
      return item.name.toLowerCase().contains(q) ||
          item.phone.toLowerCase().contains(q) ||
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
                            border: Border.all(color: Colors.grey.shade400),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.date_range, size: 18, color: _primaryBlue),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${DateFormat('dd-MM-yy').format(_startDate)} to ${DateFormat('dd-MM-yy').format(_endDate)}',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
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
                              _fetchReportData();
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
                        onChanged: (val) => setState(() => _searchQuery = val),
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
              ],
            ),
          ),

          // Total Count Banner
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
}
