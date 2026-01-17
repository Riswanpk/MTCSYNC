import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

class TodoLeadsFullMonthPage extends StatefulWidget {
  const TodoLeadsFullMonthPage({super.key});

  @override
  State<TodoLeadsFullMonthPage> createState() => _TodoLeadsFullMonthPageState();
}

class _TodoLeadsFullMonthPageState extends State<TodoLeadsFullMonthPage> {
  DateTime? _selectedDate;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2023, 1, 1),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _generateAndShareReport() async {
    if (_selectedDate == null) return;
    setState(() => _loading = true);

    final today = DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day);

    // Calculate interval (same as JS logic)
    DateTime start, end, reportDate;
    if (today.weekday == DateTime.monday) {
      start = today.subtract(const Duration(days: 2)).add(const Duration(hours: 12)); // Saturday 12 PM
      reportDate = today;
    } else {
      start = today.subtract(const Duration(days: 1)).add(const Duration(hours: 12)); // Previous day 12 PM
      reportDate = today;
    }
    end = today.add(const Duration(hours: 12)); // Today 12 PM

    // Fetch all users except admin
    final usersSnap = await FirebaseFirestore.instance
        .collection('users')
        .where('role', isNotEqualTo: 'admin')
        .get();
    final userMap = <String, Map<String, dynamic>>{};
    final emailToUserId = <String, String>{};
    for (var doc in usersSnap.docs) {
      userMap[doc.id] = doc.data();
      final email = doc['email'];
      if (email != null) {
        emailToUserId[email] = doc.id;
      }
    }

    // Prepare user status per branch
    final branchUserStatus = <String, Map<String, Map<String, bool>>>{};
    for (final userId in userMap.keys) {
      final user = userMap[userId]!;
      final branch = user['branch'] ?? 'Unknown';
      branchUserStatus[branch] ??= {};
      branchUserStatus[branch]![userId] = {'lead': false, 'todo': false};
    }

    // --- Optimization: Batch fetch daily_report for all users in interval ---
    final dailyReportSnap = await FirebaseFirestore.instance
        .collection('daily_report')
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('timestamp', isLessThan: Timestamp.fromDate(end))
        .get();

    // Map userId to lead/todo status
    for (final doc in dailyReportSnap.docs) {
      final data = doc.data();
      final userId = data['userId'];
      final type = data['type'];
      if (userId == null || type == null) continue;
      // Only process users in userMap
      if (!userMap.containsKey(userId)) continue;
      final branch = userMap[userId]?['branch'] ?? 'Unknown';
      if (!branchUserStatus.containsKey(branch)) continue;
      if (!branchUserStatus[branch]!.containsKey(userId)) continue;
      if (type == 'leads') {
        branchUserStatus[branch]![userId]!['lead'] = true;
      } else if (type == 'todo') {
        branchUserStatus[branch]![userId]!['todo'] = true;
      }
    }

    // --- Optimization: Batch fetch todos for all users in interval ---
    final todosSnap = await FirebaseFirestore.instance
        .collection('todo')
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('timestamp', isLessThan: Timestamp.fromDate(end))
        .get();

    // Map userId to todos
    final todosByUser = <String, List<Map<String, dynamic>>>{};
    for (final doc in todosSnap.docs) {
      final data = doc.data();
      final email = data['email'];
      if (email == null) continue;
      final userId = emailToUserId[email];
      if (userId == null) continue;
      todosByUser[userId] ??= [];
      todosByUser[userId]!.add(data);
    }

    // Generate Excel using Syncfusion
    final workbook = xlsio.Workbook();
    int _branchIndex = 0;
    for (final branch in branchUserStatus.keys) {
      xlsio.Worksheet sheet;
      if (_branchIndex == 0) {
        sheet = workbook.worksheets[0]; // default sheet
        sheet.name = branch;
      } else {
        sheet = workbook.worksheets.addWithName(branch);
      }
      _branchIndex++;

      // Summary table
      sheet.getRangeByIndex(1, 1).setText('Username');
      sheet.getRangeByIndex(1, 2).setText('Leads');
      sheet.getRangeByIndex(1, 3).setText('Todo');
      int row = 2;
      for (final userId in branchUserStatus[branch]!.keys) {
        final user = userMap[userId]!;
        sheet.getRangeByIndex(row, 1).setText(user['username'] ?? '');
        sheet.getRangeByIndex(row, 2).setText(branchUserStatus[branch]![userId]!['lead']! ? 'Yes' : 'No');
        sheet.getRangeByIndex(row, 3).setText(branchUserStatus[branch]![userId]!['todo']! ? 'Yes' : 'No');
        row++;
      }

      // Add borders to the summary table
      final tableRange = sheet.getRangeByName('A1:C${row - 1}');
      tableRange.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
    }
    // no need to remove default sheet anymore

    final List<int> bytes = workbook.saveAsStream();
    workbook.dispose();

    // Save to file and share
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/leads_todos_${reportDate.year}_${reportDate.month}_${reportDate.day}.xlsx');
    await file.writeAsBytes(bytes, flush: true);

    setState(() => _loading = false);

    await Share.shareXFiles([XFile(file.path)], text: 'Leads & Todo Report');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Download Leads & Todo Report'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _selectedDate == null
                      ? 'Select Date'
                      : 'Selected: ${_selectedDate!.day}-${_selectedDate!.month}-${_selectedDate!.year}',
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  icon: const Icon(Icons.calendar_today),
                  label: const Text('Pick Date'),
                  onPressed: _pickDate,
                ),
              ],
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              icon: const Icon(Icons.download),
              label: const Text('Download & Share Report'),
              onPressed: _loading ? null : _generateAndShareReport,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF005BAC),
                foregroundColor: Colors.white,
                minimumSize: const Size(220, 48),
              ),
            ),
            if (_loading) ...[
              const SizedBox(height: 32),
              const CircularProgressIndicator(),
            ]
          ],
        ),
      ),
    );
  }
}
