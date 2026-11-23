import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../Navigation/user_cache_service.dart';
import '../expo_service.dart';

/// Helper service for generating dynamic PDF for Expo orders matching the
/// custom layout template with dynamic item list count, table borders, and totals.
class ExpoPdfService {
  ExpoPdfService._();
  static final ExpoPdfService instance = ExpoPdfService._();

  // Primary brand palette matching reference template
  static const PdfColor colorNavy =
      PdfColor.fromInt(0xFF0F3E7A); // Top header dark navy blue
  static const PdfColor colorLimeGreen =
      PdfColor.fromInt(0xFF689F38); // Olive green label background
  static const PdfColor colorNavyAccent =
      PdfColor.fromInt(0xFF0D47A1); // Blue badge / Table header
  static const PdfColor colorBorderGrey =
      PdfColor.fromInt(0xFFB0BEC5); // Border grey
  static const PdfColor colorRowAlt =
      PdfColor.fromInt(0xFFF8FAFC); // Table alternate row

  /// Generates a dynamic PDF based on the custom template and order data,
  /// saves to temporary storage, and triggers the share/print sheet.
  Future<void> exportOrderPdf(ExpoOrder order) async {
    try {
      final pdf = pw.Document();
      final dateFormatted = DateFormat('dd/MM/yyyy').format(order.orderDate);
      final isSpotDelivery = order.orderType == 'Spot Delivery';
      final isStallDelivery = order.orderType == 'Stall Delivery';
      final deliveryDateFormatted = order.deliveryDate != null
          ? DateFormat('dd/MM/yyyy').format(order.deliveryDate!)
          : (order.stallPickupDate != null
              ? DateFormat('dd/MM/yyyy').format(order.stallPickupDate!)
              : (order.orderType == 'Booking'
                  ? 'To be confirmed'
                  : 'Immediate'));
      final currencyFormat =
          NumberFormat.currency(symbol: 'Rs. ', decimalDigits: 2);

      // Look up preferred salesman phone from UserCacheService
      String preferredSalesmanDisplay = '-';
      if (!isSpotDelivery &&
          order.preferredSalesman != 'N/A' &&
          order.preferredSalesman.isNotEmpty) {
        preferredSalesmanDisplay = order.preferredSalesman;
        try {
          var users = await UserCacheService.instance.getAllUsers();
          final target = order.preferredSalesman.trim().toLowerCase();
          String findPhone(List<Map<String, dynamic>> list) {
            for (final u in list) {
              final uname =
                  (u['username'] ?? '').toString().trim().toLowerCase();
              if (uname == target) {
                return (u['phone'] ?? '').toString().trim();
              }
            }
            return '';
          }

          var phone = findPhone(users);
          if (phone.isEmpty) {
            users =
                await UserCacheService.instance.getAllUsers(forceRefresh: true);
            phone = findPhone(users);
          }
          if (phone.isNotEmpty) {
            preferredSalesmanDisplay = '${order.preferredSalesman}($phone)';
          }
        } catch (_) {}
      }

      // Try loading company logo if present
      pw.MemoryImage? logoImage;
      try {
        final logoBytes = await rootBundle.load('assets/images/bill_logo.png');
        logoImage = pw.MemoryImage(logoBytes.buffer.asUint8List());
      } catch (_) {}

      final pdfTheme = pw.ThemeData.withFont(
        base: pw.Font.times(),
        bold: pw.Font.timesBold(),
      );

      final themedPdf = pw.Document(theme: pdfTheme);
      themedPdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          header: (pw.Context context) {
            if (context.pageNumber > 1) {
              return pw.Column(
                children: [
                  pw.Container(
                    height: 4,
                    width: double.infinity,
                    decoration: const pw.BoxDecoration(
                      color: colorLimeGreen,
                      borderRadius: pw.BorderRadius.all(pw.Radius.circular(2)),
                    ),
                  ),
                  pw.SizedBox(height: 10),
                ],
              );
            }
            return pw.Column(
              children: [
                // 1. Top Header Banner: MALABAR TRADING COMPANY
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.symmetric(vertical: 8),
                  decoration: const pw.BoxDecoration(
                    color: colorNavy,
                    borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  alignment: pw.Alignment.center,
                  child: pw.Text(
                    'MALABAR TRADING COMPANY',
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  'ORDER BOOKING FORM',
                  style: pw.TextStyle(
                    color: colorNavy,
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                pw.SizedBox(height: 10),
              ],
            );
          },
          build: (pw.Context context) {
            return [
              // 2. Customer Details & Right-Side Box (Logo / Date / Sales Rep)
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Left Column: Customer Form Fields
                  pw.Expanded(
                    flex: 6,
                    child: pw.Column(
                      children: [
                        _buildTemplateField(
                            'Shop Name', order.shopName, colorLimeGreen),
                        pw.SizedBox(height: 4),
                        _buildTemplateField('Customer Name', order.customerName,
                            colorLimeGreen),
                        pw.SizedBox(height: 4),
                        _buildTemplateField(
                            'Phone No.', order.phone, colorLimeGreen),
                        pw.SizedBox(height: 4),
                        _buildTemplateField(
                            'Place', order.place, colorLimeGreen),
                        pw.SizedBox(height: 4),
                        _buildTemplateField(
                            'District', order.district, colorLimeGreen),
                        pw.SizedBox(height: 4),
                        _buildTemplateField(
                            'State', order.state, colorLimeGreen),
                        pw.SizedBox(height: 4),
                        _buildTemplateField(
                          'Sales Rep.',
                          order.createdUserName.isNotEmpty
                              ? order.createdUserName
                              : '-',
                          colorLimeGreen,
                        ),
                        pw.SizedBox(height: 4),
                        _buildTemplateField(
                          'Delivery Type',
                          isSpotDelivery
                              ? order.orderType
                              : '${order.orderType} ($deliveryDateFormatted)',
                          colorNavyAccent,
                        ),
                        pw.SizedBox(height: 6),
                        pw.Align(
                          alignment: pw.Alignment.centerLeft,
                          child: pw.Text(
                            order.notes.trim().isNotEmpty
                                ? 'Notes: ${order.notes.trim()}'
                                : 'Notes:',
                            style: const pw.TextStyle(
                                fontSize: 8.5, color: PdfColors.grey800),
                          ),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 14),

                  // Right Column: Company/Exhibition Box + Date + Sales Rep
                  pw.Expanded(
                    flex: 4,
                    child: pw.Column(
                      children: [
                        // Top Right Box (Logo / Exhibition Info)
                        pw.Container(
                          height: 110,
                          width: double.infinity,
                          padding: const pw.EdgeInsets.all(4),
                          alignment: pw.Alignment.center,
                          child: logoImage != null
                              ? pw.Column(
                                  mainAxisAlignment:
                                      pw.MainAxisAlignment.center,
                                  children: [
                                    pw.Expanded(
                                      child: pw.Image(logoImage,
                                          fit: pw.BoxFit.contain),
                                    ),
                                    pw.SizedBox(height: 3),
                                    pw.Text(
                                      order.exhibitionName,
                                      maxLines: 2,
                                      textAlign: pw.TextAlign.center,
                                      style: pw.TextStyle(
                                        fontSize: 8.5,
                                        fontWeight: pw.FontWeight.bold,
                                        color: colorNavy,
                                      ),
                                    ),
                                  ],
                                )
                              : pw.Text(
                                  order.exhibitionName,
                                  textAlign: pw.TextAlign.center,
                                  style: pw.TextStyle(
                                    fontSize: 11,
                                    fontWeight: pw.FontWeight.bold,
                                    color: colorNavy,
                                  ),
                                ),
                        ),
                        pw.SizedBox(height: 8),

                        // Date Field
                        _buildTemplateField(
                            'Date', dateFormatted, colorLimeGreen),
                        pw.SizedBox(height: 4),

                        if (order.billNumber != null) ...[
                          _buildTemplateField('Bill No.',
                              '#${order.billNumber}', colorLimeGreen),
                          pw.SizedBox(height: 4),
                        ],

                        // Branch Field
                        _buildTemplateField(
                          'Branch',
                          isSpotDelivery
                              ? '-'
                              : (order.preferredBranch != 'N/A' &&
                                      order.preferredBranch.isNotEmpty
                                  ? order.preferredBranch
                                  : '-'),
                          colorLimeGreen,
                        ),
                        pw.SizedBox(height: 4),

                        // Preferred Salesman Field
                        _buildTemplateField(
                          'Pref. Salesman',
                          preferredSalesmanDisplay,
                          colorLimeGreen,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 8),

              // 3. Dynamic Items Table:
              // S.No. | Code | Item Description | Qty | Rate | GST | Total
              pw.Table(
                border: pw.TableBorder.all(color: colorBorderGrey, width: 0.8),
                columnWidths: const {
                  0: pw.FlexColumnWidth(0.7), // S.No.
                  1: pw.FlexColumnWidth(1.3), // Code
                  2: pw.FlexColumnWidth(3.5), // Item Description
                  3: pw.FlexColumnWidth(0.9), // Qty
                  4: pw.FlexColumnWidth(1.3), // Rate
                  5: pw.FlexColumnWidth(1.2), // GST
                  6: pw.FlexColumnWidth(1.5), // Total
                },
                children: [
                  // Table Header: Deep Blue background with white text
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: colorNavyAccent),
                    children: [
                      _buildHeaderCell('S.No.', align: pw.TextAlign.center),
                      _buildHeaderCell('Code'),
                      _buildHeaderCell('Item Description'),
                      _buildHeaderCell('Qty', align: pw.TextAlign.center),
                      _buildHeaderCell('Rate', align: pw.TextAlign.right),
                      _buildHeaderCell('GST', align: pw.TextAlign.center),
                      _buildHeaderCell('Total', align: pw.TextAlign.right),
                    ],
                  ),
                  // Dynamic Items Rows
                  ...order.items.asMap().entries.map((entry) {
                    final idx = entry.key + 1;
                    final it = entry.value;
                    final isEven = idx % 2 == 0;
                    return pw.TableRow(
                      decoration: pw.BoxDecoration(
                        color: isEven ? colorRowAlt : PdfColors.white,
                      ),
                      children: [
                        _buildDataCell('$idx', align: pw.TextAlign.center),
                        _buildDataCell(
                            it.mtcCode.isNotEmpty ? it.mtcCode : '-'),
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(
                              horizontal: 6, vertical: 5),
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                it.itemName,
                                style: pw.TextStyle(
                                  fontSize: 8.5,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                              if (it.description.isNotEmpty) ...[
                                pw.SizedBox(height: 1),
                                pw.Text(
                                  it.description,
                                  style: const pw.TextStyle(
                                    fontSize: 7.5,
                                    color: PdfColors.grey700,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        _buildDataCell('${it.qty}', align: pw.TextAlign.center),
                        _buildDataCell(it.rate.toStringAsFixed(2),
                            align: pw.TextAlign.right),
                        _buildDataCell(
                          '${it.gst == it.gst.roundToDouble() ? it.gst.toStringAsFixed(0) : it.gst.toStringAsFixed(2)}%',
                          align: pw.TextAlign.center,
                        ),
                        _buildDataCell(
                          (it.gstType != 1 ? it.qty * it.rate : it.total)
                              .toStringAsFixed(2),
                          align: pw.TextAlign.right,
                        ),
                      ],
                    );
                  }),
                ],
              ),
              pw.SizedBox(height: 8),

              // 5. Bottom Section: Notes & Customer Signature on Left, Totals on Right
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Left Column: Notes & Customer Signature
                  pw.Expanded(
                    flex: 5,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        // Customer Signature Box
                        pw.Container(
                          width: 140,
                          height: 44,
                          decoration: pw.BoxDecoration(
                            border:
                                pw.Border.all(color: colorBorderGrey, width: 1),
                            borderRadius: const pw.BorderRadius.all(
                                pw.Radius.circular(2)),
                          ),
                          alignment: pw.Alignment.bottomCenter,
                          padding: const pw.EdgeInsets.only(bottom: 2),
                          child: pw.Text(
                            '',
                            style: const pw.TextStyle(fontSize: 9.5),
                          ),
                        ),
                        pw.SizedBox(height: 3),
                        pw.Text(
                          'Customer Signature',
                          style: pw.TextStyle(
                            fontSize: 8.5,
                            fontWeight: pw.FontWeight.bold,
                            color: colorNavy,
                          ),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 16),

                  // Right Column: Totals Table matching reference template
                  // Total Amount | Amt. Received | Total Paid | Advance | Balance Amount
                  pw.Expanded(
                    flex: 5,
                    child: pw.Table(
                      border: pw.TableBorder.all(
                          color: colorBorderGrey, width: 0.8),
                      columnWidths: const {
                        0: pw.FlexColumnWidth(1.2),
                        1: pw.FlexColumnWidth(1.0),
                      },
                      children: [
                        _buildTotalRow(
                          'Total Amount',
                          currencyFormat.format(
                            order.totalAmount -
                                order.items
                                    .where((it) => it.gstType != 1)
                                    .fold<double>(
                                      0.0,
                                      (sum, it) =>
                                          sum +
                                          ExpoOrderItem.calculateGstAmount(
                                            it.qty,
                                            it.rate,
                                            it.gst,
                                            gstType: it.gstType,
                                          ),
                                    ),
                          ),
                        ),
                        _buildTotalRow(
                          'Total GST',
                          currencyFormat.format(
                            order.items
                                .where((it) => it.gstType != 1)
                                .fold<double>(
                                  0.0,
                                  (sum, it) =>
                                      sum +
                                      ExpoOrderItem.calculateGstAmount(
                                        it.qty,
                                        it.rate,
                                        it.gst,
                                        gstType: it.gstType,
                                      ),
                                ),
                          ),
                        ),
                        _buildTotalRow(
                          'Grand Total',
                          currencyFormat.format(order.totalAmount),
                          isBold: true,
                        ),
                        _buildTotalRow(
                          'Advance${(!isSpotDelivery && order.paymentMode.isNotEmpty) ? ' (${order.paymentMode})' : ''}',
                          currencyFormat.format(
                              isSpotDelivery ? 0.0 : order.advanceAmount),
                        ),
                        if (!isSpotDelivery && order.pickupAmount > 0)
                          _buildTotalRow(
                            'Pickup Paid',
                            currencyFormat.format(order.pickupAmount),
                          ),
                        _buildTotalRow(
                          'Balance Amount',
                          currencyFormat.format(
                              isSpotDelivery ? 0.0 : order.balanceAmount),
                          isBold: true,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 16),
              pw.Text(
                'Note: This is an approximate estimate. Final pricing and applicable taxes are subject to actuals on the final tax invoice. This document is issued for reference purposes only and does not constitute a tax invoice. The official original bill will be generated and issued exclusively by the respective branch. Order will be cancelled if not taken delivery within 90 days.',
                textAlign: pw.TextAlign.center,
                style:
                    const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
              ),
              pw.SizedBox(height: 8),
              _buildBranchesSection(),
            ];
          },
          footer: (pw.Context context) {
            return pw.Column(
              children: [
                pw.SizedBox(height: 6),
                pw.Container(
                  height: 4,
                  width: double.infinity,
                  decoration: const pw.BoxDecoration(
                    color: colorLimeGreen,
                    borderRadius: pw.BorderRadius.all(pw.Radius.circular(2)),
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'Page ${context.pageNumber} of ${context.pagesCount}',
                      style: const pw.TextStyle(
                          fontSize: 8, color: PdfColors.grey600),
                    ),
                    pw.Text(
                      'Generated on: ${DateFormat("dd/MM/yyyy hh:mm a").format(DateTime.now())}',
                      style: const pw.TextStyle(
                          fontSize: 8, color: PdfColors.grey600),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      );

      final bytes = await themedPdf.save();
      final tempDir = await getTemporaryDirectory();
      final dateStr = DateFormat('dd-MM-yyyy').format(order.orderDate);
      final sanitizedShop =
          order.shopName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '').trim();
      final sanitizedType =
          order.orderType.replaceAll(RegExp(r'[\\/:*?"<>|]'), '').trim();
      final safeShop = sanitizedShop.isNotEmpty ? sanitizedShop : 'Shop';
      final safeType = sanitizedType.isNotEmpty ? sanitizedType : 'Order';
      final fileName = '$safeShop $safeType $dateStr.pdf';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(bytes);

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/pdf', name: fileName)],
        text: '$safeShop $safeType $dateStr',
      );
    } catch (e) {
      debugPrint('Error generating/exporting PDF: $e');
      rethrow;
    }
  }

  /// Builds a template field with colored label badge on left and boxed value container on right
  static pw.Widget _buildTemplateField(
      String label, String value, PdfColor labelColor) {
    return pw.Row(
      children: [
        // Label Box
        pw.Container(
          width: 82,
          height: 19,
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: pw.BoxDecoration(
            color: labelColor,
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
          ),
          alignment: pw.Alignment.centerLeft,
          child: pw.Text(
            label,
            style: pw.TextStyle(
              color: PdfColors.white,
              fontSize: 8.5,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
        pw.SizedBox(width: 4),
        // Value Box
        pw.Expanded(
          child: pw.Container(
            height: 19,
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: colorBorderGrey, width: 0.8),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
              color: PdfColors.white,
            ),
            alignment: pw.Alignment.centerLeft,
            child: pw.FittedBox(
              fit: pw.BoxFit.scaleDown,
              alignment: pw.Alignment.centerLeft,
              child: pw.Text(
                value.isNotEmpty ? value : '-',
                maxLines: 1,
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.black,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildHeaderCell(String text,
      {pw.TextAlign align = pw.TextAlign.left}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          color: PdfColors.white,
          fontSize: 10,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }

  static pw.Widget _buildDataCell(String text,
      {pw.TextAlign align = pw.TextAlign.left}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
      child: pw.Text(
        text,
        textAlign: align,
        style: const pw.TextStyle(fontSize: 9.5),
      ),
    );
  }

  static pw.TableRow _buildTotalRow(String label, String value,
      {bool isBold = false}) {
    return pw.TableRow(
      decoration: pw.BoxDecoration(
        color: isBold ? PdfColor.fromInt(0xFFEEF2F6) : PdfColors.white,
      ),
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 8.5,
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: isBold ? colorNavy : PdfColors.black,
            ),
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: pw.Text(
            value,
            textAlign: pw.TextAlign.right,
            style: pw.TextStyle(
              fontSize: 8.5,
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: isBold ? colorNavy : PdfColors.black,
            ),
          ),
        ),
      ],
    );
  }

  /// Builds the branches contact section matching the official branch card.
  static pw.Widget _buildBranchesSection() {
    const topBranches = [
      'DUBAI : +971 55 447 1448',
      'HYDERABAD : +91 99956 22203',
    ];

    const branches = [
      'BENGALURU : +91 82175 36200',
      'CHENNAI : +91 95390 50060',
      'UDUPI : +91 88910 17775',
      'COIMBATORE : +91 73737 03015',
      'TRIVANDRUM : +91 90481 73174',
      'KAYAMKULAM : +91 81578 68882',
      'KOTTAYAM : +91 90725 78355',
      'KOCHI : +91 97786 89257',
      'THRISSUR : +91 75580 15000',
      'PALAKKAD : +91 90725 81095',
      'PERINTHALMANNA : 81118 85757',
      'TIRUR : +91 81118 85760',
      'POOKKOTTUR : +91 92076 26666',
      'WAYANAD : +91 75929 34444',
      'CALICUT : +91 94959 21876',
      'VADAKARA : +91 90725 78352',
      'THALASSERI : +91 99958 50060',
      'KASARAGOD : +91 75940 33107',
    ];

    pw.Widget buildPill(String text) {
      return pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: const pw.BoxDecoration(
          color: colorNavyAccent,
          borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
        ),
        alignment: pw.Alignment.center,
        child: pw.FittedBox(
          fit: pw.BoxFit.scaleDown,
          child: pw.Text(
            text,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              fontSize: 7,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
          ),
        ),
      );
    }

    final gridRows = <pw.Widget>[];
    for (var i = 0; i < branches.length; i += 3) {
      final slice = branches.sublist(i, i + 3);
      gridRows.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 4),
          child: pw.Row(
            children: [
              pw.Expanded(child: buildPill(slice[0])),
              pw.SizedBox(width: 5),
              pw.Expanded(child: buildPill(slice[1])),
              pw.SizedBox(width: 5),
              pw.Expanded(child: buildPill(slice[2])),
            ],
          ),
        ),
      );
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 28),
          decoration: const pw.BoxDecoration(
            color: colorNavyAccent,
            borderRadius: pw.BorderRadius.all(pw.Radius.circular(8)),
          ),
          child: pw.Text(
            'OUR BRANCHES',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              fontSize: 9.5,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
              letterSpacing: 1.0,
            ),
          ),
        ),
        pw.SizedBox(height: 5),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          children: [
            buildPill(topBranches[0]),
            pw.SizedBox(width: 6),
            buildPill(topBranches[1]),
          ],
        ),
        pw.SizedBox(height: 5),
        ...gridRows,
        pw.SizedBox(height: 2),
        pw.Text(
          'www.mtckerala.com',
          style: pw.TextStyle(
            fontSize: 8,
            fontWeight: pw.FontWeight.bold,
            color: colorLimeGreen,
          ),
        ),
      ],
    );
  }
}
