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

class _ReportMarketingPageState extends State<ReportMarketingPage> with SingleTickerProviderStateMixin {
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
  double progress = 0.0;
  late AnimationController _progressController;
  late Animation<double> _progressAnimation;

  @override
  void initState() {
    super.initState();
    _fetchBranches();
    for (var type in formTypes) {
      selectedForms[type] = false;
    }
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _progressAnimation = Tween<double>(begin: 0, end: 0).animate(_progressController);
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
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
    int totalRows = data.isNotEmpty ? data.length : 1;
    int processedRows = 0;

    for (final entry in grouped.entries) {
      final sheet = sheetIndex == 0
          ? workbook.worksheets[0]
          : workbook.worksheets.addWithName(entry.key);
      sheet.name = entry.key;

      final formData = entry.value;
      if (formData.isEmpty) {
        sheet.getRangeByIndex(1, 1).setText("No data available");
      } else {
        final allKeys = formData.first.keys.toList();
        allKeys.remove('Document ID');
        final orderedKeys = [
          'formType',
          'username',
          'timestamp',
          ...allKeys.where((k) => k != 'formType' && k != 'username' && k != 'timestamp')
        ];

        String prettify(String key) {
          return key
              .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
              .replaceAll('_', ' ')
              .replaceAll('formtype', 'Form Type')
              .replaceAll('username', 'Username')
              .replaceAll('timestamp', 'Timestamp')
              .split(' ')
              .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
              .join(' ');
        }

        for (int i = 0; i < orderedKeys.length; i++) {
          final cell = sheet.getRangeByIndex(1, i + 1);
          cell.setText(prettify(orderedKeys[i]));
          cell.cellStyle.bold = true;
          cell.cellStyle.backColor = "#D9E1F2";
        }

        for (int row = 0; row < formData.length; row++) {
          final rowData = formData[row];
          for (int col = 0; col < orderedKeys.length; col++) {
            final key = orderedKeys[col];
            final value = rowData[key];
            final cell = sheet.getRangeByIndex(row + 2, col + 1);

            if (key.toLowerCase().contains('image') && value is String && value.isNotEmpty) {
              try {
                final response = await http.get(Uri.parse(value));
                if (response.statusCode == 200) {
                  final bytes = response.bodyBytes;
                  final picture = sheet.pictures.addStream(row + 2, col + 1, bytes);
                  picture.height = 80;
                  picture.width = 80;
                  sheet.getRangeByIndex(row + 2, col + 1).rowHeight = 60;
                  sheet.getRangeByIndex(1, col + 1).columnWidth = 15;
                } else {
                  cell.setText('Image not found');
                }
              } catch (e) {
                cell.setText('Error loading image');
              }
            } else if (key == 'locationString') {
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
          // Update progress after each row
          processedRows++;
          double newProgress = processedRows / totalRows;
          _progressController.stop();
          _progressAnimation = Tween<double>(begin: progress, end: newProgress).animate(
            CurvedAnimation(parent: _progressController, curve: Curves.easeInOutCubic),
          );
          _progressController
            ..reset()
            ..forward();
          setState(() {
            progress = newProgress;
          });
          await Future.delayed(const Duration(milliseconds: 8)); // Smooth animation
        }

        for (int i = 0; i < orderedKeys.length; i++) {
          if (!orderedKeys[i].toLowerCase().contains('image')) {
            sheet.autoFitColumn(i + 1);
          }
        }
      }
      sheetIndex++;
    }

    final bytes = workbook.saveAsStream();
    workbook.dispose();

    // --- File name as "Report <DATE RANGE> <BRANCH>.xlsx" ---
    String formatDate(DateTime? d) =>
        d == null ? 'All' : DateFormat('dd-MM-yyyy').format(d);
    String branchName = (selectedBranch == null || selectedBranch == 'Select All')
        ? 'All Branches'
        : selectedBranch!.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    String dateRange = "${formatDate(startDate)}-${formatDate(endDate)}";
    final dir = await getApplicationDocumentsDirectory();
    final file = File(
        "${dir.path}/Report $dateRange $branchName.xlsx");
    await file.writeAsBytes(bytes, flush: true);

    return file;
  }

  Future<void> _generateAndShareSyncfusionReport() async {
    setState(() {
      isLoading = true;
      progress = 0.0;
    });
    _progressController.value = 0;
    final data = await _fetchReportData();
    final file = await _generateSyncfusionExcel(data);
    setState(() {
      isLoading = false;
      progress = 0.0;
    });
    await Share.shareXFiles([XFile(file.path)], text: "Marketing Report");
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
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    "Generating Report...",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 32),
                  Container(
                    width: 300,
                    height: 24,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: Colors.grey[300],
                      boxShadow: [
                        BoxShadow(
                          color: Colors.green.withOpacity(0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Stack(
                        children: [
                          // Gradient progress bar
                          AnimatedBuilder(
                            animation: _progressAnimation,
                            builder: (context, child) => FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: _progressAnimation.value,
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.greenAccent.shade400,
                                      Colors.green.shade700,
                                      Colors.lightGreenAccent.shade100,
                                    ],
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // Liquid shimmer overlay
                          AnimatedBuilder(
                            animation: _progressAnimation,
                            builder: (context, child) {
                              return FractionallySizedBox(
                                alignment: Alignment.centerLeft,
                                widthFactor: _progressAnimation.value,
                                child: ShaderMask(
                                  shaderCallback: (Rect bounds) {
                                    return LinearGradient(
                                      colors: [
                                       Colors.greenAccent.shade400,
                                      Colors.green.shade700,
                                      Colors.lightGreenAccent.shade100,
                                      ],
                                      stops: const [0.0, 0.5, 1.0],
                                      begin: Alignment(-1.0 + 2.0 * (_progressController.value), 0),
                                      end: Alignment(1.0 + 2.0 * (_progressController.value), 0),
                                      tileMode: TileMode.mirror,
                                    ).createShader(bounds);
                                  },
                                  blendMode: BlendMode.srcATop,
                                  child: Container(
                                    color: Colors.white,
                                  ),
                                ),
                              );
                            },
                          ),
                          // Progress text overlay (optional)
                          Center(
                            child: AnimatedBuilder(
                              animation: _progressAnimation,
                              builder: (context, child) => Text(
                                "${(_progressAnimation.value * 100).toStringAsFixed(0)}%",
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  shadows: [
                                    Shadow(
                                      blurRadius: 4,
                                      color: Colors.black26,
                                      offset: Offset(0, 1),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            )
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
                                      ? DateFormat('dd-MM-yyyy').format(startDate!)
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
                                      ? DateFormat('dd-MM-yyyy').format(endDate!)
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
                          label: const Text("Download Report"),
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
