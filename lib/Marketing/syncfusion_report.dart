import 'dart:io';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class SyncfusionReport {
  /// Generate Excel report using Syncfusion XlsIO
  static Future<File> generateExcel(List<Map<String, dynamic>> data) async {
    final workbook = xlsio.Workbook();
    final sheet = workbook.worksheets[0];
    sheet.name = "Marketing Report";

    if (data.isEmpty) {
      sheet.getRangeByIndex(1, 1).setText("No data available");
    } else {
      // Extract headers from keys of first map
      final headers = data.first.keys.toList();

      // Add headers
      for (int i = 0; i < headers.length; i++) {
        final cell = sheet.getRangeByIndex(1, i + 1);
        cell.setText(headers[i]);
        cell.cellStyle.bold = true;
        cell.cellStyle.backColor = "#D9E1F2"; // Light blue
      }

      // Add rows
      for (int row = 0; row < data.length; row++) {
        final rowData = data[row];
        for (int col = 0; col < headers.length; col++) {
          final value = rowData[headers[col]];
          final cell = sheet.getRangeByIndex(row + 2, col + 1);

          if (value is DateTime) {
            cell.dateTime = value;
            cell.numberFormat = 'yyyy-mm-dd hh:mm';
          } else {
            cell.setText(value?.toString() ?? '');
          }
        }
      }

      // Autofit columns
      for (int i = 1; i <= headers.length; i++) {
        sheet.autoFitColumn(i);
      }
    }

    final bytes = workbook.saveAsStream();
    workbook.dispose();

    final dir = await getApplicationDocumentsDirectory();
    final file = File(
        "${dir.path}/syncfusion_marketing_report_${DateTime.now().millisecondsSinceEpoch}.xlsx");
    await file.writeAsBytes(bytes, flush: true);

    return file;
  }

  /// Share the generated Excel file
  static Future<void> shareExcel(List<Map<String, dynamic>> data) async {
    final file = await generateExcel(data);
    await Share.shareXFiles([XFile(file.path)], text: "Syncfusion Marketing Report");
  }
}
