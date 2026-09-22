import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

import '../../../Misc/dme_config.dart';
import '../../../Misc/dme_constants.dart';

const Color _primaryBlue = Color(0xFF005BAC);
const Color _primaryGreen = Color(0xFF8CC63F);

class DmeExcelUploadItem {
  final int? id;
  final String fileName;
  final String fileHash;
  final String uploadedBy;
  final DateTime uploadedAt;
  final int salesCount;
  final int rowsCount;
  final String? branch;

  DmeExcelUploadItem({
    this.id,
    required this.fileName,
    required this.fileHash,
    required this.uploadedBy,
    required this.uploadedAt,
    required this.salesCount,
    required this.rowsCount,
    this.branch,
  });

  factory DmeExcelUploadItem.fromMap(Map<String, dynamic> map) {
    DateTime dt;
    final uploadedAtRaw = map['uploaded_at']?.toString();
    if (uploadedAtRaw != null) {
      dt = DateTime.tryParse(uploadedAtRaw) ?? DateTime.now();
    } else {
      dt = DateTime.now();
    }

    final branchVal = map['branch']?.toString().trim();

    return DmeExcelUploadItem(
      id: map['id'] as int?,
      fileName: (map['file_name'] ?? 'Unnamed File').toString(),
      fileHash: (map['file_hash'] ?? '').toString(),
      uploadedBy: (map['uploaded_by'] ?? 'Unknown').toString(),
      uploadedAt: dt,
      salesCount: int.tryParse(map['sales_count']?.toString() ?? '0') ?? 0,
      rowsCount: int.tryParse(map['rows_count']?.toString() ?? '0') ?? 0,
      branch: (branchVal != null && branchVal.isNotEmpty) ? branchVal : null,
    );
  }
}

class BranchUploadStatus {
  final DmeBranch branch;
  final bool hasUploaded;
  final List<DmeExcelUploadItem> uploads;

  BranchUploadStatus({
    required this.branch,
    required this.hasUploaded,
    required this.uploads,
  });
}

class DmeExcelUploadReportPage extends StatefulWidget {
  const DmeExcelUploadReportPage({super.key});

  @override
  State<DmeExcelUploadReportPage> createState() => _DmeExcelUploadReportPageState();
}

