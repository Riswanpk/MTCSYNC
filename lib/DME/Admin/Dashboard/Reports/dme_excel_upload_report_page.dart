import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

import '../../../dme_config.dart';

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

  DmeExcelUploadItem({
    this.id,
    required this.fileName,
    required this.fileHash,
    required this.uploadedBy,
    required this.uploadedAt,
    required this.salesCount,
    required this.rowsCount,
  });

  factory DmeExcelUploadItem.fromMap(Map<String, dynamic> map) {
    DateTime dt;
    final uploadedAtRaw = map['uploaded_at']?.toString();
    if (uploadedAtRaw != null) {
      dt = DateTime.tryParse(uploadedAtRaw)?.toLocal() ?? DateTime.now();
    } else {
      dt = DateTime.now();
    }

    return DmeExcelUploadItem(
      id: map['id'] as int?,
      fileName: (map['file_name'] ?? 'Unnamed File').toString(),
      fileHash: (map['file_hash'] ?? '').toString(),
      uploadedBy: (map['uploaded_by'] ?? 'Unknown').toString(),
      uploadedAt: dt,
      salesCount: int.tryParse(map['sales_count']?.toString() ?? '0') ?? 0,
      rowsCount: int.tryParse(map['rows_count']?.toString() ?? '0') ?? 0,
    );
  }
}

class DmeExcelUploadReportPage extends StatefulWidget {
  const DmeExcelUploadReportPage({super.key});

  @override
  State<DmeExcelUploadReportPage> createState() => _DmeExcelUploadReportPageState();
}

class _DmeExcelUploadReportPageState extends State<DmeExcelUploadReportPage> {
  bool _isLoading = true;
  bool _isExporting = false;
  String? _errorMessage;

  List<DmeExcelUploadItem> _allUploads = [];
  String _searchQuery = '';

  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    _fetchUploadHistory();
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
          .select('id, file_name, file_hash, uploaded_by, uploaded_at, sales_count, rows_count')
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

