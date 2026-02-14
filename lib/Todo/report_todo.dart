import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';

class ReportTodoPage extends StatefulWidget {
  const ReportTodoPage({super.key});

  @override
  State<ReportTodoPage> createState() => _ReportTodoPageState();
}

class _ReportTodoPageState extends State<ReportTodoPage> {
  List<String> _branches = [];
  String? _selectedBranch;
  DateTime? _startDate;
  DateTime? _endDate;
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    _fetchBranches();
    // Default to the current month
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, 1);
    _endDate = DateTime(now.year, now.month + 1, 0);
  }

  Future<void> _fetchBranches() async {
    final snapshot = await FirebaseFirestore.instance.collection('users').get();
    final branches = snapshot.docs
        .map((doc) => doc.data()['branch'] as String?)
        .where((branch) => branch != null)
        .toSet()
        .cast<String>() .toList();
    setState(() {
      _branches = branches;
    });
  }

  Future<void> _generateReport() async {
    if (_selectedBranch == null || _startDate == null || _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a branch and date range.')),
      );
      return;
    }
    if (_startDate!.isAfter(_endDate!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a branch first.')),
      );
      return;
    }

    setState(() => _isGenerating = true);

    try {
      // 1. Fetch users for the selected branch
      final usersSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('branch', isEqualTo: _selectedBranch)
          .get();

      final users = usersSnapshot.docs.map((doc) {
        return {'id': doc.id, 'username': doc.data()['username'] ?? 'Unknown'};
      }).toList();

      // 2. Create an Excel workbook
      final xlsio.Workbook workbook = xlsio.Workbook();
      // Create the header style once, outside the loop
      final xlsio.Style headerStyle = workbook.styles.add('headerStyle');
      headerStyle.bold = true;
      headerStyle.fontSize = 12;

      // 3. For each user, create a sheet and add their todos
      for (var user in users) {
        final String userId = user['id'];
        final String username = user['username'];

        final xlsio.Worksheet sheet = workbook.worksheets.addWithName(username);
        sheet.showGridlines = true;

        // Add headers
        sheet.getRangeByName('A1').setText('Date Created');
        sheet.getRangeByName('B1').setText('Title');
        sheet.getRangeByName('C1').setText('Description');
        sheet.getRangeByName('A1:C1').cellStyle = headerStyle;

        // Fetch todos for this user
        final endOfDay = DateTime(_endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59);
        final todosSnapshot = await FirebaseFirestore.instance //
            .collection('todo')
            .where('created_by', isEqualTo: userId)
            .where('timestamp', isGreaterThanOrEqualTo: _startDate)
            .where('timestamp', isLessThanOrEqualTo: endOfDay)
            .get();

        int rowIndex = 2;
        for (var todoDoc in todosSnapshot.docs) {
          final todoData = todoDoc.data();
          final timestamp = todoData['timestamp'] as Timestamp?;
          final dateCreated = timestamp != null ? DateFormat('yyyy-MM-dd').format(timestamp.toDate()) : 'N/A';

          sheet.getRangeByName('A$rowIndex').setText(dateCreated);
          sheet.getRangeByName('B$rowIndex').setText(todoData['title'] ?? '');
          sheet.getRangeByName('C$rowIndex').setText(todoData['description'] ?? '');
          rowIndex++;
        }

        // Auto-fit columns
        sheet.getRangeByName('A1').columnWidth = 30;
        sheet.getRangeByName('B1').columnWidth = 50;
      }

      // 4. Save the file
      final List<int> bytes = workbook.saveAsStream();
      workbook.dispose();

      final directory = await getTemporaryDirectory();
      final path = directory.path;
      final String fileName = '$path/Todo_Report_$_selectedBranch.xlsx';
      final File file = File(fileName);
      await file.writeAsBytes(bytes, flush: true);

      // 5. Share the file
      await Share.shareXFiles([XFile(fileName)], text: 'To-Do Report for $_selectedBranch');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to generate report: $e')),
      );
    } finally {
      setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('To-Do Report'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              value: _selectedBranch,
              hint: const Text('Select a Branch'),
              items: _branches.map((String branch) {
                return DropdownMenuItem<String>(
                  value: branch,
                  child: Text(branch),
                );
              }).toList(),
              onChanged: (newValue) {
                setState(() {
                  _selectedBranch = newValue;
                });
              },
              decoration: const InputDecoration(
                labelText: 'Branch',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _startDate ?? DateTime.now(),
                        firstDate: DateTime(2022),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) setState(() => _startDate = picked);
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Start Date',
                        border: OutlineInputBorder(),
                      ),
                      child: Text(
                        _startDate != null ? DateFormat('dd-MM-yyyy').format(_startDate!) : 'Select',
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _endDate ?? DateTime.now(),
                        firstDate: DateTime(2022),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) setState(() => _endDate = picked);
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'End Date',
                        border: OutlineInputBorder(),
                      ),
                      child: Text(
                        _endDate != null ? DateFormat('dd-MM-yyyy').format(_endDate!) : 'Select',
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              onPressed: _isGenerating ? null : _generateReport,
              icon: _isGenerating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.download_rounded),
              label: Text(_isGenerating ? 'Generating...' : 'Generate Excel Report'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8CC63F), // primaryGreen
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}