class _DmeExcelUploadReportPageState extends State<DmeExcelUploadReportPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  bool _isLoading = true;
  bool _isExporting = false;
  String? _errorMessage;

  List<DmeExcelUploadItem> _allUploads = [];
  
  // Date selector for Tab 2 (Branch Status)
  DateTime _selectedDate = DateTime.now();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchUploadHistory();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchUploadHistory() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final client = await DmeConfig.getClient();
      if (client == null) {
        throw Exception('Supabase client not initialized');
      }

      final res = await client
          .from('dme_excel_uploads')
          .select('id, file_name, file_hash, uploaded_by, uploaded_at, sales_count, rows_count, branch')
          .order('uploaded_at', ascending: false);

      final list = (res as List)
          .map((item) => DmeExcelUploadItem.fromMap(Map<String, dynamic>.from(item)))
          .toList();

      if (mounted) {
        setState(() {
          _allUploads = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching dme_excel_uploads: $e');
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  /// Filtered list of uploads for Tab 1 (Today's Uploaded Excels)
  List<DmeExcelUploadItem> get _todayUploads {
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return _allUploads.where((item) {
      final itemDayStr = DateFormat('yyyy-MM-dd').format(item.uploadedAt);
      if (itemDayStr != todayStr) return false;

      if (_searchQuery.trim().isNotEmpty) {
        final q = _searchQuery.trim().toLowerCase();
        final name = item.fileName.toLowerCase();
        final uploader = item.uploadedBy.toLowerCase();
        final hash = item.fileHash.toLowerCase();
        final branch = (item.branch ?? '').toLowerCase();
        return name.contains(q) || uploader.contains(q) || hash.contains(q) || branch.contains(q);
      }
      return true;
    }).toList();
  }

  /// Branch upload status for Tab 2 based on selected date
  /// Yesterday's sale date corresponds to today's upload target date
  List<BranchUploadStatus> get _branchStatuses {
    final selectedDayStr = DateFormat('yyyy-MM-dd').format(_selectedDate);

    // Filter uploads matching the target date
    final uploadsOnSelectedDate = _allUploads.where((item) {
      final itemDayStr = DateFormat('yyyy-MM-dd').format(item.uploadedAt);
      return itemDayStr == selectedDayStr;
    }).toList();

    return DmeConstants.branches.map((branch) {
      final branchCode = branch.name.toUpperCase();
      final branchUploads = uploadsOnSelectedDate.where((item) {
        if (item.branch != null && item.branch!.trim().isNotEmpty) {
          if (item.branch!.trim().toUpperCase() == branchCode) return true;
        }
        final upperName = item.fileName.toUpperCase();
        return upperName.contains(branchCode);
      }).toList();

      return BranchUploadStatus(
        branch: branch,
        hasUploaded: branchUploads.isNotEmpty,
        uploads: branchUploads,
      );
    }).where((status) {
      if (_searchQuery.trim().isEmpty) return true;
      final q = _searchQuery.trim().toLowerCase();
      final bName = status.branch.name.toLowerCase();
      final matchesFile = status.uploads.any(
        (u) => u.fileName.toLowerCase().contains(q) || u.uploadedBy.toLowerCase().contains(q),
      );
      return bName.contains(q) || matchesFile;
    }).toList();
  }

  Future<void> _pickSingleDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: _primaryBlue,
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _exportToExcel() async {
    final isTab1 = _tabController.index == 0;
    if (isTab1) {
      await _exportTab1ToExcel();
    } else {
      await _exportTab2ToExcel();
    }
  }

  Future<void> _exportTab1ToExcel() async {
    final items = _todayUploads;
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No upload records for today to export.')),
      );
      return;
    }

    setState(() => _isExporting = true);

    try {
      final xlsio.Workbook workbook = xlsio.Workbook();
      final xlsio.Worksheet sheet = workbook.worksheets[0];
      sheet.name = 'Today Uploads';

      sheet.getRangeByName('A1:H1').merge();
      sheet.getRangeByName('A1').setText('DME Today Excel Uploads Report');
      sheet.getRangeByName('A1').cellStyle.bold = true;
      sheet.getRangeByName('A1').cellStyle.fontSize = 15;
      sheet.getRangeByName('A1').cellStyle.fontColor = '#005BAC';
      sheet.getRangeByName('A1').cellStyle.hAlign = xlsio.HAlignType.center;

      sheet.getRangeByName('A2:H2').merge();
      final dateStr = DateFormat('dd MMM yyyy').format(DateTime.now());
      sheet.getRangeByName('A2').setText('Date: $dateStr | Total Records: ${items.length}');
      sheet.getRangeByName('A2').cellStyle.fontSize = 10;
      sheet.getRangeByName('A2').cellStyle.fontColor = '#666666';
      sheet.getRangeByName('A2').cellStyle.hAlign = xlsio.HAlignType.center;

      final headers = ['#', 'Branch', 'File Name', 'Uploaded Time', 'Uploaded By', 'Sales Count', 'Rows Count', 'File Hash'];

      for (int col = 0; col < headers.length; col++) {
        final cell = sheet.getRangeByIndex(4, col + 1);
        cell.setText(headers[col]);
        cell.cellStyle.bold = true;
        cell.cellStyle.backColor = '#005BAC';
        cell.cellStyle.fontColor = '#FFFFFF';
        cell.cellStyle.fontSize = 11;
        cell.cellStyle.hAlign = (col == 0 || col == 5 || col == 6)
            ? xlsio.HAlignType.center
            : xlsio.HAlignType.left;
      }

      for (int r = 0; r < items.length; r++) {
        final item = items[r];
        final rowIdx = 5 + r;

        sheet.getRangeByIndex(rowIdx, 1).setNumber((r + 1).toDouble());
        sheet.getRangeByIndex(rowIdx, 2).setText(item.branch ?? '-');
        sheet.getRangeByIndex(rowIdx, 3).setText(item.fileName);
        sheet.getRangeByIndex(rowIdx, 4).setText(DateFormat('HH:mm:ss').format(item.uploadedAt));
        sheet.getRangeByIndex(rowIdx, 5).setText(item.uploadedBy);
        sheet.getRangeByIndex(rowIdx, 6).setNumber(item.salesCount.toDouble());
        sheet.getRangeByIndex(rowIdx, 7).setNumber(item.rowsCount.toDouble());
        sheet.getRangeByIndex(rowIdx, 8).setText(item.fileHash);

        if (r % 2 == 1) {
          sheet.getRangeByIndex(rowIdx, 1, rowIdx, 8).cellStyle.backColor = '#F5F7FA';
        }
      }

      for (int c = 1; c <= 8; c++) {
        sheet.autoFitColumn(c);
      }

      final List<int> bytes = workbook.saveAsStream();
      workbook.dispose();

      final tempDir = await getTemporaryDirectory();
      final timeStamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final filePath = '${tempDir.path}/dme_today_uploads_$timeStamp.xlsx';
      final file = File(filePath);
      await file.writeAsBytes(bytes, flush: true);

      setState(() => _isExporting = false);

      await Share.shareXFiles(
        [XFile(filePath)],
        text: 'DME Today Excel Uploads Report - $dateStr',
      );
    } catch (e) {
      debugPrint('Error generating today upload report: $e');
      setState(() => _isExporting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _exportTab2ToExcel() async {
    final statuses = _branchStatuses;
    if (statuses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No branch data to export.')),
      );
      return;
    }

    setState(() => _isExporting = true);

    try {
      final xlsio.Workbook workbook = xlsio.Workbook();
      final xlsio.Worksheet sheet = workbook.worksheets[0];
      sheet.name = 'Branch Upload Status';

      sheet.getRangeByName('A1:E1').merge();
      sheet.getRangeByName('A1').setText('DME Branch Excel Upload Report');
      sheet.getRangeByName('A1').cellStyle.bold = true;
      sheet.getRangeByName('A1').cellStyle.fontSize = 15;
      sheet.getRangeByName('A1').cellStyle.fontColor = '#005BAC';
      sheet.getRangeByName('A1').cellStyle.hAlign = xlsio.HAlignType.center;

      sheet.getRangeByName('A2:E2').merge();
      final dateStr = DateFormat('dd MMM yyyy').format(_selectedDate);
      final saleDateStr = DateFormat('dd MMM yyyy').format(_selectedDate.subtract(const Duration(days: 1)));
      sheet.getRangeByName('A2').setText('Uploaded Date: $dateStr (Sale Data: $saleDateStr) | Branches: ${statuses.length}');
      sheet.getRangeByName('A2').cellStyle.fontSize = 10;
      sheet.getRangeByName('A2').cellStyle.fontColor = '#666666';
      sheet.getRangeByName('A2').cellStyle.hAlign = xlsio.HAlignType.center;

      final headers = ['#', 'Branch Code', 'Upload Status', 'Uploaded File(s)', 'Uploaded By'];

      for (int col = 0; col < headers.length; col++) {
        final cell = sheet.getRangeByIndex(4, col + 1);
        cell.setText(headers[col]);
        cell.cellStyle.bold = true;
        cell.cellStyle.backColor = '#005BAC';
        cell.cellStyle.fontColor = '#FFFFFF';
        cell.cellStyle.fontSize = 11;
        cell.cellStyle.hAlign = (col == 0 || col == 2)
            ? xlsio.HAlignType.center
            : xlsio.HAlignType.left;
      }

      for (int r = 0; r < statuses.length; r++) {
        final status = statuses[r];
        final rowIdx = 5 + r;

        sheet.getRangeByIndex(rowIdx, 1).setNumber((r + 1).toDouble());
        sheet.getRangeByIndex(rowIdx, 2).setText(status.branch.name);
        sheet.getRangeByIndex(rowIdx, 3).setText(status.hasUploaded ? 'Uploaded (âœ“)' : 'Pending (âœ—)');
        sheet.getRangeByIndex(rowIdx, 4).setText(
          status.uploads.isNotEmpty
              ? status.uploads.map((u) => u.fileName).join(', ')
              : '-',
        );
        sheet.getRangeByIndex(rowIdx, 5).setText(
          status.uploads.isNotEmpty
              ? status.uploads.map((u) => u.uploadedBy).join(', ')
              : '-',
        );

        if (status.hasUploaded) {
          sheet.getRangeByIndex(rowIdx, 3).cellStyle.fontColor = '#2E7D32';
          sheet.getRangeByIndex(rowIdx, 3).cellStyle.bold = true;
        } else {
          sheet.getRangeByIndex(rowIdx, 3).cellStyle.fontColor = '#C62828';
        }

        if (r % 2 == 1) {
          sheet.getRangeByIndex(rowIdx, 1, rowIdx, 5).cellStyle.backColor = '#F5F7FA';
        }
      }

      for (int c = 1; c <= 5; c++) {
        sheet.autoFitColumn(c);
      }

      final List<int> bytes = workbook.saveAsStream();
      workbook.dispose();

      final tempDir = await getTemporaryDirectory();
      final timeStamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final filePath = '${tempDir.path}/dme_branch_uploads_$timeStamp.xlsx';
      final file = File(filePath);
      await file.writeAsBytes(bytes, flush: true);

      setState(() => _isExporting = false);

      await Share.shareXFiles(
        [XFile(filePath)],
        text: 'DME Branch Excel Upload Report - $dateStr',
      );
    } catch (e) {
      debugPrint('Error generating Excel upload report: $e');
      setState(() => _isExporting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showItemDetailsSheet(DmeExcelUploadItem item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _primaryBlue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.description_rounded, color: _primaryBlue, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.fileName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Upload ID: #${item.id ?? 'N/A'}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            if (item.branch != null && item.branch!.isNotEmpty)
              _buildDetailRow('Branch', item.branch!),
            _buildDetailRow('Uploaded On', DateFormat('dd MMMM yyyy, hh:mm:ss a').format(item.uploadedAt)),
            _buildDetailRow('Uploaded By', item.uploadedBy),
            _buildDetailRow('Total Sales Synced', '${item.salesCount} sale records'),
            _buildDetailRow('Total Excel Rows', '${item.rowsCount} raw rows'),
            const SizedBox(height: 12),
            const Text(
              'SHA-256 Content Hash',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _primaryBlue),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      item.fileHash,
                      style: const TextStyle(fontSize: 11, fontFamily: 'monospace', height: 1.3),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 18, color: _primaryBlue),
                    tooltip: 'Copy Hash',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: item.fileHash));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('File hash copied to clipboard')),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryBlue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showBranchDetailsSheet(BranchUploadStatus status) {
    final saleDate = _selectedDate.subtract(const Duration(days: 1));
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: (status.hasUploaded ? Colors.green : Colors.red).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    status.hasUploaded ? Icons.check_circle_rounded : Icons.cancel_rounded,
                    color: status.hasUploaded ? Colors.green : Colors.red,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Branch: ${status.branch.name}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Upload Date: ${DateFormat('dd MMM yyyy').format(_selectedDate)} (Sale: ${DateFormat('dd MMM').format(saleDate)})',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Text(
              'Upload Status: ${status.hasUploaded ? 'Uploaded âœ“' : 'Not Uploaded âœ—'}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: status.hasUploaded ? Colors.green[700] : Colors.red[700],
              ),
            ),
            const SizedBox(height: 12),
            if (status.uploads.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12.0),
                child: Text(
                  'No Excel upload found for ${status.branch.name} on ${DateFormat('dd MMM yyyy').format(_selectedDate)}.',
                  style: TextStyle(color: Colors.grey[600], fontStyle: FontStyle.italic),
                ),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Uploaded Files:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _primaryBlue),
                  ),
                  const SizedBox(height: 8),
                  ...status.uploads.map(
                    (item) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.fileName,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Time: ${DateFormat('hh:mm a').format(item.uploadedAt)}',
                                style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                              ),
                              Text(
                                'By: ${item.uploadedBy.split('@').first}',
                                style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Sales: ${item.salesCount} | Rows: ${item.rowsCount}',
                            style: const TextStyle(fontSize: 11, color: _primaryBlue, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryBlue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: Colors.grey[600], fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final todayUploadsList = _todayUploads;
    final branchStatusList = _branchStatuses;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Excel Upload Reports',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: _primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: _isExporting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.share_rounded),
            tooltip: 'Export Report',
            onPressed: (_isLoading || _isExporting) ? null : _exportToExcel,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _fetchUploadHistory,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white.withValues(alpha: 0.7),
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 13, color: Colors.white70),
          tabs: const [
            Tab(
              icon: Icon(Icons.cloud_done_rounded, size: 20),
              text: 'Uploaded Today',
            ),
            Tab(
              icon: Icon(Icons.storefront_rounded, size: 20),
              text: 'Branch Upload Status',
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Search Input Bar (Shared)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search by branch, file name, or uploader...',
                hintStyle: const TextStyle(fontSize: 13),
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () => setState(() => _searchQuery = ''),
                      )
                    : null,
                filled: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
          ),

          // Tab Views Body
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildUploadedTodayTab(todayUploadsList),
                _buildBranchStatusTab(branchStatusList),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Tab 1 View: Excels Uploaded Today
  Widget _buildUploadedTodayTab(List<DmeExcelUploadItem> todayUploads) {
    final totalSales = todayUploads.fold<int>(0, (sum, item) => sum + item.salesCount);
    final totalRows = todayUploads.fold<int>(0, (sum, item) => sum + item.rowsCount);

    return Column(
      children: [
        // KPI Ribbon for Today
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: _primaryBlue.withValues(alpha: 0.07),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildKpiSummaryItem('Today Uploads', '${todayUploads.length}', Icons.cloud_done_rounded, _primaryBlue),
              _buildKpiSummaryItem('Total Sales', '$totalSales', Icons.receipt_long_rounded, _primaryGreen),
              _buildKpiSummaryItem('Total Rows', '$totalRows', Icons.table_rows_rounded, Colors.orange.shade800),
            ],
          ),
        ),

        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _errorMessage != null
                  ? _buildErrorWidget()
                  : todayUploads.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.folder_open_rounded, size: 48, color: Colors.grey[400]),
                              const SizedBox(height: 8),
                              Text(
                                'No Excel files uploaded today (${DateFormat('dd MMM yyyy').format(DateTime.now())}).',
                                style: TextStyle(color: Colors.grey[600], fontSize: 13),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: todayUploads.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, idx) {
                            final item = todayUploads[idx];
                            return Card(
                              elevation: 1.5,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => _showItemDetailsSheet(item),
                                child: Padding(
                                  padding: const EdgeInsets.all(14.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          CircleAvatar(
                                            radius: 18,
                                            backgroundColor: _primaryBlue.withValues(alpha: 0.12),
                                            foregroundColor: _primaryBlue,
                                            child: const Icon(Icons.table_chart_rounded, size: 20),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  item.fileName,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  'Uploaded at ${DateFormat('hh:mm a').format(item.uploadedAt)}',
                                                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      const Divider(height: 1),
                                      const SizedBox(height: 10),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Wrap(
                                            spacing: 8,
                                            children: [
                                              if (item.branch != null && item.branch!.isNotEmpty)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color: _primaryBlue.withValues(alpha: 0.12),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      const Icon(Icons.storefront_rounded, size: 12, color: _primaryBlue),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        item.branch!,
                                                        style: const TextStyle(
                                                          fontSize: 11,
                                                          fontWeight: FontWeight.bold,
                                                          color: _primaryBlue,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: _primaryGreen.withValues(alpha: 0.15),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    const Icon(Icons.receipt_long_rounded, size: 12, color: Colors.green),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      '${item.salesCount} Sales',
                                                      style: const TextStyle(
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.bold,
                                                        color: Colors.green,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: Colors.orange.withValues(alpha: 0.15),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(Icons.table_rows_rounded, size: 12, color: Colors.orange[800]),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      '${item.rowsCount} Rows',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.bold,
                                                        color: Colors.orange[800],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                          Text(
                                            'By: ${item.uploadedBy.split('@').first}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontStyle: FontStyle.italic,
                                              color: Colors.grey[700],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
        ),
      ],
    );
  }

  /// Tab 2 View: Branch Upload Status (With single date picker)
  Widget _buildBranchStatusTab(List<BranchUploadStatus> statuses) {
    final uploadedCount = statuses.where((s) => s.hasUploaded).length;
    final pendingCount = statuses.length - uploadedCount;
    final isToday = DateFormat('yyyy-MM-dd').format(_selectedDate) == DateFormat('yyyy-MM-dd').format(DateTime.now());
    final saleDateStr = DateFormat('dd MMM yyyy').format(_selectedDate.subtract(const Duration(days: 1)));

    return Column(
      children: [
        // Date Selector Bar & Sale Date Hint
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          color: Theme.of(context).cardColor,
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: _pickSingleDate,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: _primaryBlue.withValues(alpha: 0.3)),
                      borderRadius: BorderRadius.circular(10),
                      color: _primaryBlue.withValues(alpha: 0.06),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.calendar_today_rounded,
                          size: 18,
                          color: _primaryBlue,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    isToday ? 'Today\'s Upload Target' : 'Upload Date',
                                    style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '(Sale Data: $saleDateStr)',
                                    style: TextStyle(fontSize: 10, color: Colors.orange[800], fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                              Text(
                                isToday
                                    ? 'Today (${DateFormat('dd MMM yyyy').format(_selectedDate)})'
                                    : DateFormat('dd MMMM yyyy (EEEE)').format(_selectedDate),
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: _primaryBlue,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.arrow_drop_down_rounded,
                          color: _primaryBlue,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (!isToday) ...[
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () => setState(() => _selectedDate = DateTime.now()),
                  icon: const Icon(Icons.today_rounded, size: 16),
                  label: const Text('Today'),
                  style: TextButton.styleFrom(
                    foregroundColor: _primaryBlue,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                ),
              ],
            ],
          ),
        ),

        // KPI Summary Ribbon for Branch Status
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: _primaryBlue.withValues(alpha: 0.07),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildKpiSummaryItem('Total Branches', '${statuses.length}', Icons.store_rounded, _primaryBlue),
              _buildKpiSummaryItem('Uploaded', '$uploadedCount', Icons.check_circle_rounded, Colors.green),
              _buildKpiSummaryItem('Pending', '$pendingCount', Icons.pending_actions_rounded, Colors.red),
            ],
          ),
        ),

        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _errorMessage != null
                  ? _buildErrorWidget()
                  : statuses.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.search_off_rounded, size: 48, color: Colors.grey[400]),
                              const SizedBox(height: 8),
                              Text(
                                'No branches match your search query.',
                                style: TextStyle(color: Colors.grey[600], fontSize: 13),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: statuses.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, idx) {
                            final status = statuses[idx];
                            return Card(
                              elevation: 1.5,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: status.hasUploaded
                                      ? Colors.green.withValues(alpha: 0.4)
                                      : Colors.red.withValues(alpha: 0.2),
                                  width: 1,
                                ),
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => _showBranchDetailsSheet(status),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
                                  child: Row(
                                    children: [
                                      // Branch Avatar
                                      CircleAvatar(
                                        radius: 20,
                                        backgroundColor: status.hasUploaded
                                            ? Colors.green.withValues(alpha: 0.12)
                                            : Colors.red.withValues(alpha: 0.12),
                                        child: Text(
                                          status.branch.name,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: status.hasUploaded ? Colors.green[800] : Colors.red[800],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 14),

                                      // Branch Name & Details
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Branch ${status.branch.name}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 15,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              status.hasUploaded
                                                  ? 'Uploaded ${status.uploads.length} file(s)'
                                                  : 'No file uploaded on ${DateFormat('dd MMM').format(_selectedDate)}',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: status.hasUploaded ? Colors.green[700] : Colors.grey[600],
                                                fontWeight: status.hasUploaded ? FontWeight.w600 : FontWeight.normal,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                      // Tick Mark / Cross Badge
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: status.hasUploaded
                                              ? Colors.green.withValues(alpha: 0.12)
                                              : Colors.red.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              status.hasUploaded ? Icons.check_circle_rounded : Icons.cancel_rounded,
                                              size: 16,
                                              color: status.hasUploaded ? Colors.green : Colors.red,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              status.hasUploaded ? 'Uploaded' : 'Pending',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: status.hasUploaded ? Colors.green[800] : Colors.red[800],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
        ),
      ],
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.red, size: 48),
            const SizedBox(height: 12),
            Text('Failed to load uploads:\n$_errorMessage', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _fetchUploadHistory,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKpiSummaryItem(String label, String value, IconData icon, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: color)),
            Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[600])),
          ],
        ),
      ],
    );
  }
}