  List<DmeExcelUploadItem> get _filteredUploads {
    return _allUploads.where((item) {
      // Date filter
      if (_startDate != null) {
        final startBoundary = DateTime(_startDate!.year, _startDate!.month, _startDate!.day, 0, 0, 0);
        if (item.uploadedAt.isBefore(startBoundary)) return false;
      }
      if (_endDate != null) {
        final endBoundary = DateTime(_endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59);
        if (item.uploadedAt.isAfter(endBoundary)) return false;
      }

      // Search query
      if (_searchQuery.trim().isNotEmpty) {
        final q = _searchQuery.trim().toLowerCase();
        final name = item.fileName.toLowerCase();
        final uploader = item.uploadedBy.toLowerCase();
        final hash = item.fileHash.toLowerCase();
        return name.contains(q) || uploader.contains(q) || hash.contains(q);
      }

      return true;
    }).toList();
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(
        start: _startDate ?? DateTime(now.year, now.month, 1),
        end: _endDate ?? now,
      ),
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 2),
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
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }

  void _clearDateRange() {
    setState(() {
      _startDate = null;
      _endDate = null;
    });
  }

  Future<void> _exportToExcel() async {
    final items = _filteredUploads;
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No records to export.')),
      );
      return;
    }

    setState(() => _isExporting = true);

    try {
      final xlsio.Workbook workbook = xlsio.Workbook();
      final xlsio.Worksheet sheet = workbook.worksheets[0];
      sheet.name = 'Excel Uploads';

      // Title header
      sheet.getRangeByName('A1:G1').merge();
      sheet.getRangeByName('A1').setText('DME Excel Upload History Report');
      sheet.getRangeByName('A1').cellStyle.bold = true;
      sheet.getRangeByName('A1').cellStyle.fontSize = 15;
      sheet.getRangeByName('A1').cellStyle.fontColor = '#005BAC';
      sheet.getRangeByName('A1').cellStyle.hAlign = xlsio.HAlignType.center;

      sheet.getRangeByName('A2:G2').merge();
      final dateStr = DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now());
      sheet.getRangeByName('A2').setText('Generated on: $dateStr | Total Records: ${items.length}');
      sheet.getRangeByName('A2').cellStyle.fontSize = 10;
      sheet.getRangeByName('A2').cellStyle.fontColor = '#666666';
      sheet.getRangeByName('A2').cellStyle.hAlign = xlsio.HAlignType.center;

      // Table Headers
      final headers = [
        '#',
        'File Name',
        'Uploaded Date & Time',
        'Uploaded By',
        'Sales Count',
        'Rows Count',
        'SHA-256 File Hash'
      ];

      for (int col = 0; col < headers.length; col++) {
        final cell = sheet.getRangeByIndex(4, col + 1);
        cell.setText(headers[col]);
        cell.cellStyle.bold = true;
        cell.cellStyle.backColor = '#005BAC';
        cell.cellStyle.fontColor = '#FFFFFF';
        cell.cellStyle.fontSize = 11;
        cell.cellStyle.hAlign = (col == 0 || col == 4 || col == 5)
            ? xlsio.HAlignType.center
            : xlsio.HAlignType.left;
      }

      // Populate Data Rows
      for (int r = 0; r < items.length; r++) {
        final item = items[r];
        final rowIdx = 5 + r;

        sheet.getRangeByIndex(rowIdx, 1).setNumber((r + 1).toDouble());
        sheet.getRangeByIndex(rowIdx, 2).setText(item.fileName);
        sheet.getRangeByIndex(rowIdx, 3).setText(DateFormat('dd-MM-yyyy HH:mm').format(item.uploadedAt));
        sheet.getRangeByIndex(rowIdx, 4).setText(item.uploadedBy);
        sheet.getRangeByIndex(rowIdx, 5).setNumber(item.salesCount.toDouble());
        sheet.getRangeByIndex(rowIdx, 6).setNumber(item.rowsCount.toDouble());
        sheet.getRangeByIndex(rowIdx, 7).setText(item.fileHash);

        if (r % 2 == 1) {
          sheet.getRangeByIndex(rowIdx, 1, rowIdx, 7).cellStyle.backColor = '#F5F7FA';
        }
      }

      // Auto-fit column widths
      for (int c = 1; c <= 7; c++) {
        sheet.autoFitColumn(c);
      }

      final List<int> bytes = workbook.saveAsStream();
      workbook.dispose();

      final tempDir = await getTemporaryDirectory();
      final timeStamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final filePath = '${tempDir.path}/dme_excel_uploads_$timeStamp.xlsx';
      final file = File(filePath);
      await file.writeAsBytes(bytes, flush: true);

      setState(() => _isExporting = false);

      await Share.shareXFiles(
        [XFile(filePath)],
        text: 'DME Excel Upload History Report - $dateStr',
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

  void _showDetailsSheet(DmeExcelUploadItem item) {
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
    final filtered = _filteredUploads;
    final totalSales = filtered.fold<int>(0, (sum, item) => sum + item.salesCount);
    final totalRows = filtered.fold<int>(0, (sum, item) => sum + item.rowsCount);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Excel Upload History Report',
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
            tooltip: 'Export Excel Report',
            onPressed: (_isLoading || _isExporting || filtered.isEmpty) ? null : _exportToExcel,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _fetchUploadHistory,
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter & Search Bar
          Container(
            padding: const EdgeInsets.all(14),
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
            child: Column(
              children: [
                // Search Input
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Search by file name, uploader or hash...',
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
                const SizedBox(height: 10),

                // Date Filter Chips
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: _pickDateRange,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                            color: _startDate != null ? _primaryBlue.withValues(alpha: 0.08) : null,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.date_range_rounded,
                                size: 16,
                                color: _startDate != null ? _primaryBlue : Colors.grey[700],
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _startDate != null && _endDate != null
                                      ? '${DateFormat('dd MMM yy').format(_startDate!)} - ${DateFormat('dd MMM yy').format(_endDate!)}'
                                      : 'Filter by Upload Date Range',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: _startDate != null ? FontWeight.bold : FontWeight.normal,
                                    color: _startDate != null ? _primaryBlue : null,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (_startDate != null) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20),
                        tooltip: 'Clear Date Filter',
                        onPressed: _clearDateRange,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // KPI Metric Summary Ribbon
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: _primaryBlue.withValues(alpha: 0.07),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildKpiSummaryItem('Uploads', '${filtered.length}', Icons.cloud_done_rounded, _primaryBlue),
                _buildKpiSummaryItem('Total Sales', '$totalSales', Icons.receipt_long_rounded, _primaryGreen),
                _buildKpiSummaryItem('Total Rows', '$totalRows', Icons.table_rows_rounded, Colors.orange.shade800),
              ],
            ),
          ),

          // Upload History List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? Center(
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
                      )
                    : filtered.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.folder_open_rounded, size: 48, color: Colors.grey[400]),
                                const SizedBox(height: 8),
                                Text(
                                  'No Excel upload records match your filter.',
                                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(12),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, idx) {
                              final item = filtered[idx];
                              return Card(
                                elevation: 1.5,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () => _showDetailsSheet(item),
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
                                                    'Uploaded on ${DateFormat('dd MMM yyyy, hh:mm a').format(item.uploadedAt)}',
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
