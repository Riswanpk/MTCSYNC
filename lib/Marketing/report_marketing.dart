import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'dart:typed_data';
import 'report_excel_marketing.dart'; // Import the Excel report generator

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
      final result = <String, dynamic>{};
      data.forEach((key, value) {
        if (value is Timestamp) {
          result[key] = value.toDate();
        } else {
          result[key] = value ?? '';
        }
      });
      result['Document ID'] = doc.id;
      return result;
    }).toList();

    // Sort by branch then date
    filtered.sort((a, b) {
      final branchA = a['branch']?.toString() ?? '';
      final branchB = b['branch']?.toString() ?? '';
      final dateA = a['timestamp'] is DateTime ? a['timestamp'] as DateTime : DateTime.tryParse(a['timestamp']?.toString() ?? '') ?? DateTime(2000);
      final dateB = b['timestamp'] is DateTime ? b['timestamp'] as DateTime : DateTime.tryParse(b['timestamp']?.toString() ?? '') ?? DateTime(2000);
      final branchCompare = branchA.compareTo(branchB);
      if (branchCompare != 0) return branchCompare;
      return dateA.compareTo(dateB);
    });

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
    for (var entry in data) {
      // Load photo if available
      pw.Widget? photoWidget;
      if (entry['photoUrl'] != null && entry['photoUrl'].toString().isNotEmpty) {
        final imageProvider = await networkImage(entry['photoUrl']);
        photoWidget = pw.Container(
          height: 180,
          width: 180,
          child: pw.Image(imageProvider, fit: pw.BoxFit.cover),
        );
      }

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Padding(
              padding: const pw.EdgeInsets.all(24),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Marketing Form Entry',
                    style: pw.TextStyle(
                      fontSize: 20,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 12),

                  // Display photo (not clickable)
                  if (photoWidget != null) ...[
                    pw.Text('Photo:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    photoWidget,
                    pw.SizedBox(height: 12),
                  ],

                  // Display other fields
                  ...entry.entries
                      .where((e) => e.key != 'photoUrl' && e.key != 'Document ID')
                      .map((e) {
                    String value;
                    if (e.value is DateTime) {
                      value = DateFormat('yyyy-MM-dd HH:mm').format(e.value as DateTime);
                    } else {
                      value = e.value?.toString() ?? '';
                    }

                    if (e.key == 'location' && value.isNotEmpty) {
                      final mapsUrl =
                          'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(value)}';

                      return pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(vertical: 4),
                        child: pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text('Location: ',
                                style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                            pw.UrlLink(
                              destination: mapsUrl,
                              child: pw.Text(
                                value,
                                style: pw.TextStyle(
                                  color: PdfColors.blue,
                                  decoration: pw.TextDecoration.underline,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(vertical: 4),
                      child: pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('${e.key}: ',
                              style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                          pw.Expanded(child: pw.Text(value)),
                        ],
                      ),
                    );
                  }).toList(),
                ],
              ),
            );
          },
        ),
      );
    }
  }

  final dir = await getApplicationDocumentsDirectory();
  final file = File(
      '${dir.path}/marketing_report_${DateTime.now().millisecondsSinceEpoch}.pdf');
  await file.writeAsBytes(await pdf.save());
  return file;
}


  // Helper for network image
  Future<pw.ImageProvider> networkImage(String url) async {
    final response = await HttpClient().getUrl(Uri.parse(url));
    final bytes = await response.close().then((r) => r.fold<List<int>>([], (p, e) => p..addAll(e)));
    return pw.MemoryImage(Uint8List.fromList(bytes));
  }

  Future<void> _generateAndShareReport() async {
    setState(() => isLoading = true);
    final data = await _fetchReportData();
    final file = await _generatePdf(data);
    setState(() => isLoading = false);
    await Share.shareXFiles([XFile(file.path)], text: 'Marketing Report');
  }

  Future<void> _generateAndShareExcel() async {
    setState(() => isLoading = true);
    final data = await _fetchReportData();
    final file = await generateExcelMarketingReport(data);
    setState(() => isLoading = false);
    await Share.shareXFiles([XFile(file.path)], text: 'Marketing Excel Report');
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
                  Center(
                    child: Column(
                      children: [
                        ElevatedButton.icon(
                          icon: const Icon(Icons.share),
                          label: const Text('Share Report'),
                          onPressed: _generateAndShareReport,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF005BAC),
                            foregroundColor: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.table_chart),
                          label: const Text('Share Excel'),
                          onPressed: _generateAndShareExcel,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
