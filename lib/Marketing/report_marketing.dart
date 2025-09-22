import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:excel/excel.dart' as excel;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:share_plus/share_plus.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class ReportMarketingPage extends StatefulWidget {
  @override
  State<ReportMarketingPage> createState() => _ReportMarketingPageState();
}

class _ReportMarketingPageState extends State<ReportMarketingPage> {
  String? selectedBranch;
  DateTime? startDate;
  DateTime? endDate;
  List<String> branches = [];
  List<String> formTypes = [
    'General Customer',
    'Premium Customer',
    'Hotel / Resort Customer'
  ];
  Map<String, bool> selectedForms = {};
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchBranches();
    for (var type in formTypes) {
      selectedForms[type] = false;
    }
  }

  Future<void> _fetchBranches() async {
    final snap = await FirebaseFirestore.instance.collection('users').get();
    final branchSet = <String>{};
    for (var doc in snap.docs) {
      final branch = doc.data()['branch'];
      if (branch != null) branchSet.add(branch);
    }
    setState(() {
      branches = ['Select All', ...branchSet];
      selectedBranch = branches.first;
    });
  }

  Future<List<Map<String, dynamic>>> _fetchReportData() async {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance.collection('marketing');
    if (selectedBranch != null && selectedBranch != 'Select All') {
      query = query.where('branch', isEqualTo: selectedBranch);
    }
    if (selectedForms.values.any((v) => v)) {
      query = query.where('formType', whereIn: selectedForms.entries.where((e) => e.value).map((e) => e.key).toList());
    }
    final snap = await query.get();
    final filtered = snap.docs.where((doc) {
      final ts = doc.data()['timestamp'];
      if (ts is Timestamp) {
        final dt = ts.toDate();
        if (startDate != null && dt.isBefore(startDate!)) return false;
        if (endDate != null && dt.isAfter(endDate!)) return false;
      }
      return true;
    }).map((doc) {
      final data = doc.data();
      // Ensure photo URL is included and all fields are present
      final result = <String, dynamic>{};
      data.forEach((key, value) {
        if (key == 'imageUrl') {
          result['Photo URL'] = value ?? '';
        } else if (value is Timestamp) {
          result[key] = value.toDate().toString();
        } else {
          result[key] = value ?? '';
        }
      });
      // Add document ID for reference
      result['Document ID'] = doc.id;
      return result;
    }).toList();
    return filtered;
  }

  Future<File> _generatePdf(List<Map<String, dynamic>> data) async {
  final pdf = pw.Document();

  if (data.isEmpty) {
    pdf.addPage(
      pw.Page(
        build: (pw.Context context) => pw.Center(
          child: pw.Text("No data available", style: pw.TextStyle(fontSize: 18)),
        ),
      ),
    );
  } else {
    // Build table header
    final headers = data.first.keys.toList();

    // Build rows
    final rows = data.map((row) {
      return headers.map((h) => row[h]?.toString() ?? '').toList();
    }).toList();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) => [
          pw.Text('Marketing Report',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 20),
          pw.Table.fromTextArray(
            headers: headers,
            data: rows,
            border: pw.TableBorder.all(),
            headerStyle:
                pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12),
            cellStyle: const pw.TextStyle(fontSize: 10),
            cellAlignment: pw.Alignment.centerLeft,
          ),
        ],
      ),
    );
  }

  final dir = await getApplicationDocumentsDirectory();
  final file =
      File('${dir.path}/marketing_report_${DateTime.now().millisecondsSinceEpoch}.pdf');
  await file.writeAsBytes(await pdf.save());
  return file;
}



  Future<void> _notifyAndOpen(File file) async {
    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
        channelKey: 'basic_channel',
        title: 'Marketing Report Downloaded',
        body: 'Tap to open the Excel file.',
        notificationLayout: NotificationLayout.Default,
        payload: {'filePath': file.path},
      ),
      actionButtons: [
        NotificationActionButton(
          key: 'OPEN_REPORT',
          label: 'Open',
          autoDismissible: true,
        ),
      ],
    );
  
  }

  Future<void> _generateAndHandleReport({bool shareInstead = false}) async {
    setState(() => isLoading = true);
    final data = await _fetchReportData();
    final file = await _generatePdf(data);
    setState(() => isLoading = false);
    if (shareInstead) {
      await Share.shareXFiles([XFile(file.path)], text: 'Marketing Report');
    } else {
      await _notifyAndOpen(file);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Report downloaded: ${file.path}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Marketing Report'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Branch', style: TextStyle(fontWeight: FontWeight.bold)),
                  DropdownButton<String>(
                    value: selectedBranch,
                    items: branches.map((b) => DropdownMenuItem(value: b, child: Text(b))).toList(),
                    onChanged: (val) => setState(() => selectedBranch = val),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Start Date', style: TextStyle(fontWeight: FontWeight.bold)),
                            InkWell(
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: startDate ?? DateTime.now(),
                                  firstDate: DateTime(2022),
                                  lastDate: DateTime.now(),
                                );
                                if (picked != null) setState(() => startDate = picked);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  startDate != null
                                      ? DateFormat('yyyy-MM-dd').format(startDate!)
                                      : 'Select',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('End Date', style: TextStyle(fontWeight: FontWeight.bold)),
                            InkWell(
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: endDate ?? DateTime.now(),
                                  firstDate: DateTime(2022),
                                  lastDate: DateTime.now(),
                                );
                                if (picked != null) setState(() => endDate = picked);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  endDate != null
                                      ? DateFormat('yyyy-MM-dd').format(endDate!)
                                      : 'Select',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('Form Types', style: TextStyle(fontWeight: FontWeight.bold)),
                  ...formTypes.map((type) => CheckboxListTile(
                        title: Text(type),
                        value: selectedForms[type] ?? false,
                        onChanged: (val) => setState(() => selectedForms[type] = val ?? false),
                      )),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.download),
                          label: const Text('Download Excel'),
                          onPressed: () => _generateAndHandleReport(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF005BAC),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.share),
                          label: const Text('Share Excel'),
                          onPressed: () => _generateAndHandleReport(shareInstead: true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}
