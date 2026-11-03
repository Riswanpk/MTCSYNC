import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;
import 'supersale_admin_dashboard_models.dart';

Future<void> generateSupersaleMasterDashboardExcel({
  required SupersaleComputedAnalytics analytics,
  String? filterLabel,
}) async {
  final xlsio.Workbook workbook = xlsio.Workbook();
  final DateFormat dateFmt = DateFormat('dd/MM/yyyy');
  final DateFormat dateTimeFmt = DateFormat('dd/MM/yyyy HH:mm');
  final DateTime now = DateTime.now();

  void styleHeader(
    xlsio.Worksheet sheet,
    int row,
    List<String> headers,
    String backColor,
  ) {
    for (int c = 0; c < headers.length; c++) {
      final cell = sheet.getRangeByIndex(row, c + 1);
      cell.setText(headers[c]);
      cell.cellStyle.bold = true;
      cell.cellStyle.backColor = backColor;
      cell.cellStyle.hAlign = xlsio.HAlignType.center;
    }
  }

  void writeTitle(xlsio.Worksheet sheet, String title, int cols) {
    final cell = sheet.getRangeByIndex(1, 1);
    cell.setText(title);
    cell.cellStyle.bold = true;
    cell.cellStyle.fontSize = 14;
    if (cols > 1) {
      sheet.getRangeByIndex(1, 1, 1, cols).merge();
    }
  }

  // ── SHEET 1: Executive Summary ──
  final xlsio.Worksheet summarySheet = workbook.worksheets[0];
  summarySheet.name = 'Executive Summary';
  writeTitle(
    summarySheet,
    'SUPERSALE ADMIN DASHBOARD — EXECUTIVE SUMMARY (${filterLabel ?? "All Data"})',
    4,
  );

  styleHeader(
    summarySheet,
    3,
    ['METRIC', 'COUNT / ORDERS', 'QUANTITY', 'VALUE / AMOUNT (INR)'],
    '#D9E1F2',
  );

  final List<List<dynamic>> summaryRows = [
    ['Total Campaigns', analytics.totalCampaigns, 0.0, 0.0],
    ['Active Booking Campaigns', analytics.activeBookingCampaigns, 0.0, 0.0],
    ['Active Delivery Campaigns', analytics.activeDeliveryCampaigns, 0.0, 0.0],
    ['Expired Campaigns', analytics.expiredCampaigns, 0.0, 0.0],
    [
      'Total Valid Bookings',
      analytics.totalValidOrders,
      analytics.totalBookedQty,
      analytics.totalOrderAmount,
    ],
    [
      'Delivered Orders',
      analytics.deliveredOrders,
      analytics.deliveredQty,
      analytics.deliveredAmount,
    ],
    [
      'Pending Orders',
      analytics.pendingOrders,
      analytics.pendingQty,
      analytics.pendingAmount,
    ],
    ['Overdue Pending Orders', analytics.overdueOrders, 0.0, 0.0],
    [
      'Spot Sales',
      analytics.spotSaleOrders,
      analytics.spotSaleQty,
      analytics.spotSaleAmount,
    ],
    [
      'Pre-Bookings (Normal)',
      analytics.normalBookingOrders,
      analytics.normalBookingQty,
      analytics.normalBookingAmount,
    ],
    ['Total Advance Collected', analytics.normalBookingOrders, 0.0, analytics.totalAdvanceAmount],
    [
      'Cancelled Orders',
      analytics.cancelledOrders,
      analytics.cancelledQty,
      analytics.cancelledAmount,
    ],
    ['Partial / Split Deliveries', analytics.partialSplitOrders, 0.0, 0.0],
  ];

  int sRow = 4;
  for (final r in summaryRows) {
    summarySheet.getRangeByIndex(sRow, 1).setText(r[0].toString());
    summarySheet.getRangeByIndex(sRow, 2).setNumber((r[1] as num).toDouble());
    summarySheet.getRangeByIndex(sRow, 3).setNumber((r[2] as num).toDouble());
    summarySheet.getRangeByIndex(sRow, 4).setNumber((r[3] as num).toDouble());
    sRow++;
  }
  for (int c = 1; c <= 4; c++) {
    summarySheet.autoFitColumn(c);
  }

  // ── SHEET 2: Campaign Comparison ──
  final xlsio.Worksheet campSheet = workbook.worksheets.addWithName('Campaigns');
  writeTitle(campSheet, 'CAMPAIGN-WISE PERFORMANCE REPORT', 11);
  styleHeader(
    campSheet,
    3,
    [
      'Sl.No',
      'Campaign Item',
      'Status',
      'Booking Period',
      'Delivery End',
      'Orders',
      'Booked Qty',
      'Delivered Qty',
      'Pending Qty',
      'Spot Qty',
      'Total Value',
    ],
    '#D9E1F2',
  );
  int cRow = 4;
  int sl = 1;
  for (final row in analytics.campaignRows) {
    campSheet.getRangeByIndex(cRow, 1).setNumber(sl.toDouble());
    campSheet.getRangeByIndex(cRow, 2).setText(row.campaign.item);
    campSheet.getRangeByIndex(cRow, 3).setText(row.campaign.statusLabel(now));
    campSheet
        .getRangeByIndex(cRow, 4)
        .setText('${dateFmt.format(row.campaign.bookingStart)} - ${dateFmt.format(row.campaign.bookingEnd)}');
    campSheet
        .getRangeByIndex(cRow, 5)
        .setText(dateFmt.format(row.campaign.deliveryEnd));
    campSheet.getRangeByIndex(cRow, 6).setNumber(row.totalOrders.toDouble());
    campSheet.getRangeByIndex(cRow, 7).setNumber(row.bookedQty);
    campSheet.getRangeByIndex(cRow, 8).setNumber(row.deliveredQty);
    campSheet.getRangeByIndex(cRow, 9).setNumber(row.pendingQty);
    campSheet.getRangeByIndex(cRow, 10).setNumber(row.spotSaleQty);
    campSheet.getRangeByIndex(cRow, 11).setNumber(row.totalAmount);
    sl++;
    cRow++;
  }
  for (int c = 1; c <= 11; c++) {
    campSheet.autoFitColumn(c);
  }

  // ── SHEET 3: Branch Booking & Revenue ──
  final xlsio.Worksheet bBookSheet =
      workbook.worksheets.addWithName('Branch Bookings');
  writeTitle(bBookSheet, 'BRANCH-WISE BOOKING & REVENUE REPORT', 8);
  styleHeader(
    bBookSheet,
    3,
    [
      'BRANCH',
      'ORDERS',
      'TOTAL QTY',
      'SPOT SALE QTY',
      'PRE-BOOKING QTY',
      'TOTAL AMOUNT',
      'ADVANCE COLLECTED',
      'BALANCE AMOUNT',
    ],
    '#D9E1F2',
  );
  int bbRow = 4;
  for (final row in analytics.branchBookingRows) {
    bBookSheet.getRangeByIndex(bbRow, 1).setText(row.branch);
    bBookSheet.getRangeByIndex(bbRow, 2).setNumber(row.totalOrders.toDouble());
    bBookSheet.getRangeByIndex(bbRow, 3).setNumber(row.totalQty);
    bBookSheet.getRangeByIndex(bbRow, 4).setNumber(row.spotQty);
    bBookSheet.getRangeByIndex(bbRow, 5).setNumber(row.normalQty);
    bBookSheet.getRangeByIndex(bbRow, 6).setNumber(row.totalAmount);
    bBookSheet.getRangeByIndex(bbRow, 7).setNumber(row.totalAdvance);
    bBookSheet.getRangeByIndex(bbRow, 8).setNumber(row.balanceAmount);
    bbRow++;
  }
  for (int c = 1; c <= 8; c++) {
    bBookSheet.autoFitColumn(c);
  }

  // ── SHEET 4: Branch Delivery Status ──
  final xlsio.Worksheet bDelSheet =
      workbook.worksheets.addWithName('Branch Delivery');
  writeTitle(bDelSheet, 'BRANCH-WISE DELIVERY & FULFILLMENT REPORT', 8);
  styleHeader(
    bDelSheet,
    3,
    [
      'BRANCH',
      'TOTAL BOOKED QTY',
      'DELIVERED QTY',
      'PENDING QTY',
      'CANCELLED QTY',
      'OVERDUE ORDERS',
      'DELIVERY %',
      'DELIVERED AMOUNT',
    ],
    '#E2EFDA',
  );
  int bdRow = 4;
  for (final row in analytics.branchDeliveryRows) {
    bDelSheet.getRangeByIndex(bdRow, 1).setText(row.branch);
    bDelSheet.getRangeByIndex(bdRow, 2).setNumber(row.totalBookingQty);
    bDelSheet.getRangeByIndex(bdRow, 3).setNumber(row.deliveredQty);
    bDelSheet.getRangeByIndex(bdRow, 4).setNumber(row.pendingQty);
    bDelSheet.getRangeByIndex(bdRow, 5).setNumber(row.cancelledQty);
    bDelSheet.getRangeByIndex(bdRow, 6).setNumber(row.overdueOrders.toDouble());
    bDelSheet
        .getRangeByIndex(bdRow, 7)
        .setText('${row.deliveryPct.toStringAsFixed(1)}%');
    bDelSheet.getRangeByIndex(bdRow, 8).setNumber(row.deliveredAmount);
    bdRow++;
  }
  for (int c = 1; c <= 8; c++) {
    bDelSheet.autoFitColumn(c);
  }

  // ── SHEET 5: Staff Performance ──
  final xlsio.Worksheet staffSheet =
      workbook.worksheets.addWithName('Staff Performance');
  writeTitle(staffSheet, 'STAFF PERFORMANCE & PARTICIPATION REPORT', 11);
  styleHeader(
    staffSheet,
    3,
    [
      'Sl.No',
      'Username',
      'Branch',
      'Role',
      'Campaigns (Part./Total)',
      'Orders',
      'Booked Qty',
      'Delivered Qty',
      'Pending Qty',
      'Overdue',
      'Total Sales Value',
    ],
    '#D9E1F2',
  );
  int stRow = 4;
  int stSl = 1;
  for (final row in analytics.userPerformanceRows) {
    staffSheet.getRangeByIndex(stRow, 1).setNumber(stSl.toDouble());
    staffSheet.getRangeByIndex(stRow, 2).setText(row.username);
    staffSheet.getRangeByIndex(stRow, 3).setText(row.branch);
    staffSheet.getRangeByIndex(stRow, 4).setText(row.formattedRole);
    staffSheet
        .getRangeByIndex(stRow, 5)
        .setText('${row.participatedCampaigns}/${row.applicableCampaigns}');
    staffSheet.getRangeByIndex(stRow, 6).setNumber(row.totalOrders.toDouble());
    staffSheet.getRangeByIndex(stRow, 7).setNumber(row.bookedQty);
    staffSheet.getRangeByIndex(stRow, 8).setNumber(row.deliveredQty);
    staffSheet.getRangeByIndex(stRow, 9).setNumber(row.pendingQty);
    staffSheet.getRangeByIndex(stRow, 10).setNumber(row.overdueOrders.toDouble());
    staffSheet.getRangeByIndex(stRow, 11).setNumber(row.totalAmount);
    stSl++;
    stRow++;
  }
  for (int c = 1; c <= 11; c++) {
    staffSheet.autoFitColumn(c);
  }

  // ── SHEET 6: Overdue Orders ──
  final xlsio.Worksheet overdueSheet =
      workbook.worksheets.addWithName('Overdue Orders');
  writeTitle(overdueSheet, 'OVERDUE PENDING DELIVERIES REPORT', 10);
  styleHeader(
    overdueSheet,
    3,
    [
      'Sl.No',
      'Branch',
      'Campaign Item',
      'Customer Name',
      'Phone',
      'Staff User',
      'Qty',
      'Amount',
      'Deadline',
      'Days Overdue',
    ],
    '#FCE4D6',
  );
  int ovRow = 4;
  int ovSl = 1;
  for (final e in analytics.overdueEntries) {
    overdueSheet.getRangeByIndex(ovRow, 1).setNumber(ovSl.toDouble());
    overdueSheet.getRangeByIndex(ovRow, 2).setText(e.branch);
    overdueSheet.getRangeByIndex(ovRow, 3).setText(e.itemName);
    overdueSheet.getRangeByIndex(ovRow, 4).setText(e.customerName);
    overdueSheet.getRangeByIndex(ovRow, 5).setText(e.phone);
    overdueSheet.getRangeByIndex(ovRow, 6).setText(e.username);
    overdueSheet.getRangeByIndex(ovRow, 7).setNumber(e.quantity);
    overdueSheet.getRangeByIndex(ovRow, 8).setNumber(e.totalAmount);
    overdueSheet.getRangeByIndex(ovRow, 9).setText(
          e.effectiveDeadline != null
              ? dateTimeFmt.format(e.effectiveDeadline!)
              : '-',
        );
    overdueSheet
        .getRangeByIndex(ovRow, 10)
        .setNumber(e.daysOverdue(now).toDouble());
    ovSl++;
    ovRow++;
  }
  for (int c = 1; c <= 10; c++) {
    overdueSheet.autoFitColumn(c);
  }

  // ── SHEET 7: Cancelled Orders Audit ──
  final xlsio.Worksheet cancelSheet =
      workbook.worksheets.addWithName('Cancelled Orders');
  writeTitle(cancelSheet, 'CANCELLED BOOKINGS AUDIT REPORT', 9);
  styleHeader(
    cancelSheet,
    3,
    [
      'Sl.No',
      'Branch',
      'Item',
      'Customer Name',
      'Phone',
      'Staff User',
      'Qty',
      'Amount',
      'Cancel Reason',
    ],
    '#FCE4D6',
  );
  int caRow = 4;
  int caSl = 1;
  for (final e in analytics.cancelledEntries) {
    cancelSheet.getRangeByIndex(caRow, 1).setNumber(caSl.toDouble());
    cancelSheet.getRangeByIndex(caRow, 2).setText(e.branch);
    cancelSheet.getRangeByIndex(caRow, 3).setText(e.itemName);
    cancelSheet.getRangeByIndex(caRow, 4).setText(e.customerName);
    cancelSheet.getRangeByIndex(caRow, 5).setText(e.phone);
    cancelSheet.getRangeByIndex(caRow, 6).setText(e.username);
    cancelSheet.getRangeByIndex(caRow, 7).setNumber(e.quantity);
    cancelSheet.getRangeByIndex(caRow, 8).setNumber(e.totalAmount);
    cancelSheet
        .getRangeByIndex(caRow, 9)
        .setText(e.cancelReason.isNotEmpty ? e.cancelReason : 'Not Specified');
    caSl++;
    caRow++;
  }
  for (int c = 1; c <= 9; c++) {
    cancelSheet.autoFitColumn(c);
  }

  final List<int> bytes = workbook.saveAsStream();
  workbook.dispose();

  final Directory directory = await getTemporaryDirectory();
  final String path =
      '${directory.path}/Supersale_Dashboard_Master_Report_${DateFormat('yyyyMMdd_HHmmss').format(now)}.xlsx';
  final File file = File(path);
  await file.writeAsBytes(bytes, flush: true);

  await Share.shareXFiles(
    [XFile(path)],
    text: 'Supersale Admin Master Dashboard Report',
  );
}

