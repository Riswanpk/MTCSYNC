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
      final usersSnapshot = await FirebaseFirestore.instance
          .collection('customer_target')
          .doc(_selectedMonthYear)
          .collection('users')
          .get();

      // Group users by branch and then by user
      final Map<String, Map<String, List<Map<String, dynamic>>>> branchUserMap = {};
      for (final doc in usersSnapshot.docs) {
        final data = doc.data();
        final branch = data['branch'] ?? 'Unknown';
        final user = data['user'] ?? doc.id;
        final customers = (data['customers'] as List<dynamic>? ?? [])
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        branchUserMap.putIfAbsent(branch, () => {});
        branchUserMap[branch]!.putIfAbsent(user, () => []);
        branchUserMap[branch]![user]!.addAll(customers);
      }

      // For each branch, create a sheet
      int sheetIndex = 0;
      for (final branch in branchUserMap.keys) {
        final sheet = sheetIndex == 0
            ? workbook.worksheets[0]
            : workbook.worksheets.addWithName(branch);
        sheet.name = branch;
        int row = 1;
        for (final user in branchUserMap[branch]!.keys) {
          // User header
          sheet.getRangeByName('A$row').setText(user);
          sheet.getRangeByName('A$row').cellStyle.bold = true;
          row++;
          // Table header
          sheet.getRangeByName('A$row').setText('Customer Name');
          sheet.getRangeByName('B$row').setText('Remarks');
          sheet.getRangeByName('C$row').setText('Call Status');
          sheet.getRangeByName('A$row').cellStyle.bold = true;
          sheet.getRangeByName('B$row').cellStyle.bold = true;
          sheet.getRangeByName('C$row').cellStyle.bold = true;
          row++;
          // Customer rows
          for (final customer in branchUserMap[branch]![user]!) {
            sheet.getRangeByName('A$row').setText(customer['name'] ?? '');
            sheet.getRangeByName('B$row').setText(customer['remarks'] ?? '');
            sheet.getRangeByName('C$row').setText(customer['callMade'] == true ? 'Called' : 'Not Called');
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