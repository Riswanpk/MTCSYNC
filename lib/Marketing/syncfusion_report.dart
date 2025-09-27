import 'dart:io';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class SyncfusionReport {
  /// Generate Excel report using Syncfusion XlsIO
  static Future<File> generateExcel(List<Map<String, dynamic>> data) async {
    final workbook = xlsio.Workbook();

    // Group data by 'formType'
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final row in data) {
      final formType = row['formType']?.toString() ?? 'Unknown';
      grouped.putIfAbsent(formType, () => []).add(row);
    }

    int sheetIndex = 0;
    for (final entry in grouped.entries) {
      final sheet = sheetIndex == 0
          ? workbook.worksheets[0]
          : workbook.worksheets.addWithName(entry.key);
      sheet.name = entry.key;

      final formData = entry.value;
      if (formData.isEmpty) {
        sheet.getRangeByIndex(1, 1).setText("No data available");
      } else {
        final headers = formData.first.keys.toList();

        // Add headers
        for (int i = 0; i < headers.length; i++) {
          final cell = sheet.getRangeByIndex(1, i + 1);
          cell.setText(headers[i]);
          cell.cellStyle.bold = true;
          cell.cellStyle.backColor = "#D9E1F2";
        }

        // Add rows
        for (int row = 0; row < formData.length; row++) {
          final rowData = formData[row];
          for (int col = 0; col < headers.length; col++) {
            final key = headers[col];
            final value = rowData[key];
            final cell = sheet.getRangeByIndex(row + 2, col + 1);

            if (key.toLowerCase().contains('image') && value is String && value.isNotEmpty) {
              final imageUrl = value.startsWith('=') ? value.substring(1) : value;
              cell.setFormula('HYPERLINK(IMAGE("$imageUrl"))');
              sheet.getRangeByIndex(1, col + 1).columnWidth = 30;
              sheet.getRangeByIndex(row + 2, 1).rowHeight = 120;
            } else if (key.toLowerCase().contains('location')) {
              final lat = rowData['lat']?.toString();
              final long = rowData['long']?.toString();
              if (lat != null && long != null) {
                cell.setFormula('HYPERLINK("https://www.google.com/maps?q=$lat,$long","Open in Google Maps")');
              } else {
                cell.setText(value?.toString() ?? '');
              }
            } else if (value is DateTime) {
              cell.dateTime = value;
              cell.numberFormat = 'yyyy-mm-dd hh:mm';
            } else {
              cell.setText(value?.toString() ?? '');
            }
          }
        }

        // Autofit columns except image columns
        for (int i = 0; i < headers.length; i++) {
          if (!headers[i].toLowerCase().contains('image')) {
            sheet.autoFitColumn(i + 1);
          }
        }
      }
      sheetIndex++;
    }

    final bytes = workbook.saveAsStream();
    workbook.dispose();

    final dir = await getApplicationDocumentsDirectory();
    final file = File(
        "${dir.path}/Report${DateTime.now().millisecondsSinceEpoch}.xlsx");
    await file.writeAsBytes(bytes, flush: true);

    return file;
  }

  /// Share the generated Excel file
  static Future<void> shareExcel(List<Map<String, dynamic>> data) async {
    final file = await generateExcel(data);
    await Share.shareXFiles([XFile(file.path)], text: "Syncfusion Marketing Report");
  }
}
