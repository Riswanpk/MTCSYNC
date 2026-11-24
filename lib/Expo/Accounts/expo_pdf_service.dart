import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect, Size;
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../expo_service.dart';
import '../expo_supabase_config.dart';

class ExpoPdfService {
  ExpoPdfService._();
  static final ExpoPdfService instance = ExpoPdfService._();

  static final PdfColor _colorNavy = PdfColor(10, 61, 122);
  static final PdfColor _colorNavyAccent = PdfColor(13, 71, 161);
  static final PdfColor _colorLimeGreen = PdfColor(115, 168, 50);
  static final PdfColor _colorLightBg = PdfColor(238, 244, 249);
  static final PdfColor _colorRowAlt = PdfColor(246, 248, 250);
  static final PdfColor _colorBorderGrey = PdfColor(209, 213, 219);
  static final PdfColor _colorDarkText = PdfColor(17, 24, 39);
  static final PdfColor _colorGreyText = PdfColor(107, 114, 128);
  static final PdfColor _colorWhite = PdfColor(255, 255, 255);

  /// Generates an Order Booking / Receipt PDF using Syncfusion PDF and returns
  /// the saved File. Note & OUR BRANCHES are always pinned to the bottom of the
  /// last page without leaving blank gaps on earlier pages.
  Future<File> exportOrderPdf(ExpoOrder order, {Exhibition? exhibition}) async {
    final document = PdfDocument();
    document.pageSettings.size = PdfPageSize.a4;
    document.pageSettings.margins.all = 20;

    final fontRegular = PdfStandardFont(PdfFontFamily.timesRoman, 10);
    final fontBold =
        PdfStandardFont(PdfFontFamily.timesRoman, 10, style: PdfFontStyle.bold);
    final fontHeader =
        PdfStandardFont(PdfFontFamily.timesRoman, 16, style: PdfFontStyle.bold);
    final fontSubHeader =
        PdfStandardFont(PdfFontFamily.timesRoman, 12, style: PdfFontStyle.bold);
    final fontSmall = PdfStandardFont(PdfFontFamily.timesRoman, 8.5);
    final fontSmallBold = PdfStandardFont(PdfFontFamily.timesRoman, 8.5,
        style: PdfFontStyle.bold);

    Uint8List? logoBytes;
    try {
      final data = await rootBundle.load('assets/images/bill_logo.png');
      logoBytes = data.buffer.asUint8List();
    } catch (_) {}

    final page = document.pages.add();
    final graphics = page.graphics;
    final pageWidth = page.getClientSize().width;
    final pageHeight = page.getClientSize().height;
    double y = 0;

    // 1. Header Banner
    _drawRoundedRect(
      graphics,
      Rect.fromLTWH(0, y, pageWidth, 28),
      radius: 4,
      brush: PdfSolidBrush(_colorNavy),
    );
    graphics.drawString(
      'MALABAR TRADING COMPANY',
      fontHeader,
      brush: PdfSolidBrush(_colorWhite),
      bounds: Rect.fromLTWH(0, y + 6, pageWidth, 20),
      format: PdfStringFormat(alignment: PdfTextAlignment.center),
    );
    y += 32;

    final String formTitle =
        order.orderType == 'Booking' ? 'ORDER BOOKING FORM' : 'ORDER RECEIPT';
    graphics.drawString(
      formTitle,
      fontSubHeader,
      brush: PdfSolidBrush(_colorNavy),
      bounds: Rect.fromLTWH(0, y, pageWidth, 16),
      format: PdfStringFormat(alignment: PdfTextAlignment.center),
    );
    y += 20;

    // 2. Customer & Order Info
    final leftWidth = pageWidth * 0.58;
    final rightX = leftWidth + 14;
    final rightWidth = pageWidth - rightX;

    String deliveryText = order.orderType;
    if (order.orderType == 'Booking' && order.deliveryDate != null) {
      deliveryText =
          'Booking (${DateFormat('dd/MM/yyyy').format(order.deliveryDate!)})';
    } else if (order.orderType == 'Stall Delivery') {
      deliveryText = 'Stall Delivery (${order.stallPickupStatus})';
    }

    double leftY = y;
    final leftRows = [
      ('Shop Name', order.shopName, _colorLimeGreen),
      ('Customer Name', order.customerName, _colorLimeGreen),
      ('Phone No.', order.phone, _colorLimeGreen),
      ('Place', order.place, _colorLimeGreen),
      ('District', order.district, _colorLimeGreen),
      ('State', order.state, _colorLimeGreen),
      ('Sales Rep.', order.createdUserName, _colorLimeGreen),
      ('Delivery Type', deliveryText, _colorNavy),
    ];

    for (final row in leftRows) {
      _drawInfoRow(graphics, 0, leftY, leftWidth, 16, row.$1, row.$2, row.$3,
          fontSmallBold, fontBold);
      leftY += 18;
    }

    double rightY = y;
    if (logoBytes != null) {
      final img = PdfBitmap(logoBytes);
      graphics.drawImage(
          img, Rect.fromLTWH(rightX + (rightWidth - 65) / 2, rightY, 65, 52));
      rightY += 54;
    }
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

    if (exhibitionName.isNotEmpty) {
      graphics.drawString(
        exhibitionName.toUpperCase(),
        fontSmallBold,
        brush: PdfSolidBrush(_colorNavy),
        bounds: Rect.fromLTWH(rightX, rightY, rightWidth, 14),
        format: PdfStringFormat(alignment: PdfTextAlignment.center),
      );
      rightY += 14;
    }

    final rightRows = [
      ('Date', DateFormat('dd/MM/yyyy').format(order.orderDate)),
      ('Bill No.', '#${order.billNumber}'),
      ('Branch', order.preferredBranch),
      (
        'Pref. Salesman',
        order.preferredSalesman.trim().isNotEmpty
            ? order.preferredSalesman.trim()
            : '-'
      ),
    ];
    for (final row in rightRows) {
      _drawInfoRow(graphics, rightX, rightY, rightWidth, 16, row.$1, row.$2,
          _colorLimeGreen, fontSmallBold, fontBold,
          labelWidth: 68);
      rightY += 18;
    }

    y = (leftY > rightY ? leftY : rightY) + 4;

    if (order.notes.trim().isNotEmpty) {
      graphics.drawString(
        'Notes: ${order.notes.trim()}',
        fontSmall,
        brush: PdfSolidBrush(_colorDarkText),
        bounds: Rect.fromLTWH(0, y, pageWidth, 14),
      );
      y += 14;
    }

    // 3. Items Grid (auto-paginates across pages with no reserved footer gap!)
    final grid = PdfGrid();
    grid.columns.add(count: 7);
    grid.headers.add(1);

    final colWidths = [
      pageWidth * 0.06, // S.No
      pageWidth * 0.10, // Code
      pageWidth * 0.40, // Description
      pageWidth * 0.08, // Qty
      pageWidth * 0.12, // Rate
      pageWidth * 0.08, // GST
      pageWidth * 0.16, // Total
    ];
    for (int i = 0; i < 7; i++) {
      grid.columns[i].width = colWidths[i];
    }

    final headerRow = grid.headers[0];
    final headers = [
      'S.NO.',
      'CODE',
      'ITEM DESCRIPTION',
      'QTY',
      'RATE',
      'GST',
      'TOTAL'
    ];
    for (int i = 0; i < 7; i++) {
      headerRow.cells[i].value = headers[i];
      headerRow.cells[i].style = PdfGridCellStyle(
        backgroundBrush: PdfSolidBrush(_colorNavy),
        textBrush: PdfSolidBrush(_colorWhite),
        font: fontSmallBold,
        borders: PdfBorders(
          left: PdfPen(_colorBorderGrey, width: 0.5),
          right: PdfPen(_colorBorderGrey, width: 0.5),
          top: PdfPen(_colorBorderGrey, width: 0.5),
          bottom: PdfPen(_colorBorderGrey, width: 0.5),
        ),
        cellPadding: PdfPaddings(left: 4, right: 4, top: 4, bottom: 4),
      );
      headerRow.cells[i].stringFormat = PdfStringFormat(
        alignment: i == 0 || i == 3 || i == 5
            ? PdfTextAlignment.center
            : (i == 4 || i == 6
                ? PdfTextAlignment.right
                : PdfTextAlignment.left),
        lineAlignment: PdfVerticalAlignment.middle,
      );
    }

    for (int idx = 0; idx < order.items.length; idx++) {
      final it = order.items[idx];
      final row = grid.rows.add();
      final desc = it.description.trim().isNotEmpty
          ? '${it.itemName}\n${it.description.trim()}'
          : it.itemName;
      final lineTotal =
          (it.gstType != 1 ? it.qty * it.rate : it.total).toStringAsFixed(2);
      final vals = [
        '${idx + 1}',
        it.mtcCode,
        desc,
        '${it.qty}',
        it.rate.toStringAsFixed(2),
        '${it.gst.toStringAsFixed(0)}%',
        lineTotal,
      ];
      final bg = idx.isOdd ? _colorRowAlt : _colorWhite;
      for (int i = 0; i < 7; i++) {
        row.cells[i].value = vals[i];
        row.cells[i].style = PdfGridCellStyle(
          backgroundBrush: PdfSolidBrush(bg),
          textBrush: PdfSolidBrush(_colorDarkText),
          font: i == 2 ? fontSmallBold : fontSmall,
          borders: PdfBorders(
            left: PdfPen(_colorBorderGrey, width: 0.5),
            right: PdfPen(_colorBorderGrey, width: 0.5),
            top: PdfPen(_colorBorderGrey, width: 0.5),
            bottom: PdfPen(_colorBorderGrey, width: 0.5),
          ),
          cellPadding: PdfPaddings(left: 4, right: 4, top: 3, bottom: 3),
        );
        row.cells[i].stringFormat = PdfStringFormat(
          alignment: i == 0 || i == 3 || i == 5
              ? PdfTextAlignment.center
              : (i == 4 || i == 6
                  ? PdfTextAlignment.right
                  : PdfTextAlignment.left),
          lineAlignment: PdfVerticalAlignment.middle,
          wordWrap: PdfWordWrapType.word,
        );
      }
    }

    final descSubFont = PdfStandardFont(PdfFontFamily.timesRoman, 7.0);
    grid.beginCellLayout = (sender, args) {
      if (!args.isHeaderRow && args.cellIndex == 2) {
        final item = order.items[args.rowIndex];
        if (item.description.trim().isNotEmpty) {
          args.skip = true;
          final bg = args.rowIndex.isOdd ? _colorRowAlt : _colorWhite;
          args.graphics.drawRectangle(
            brush: PdfSolidBrush(bg),
            pen: PdfPen(_colorBorderGrey, width: 0.5),
            bounds: args.bounds,
          );
          final nameLayout = fontSmallBold.measureString(
            item.itemName,
            layoutArea: Size(args.bounds.width - 8, args.bounds.height),
          );
          args.graphics.drawString(
            item.itemName,
            fontSmallBold,
            brush: PdfSolidBrush(_colorDarkText),
            bounds: Rect.fromLTWH(
              args.bounds.left + 4,
              args.bounds.top + 3,
              args.bounds.width - 8,
              nameLayout.height + 2,
            ),
          );
          args.graphics.drawString(
            item.description.trim(),
            descSubFont,
            brush: PdfSolidBrush(_colorGreyText),
            bounds: Rect.fromLTWH(
              args.bounds.left + 4,
              args.bounds.top + 3 + nameLayout.height + 1,
              args.bounds.width - 8,
              args.bounds.height - nameLayout.height - 6,
            ),
          );
        }
      }
    };

    final gridResult = grid.draw(
      page: page,
      bounds: Rect.fromLTWH(0, y, pageWidth, pageHeight - 28),
    )!;

    PdfPage lastPage = gridResult.page;
    double endY = gridResult.bounds.bottom + 10;

    // 4. Totals Box on the right
    final totalsHeight = order.roundOff != 0 ? 102.0 : 86.0;
    const bottomSectionHeight = 152.0; // Note + OUR BRANCHES + footer

    if (endY + totalsHeight > pageHeight - 28) {
      lastPage = document.pages.add();
      endY = 0;
    }

    _drawTotalsBox(
      lastPage.graphics,
      pageWidth * 0.52,
      endY,
      pageWidth * 0.48,
      order,
      fontRegular,
      fontBold,
    );
    endY += totalsHeight + 10;

    // If Note + Branches won't fit at the bottom of current lastPage, add a new page
    if (endY + bottomSectionHeight > pageHeight) {
      lastPage = document.pages.add();
    }

    // 5. Pin Note + OUR BRANCHES to the exact bottom of the last page
    final bottomStartY = pageHeight - bottomSectionHeight;
    final lastG = lastPage.graphics;

    const noteText =
        'Note: This is an approximate estimate. Final pricing and applicable taxes are subject to actuals on the final tax invoice. This document is issued for reference purposes only and does not constitute a tax invoice. The official original bill will be generated and issued exclusively by the respective branch. Order will be cancelled if not taken delivery within 90 days.';
    lastG.drawString(
      noteText,
      PdfStandardFont(PdfFontFamily.timesRoman, 6.8),
      brush: PdfSolidBrush(_colorGreyText),
      bounds: Rect.fromLTWH(0, bottomStartY, pageWidth, 24),
      format: PdfStringFormat(alignment: PdfTextAlignment.center),
    );

    _drawBranchesSection(
      lastG,
      0,
      bottomStartY + 26,
      pageWidth,
      fontSmallBold,
    );

    // 6. Draw page footer (lime bar + Page X of Y + Generated on) on EVERY page
    final totalPages = document.pages.count;
    final generatedOn =
        'Generated on: ${DateFormat("dd/MM/yyyy hh:mm a").format(DateTime.now())}';
    for (int i = 0; i < totalPages; i++) {
      final p = document.pages[i];
      final g = p.graphics;
      final pW = p.getClientSize().width;
      final pH = p.getClientSize().height;
      _drawRoundedRect(
        g,
        Rect.fromLTWH(0, pH - 18, pW, 3.5),
        radius: 1.5,
        brush: PdfSolidBrush(_colorLimeGreen),
      );
      g.drawString(
        'Page ${i + 1} of $totalPages',
        fontSmall,
        brush: PdfSolidBrush(_colorGreyText),
        bounds: Rect.fromLTWH(0, pH - 12, pW / 2, 12),
      );
      g.drawString(
        generatedOn,
        fontSmall,
        brush: PdfSolidBrush(_colorGreyText),
        bounds: Rect.fromLTWH(pW / 2, pH - 12, pW / 2, 12),
        format: PdfStringFormat(alignment: PdfTextAlignment.right),
      );
    }

    final bytes = await document.save();
    document.dispose();

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
    await OpenFile.open(file.path);
    return file;
  }

