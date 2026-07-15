import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

Future<void> generateBookingReport({
  required String selectedItem,
  required List<String> activeBranches,
}) async {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  // Fire all branch queries in parallel instead of sequentially
  final results = await Future.wait(
    activeBranches.map((branch) => firestore
        .collection('supersale_user_entries')
        .doc(branch)
        .collection(selectedItem)
        .get()),
  );

  final List<Map<String, dynamic>> branchDataList = [];

  for (int i = 0; i < activeBranches.length; i++) {
    final branch = activeBranches[i];
    final docs = results[i].docs;

    double totalQty = 0;
    double totalAmt = 0;
    double totalAdvance = 0;

    for (var doc in docs) {
      final data = doc.data();
      final double qty = (data['quantity'] ?? 0).toDouble();
      final double rate = (data['rate'] ?? 0).toDouble();
      final double advance = (data['advance'] ?? 0).toDouble();

      totalQty += qty;
      totalAmt += qty * rate;
      totalAdvance += advance;
    }

    if (totalQty > 0) {
      branchDataList.add({
        'branch': branch,
        'qty': totalQty,
        'amount': totalAmt,
        'advance': totalAdvance,
      });
    }
  }

  // Sort by QTY descending
  branchDataList.sort((a, b) => b['qty'].compareTo(a['qty']));

  // Build Excel
  final xlsio.Workbook workbook = xlsio.Workbook();
  final xlsio.Worksheet sheet = workbook.worksheets[0];
  sheet.name = 'Booking Summary';

  // Title — item name in BOLD CAPS, centered, merged across 4 columns
  sheet.getRangeByIndex(1, 1).setText(selectedItem.toUpperCase());
  sheet.getRangeByIndex(1, 1).cellStyle.bold = true;
  sheet.getRangeByIndex(1, 1).cellStyle.fontSize = 14;
  sheet.getRangeByIndex(1, 1).cellStyle.hAlign = xlsio.HAlignType.center;
  sheet.getRangeByIndex(1, 1, 1, 4).merge();

  // Headers
  const headers = ['BRANCH', 'QTY', 'TOTAL AMOUNT', 'TOTAL ADVANCE'];
  for (int i = 0; i < headers.length; i++) {
    sheet.getRangeByIndex(3, i + 1).setText(headers[i]);
    sheet.getRangeByIndex(3, i + 1).cellStyle.bold = true;
    sheet.getRangeByIndex(3, i + 1).cellStyle.backColor = '#D9E1F2';
  }

  int rowIndex = 4;
  double grandTotalQty = 0;
  double grandTotalAmount = 0;
  double grandTotalAdvance = 0;

  for (var row in branchDataList) {
    sheet.getRangeByIndex(rowIndex, 1).setText(row['branch']);
    sheet.getRangeByIndex(rowIndex, 2).setNumber(row['qty']);
    sheet.getRangeByIndex(rowIndex, 3).setNumber(row['amount']);
    sheet.getRangeByIndex(rowIndex, 4).setNumber(row['advance']);

    grandTotalQty += row['qty'];
    grandTotalAmount += row['amount'];
    grandTotalAdvance += row['advance'];
    rowIndex++;
  }

  // Total row
  sheet.getRangeByIndex(rowIndex, 1).setText('TOTAL');
  sheet.getRangeByIndex(rowIndex, 1).cellStyle.bold = true;
  sheet.getRangeByIndex(rowIndex, 2).setNumber(grandTotalQty);
  sheet.getRangeByIndex(rowIndex, 2).cellStyle.bold = true;
  sheet.getRangeByIndex(rowIndex, 3).setNumber(grandTotalAmount);
  sheet.getRangeByIndex(rowIndex, 3).cellStyle.bold = true;
  sheet.getRangeByIndex(rowIndex, 4).setNumber(grandTotalAdvance);
  sheet.getRangeByIndex(rowIndex, 4).cellStyle.bold = true;

  for (int i = 1; i <= headers.length; i++) {
    sheet.autoFitColumn(i);
  }

  final List<int> bytes = workbook.saveAsStream();
  workbook.dispose();

  final Directory directory = await getTemporaryDirectory();
  final String cleanItem = selectedItem.replaceAll(RegExp(r'[^\w\s\-]'), '_');
  final String path =
      '${directory.path}/${cleanItem}_Booking_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';
  final File file = File(path);
  await file.writeAsBytes(bytes, flush: true);

  await Share.shareXFiles([XFile(path)], text: '$selectedItem Booking Report');
}
