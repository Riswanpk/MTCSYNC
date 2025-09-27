import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;
import 'dart:typed_data';
import 'package:http/http.dart' as http;

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

  // --- Syncfusion Excel Report Generation ---
  Future<File> _generateSyncfusionExcel(List<Map<String, dynamic>> data) async {
    final workbook = xlsio.Workbook();

    // Group data by 'formType'
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final row in data) {
      final formType = row['formType']?.toString() ?? 'Unknown';
      grouped.putIfAbsent(formType, () => []).add(row);
    }

    int sheetIndex = 0;
    for (final entry in grouped.entries) {
      final sheet = sheetIndex == 0
          ? workbook.worksheets[0]
          : workbook.worksheets.addWithName(entry.key);
      sheet.name = entry.key;

      final formData = entry.value;
      if (formData.isEmpty) {
        sheet.getRangeByIndex(1, 1).setText("No data available");
      } else {
        final headers = formData.first.keys.toList();

        // Add headers
        for (int i = 0; i < headers.length; i++) {
          final cell = sheet.getRangeByIndex(1, i + 1);
          cell.setText(headers[i]);
          cell.cellStyle.bold = true;
          cell.cellStyle.backColor = "#D9E1F2";
        }

        // Add rows
        for (int row = 0; row < formData.length; row++) {
          final rowData = formData[row];
          for (int col = 0; col < headers.length; col++) {
            final key = headers[col];
            final value = rowData[key];
            final cell = sheet.getRangeByIndex(row + 2, col + 1);

            if (key.toLowerCase().contains('image') && value is String && value.isNotEmpty) {
              try {
                final response = await http.get(Uri.parse(value));
                if (response.statusCode == 200) {
                  final bytes = response.bodyBytes;
                  // Insert image at the cell position (row + 2, col + 1)
                  final picture = sheet.pictures.addStream(row + 2, col + 1, bytes);
                  picture.height = 80; // Adjust as needed
                  picture.width = 80;  // Adjust as needed
                  sheet.getRangeByIndex(row + 2, col + 1).rowHeight = 60;
                  sheet.getRangeByIndex(1, col + 1).columnWidth = 15;
                } else {
                  cell.setText('Image not found');
                }
              } catch (e) {
                cell.setText('Error loading image');
              }
            } else if (key == 'locationString') {
              // Use lat/long for Google Maps link, but only show the link, not the address text
              final lat = rowData['lat']?.toString();
              final long = rowData['long']?.toString();
              if (lat != null && long != null) {
                cell.setFormula('HYPERLINK("https://www.google.com/maps?q=$lat,$long","Open in Google Maps")');
              } else {
                cell.setText(value?.toString() ?? '');
              }
            } else if (value is DateTime) {
              cell.dateTime = value;
              cell.numberFormat = 'yyyy-mm-dd hh:mm';
            } else {
              cell.setText(value?.toString() ?? '');
            }
          }
        }

        // Autofit columns except image columns
        for (int i = 0; i < headers.length; i++) {
          if (!headers[i].toLowerCase().contains('image')) {
            sheet.autoFitColumn(i + 1);
          }
        }
      }
      sheetIndex++;
    }

    final bytes = workbook.saveAsStream();
    workbook.dispose();

    final dir = await getApplicationDocumentsDirectory();
    final file = File(
        "${dir.path}/Report${DateTime.now().millisecondsSinceEpoch}.xlsx");
    await file.writeAsBytes(bytes, flush: true);

    return file;
  }

  Future<void> _generateAndShareSyncfusionReport() async {
    setState(() => isLoading = true);
    final data = await _fetchReportData();
    final file = await _generateSyncfusionExcel(data);
    setState(() => isLoading = false);
    await Share.shareXFiles([XFile(file.path)], text: "Syncfusion Marketing Report");
  }
  // --- End Syncfusion Excel Report Generation ---

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
                          icon: const Icon(Icons.insert_drive_file),
                          label: const Text("Share Syncfusion Report"),
                          onPressed: _generateAndShareSyncfusionReport,
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