  void _drawRoundedRect(
    PdfGraphics g,
    Rect rect, {
    required double radius,
    PdfBrush? brush,
    PdfPen? pen,
  }) {
    final path = PdfPath();
    final r = radius;
    path.addArc(Rect.fromLTWH(rect.left, rect.top, r * 2, r * 2), 180, 90);
    path.addArc(
        Rect.fromLTWH(rect.right - r * 2, rect.top, r * 2, r * 2), 270, 90);
    path.addArc(
        Rect.fromLTWH(rect.right - r * 2, rect.bottom - r * 2, r * 2, r * 2),
        0,
        90);
    path.addArc(
        Rect.fromLTWH(rect.left, rect.bottom - r * 2, r * 2, r * 2), 90, 90);
    path.closeFigure();
    g.drawPath(path, brush: brush, pen: pen);
  }

  void _drawInfoRow(
    PdfGraphics g,
    double x,
    double y,
    double totalWidth,
    double height,
    String label,
    String value,
    PdfColor labelColor,
    PdfFont labelFont,
    PdfFont valueFont, {
    double labelWidth = 84,
  }) {
    _drawRoundedRect(
      g,
      Rect.fromLTWH(x, y, labelWidth, height),
      radius: 2,
      brush: PdfSolidBrush(labelColor),
    );
    g.drawString(
      label.toUpperCase(),
      labelFont,
      brush: PdfSolidBrush(_colorWhite),
      bounds: Rect.fromLTWH(x + 5, y + 3, labelWidth - 8, height - 4),
    );
    final valX = x + labelWidth + 4;
    final valW = totalWidth - labelWidth - 4;
    _drawRoundedRect(
      g,
      Rect.fromLTWH(valX, y, valW, height),
      radius: 2,
      pen: PdfPen(_colorBorderGrey, width: 0.7),
    );
    g.drawString(
      value.toUpperCase(),
      valueFont,
      brush: PdfSolidBrush(_colorDarkText),
      bounds: Rect.fromLTWH(valX + 5, y + 3, valW - 8, height - 4),
    );
  }

