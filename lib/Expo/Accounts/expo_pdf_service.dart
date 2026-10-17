import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../expo_service.dart';

/// Helper service for generating dynamic PDF for Expo orders matching the
/// custom layout template with dynamic item list count, table borders, and totals.
class ExpoPdfService {
  ExpoPdfService._();
  static final ExpoPdfService instance = ExpoPdfService._();

  // Primary brand palette matching reference template
  static const PdfColor colorNavy = PdfColor.fromInt(0xFF0F3E7A); // Top header dark navy blue
  static const PdfColor colorLimeGreen = PdfColor.fromInt(0xFF689F38); // Olive green label background
  static const PdfColor colorNavyAccent = PdfColor.fromInt(0xFF0D47A1); // Blue badge / Table header
  static const PdfColor colorBorderGrey = PdfColor.fromInt(0xFFB0BEC5); // Border grey
  static const PdfColor colorRowAlt = PdfColor.fromInt(0xFFF8FAFC); // Table alternate row

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
              : (order.orderType == 'Booking' ? 'To be confirmed' : 'Immediate'));
      final currencyFormat = NumberFormat.currency(symbol: 'Rs. ', decimalDigits: 2);

      // Try loading company logo if present
      pw.MemoryImage? logoImage;
      try {
        final logoBytes = await rootBundle.load('assets/images/logo.png');
        logoImage = pw.MemoryImage(logoBytes.buffer.asUint8List());
      } catch (_) {}

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          header: (pw.Context context) {
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
                pw.SizedBox(height: 12),
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
                        _buildTemplateField('Shop Name', order.shopName, colorLimeGreen),
                        pw.SizedBox(height: 4),
                        _buildTemplateField('Customer Name', order.customerName, colorLimeGreen),
                        pw.SizedBox(height: 4),
                        _buildTemplateField('Phone No.', order.phone, colorLimeGreen),
                        pw.SizedBox(height: 4),
                        _buildTemplateField('Place', order.place, colorLimeGreen),
                        pw.SizedBox(height: 4),
                        _buildTemplateField('District', order.district, colorLimeGreen),
                        pw.SizedBox(height: 4),
                        _buildTemplateField('State', order.state, colorLimeGreen),
                        pw.SizedBox(height: 4),
                        _buildTemplateField('Delivery Type', order.orderType, colorNavyAccent),
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
                          padding: const pw.EdgeInsets.all(8),
                          decoration: pw.BoxDecoration(
                            border: pw.Border.all(color: colorBorderGrey, width: 1.2),
                            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
                          ),
                          alignment: pw.Alignment.center,
                          child: logoImage != null
                              ? pw.Column(
                                  mainAxisAlignment: pw.MainAxisAlignment.center,
                                  children: [
                                    pw.Image(logoImage, height: 48, fit: pw.BoxFit.contain),
                                    pw.SizedBox(height: 4),
                                    pw.Text(
                                      order.exhibitionName,
                                      maxLines: 2,
                                      textAlign: pw.TextAlign.center,
                                      style: pw.TextStyle(
                                        fontSize: 9,
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
                        _buildTemplateField('Date', dateFormatted, colorLimeGreen),
                        pw.SizedBox(height: 4),

                        // Sales Rep Field
                        _buildTemplateField(
                          'Sales Rep.',
                          order.orderType == 'Spot Delivery'
                              ? '-'
                              : (order.preferredSalesman != 'N/A' && order.preferredSalesman.isNotEmpty
                                  ? order.preferredSalesman
                                  : '-'),
                          colorLimeGreen,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 8),

              // 3. Branch & Delivery Date Row
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: colorBorderGrey, width: 1),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
                  color: PdfColor.fromInt(0xFFFAFAFA),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.RichText(
                      text: pw.TextSpan(
                        children: [
                          pw.TextSpan(
                            text: 'Branch: ',
                            style: pw.TextStyle(
                              fontSize: 10,
                              fontWeight: pw.FontWeight.bold,
                              color: colorNavy,
                            ),
                          ),
                          pw.TextSpan(
                            text: isSpotDelivery
                                ? '-'
                                : (order.preferredBranch != 'N/A' && order.preferredBranch.isNotEmpty
                                    ? order.preferredBranch
                                    : '-'),
                            style: pw.TextStyle(
                              fontSize: 10,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.black,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!isSpotDelivery)
                      pw.RichText(
                        text: pw.TextSpan(
                          children: [
                            pw.TextSpan(
                              text: isStallDelivery
                                  ? 'Pickup Date: '
                                  : 'Delivery Date: ',
                              style: pw.TextStyle(
                                fontSize: 10,
                                fontWeight: pw.FontWeight.bold,
                                color: colorNavy,
                              ),
                            ),
                            pw.TextSpan(
                              text: deliveryDateFormatted,
                              style: pw.TextStyle(
                                fontSize: 10,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.black,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              pw.SizedBox(height: 8),

              // 4. Dynamic Items Table matching template column structure:
              // S.No. | Code | Item Description | Qty | Rate | GST | Total
              pw.Table(
                border: pw.TableBorder.all(color: colorBorderGrey, width: 0.8),
                columnWidths: const {
                  0: pw.FlexColumnWidth(0.8), // S.No.
                  1: pw.FlexColumnWidth(1.4), // Code
                  2: pw.FlexColumnWidth(3.8), // Item Description
                  3: pw.FlexColumnWidth(1.0), // Qty
                  4: pw.FlexColumnWidth(1.4), // Rate
                  5: pw.FlexColumnWidth(1.0), // GST
                  6: pw.FlexColumnWidth(1.6), // Total
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
                        _buildDataCell(it.mtcCode.isNotEmpty ? it.mtcCode : '-'),
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
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
                        _buildDataCell(it.rate.toStringAsFixed(2), align: pw.TextAlign.right),
                        _buildDataCell('${it.gst.toStringAsFixed(0)}%', align: pw.TextAlign.center),
                        _buildDataCell(it.total.toStringAsFixed(2), align: pw.TextAlign.right),
                      ],
                    );
                  }),
                  // Optional minimum fill rows to give the clean invoice structure if items are few
                  if (order.items.length < 5)
                    ...List.generate(5 - order.items.length, (_) {
                      return pw.TableRow(
                        children: List.generate(7, (i) {
                          return pw.Container(height: 18);
                        }),
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
                        // Notes area
                        pw.Text(
                          'Notes: Payment Mode - ${order.paymentMode}${!isSpotDelivery && order.advanceAmount > 0 ? " • Advance Paid: ${currencyFormat.format(order.advanceAmount)}" : ""}${!isSpotDelivery && order.balanceAmount > 0 ? " • Balance Due: ${currencyFormat.format(order.balanceAmount)}" : ""}${!isSpotDelivery && order.deliveryDate != null ? " • Expected Delivery: $deliveryDateFormatted" : ""}',
                          style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey800),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          'Booked by: ${order.createdUserName}${order.createdUserBranch.isNotEmpty ? " (${order.createdUserBranch})" : ""}',
                          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                        ),
                        pw.SizedBox(height: 16),

                        // Customer Signature Box
                        pw.Container(
                          width: 140,
                          height: 44,
                          decoration: pw.BoxDecoration(
                            border: pw.Border.all(color: colorBorderGrey, width: 1),
                            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
                          ),
                          alignment: pw.Alignment.bottomCenter,
                          padding: const pw.EdgeInsets.only(bottom: 2),
                          child: pw.Text(
                            '',
                            style: const pw.TextStyle(fontSize: 8),
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
                      border: pw.TableBorder.all(color: colorBorderGrey, width: 0.8),
                      columnWidths: const {
                        0: pw.FlexColumnWidth(1.2),
                        1: pw.FlexColumnWidth(1.0),
                      },
                      children: [
                        _buildTotalRow('Total Amount', currencyFormat.format(order.totalAmount)),
                        _buildTotalRow(
                          'Amt. Received',
                          currencyFormat.format(isSpotDelivery ? order.totalAmount : order.advanceAmount),
                        ),
                        _buildTotalRow(
                          'Total Paid',
                          currencyFormat.format(isSpotDelivery ? order.totalAmount : order.advanceAmount),
                        ),
                        _buildTotalRow(
                          'Advance',
                          currencyFormat.format(isSpotDelivery ? 0.0 : order.advanceAmount),
                        ),
                        _buildTotalRow(
                          'Balance Amount',
                          currencyFormat.format(isSpotDelivery ? 0.0 : order.balanceAmount),
                          isBold: true,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ];
          },
          footer: (pw.Context context) {
            return pw.Column(
              children: [
                pw.SizedBox(height: 12),
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
                      style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                    ),
                    pw.Text(
                      'Generated on: ${DateFormat("dd/MM/yyyy hh:mm a").format(DateTime.now())}',
                      style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      );

      final bytes = await pdf.save();
      final tempDir = await getTemporaryDirectory();
      final dateStr = DateFormat('dd-MM-yyyy').format(order.orderDate);
      final sanitizedShop = order.shopName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '').trim();
      final sanitizedType = order.orderType.replaceAll(RegExp(r'[\\/:*?"<>|]'), '').trim();
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
  static pw.Widget _buildTemplateField(String label, String value, PdfColor labelColor) {
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
            child: pw.Text(
              value.isNotEmpty ? value : '-',
              maxLines: 1,
              style: pw.TextStyle(
                fontSize: 8.5,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.black,
              ),
            ),
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildHeaderCell(String text, {pw.TextAlign align = pw.TextAlign.left}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          color: PdfColors.white,
          fontSize: 8.5,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }

  static pw.Widget _buildDataCell(String text, {pw.TextAlign align = pw.TextAlign.left}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
      child: pw.Text(
        text,
        textAlign: align,
        style: const pw.TextStyle(fontSize: 8),
      ),
    );
  }

  static pw.TableRow _buildTotalRow(String label, String value, {bool isBold = false}) {
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
}
