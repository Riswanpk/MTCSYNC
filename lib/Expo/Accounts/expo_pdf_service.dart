import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../expo_service.dart';

/// Helper service for generating and exporting PDF for Expo orders.
/// The layout and details can be expanded as needed.
class ExpoPdfService {
  ExpoPdfService._();
  static final ExpoPdfService instance = ExpoPdfService._();

  /// Generates a PDF invoice/summary for the given order, writes it to a temporary file,
  /// and opens the system share/print sheet.
  Future<void> exportOrderPdf(ExpoOrder order) async {
    try {
      final pdf = pw.Document();
      final dateFormatted = DateFormat('dd/MM/yyyy hh:mm a').format(order.orderDate);
      final currencyFormat = NumberFormat.currency(symbol: 'Rs. ', decimalDigits: 2);

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          header: (pw.Context context) {
            return pw.Container(
              padding: const pw.EdgeInsets.only(bottom: 12),
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(color: PdfColors.grey300, width: 1.5),
                ),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'EXHIBITION ORDER',
                        style: pw.TextStyle(
                          fontSize: 20,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColor.fromInt(0xFF1E3A8A),
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        order.exhibitionName,
                        style: pw.TextStyle(
                          fontSize: 13,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColor.fromInt(0xFF10B981),
                        ),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: pw.BoxDecoration(
                          color: PdfColor.fromInt(0xFFEEF2F6),
                          borderRadius: pw.BorderRadius.circular(4),
                        ),
                        child: pw.Text(
                          order.orderType.toUpperCase(),
                          style: pw.TextStyle(
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColor.fromInt(0xFF1E3A8A),
                          ),
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'Date: $dateFormatted',
                        style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                      ),
                      pw.Text(
                        'Status: ${order.status.toUpperCase()}',
                        style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                          color: order.status == 'Completed'
                              ? PdfColor.fromInt(0xFF10B981)
                              : PdfColor.fromInt(0xFFF59E0B),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
          build: (pw.Context context) {
            return [
              pw.SizedBox(height: 16),
              // Customer & Order Info Section
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Customer Details
                  pw.Expanded(
                    flex: 1,
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(12),
                      decoration: pw.BoxDecoration(
                        color: PdfColor.fromInt(0xFFF8FAFC),
                        borderRadius: pw.BorderRadius.circular(6),
                        border: pw.Border.all(color: PdfColors.grey300),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'CUSTOMER DETAILS',
                            style: pw.TextStyle(
                              fontSize: 10,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.grey700,
                            ),
                          ),
                          pw.SizedBox(height: 6),
                          pw.Text(
                            order.shopName,
                            style: pw.TextStyle(
                              fontSize: 13,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.black,
                            ),
                          ),
                          if (order.customerName.isNotEmpty) ...[
                            pw.SizedBox(height: 2),
                            pw.Text('Contact: ${order.customerName}',
                                style: const pw.TextStyle(fontSize: 10)),
                          ],
                          if (order.phone.isNotEmpty) ...[
                            pw.SizedBox(height: 2),
                            pw.Text('Phone: ${order.phone}',
                                style: const pw.TextStyle(fontSize: 10)),
                          ],
                          if (order.place.isNotEmpty || order.district.isNotEmpty) ...[
                            pw.SizedBox(height: 2),
                            pw.Text(
                              'Place: ${[order.place, order.district, order.state].where((e) => e.isNotEmpty).join(", ")}',
                              style: const pw.TextStyle(fontSize: 10),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 16),
                  // Order / Sales Info
                  pw.Expanded(
                    flex: 1,
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(12),
                      decoration: pw.BoxDecoration(
                        color: PdfColor.fromInt(0xFFF8FAFC),
                        borderRadius: pw.BorderRadius.circular(6),
                        border: pw.Border.all(color: PdfColors.grey300),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'ORDER INFORMATION',
                            style: pw.TextStyle(
                              fontSize: 10,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.grey700,
                            ),
                          ),
                          pw.SizedBox(height: 6),
                          _buildPdfInfoRow('Branch', order.preferredBranch),
                          _buildPdfInfoRow('Salesman', order.preferredSalesman),
                          _buildPdfInfoRow('Payment Mode', order.paymentMode),
                          _buildPdfInfoRow('Booked By', order.createdUserName),
                          if (order.createdUserBranch.isNotEmpty)
                            _buildPdfInfoRow('User Branch', order.createdUserBranch),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 20),

              // Items Table
              pw.Text(
                'ITEMS',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.black,
                ),
              ),
              pw.SizedBox(height: 8),

              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.8),
                columnWidths: {
                  0: const pw.FlexColumnWidth(0.8), // Sl No
                  1: const pw.FlexColumnWidth(1.4), // MTC Code
                  2: const pw.FlexColumnWidth(3.5), // Item Name & Desc
                  3: const pw.FlexColumnWidth(0.9), // Qty
                  4: const pw.FlexColumnWidth(1.4), // Rate
                  5: const pw.FlexColumnWidth(1.0), // GST %
                  6: const pw.FlexColumnWidth(1.6), // Total
                },
                children: [
                  // Table Header
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF1E3A8A)),
                    children: [
                      _buildTableHeaderCell('#'),
                      _buildTableHeaderCell('MTC Code'),
                      _buildTableHeaderCell('Item Name'),
                      _buildTableHeaderCell('Qty', align: pw.TextAlign.center),
                      _buildTableHeaderCell('Rate', align: pw.TextAlign.right),
                      _buildTableHeaderCell('GST', align: pw.TextAlign.center),
                      _buildTableHeaderCell('Total', align: pw.TextAlign.right),
                    ],
                  ),
                  // Table Rows
                  ...order.items.asMap().entries.map((entry) {
                    final idx = entry.key + 1;
                    final it = entry.value;
                    final isEven = idx % 2 == 0;
                    return pw.TableRow(
                      decoration: pw.BoxDecoration(
                        color: isEven ? const PdfColor.fromInt(0xFFF9FAFB) : PdfColors.white,
                      ),
                      children: [
                        _buildTableCell('$idx', align: pw.TextAlign.center),
                        _buildTableCell(it.mtcCode.isNotEmpty ? it.mtcCode : '-'),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                it.itemName,
                                style: pw.TextStyle(
                                  fontSize: 9,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                              if (it.description.isNotEmpty) ...[
                                pw.SizedBox(height: 2),
                                pw.Text(
                                  it.description,
                                  style: const pw.TextStyle(
                                    fontSize: 8,
                                    color: PdfColors.grey700,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        _buildTableCell('${it.qty}', align: pw.TextAlign.center),
                        _buildTableCell(it.rate.toStringAsFixed(2), align: pw.TextAlign.right),
                        _buildTableCell('${it.gst.toStringAsFixed(0)}%',
                            align: pw.TextAlign.center),
                        _buildTableCell(it.total.toStringAsFixed(2), align: pw.TextAlign.right),
                      ],
                    );
                  }),
                ],
              ),
              pw.SizedBox(height: 16),

              // Summary Section
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Container(
                    width: 240,
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(
                      color: PdfColor.fromInt(0xFFF8FAFC),
                      borderRadius: pw.BorderRadius.circular(6),
                      border: pw.Border.all(color: PdfColors.grey300),
                    ),
                    child: pw.Column(
                      children: [
                        _buildPdfSummaryRow('Total Items / Qty:',
                            '${order.items.length} items (${order.totalQty} pcs)'),
                        _buildPdfSummaryRow('Subtotal:', currencyFormat.format(order.subtotal)),
                        _buildPdfSummaryRow('Total GST:', currencyFormat.format(order.totalGst)),
                        pw.Divider(color: PdfColors.grey400, thickness: 1),
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text(
                              'Grand Total:',
                              style: pw.TextStyle(
                                fontSize: 12,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.black,
                              ),
                            ),
                            pw.Text(
                              currencyFormat.format(order.totalAmount),
                              style: pw.TextStyle(
                                fontSize: 13,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColor.fromInt(0xFF10B981),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 24),

              // Notes / Verification Info
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromInt(0xFFF1F5F9),
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Payment Method: ${order.paymentMode}',
                      style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                    ),
                    pw.Text(
                      'Note: This is an auto-generated order summary for the exhibition.',
                      style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                    ),
                  ],
                ),
              ),
            ];
          },
          footer: (pw.Context context) {
            return pw.Container(
              margin: const pw.EdgeInsets.only(top: 16),
              padding: const pw.EdgeInsets.only(top: 8),
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  top: pw.BorderSide(color: PdfColors.grey300, width: 0.8),
                ),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Page ${context.pageNumber} of ${context.pagesCount}',
                    style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                  ),
                  pw.Text(
                    'MTCSYNC Exhibition Module',
                    style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                  ),
                ],
              ),
            );
          },
        ),
      );

      final bytes = await pdf.save();
      final tempDir = await getTemporaryDirectory();
      final sanitizedShop = order.shopName.replaceAll(RegExp(r'[^\w\s-]'), '').trim();
      final fileName = 'Order_${sanitizedShop.isEmpty ? "Expo" : sanitizedShop}_${order.id.isNotEmpty ? order.id.substring(0, order.id.length.clamp(0, 6)) : DateTime.now().millisecondsSinceEpoch}.pdf';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(bytes);

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/pdf', name: fileName)],
        text: 'Expo Order - ${order.shopName} (${order.exhibitionName})',
      );
    } catch (e) {
      debugPrint('Error generating/exporting PDF: $e');
      rethrow;
    }
  }

  static pw.Widget _buildTableHeaderCell(String text, {pw.TextAlign align = pw.TextAlign.left}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          color: PdfColors.white,
          fontSize: 9,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }

  static pw.Widget _buildTableCell(String text, {pw.TextAlign align = pw.TextAlign.left}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        textAlign: align,
        style: const pw.TextStyle(fontSize: 9),
      ),
    );
  }

  static pw.Widget _buildPdfInfoRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.Row(
        children: [
          pw.SizedBox(
            width: 75,
            child: pw.Text(
              '$label:',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value.isNotEmpty ? value : '-',
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildPdfSummaryRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