  void _drawTotalsBox(
    PdfGraphics g,
    double x,
    double y,
    double width,
    ExpoOrder order,
    PdfFont fontRegular,
    PdfFont fontBold,
  ) {
    final double tableTotalSum = order.items.fold(
      0.0,
      (acc, it) => acc + (it.gstType != 1 ? it.qty * it.rate : it.total),
    );
    final double excludingGstSum = order.items.fold(
      0.0,
      (acc, it) =>
          acc + (it.gstType != 1 ? (it.qty * it.rate * (it.gst / 100.0)) : 0.0),
    );

    final rows = <(String, String, bool)>[
      ('Total Amount', 'Rs. ${tableTotalSum.toStringAsFixed(2)}', false),
      ('Total GST', 'Rs. ${excludingGstSum.toStringAsFixed(2)}', false),
      if (order.roundOff != 0)
        (
          'Round Off',
          '${order.roundOff >= 0 ? '+' : '-'} Rs. ${order.roundOff.abs().toStringAsFixed(2)}',
          false
        ),
      ('Grand Total', 'Rs. ${order.totalAmount.toStringAsFixed(2)}', true),
      (
        'Advance (${ExpoOrder.normalizePaymentMode(order.paymentMode)})',
        'Rs. ${order.advanceAmount.toStringAsFixed(2)}',
        false
      ),
      ('Balance Amount', 'Rs. ${order.balanceAmount.toStringAsFixed(2)}', true),
    ];

    double curY = y;
    const rowH = 16.0;
    final labelW = width * 0.56;
    final valW = width * 0.44;

    for (final r in rows) {
      if (r.$3) {
        g.drawRectangle(
          brush: PdfSolidBrush(_colorLightBg),
          bounds: Rect.fromLTWH(x, curY, width, rowH),
        );
      }
      g.drawRectangle(
        pen: PdfPen(_colorBorderGrey, width: 0.6),
        bounds: Rect.fromLTWH(x, curY, labelW, rowH),
      );
      g.drawRectangle(
        pen: PdfPen(_colorBorderGrey, width: 0.6),
        bounds: Rect.fromLTWH(x + labelW, curY, valW, rowH),
      );
      g.drawString(
        r.$1,
        r.$3 ? fontBold : fontRegular,
        brush: PdfSolidBrush(r.$3 ? _colorNavy : _colorDarkText),
        bounds: Rect.fromLTWH(x + 6, curY + 3, labelW - 10, rowH - 4),
      );
      g.drawString(
        r.$2,
        r.$3 ? fontBold : fontRegular,
        brush: PdfSolidBrush(r.$3 ? _colorNavy : _colorDarkText),
        bounds: Rect.fromLTWH(x + labelW + 4, curY + 3, valW - 10, rowH - 4),
        format: PdfStringFormat(alignment: PdfTextAlignment.right),
      );
      curY += rowH;
    }
  }

