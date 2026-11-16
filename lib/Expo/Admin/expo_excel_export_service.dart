import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

import '../expo_service.dart';

/// Generates and shares a detailed Excel (.xlsx) report of all orders
/// for a given [Exhibition].
class ExpoExcelExportService {
  ExpoExcelExportService._();

  static const List<String> _headers = [
    'Sl. No',
    'Bill No.',
    'Order Date',
    'Order Type',
    'Verification Status',
    'Shop Name',
    'Customer Name',
    'Phone',
    'Place',
    'District',
    'State',
    'Preferred Branch',
    'Preferred Salesman',
    'Booked By',
    'MTC Code',
    'Item Name',
    'Description',
    'Qty',
    'Rate',
    'GST %',
    'GST Type',
    'Item Total',
    'Order Subtotal',
    'Order GST',
    'Grand Total',
    'Advance Paid',
    'Pickup Paid',
    'Balance Due',
    'Payment Mode',
    'Cash Amount',
    'Online Amount',
    'Delivery / Pickup Date',
    'Stall Status',
    'Notes',
  ];

  static Future<void> exportExhibitionOrdersExcel(
    BuildContext context,
    Exhibition exhibition,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final orders =
        await ExpoService.instance.fetchOrdersForExhibition(exhibition.id);

    if (orders.isEmpty) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text('No orders found for "${exhibition.name}".'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final xlsio.Workbook workbook = xlsio.Workbook();
    final xlsio.Worksheet sheet = workbook.worksheets[0];
    sheet.name = 'Expo Orders';

    final DateFormat dtFmt = DateFormat('dd-MM-yyyy hh:mm a');
    final DateFormat dFmt = DateFormat('dd-MM-yyyy');

    // Row 1: Title Banner
    final titleRange = sheet.getRangeByIndex(1, 1, 1, _headers.length);
    titleRange.merge();
    titleRange.setText(
      'EXHIBITION: ${exhibition.name.toUpperCase()} (${exhibition.location})',
    );
    titleRange.cellStyle.bold = true;
    titleRange.cellStyle.fontSize = 14;
    titleRange.cellStyle.fontColor = '#005BAC';

    // Row 2: Subtitle
    final subRange = sheet.getRangeByIndex(2, 1, 2, _headers.length);
    subRange.merge();
    subRange.setText(
      'Duration: ${dFmt.format(exhibition.startDate.toLocal())} to ${dFmt.format(exhibition.endDate.toLocal())}   |   Total Orders: ${orders.length}',
    );
    subRange.cellStyle.fontSize = 11;
    subRange.cellStyle.fontColor = '#475569';

    // Row 4: Table Headers
    const int headerRow = 4;
    for (int col = 0; col < _headers.length; col++) {
      final cell = sheet.getRangeByIndex(headerRow, col + 1);
      cell.setText(_headers[col]);
      cell.cellStyle.bold = true;
      cell.cellStyle.backColor = '#005BAC';
      cell.cellStyle.fontColor = '#FFFFFF';
      cell.cellStyle.hAlign = xlsio.HAlignType.center;
      cell.cellStyle.vAlign = xlsio.VAlignType.center;
      cell.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
      cell.cellStyle.borders.all.color = '#CBD5E1';
    }
    sheet.getRangeByIndex(headerRow, 1).rowHeight = 24;

    int currentRow = headerRow + 1;
    int slNo = 1;

    for (final order in orders) {
      final String? rowBackColor;
      if (order.orderType == 'Spot Delivery') {
        rowBackColor = '#C6EFCE'; // Green highlight for Spot Delivery
      } else if (order.orderType == 'Stall Delivery') {
        rowBackColor = '#FFFF00'; // Yellow highlight for Stall Delivery
      } else {
        rowBackColor = null; // Default color for Booking
      }

      final String billNoStr =
          order.billNumber != null ? '#${order.billNumber}' : '-';
      final String orderDateStr = dtFmt.format(order.orderDate.toLocal());
      final String prefBranch = order.orderType == 'Spot Delivery'
          ? 'N/A'
          : (order.preferredBranch.isEmpty ? 'N/A' : order.preferredBranch);
      final String prefSalesman = order.orderType == 'Spot Delivery'
          ? 'N/A'
          : (order.preferredSalesman.isEmpty ? 'N/A' : order.preferredSalesman);
      final String bookedBy = order.createdUserBranch.isNotEmpty
          ? '${order.createdUserName} (${order.createdUserBranch})'
          : order.createdUserName;
      final String paymentModeDisplay = order.pickupPaymentMode != null &&
              order.pickupPaymentMode!.isNotEmpty
          ? '${ExpoOrder.normalizePaymentMode(order.paymentMode)} / Pickup: ${ExpoOrder.normalizePaymentMode(order.pickupPaymentMode)}'
          : ExpoOrder.normalizePaymentMode(order.paymentMode);
      final double totalCash = order.totalCashCollected;
      final double totalOnline =
          order.effectiveOnlineAmount + order.effectivePickupOnlineAmount;
      final String targetDateStr = order.deliveryDate != null
          ? dFmt.format(order.deliveryDate!.toLocal())
          : (order.stallPickupDate != null
              ? dFmt.format(order.stallPickupDate!.toLocal())
              : '');
      final String stallStatusStr = order.stallPickupStatus ?? '';

      final List<ExpoOrderItem?> itemRows =
          order.items.isEmpty ? <ExpoOrderItem?>[null] : order.items;

      for (final item in itemRows) {
        _writeOrderItemRow(
          sheet: sheet,
          row: currentRow,
          slNo: slNo,
          billNo: billNoStr,
          orderDate: orderDateStr,
          order: order,
          prefBranch: prefBranch,
          prefSalesman: prefSalesman,
          bookedBy: bookedBy,
          item: item,
          paymentModeDisplay: paymentModeDisplay,
          totalCash: totalCash,
          totalOnline: totalOnline,
          targetDateStr: targetDateStr,
          stallStatusStr: stallStatusStr,
          rowBackColor: rowBackColor,
        );
        currentRow++;
      }

      // Leave an empty uncolored gap row after each customer order for clear visual separation
      currentRow++;
      slNo++;
    }

    for (int col = 1; col <= _headers.length; col++) {
      sheet.autoFitColumn(col);
    }

    final List<int> bytes = workbook.saveAsStream();
    workbook.dispose();

    final Directory directory = await getTemporaryDirectory();
    final String cleanName =
        exhibition.name.replaceAll(RegExp(r'[^\w\s\-]'), '_').trim();
    final String fileName =
        '${cleanName.isEmpty ? 'Expo' : cleanName}_Orders_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';
    final String path = '${directory.path}/$fileName';
    final File file = File(path);
    await file.writeAsBytes(bytes, flush: true);

    await Share.shareXFiles(
      [XFile(path)],
      text: '${exhibition.name} Detailed Orders Report',
    );
  }

  static void _writeOrderItemRow({
    required xlsio.Worksheet sheet,
    required int row,
    required int slNo,
    required String billNo,
    required String orderDate,
    required ExpoOrder order,
    required String prefBranch,
    required String prefSalesman,
    required String bookedBy,
    required ExpoOrderItem? item,
    required String paymentModeDisplay,
    required double totalCash,
    required double totalOnline,
    required String targetDateStr,
    required String stallStatusStr,
    required String? rowBackColor,
  }) {
    sheet.getRangeByIndex(row, 1).setNumber(slNo.toDouble());
    sheet.getRangeByIndex(row, 2).setText(billNo);
    sheet.getRangeByIndex(row, 3).setText(orderDate);
    sheet.getRangeByIndex(row, 4).setText(order.orderType);
    sheet.getRangeByIndex(row, 5).setText(order.status);
    sheet.getRangeByIndex(row, 6).setText(order.shopName);
    sheet.getRangeByIndex(row, 7).setText(order.customerName);
    sheet.getRangeByIndex(row, 8).setText(order.phone);
    sheet.getRangeByIndex(row, 9).setText(order.place);
    sheet.getRangeByIndex(row, 10).setText(order.district);
    sheet.getRangeByIndex(row, 11).setText(order.state);
    sheet.getRangeByIndex(row, 12).setText(prefBranch);
    sheet.getRangeByIndex(row, 13).setText(prefSalesman);
    sheet.getRangeByIndex(row, 14).setText(bookedBy);

    sheet.getRangeByIndex(row, 15).setText(item?.mtcCode ?? '');
    sheet.getRangeByIndex(row, 16).setText(item?.itemName ?? '');
    sheet.getRangeByIndex(row, 17).setText(item?.description ?? '');
    sheet.getRangeByIndex(row, 18).setNumber((item?.qty ?? 0).toDouble());
    sheet.getRangeByIndex(row, 19).setNumber(item?.rate ?? 0.0);
    sheet.getRangeByIndex(row, 20).setNumber(item?.gst ?? 0.0);
    sheet.getRangeByIndex(row, 21).setText(
          item == null ? '' : (item.gstType == 1 ? 'Include' : 'Exclude'),
        );
    sheet.getRangeByIndex(row, 22).setNumber(item?.total ?? 0.0);

    sheet.getRangeByIndex(row, 23).setNumber(order.subtotal);
    sheet.getRangeByIndex(row, 24).setNumber(order.totalGst);
    sheet.getRangeByIndex(row, 25).setNumber(order.totalAmount);
    sheet.getRangeByIndex(row, 26).setNumber(order.advanceAmount);
    sheet.getRangeByIndex(row, 27).setNumber(order.pickupAmount);
    sheet.getRangeByIndex(row, 28).setNumber(order.balanceAmount);
    sheet.getRangeByIndex(row, 29).setText(paymentModeDisplay);
    sheet.getRangeByIndex(row, 30).setNumber(totalCash);
    sheet.getRangeByIndex(row, 31).setNumber(totalOnline);
    sheet.getRangeByIndex(row, 32).setText(targetDateStr);
    sheet.getRangeByIndex(row, 33).setText(stallStatusStr);
    sheet.getRangeByIndex(row, 34).setText(order.notes);

    const moneyCols = {19, 22, 23, 24, 25, 26, 27, 28, 30, 31};
    for (int col = 1; col <= _headers.length; col++) {
      final cell = sheet.getRangeByIndex(row, col);
      if (rowBackColor != null) {
        cell.cellStyle.backColor = rowBackColor;
      }
      if (moneyCols.contains(col)) {
        cell.numberFormat = '#,##0.00';
      }
      cell.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
      cell.cellStyle.borders.all.color = '#E2E8F0';
    }
  }
}
