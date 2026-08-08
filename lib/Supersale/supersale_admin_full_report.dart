import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

Future<void> generateFullReport({
  required String selectedItem,
  required List<String> activeBranches,
}) async {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  // Fire all branch queries in parallel
  final results = await Future.wait(
    activeBranches.map((branch) => firestore
        .collection('supersale_user_entries')
        .doc(branch)
        .collection(selectedItem)
        .get()),
  );

  final xlsio.Workbook workbook = xlsio.Workbook();
  bool isFirstSheetCreated = false;

  final DateFormat dateFormat = DateFormat('yyyy-MM-dd HH:mm');

  for (int i = 0; i < activeBranches.length; i++) {
    final branch = activeBranches[i];
    final docs = results[i].docs;

    if (docs.isEmpty) continue;

    // Group entries by username
    final Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>> userGroups = {};
    for (var doc in docs) {
      final data = doc.data();
      final String username = (data['username']?.toString().isNotEmpty == true)
          ? data['username'].toString()
          : (data['email']?.toString() ?? 'Unknown User');
      
      userGroups.putIfAbsent(username, () => []).add(doc);
    }

    xlsio.Worksheet sheet;
    if (!isFirstSheetCreated) {
      sheet = workbook.worksheets[0];
      sheet.name = branch;
      isFirstSheetCreated = true;
    } else {
      sheet = workbook.worksheets.addWithName(branch);
    }

    // Row 1: Header - Supersale Item & Branch
    sheet.getRangeByIndex(1, 1).setText('SUPERSALE: ${selectedItem.toUpperCase()}');
    sheet.getRangeByIndex(1, 1).cellStyle.bold = true;
    sheet.getRangeByIndex(1, 1).cellStyle.fontSize = 14;

    sheet.getRangeByIndex(1, 6).setText('BRANCH: $branch');
    sheet.getRangeByIndex(1, 6).cellStyle.bold = true;
    sheet.getRangeByIndex(1, 6).cellStyle.fontSize = 14;

    int currentRow = 3;

    final headers = [
      'Sl.No',
      'Customer Name',
      'Phone No.',
      'Quantity',
      'Rate',
      'Source',
      'Booked Date',
      'Deliver Date',
      'Delivery Status',
    ];

    // Iterate through each username group
    userGroups.forEach((username, userDocs) {
      // Username heading right above table
      sheet.getRangeByIndex(currentRow, 1).setText('USER: $username');
      sheet.getRangeByIndex(currentRow, 1).cellStyle.bold = true;
      sheet.getRangeByIndex(currentRow, 1).cellStyle.fontSize = 12;
      sheet.getRangeByIndex(currentRow, 1).cellStyle.fontColor = '#005BAC';
      currentRow++;

      // Table Headers
      for (int col = 0; col < headers.length; col++) {
        final cell = sheet.getRangeByIndex(currentRow, col + 1);
        cell.setText(headers[col]);
        cell.cellStyle.bold = true;
        cell.cellStyle.backColor = '#D9E1F2';
        cell.cellStyle.hAlign = xlsio.HAlignType.center;
      }
      currentRow++;

      // Populate user rows
      int slNo = 1;
      for (var doc in userDocs) {
        final data = doc.data();

        final String customerName = data['customerName']?.toString() ?? '';
        final String phone = data['phone']?.toString() ?? '';
        final double quantity = (data['quantity'] ?? 0).toDouble();
        final double rate = (data['rate'] ?? 0).toDouble();

        // Source: Spot Sale vs Normal Booking
        final bool isSpotSale = data['isSpotSale'] == true || data['saleType'] == 'spot_sale';
        final String sourceStr = isSpotSale ? 'Spot Sale' : 'Booking';

        final Timestamp? createdAtTs = data['created_at'] as Timestamp?;
        final String bookedDate = createdAtTs != null
            ? dateFormat.format(createdAtTs.toDate())
            : '';

        final Timestamp? deliveryEndTs = data['deliveryEnd'] as Timestamp?;
        final String deliverDate = deliveryEndTs != null
            ? dateFormat.format(deliveryEndTs.toDate())
            : '';

        final String rawStatus = data['status']?.toString() ?? 'pending';
        final bool isDelivered = rawStatus.toLowerCase() == 'delivered';
        final String deliveryStatus = isDelivered ? 'Delivered' : 'Pending';

        sheet.getRangeByIndex(currentRow, 1).setNumber(slNo.toDouble());
        sheet.getRangeByIndex(currentRow, 2).setText(customerName);
        sheet.getRangeByIndex(currentRow, 3).setText(phone);
        sheet.getRangeByIndex(currentRow, 4).setNumber(quantity);
        sheet.getRangeByIndex(currentRow, 5).setNumber(rate);
        sheet.getRangeByIndex(currentRow, 6).setText(sourceStr);
        sheet.getRangeByIndex(currentRow, 7).setText(bookedDate);
        sheet.getRangeByIndex(currentRow, 8).setText(deliverDate);
        sheet.getRangeByIndex(currentRow, 9).setText(deliveryStatus);

        // Highlight non-delivered rows in yellow
        if (!isDelivered) {
          for (int col = 1; col <= headers.length; col++) {
            sheet.getRangeByIndex(currentRow, col).cellStyle.backColor = '#FFFF00';
          }
        }

        slNo++;
        currentRow++;
      }

      // Leave a gap of 2 empty rows after each table
      currentRow += 2;
    });

    // Auto-fit columns for this sheet
    for (int col = 1; col <= headers.length; col++) {
      sheet.autoFitColumn(col);
    }
  }

  // If no branches had any data
  if (!isFirstSheetCreated) {
    final sheet = workbook.worksheets[0];
    sheet.name = selectedItem;
    sheet.getRangeByIndex(1, 1).setText('No bookings found for $selectedItem');
  }

  final List<int> bytes = workbook.saveAsStream();
  workbook.dispose();

  final Directory directory = await getTemporaryDirectory();
  final String cleanItem = selectedItem.replaceAll(RegExp(r'[^\w\s\-]'), '_');
  final String path =
      '${directory.path}/${cleanItem}_Full_Report_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';
  final File file = File(path);
  await file.writeAsBytes(bytes, flush: true);

  await Share.shareXFiles([XFile(path)], text: '$selectedItem Full Report');
}