  void _drawBranchesSection(
    PdfGraphics g,
    double x,
    double y,
    double width,
    PdfFont fontBold,
  ) {
    // Full-width navy header bar
    _drawRoundedRect(
      g,
      Rect.fromLTWH(x, y, width, 16),
      radius: 3,
      brush: PdfSolidBrush(_colorNavy),
    );
    g.drawString(
      'OUR BRANCHES',
      PdfStandardFont(PdfFontFamily.timesRoman, 8.5,
          style: PdfFontStyle.bold),
      brush: PdfSolidBrush(_colorWhite),
      bounds: Rect.fromLTWH(x, y + 3, width, 12),
      format: PdfStringFormat(alignment: PdfTextAlignment.center),
    );

    double curY = y + 16;
    final nameFont =
        PdfStandardFont(PdfFontFamily.timesRoman, 7.5, style: PdfFontStyle.bold);
    final phoneFont = PdfStandardFont(PdfFontFamily.timesRoman, 7.2);

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
      ('THALASSERI', '+91 99958 50060'),
      ('KASARAGOD', '+91 75940 33107'),
    ];

    // 5 columns x 4 rows = 20 branches
    const int cols = 5;
    final double cellW = width / cols;
    const double cellH = 21.0;

    for (int i = 0; i < allBranches.length; i += cols) {
      for (int c = 0; c < cols; c++) {
        final b = allBranches[i + c];
        final cx = x + c * cellW;
        g.drawRectangle(
          pen: PdfPen(_colorBorderGrey, width: 0.6),
          bounds: Rect.fromLTWH(cx, curY, cellW, cellH),
        );
        g.drawString(
          b.$1,
          nameFont,
          brush: PdfSolidBrush(_colorNavy),
          bounds: Rect.fromLTWH(cx + 2, curY + 2.5, cellW - 4, 9),
          format: PdfStringFormat(alignment: PdfTextAlignment.center),
        );
        g.drawString(
          b.$2,
          phoneFont,
          brush: PdfSolidBrush(_colorDarkText),
          bounds: Rect.fromLTWH(cx + 2, curY + 11, cellW - 4, 9),
          format: PdfStringFormat(alignment: PdfTextAlignment.center),
        );
      }
      curY += cellH;
    }
  }
}
