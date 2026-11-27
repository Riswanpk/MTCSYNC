import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import '../expo_service.dart';
import '../expo_supabase_config.dart';

class ExpoPdfService {
  ExpoPdfService._();
  static final ExpoPdfService instance = ExpoPdfService._();

  static const PdfColor _colorNavy = PdfColor.fromInt(0xFF0A3D7A);
  static const PdfColor _colorLimeGreen = PdfColor.fromInt(0xFF73A832);
  static const PdfColor _colorLightBg = PdfColor.fromInt(0xFFEEF4F9);
  static const PdfColor _colorRowAlt = PdfColor.fromInt(0xFFF6F8FA);
  static const PdfColor _colorBorderGrey = PdfColor.fromInt(0xFFD1D5DB);
  static const PdfColor _colorDarkText = PdfColor.fromInt(0xFF111827);
  static const PdfColor _colorGreyText = PdfColor.fromInt(0xFF6B7280);

  Future<File> exportOrderPdf(ExpoOrder order, {Exhibition? exhibition}) async {
    final pdf = pw.Document();

    pw.MemoryImage? logoImage;
    try {
      final data = await rootBundle.load('assets/images/bill_logo.png');
      logoImage = pw.MemoryImage(data.buffer.asUint8List());
    } catch (_) {}

    String exhibitionName = exhibition?.name ?? '';
    if (exhibitionName.isEmpty && order.exhibitionId.isNotEmpty) {
      try {
        final row = await ExpoSupabaseConfig.client
            .schema(ExpoSupabaseConfig.schema)
            .from('exhibitions')
            .select('name')
            .eq('id', order.exhibitionId)
            .maybeSingle();
        exhibitionName = (row?['name'] ?? '').toString();
      } catch (_) {}
    }

    String deliveryText = order.orderType;
    if (order.orderType == 'Booking' && order.deliveryDate != null) {
      deliveryText =
          'Booking (${DateFormat('dd/MM/yyyy').format(order.deliveryDate!)})';
    } else if (order.orderType == 'Stall Delivery') {
      deliveryText = 'Stall Delivery (${order.stallPickupStatus})';
    }

    final String formTitle =
        order.orderType == 'Booking' ? 'ORDER BOOKING FORM' : 'ORDER RECEIPT';

    final double tableTotalSum = order.items.fold(
      0.0,
      (acc, it) => acc + (it.gstType != 1 ? it.qty * it.rate : it.total),
    );
    final double excludingGstSum = order.items.fold(
      0.0,
      (acc, it) =>
          acc + (it.gstType != 1 ? (it.qty * it.rate * (it.gst / 100.0)) : 0.0),
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        header: (pw.Context context) {
          if (context.pageNumber <= 1) return pw.SizedBox.shrink();
          return pw.Column(
            children: [
              pw.Container(
                height: 3.5,
                width: double.infinity,
                decoration: const pw.BoxDecoration(
                  color: _colorLimeGreen,
                  borderRadius: pw.BorderRadius.all(pw.Radius.circular(2)),
                ),
              ),
              pw.SizedBox(height: 8),
            ],
          );
        },
        build: (pw.Context context) {
          return [
            // 1. Header Banner
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.symmetric(vertical: 6),
              decoration: const pw.BoxDecoration(
                color: _colorNavy,
                borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Text(
                'MALABAR TRADING COMPANY',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  fontSize: 15,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Center(
              child: pw.Text(
                formTitle,
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: _colorNavy,
                ),
              ),
            ),
            pw.SizedBox(height: 6),

            // 2. Customer & Order Info
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  flex: 6,
                  child: pw.Column(
                    children: [
                      _buildInfoRow('SHOP NAME', order.shopName, _colorLimeGreen),
                      _buildInfoRow(
                          'CUSTOMER NAME', order.customerName, _colorLimeGreen),
                      _buildInfoRow('PHONE NO.', order.phone, _colorLimeGreen),
                      _buildInfoRow('PLACE', order.place, _colorLimeGreen),
                      _buildInfoRow('DISTRICT', order.district, _colorLimeGreen),
                      _buildInfoRow('STATE', order.state, _colorLimeGreen),
                      _buildInfoRow(
                          'SALES REP.', order.createdUserName, _colorLimeGreen),
                      _buildInfoRow('DELIVERY TYPE', deliveryText, _colorNavy),
                    ],
                  ),
                ),
                pw.SizedBox(width: 10),
                pw.Expanded(
                  flex: 4,
                  child: pw.Column(
                    children: [
                      if (logoImage != null)
                        pw.Image(logoImage, height: 48, fit: pw.BoxFit.contain),
                      if (exhibitionName.isNotEmpty) ...[
                        pw.SizedBox(height: 2),
                        pw.Text(
                          exhibitionName.toUpperCase(),
                          textAlign: pw.TextAlign.center,
                          style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                            color: _colorNavy,
                          ),
                        ),
                      ],
                      pw.SizedBox(height: 4),
                      _buildInfoRow(
                        'DATE',
                        DateFormat('dd/MM/yyyy').format(order.orderDate),
                        _colorLimeGreen,
                        labelWidth: 68,
                      ),
                      _buildInfoRow(
                        'BILL NO.',
                        '#${order.billNumber}',
                        _colorLimeGreen,
                        labelWidth: 68,
                      ),
                      _buildInfoRow(
                        'BRANCH',
                        _fullBranchName(order.preferredBranch),
                        _colorLimeGreen,
                        labelWidth: 68,
                      ),
                      _buildInfoRow(
                        'PREF. SALESMAN',
                        order.preferredSalesman.trim().isNotEmpty
                            ? order.preferredSalesman.trim()
                            : '-',
                        _colorLimeGreen,
                        labelWidth: 68,
                      ),
                    ],
                  ),
                ),
              ],
            ),

            if (order.notes.trim().isNotEmpty) ...[
              pw.SizedBox(height: 4),
              pw.Text(
                'Notes: ${order.notes.trim()}',
                style: const pw.TextStyle(fontSize: 8, color: _colorDarkText),
              ),
            ],
            pw.SizedBox(height: 6),

            // 3. Items Table
            pw.Table(
              border: pw.TableBorder.all(color: _colorBorderGrey, width: 0.5),
              columnWidths: {
                0: const pw.FlexColumnWidth(0.55),
                1: const pw.FlexColumnWidth(0.9),
                2: const pw.FlexColumnWidth(4.95),
                3: const pw.FlexColumnWidth(0.65),
                4: const pw.FlexColumnWidth(0.95),
                5: const pw.FlexColumnWidth(0.7),
                6: const pw.FlexColumnWidth(1.3),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: _colorNavy),
                  children: [
                    _buildHeaderCell('S.NO.', align: pw.TextAlign.center),
                    _buildHeaderCell('CODE'),
                    _buildHeaderCell('ITEM DESCRIPTION'),
                    _buildHeaderCell('QTY', align: pw.TextAlign.center),
                    _buildHeaderCell('RATE', align: pw.TextAlign.right),
                    _buildHeaderCell('GST', align: pw.TextAlign.center),
                    _buildHeaderCell('TOTAL', align: pw.TextAlign.right),
                  ],
                ),
                ...List.generate(order.items.length, (idx) {
                  final it = order.items[idx];
                  final lineTotal =
                      (it.gstType != 1 ? it.qty * it.rate : it.total)
                          .toStringAsFixed(2);
                  return pw.TableRow(
                    decoration: pw.BoxDecoration(
                      color: idx.isOdd ? _colorRowAlt : PdfColors.white,
                    ),
                    children: [
                      _buildDataCell('${idx + 1}', align: pw.TextAlign.center),
                      _buildDataCell(it.mtcCode),
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(
                            horizontal: 4, vertical: 3),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              it.itemName,
                              style: pw.TextStyle(
                                fontSize: 9.5,
                                fontWeight: pw.FontWeight.bold,
                                color: _colorDarkText,
                              ),
                            ),
                            if (it.description.trim().isNotEmpty)
                              pw.Text(
                                it.description.trim(),
                                style: const pw.TextStyle(
                                  fontSize: 8.0,
                                  color: _colorGreyText,
                                ),
                              ),
                          ],
                        ),
                      ),
                      _buildDataCell('${it.qty}', align: pw.TextAlign.center),
                      _buildDataCell(it.rate.toStringAsFixed(2),
                          align: pw.TextAlign.right),
                      _buildDataCell('${it.gst.toStringAsFixed(0)}%',
                          align: pw.TextAlign.center),
                      _buildDataCell(lineTotal, align: pw.TextAlign.right),
                    ],
                  );
                }),
              ],
            ),
            pw.SizedBox(height: 8),

            // 4. Totals Box on Right
            pw.Row(
              children: [
                pw.Expanded(flex: 5, child: pw.SizedBox()),
                pw.Expanded(
                  flex: 5,
                  child: pw.Table(
                    border:
                        pw.TableBorder.all(color: _colorBorderGrey, width: 0.6),
                    children: [
                      _buildTotalRow('Total Amount',
                          'Rs. ${tableTotalSum.toStringAsFixed(2)}', false),
                      _buildTotalRow('Total GST',
                          'Rs. ${excludingGstSum.toStringAsFixed(2)}', false),
                      if (order.roundOff != 0)
                        _buildTotalRow(
                          'Round Off',
                          '${order.roundOff >= 0 ? '+' : '-'} Rs. ${order.roundOff.abs().toStringAsFixed(2)}',
                          false,
                        ),
                      _buildTotalRow(
                          'Grand Total',
                          'Rs. ${(order.totalAmount + order.discountAmount).toStringAsFixed(2)}',
                          true),
                      _buildTotalRow(
                        '${order.orderType == 'Spot Delivery' ? 'Received' : 'Advance'} (${ExpoOrder.normalizePaymentMode(order.paymentMode)})',
                        'Rs. ${order.advanceAmount.toStringAsFixed(2)}',
                        false,
                      ),
                      if (order.discountAmount > 0)
                        _buildTotalRow(
                          'Discount',
                          '- Rs. ${order.discountAmount.toStringAsFixed(2)}',
                          false,
                        ),
                      _buildTotalRow('Balance Amount',
                          'Rs. ${order.balanceAmount.toStringAsFixed(2)}', true),
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
              pw.SizedBox(height: 4),
              pw.Text(
                'Note: This is an approximate estimate. Final pricing and applicable taxes are subject to actuals on the final tax invoice. This document is issued for reference purposes only and does not constitute a tax invoice. The official original bill will be generated and issued exclusively by the respective branch. Order will be cancelled if not taken delivery within 90 days.',
                textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(fontSize: 6.5, color: _colorGreyText),
              ),
              pw.SizedBox(height: 4),
              _buildBranchesSection(),
              pw.SizedBox(height: 4),
              pw.Container(
                height: 3.5,
                width: double.infinity,
                decoration: const pw.BoxDecoration(
                  color: _colorLimeGreen,
                  borderRadius: pw.BorderRadius.all(pw.Radius.circular(2)),
                ),
              ),
              pw.SizedBox(height: 3),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Page ${context.pageNumber} of ${context.pagesCount}',
                    style:
                        const pw.TextStyle(fontSize: 7.5, color: _colorGreyText),
                  ),
                  pw.Text(
                    'Generated on: ${DateFormat("dd/MM/yyyy hh:mm a").format(DateTime.now())}',
                    style:
                        const pw.TextStyle(fontSize: 7.5, color: _colorGreyText),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    final bytes = await pdf.save();
    final dir = await getTemporaryDirectory();
    final safeShop =
        order.shopName.replaceAll(RegExp(r'[^a-zA-Z0-9\s]'), '').trim();
    final safeType =
        order.orderType.replaceAll(RegExp(r'[^a-zA-Z0-9\s]'), '').trim();
    final dateStr = DateFormat('dd-MM-yyyy').format(order.orderDate);
    final billPart = order.billNumber != null ? ' #${order.billNumber}' : '';
    final fileName = '$safeShop$billPart $safeType $dateStr.pdf';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);
    await Share.shareXFiles([XFile(file.path)]);
    return file;
  }

  pw.Widget _buildInfoRow(String label, String value, PdfColor labelColor,
      {double labelWidth = 82}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.Row(
        children: [
          pw.Container(
            width: labelWidth,
            padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 2.5),
            decoration: pw.BoxDecoration(
              color: labelColor,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
            ),
            child: pw.Text(
              label.toUpperCase(),
              style: pw.TextStyle(
                fontSize: 8.5,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
            ),
          ),
          pw.SizedBox(width: 4),
          pw.Expanded(
            child: pw.Container(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 2.5),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: _colorBorderGrey, width: 0.7),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
              ),
              child: pw.Text(
                value.toUpperCase(),
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: _colorDarkText,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildHeaderCell(String text,
      {pw.TextAlign align = pw.TextAlign.left}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.white,
        ),
      ),
    );
  }

  pw.Widget _buildDataCell(String text,
      {pw.TextAlign align = pw.TextAlign.left}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: pw.Text(
        text,
        textAlign: align,
        style: const pw.TextStyle(fontSize: 9.5, color: _colorDarkText),
      ),
    );
  }

  pw.TableRow _buildTotalRow(String label, String value, bool highlight) {
    return pw.TableRow(
      decoration:
          highlight ? const pw.BoxDecoration(color: _colorLightBg) : null,
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: highlight ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: highlight ? _colorNavy : _colorDarkText,
            ),
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: pw.Text(
            value,
            textAlign: pw.TextAlign.right,
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: highlight ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: highlight ? _colorNavy : _colorDarkText,
            ),
          ),
        ),
      ],
    );
  }

  String _fullBranchName(String code) {
    const map = {
      'BGR': 'BENGALURU',
      'CBE': 'COIMBATORE',
      'CHN': 'CHENNAI',
      'CLT': 'CALICUT',
      'DXB': 'DUBAI',
      'EKM': 'KOCHI',
      'HYD': 'HYDERABAD',
      'KKM': 'KAYAMKULAM',
      'KSD': 'KASARAGOD',
      'KTM': 'KOTTAYAM',
      'PKD': 'PALAKKAD',
      'PKT': 'POOKKOTTUR',
      'PMN': 'PERINTHALMANNA',
      'TLY': 'THALASSERY',
      'TRR': 'TIRUR',
      'TSR': 'THRISSUR',
      'TVM': 'TRIVANDRUM',
      'UDP': 'UDUPI',
      'VDK': 'VADAKARA',
      'WND': 'WAYANAD',
    };
    final upper = code.trim().toUpperCase();
    return map[upper] ?? upper;
  }

  pw.Widget _buildBranchesSection() {
    const allBranches = [
      ('DUBAI', '+971 55 447 1448'),
      ('HYDERABAD', '+91 99956 22203'),
      ('BENGALURU', '+91 82175 36200'),
      ('CHENNAI', '+91 95390 50060'),
      ('UDUPI', '+91 88910 17775'),
      ('COIMBATORE', '+91 73737 03015'),
      ('TRIVANDRUM', '+91 90481 73174'),
      ('KAYAMKULAM', '+91 81578 68882'),
      ('KOTTAYAM', '+91 90725 78355'),
      ('KOCHI', '+91 97786 89257'),
      ('THRISSUR', '+91 75580 15000'),
      ('PALAKKAD', '+91 90725 81095'),
      ('PERINTHALMANNA', '81118 85757'),
      ('TIRUR', '+91 81118 85760'),
      ('POOKKOTTUR', '+91 92076 26666'),
      ('WAYANAD', '+91 75929 34444'),
      ('CALICUT', '+91 94959 21876'),
      ('VADAKARA', '+91 90725 78352'),
      ('THALASSERY', '+91 99958 50060'),
      ('KASARAGOD', '+91 75940 33107'),
    ];

    final rows = <pw.TableRow>[];
    for (int i = 0; i < allBranches.length; i += 5) {
      rows.add(
        pw.TableRow(
          children: List.generate(5, (c) {
            final b = allBranches[i + c];
            return pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              child: pw.Column(
                children: [
                  pw.Text(
                    b.$1,
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                      fontSize: 7.5,
                      fontWeight: pw.FontWeight.bold,
                      color: _colorNavy,
                    ),
                  ),
                  pw.Text(
                    b.$2,
                    textAlign: pw.TextAlign.center,
                    style: const pw.TextStyle(
                      fontSize: 7.2,
                      color: _colorDarkText,
                    ),
                  ),
                ],
              ),
            );
          }),
        ),
      );
    }

    return pw.Column(
      children: [
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(vertical: 3),
          decoration: const pw.BoxDecoration(
            color: _colorNavy,
            borderRadius: pw.BorderRadius.only(
              topLeft: pw.Radius.circular(3),
              topRight: pw.Radius.circular(3),
            ),
          ),
          child: pw.Text(
            'OUR BRANCHES',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
          ),
        ),
        pw.Table(
          border: pw.TableBorder.all(color: _colorBorderGrey, width: 0.5),
          children: rows,
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          'www.mtckerala.com',
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
            fontSize: 7.5,
            fontWeight: pw.FontWeight.bold,
            color: _colorLimeGreen,
          ),
        ),
      ],
    );
  }
}
