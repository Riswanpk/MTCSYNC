import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as syncfusion;
import 'package:cloud_functions/cloud_functions.dart';

class CustomerTargetExportPage extends StatefulWidget {
  const CustomerTargetExportPage({super.key});

  @override
  State<CustomerTargetExportPage> createState() => _CustomerTargetExportPageState();
}

class _CustomerTargetExportPageState extends State<CustomerTargetExportPage> {
  String? _selectedMonthYear;
  bool _loading = false;
  String? _error;

  final List<String> _monthYears = List.generate(
    12,
    (i) {
      final now = DateTime.now();
      final date = DateTime(now.year, now.month - i, 1);
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return "${months[date.month - 1]} ${date.year}";
    },
  );

  @override
  void initState() {
    super.initState();
    _selectedMonthYear = _monthYears.first;
  }

  Future<void> _exportExcel() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final workbook = syncfusion.Workbook();

      // Fetch username map from users collection
      final usersCollSnapshot = await FirebaseFirestore.instance.collection('users').get();
      final Map<String, String> emailToUsername = {};
      for (final doc in usersCollSnapshot.docs) {
        final email = (doc.data()['email'] as String? ?? '').toLowerCase();
        final username = doc.data()['username'] as String? ?? '';
        if (email.isNotEmpty) emailToUsername[email] = username;
      }

      final usersSnapshot = await FirebaseFirestore.instance
          .collection('customer_target')
          .doc(_selectedMonthYear)
          .collection('users')
          .get();

      // Group users by branch and then by user email, keeping customers per user
      final Map<String, Map<String, List<Map<String, dynamic>>>> branchUserMap = {};
      for (final doc in usersSnapshot.docs) {
        final data = doc.data();
        final branch = data['branch'] ?? 'Unknown';
        final userEmail = (data['user'] ?? doc.id).toString().toLowerCase();
        final customers = (data['customers'] as List<dynamic>? ?? [])
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        branchUserMap.putIfAbsent(branch, () => {});
        branchUserMap[branch]!.putIfAbsent(userEmail, () => []);
        branchUserMap[branch]![userEmail]!.addAll(customers);
      }

      // For each branch, create a sheet
      int sheetIndex = 0;
      for (final branch in branchUserMap.keys) {
        final sheet = sheetIndex == 0
            ? workbook.worksheets[0]
            : workbook.worksheets.addWithName(branch);
        sheet.name = branch;
        int row = 1;
        for (final userEmail in branchUserMap[branch]!.keys) {
          final customers = List<Map<String, dynamic>>.from(branchUserMap[branch]![userEmail]!);
          // Sort: Called first, Not Called second
          customers.sort((a, b) =>
              (b['callMade'] == true ? 1 : 0) - (a['callMade'] == true ? 1 : 0));

          final username = emailToUsername[userEmail] ?? userEmail;
          final calledCount = customers.where((c) => c['callMade'] == true).length;
          final totalCount = customers.length;

          // --- Username header row ---
          final userRange = sheet.getRangeByName('A$row:C$row');
          userRange.merge();
          userRange.setText(username);
          userRange.cellStyle.bold = true;
          userRange.cellStyle.backColor = '#005BAC';
          userRange.cellStyle.fontColor = '#FFFFFF';
          userRange.cellStyle.fontSize = 12;
          userRange.cellStyle.borders.all.lineStyle = syncfusion.LineStyle.thin;
          userRange.cellStyle.borders.all.color = '#CCCCCC';
          row++;

          // --- Called progress row ---
          final progressRange = sheet.getRangeByName('A$row:C$row');
          progressRange.merge();
          progressRange.setText('Customers Called: $calledCount / $totalCount');
          progressRange.cellStyle.bold = true;
          progressRange.cellStyle.backColor = '#E8F5E9';
          progressRange.cellStyle.fontColor = '#1B5E20';
          progressRange.cellStyle.borders.all.lineStyle = syncfusion.LineStyle.thin;
          progressRange.cellStyle.borders.all.color = '#CCCCCC';
          row++;

          // --- Table column headers ---
          void applyHeaderStyle(syncfusion.Range r) {
            r.cellStyle.bold = true;
            r.cellStyle.backColor = '#37474F';
            r.cellStyle.fontColor = '#FFFFFF';
            r.cellStyle.borders.all.lineStyle = syncfusion.LineStyle.thin;
            r.cellStyle.borders.all.color = '#CCCCCC';
          }
          final hA = sheet.getRangeByName('A$row');
          final hB = sheet.getRangeByName('B$row');
          final hC = sheet.getRangeByName('C$row');
          hA.setText('Customer Name');
          hB.setText('Remarks');
          hC.setText('Call Status');
          applyHeaderStyle(hA);
          applyHeaderStyle(hB);
          applyHeaderStyle(hC);
          row++;

          // --- Customer data rows ---
          for (final customer in customers) {
            final isCalled = customer['callMade'] == true;
            final cellA = sheet.getRangeByName('A$row');
            final cellB = sheet.getRangeByName('B$row');
            final cellC = sheet.getRangeByName('C$row');

            cellA.setText(customer['name'] ?? '');
            cellB.setText(customer['remarks'] ?? '');
            cellC.setText(isCalled ? 'Called' : 'Not Called');

            // Cell borders
            for (final cell in [cellA, cellB, cellC]) {
              cell.cellStyle.borders.all.lineStyle = syncfusion.LineStyle.thin;
              cell.cellStyle.borders.all.color = '#CCCCCC';
            }

            // Call Status colouring
            if (isCalled) {
              cellC.cellStyle.backColor = '#4CAF50';
              cellC.cellStyle.fontColor = '#FFFFFF';
              cellC.cellStyle.bold = true;
            } else {
              cellC.cellStyle.backColor = '#F44336';
              cellC.cellStyle.fontColor = '#FFFFFF';
              cellC.cellStyle.bold = true;
            }
            row++;
          }
          row++; // Empty row between users
        }
        // --- Autofit columns after filling data ---
        sheet.autoFitColumn(1);
        sheet.autoFitColumn(2);
        sheet.autoFitColumn(3);
        sheetIndex++;
      }

      final List<int> bytes = workbook.saveAsStream();
      workbook.dispose();

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/CustomerTarget_${_selectedMonthYear!.replaceAll(' ', '_')}.xlsx');
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles([XFile(file.path)], text: 'Customer Target $_selectedMonthYear');
    } catch (e) {
      setState(() {
        _error = 'Export failed: $e';
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> triggerCustomerTargetExport(String monthYear, String fileMonth) async {
    final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable('exportCustomerTargetIndividualReport');
    final result = await callable.call({'monthYear': monthYear, 'fileMonth': fileMonth});
    // Handle result (e.g., show a dialog with the download link)
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Export Customer Target'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              value: _selectedMonthYear,
              items: _monthYears
                  .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                  .toList(),
              onChanged: (val) => setState(() => _selectedMonthYear = val),
              decoration: const InputDecoration(labelText: 'Select Month'),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: const Icon(Icons.download),
              label: const Text('Export as Excel'),
              onPressed: _loading ? null : _exportExcel,
            ),
            if (_loading) const Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
            if (_error != null) Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
  }
}