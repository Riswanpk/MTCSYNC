import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;
import 'package:intl/intl.dart';

const Color primaryBlue = Color(0xFF005BAC);
const Color primaryGreen = Color(0xFF8CC63F);

class SupersaleAdminReportPage extends StatefulWidget {
  const SupersaleAdminReportPage({Key? key}) : super(key: key);

  @override
  State<SupersaleAdminReportPage> createState() => _SupersaleAdminReportPageState();
}

class _SupersaleAdminReportPageState extends State<SupersaleAdminReportPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isGenerating = false;

  Future<void> _generateExcelReport() async {
    setState(() => _isGenerating = true);
    
    try {
      // 1. Fetch active admin postings to know the active items and branches
      final postingsSnapshot = await _firestore.collection('supersales').get();
      
      final xlsio.Workbook workbook = xlsio.Workbook();
      final xlsio.Worksheet sheet = workbook.worksheets[0];
      sheet.name = 'Supersale Report';

      // Define header
      final List<String> headers = [
        'Item',
        'Branch',
        'Customer Name',
        'Phone',
        'Quantity',
        'Rate',
        'Advance',
        'Status',
        'Sales Exec',
        'Booking Date'
      ];

      for (int i = 0; i < headers.length; i++) {
        sheet.getRangeByIndex(1, i + 1).setText(headers[i]);
        sheet.getRangeByIndex(1, i + 1).cellStyle.bold = true;
        sheet.getRangeByIndex(1, i + 1).cellStyle.backColor = '#D9E1F2';
      }

      int rowIndex = 2;

      // 2. Iterate through postings to get all entries
      for (var posting in postingsSnapshot.docs) {
        final data = posting.data();
        final itemName = data['item'] as String? ?? 'Unknown';
        final branches = List<String>.from(data['branches'] ?? []);

        for (var branch in branches) {
          final entriesSnapshot = await _firestore
              .collection('supersale_user_entries')
              .doc(branch)
              .collection(itemName)
              .get();

          for (var entryDoc in entriesSnapshot.docs) {
            final entry = entryDoc.data();
            sheet.getRangeByIndex(rowIndex, 1).setText(itemName);
            sheet.getRangeByIndex(rowIndex, 2).setText(branch);
            sheet.getRangeByIndex(rowIndex, 3).setText(entry['customerName']?.toString() ?? '');
            sheet.getRangeByIndex(rowIndex, 4).setText(entry['phone']?.toString() ?? '');
            sheet.getRangeByIndex(rowIndex, 5).setNumber((entry['quantity'] ?? 0).toDouble());
            sheet.getRangeByIndex(rowIndex, 6).setNumber((entry['rate'] ?? 0).toDouble());
            sheet.getRangeByIndex(rowIndex, 7).setNumber((entry['advance'] ?? 0).toDouble());
            sheet.getRangeByIndex(rowIndex, 8).setText(entry['status']?.toString() ?? 'pending');
            sheet.getRangeByIndex(rowIndex, 9).setText(entry['username']?.toString() ?? '');
            
            final createdAt = entry['created_at'];
            if (createdAt is Timestamp) {
              final dateStr = DateFormat('dd-MM-yyyy HH:mm').format(createdAt.toDate());
              sheet.getRangeByIndex(rowIndex, 10).setText(dateStr);
            } else {
              sheet.getRangeByIndex(rowIndex, 10).setText('');
            }
            
            rowIndex++;
          }
        }
      }

      // Auto-fit columns
      for (int i = 1; i <= headers.length; i++) {
        sheet.autoFitColumn(i);
      }

      final List<int> bytes = workbook.saveAsStream();
      workbook.dispose();

      // Save and share
      final Directory directory = await getTemporaryDirectory();
      final String path = '${directory.path}/Supersale_Report_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';
      final File file = File(path);
      await file.writeAsBytes(bytes, flush: true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Report generated successfully! Opening...'),
            backgroundColor: Colors.green,
          ),
        );
      }
      
      await Share.shareXFiles([XFile(path)], text: 'Supersale Report');

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to generate report: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A1628) : Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'Supersale Reports',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        elevation: 0,
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.analytics_rounded,
                size: 80,
                color: primaryGreen.withOpacity(0.8),
              ),
              const SizedBox(height: 24),
              Text(
                'Generate Excel Report',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Download a complete report of all supersale bookings across all branches. The data will be exported as an Excel (.xlsx) file.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
              const SizedBox(height: 48),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _isGenerating ? null : _generateExcelReport,
                  icon: _isGenerating 
                      ? const SizedBox(
                          width: 20, 
                          height: 20, 
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                        )
                      : const Icon(Icons.download_rounded),
                  label: Text(
                    _isGenerating ? 'Generating...' : 'Download Report',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
