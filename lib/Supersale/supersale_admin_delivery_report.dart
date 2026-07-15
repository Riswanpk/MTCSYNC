import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

Future<void> generateDeliveryReport({
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

    double totalBooking = 0;
    double totalDelivered = 0;

    for (var doc in docs) {
      final data = doc.data();
      final double qty = (data['quantity'] ?? 0).toDouble();
      final String status = data['status']?.toString() ?? 'pending';

      totalBooking += qty;
      if (status == 'delivered') {
        totalDelivered += qty;
      }
    }

    if (totalBooking > 0) {
      final double pending = totalBooking - totalDelivered;
      branchDataList.add({
        'branch': branch,
        'totalBooking': totalBooking,
        'totalDelivered': totalDelivered,
        'pending': pending,
      });
    }
  }

  // Sort by PENDING descending (matching reference image)
  branchDataList.sort((a, b) => b['pending'].compareTo(a['pending']));

  // Build Excel
  final xlsio.Workbook workbook = xlsio.Workbook();
  final xlsio.Worksheet sheet = workbook.worksheets[0];
  sheet.name = 'Delivery Summary';

  // Title — item name in BOLD CAPS, centered, merged across 4 columns
  sheet.getRangeByIndex(1, 1).setText(selectedItem.toUpperCase());
  sheet.getRangeByIndex(1, 1).cellStyle.bold = true;
  sheet.getRangeByIndex(1, 1).cellStyle.fontSize = 14;
  sheet.getRangeByIndex(1, 1).cellStyle.hAlign = xlsio.HAlignType.center;
  sheet.getRangeByIndex(1, 1, 1, 4).merge();

  // Headers
  const headers = ['BRANCHES', 'TOTAL BOOKING', 'TOTAL DELIVERED', 'PENDING'];
  for (int i = 0; i < headers.length; i++) {
    sheet.getRangeByIndex(3, i + 1).setText(headers[i]);
    sheet.getRangeByIndex(3, i + 1).cellStyle.bold = true;
    sheet.getRangeByIndex(3, i + 1).cellStyle.backColor = '#D9E1F2';
    sheet.getRangeByIndex(3, i + 1).cellStyle.hAlign = xlsio.HAlignType.center;
  }

  int rowIndex = 4;
  double grandTotalBooking = 0;
  double grandTotalDelivered = 0;
  double grandTotalPending = 0;

  for (var row in branchDataList) {
    sheet.getRangeByIndex(rowIndex, 1).setText(row['branch']);
    sheet.getRangeByIndex(rowIndex, 2).setNumber(row['totalBooking']);
    sheet.getRangeByIndex(rowIndex, 3).setNumber(row['totalDelivered']);
    sheet.getRangeByIndex(rowIndex, 4).setNumber(row['pending']);

    grandTotalBooking += row['totalBooking'];
    grandTotalDelivered += row['totalDelivered'];
    grandTotalPending += row['pending'];
    rowIndex++;
  }

  // Total row
  sheet.getRangeByIndex(rowIndex, 1).setText('TOTAL');
  sheet.getRangeByIndex(rowIndex, 1).cellStyle.bold = true;
  sheet.getRangeByIndex(rowIndex, 2).setNumber(grandTotalBooking);
  sheet.getRangeByIndex(rowIndex, 2).cellStyle.bold = true;
  sheet.getRangeByIndex(rowIndex, 3).setNumber(grandTotalDelivered);
  sheet.getRangeByIndex(rowIndex, 3).cellStyle.bold = true;
  sheet.getRangeByIndex(rowIndex, 4).setNumber(grandTotalPending);
  sheet.getRangeByIndex(rowIndex, 4).cellStyle.bold = true;

  for (int i = 1; i <= headers.length; i++) {
    sheet.autoFitColumn(i);
  }

  final List<int> bytes = workbook.saveAsStream();
  workbook.dispose();

  final Directory directory = await getTemporaryDirectory();
  final String cleanItem = selectedItem.replaceAll(RegExp(r'[^\w\s\-]'), '_');
  final String path =
      '${directory.path}/${cleanItem}_Delivery_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';
  final File file = File(path);
  await file.writeAsBytes(bytes, flush: true);

  await Share.shareXFiles([XFile(path)], text: '$selectedItem Delivery Report');
}
