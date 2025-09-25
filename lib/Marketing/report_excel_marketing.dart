import 'package:excel/excel.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

Future<File> generateExcelMarketingReport(List<Map<String, dynamic>> data) async {
  final excel = Excel.createExcel();
  final sheet = excel['Report'];

  // Add header row
  if (data.isNotEmpty) {
    sheet.appendRow(
      data.first.keys.map((key) => TextCellValue(key)).toList(),
    );
  }

  // Add rows
  for (var entry in data) {
    sheet.appendRow(
      entry.values.map((v) {
        if (v is DateTime) {
          return TextCellValue(v.toIso8601String());
        } else if (v is num) {
          return DoubleCellValue(v.toDouble());
        } else {
          return TextCellValue(v?.toString() ?? '');
        }
      }).toList(),
    );
  }

  final dir = await getApplicationDocumentsDirectory();
  final file = File(
    '${dir.path}/marketing_report_${DateTime.now().millisecondsSinceEpoch}.xlsx',
  );
  await file.writeAsBytes(excel.encode()!);
  return file;
}
