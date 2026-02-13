import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart' as ex;
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

String monthShort(int month) {
  const months = [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return months[month];
}

int isoWeekNumber(DateTime date) {
  final thursday = date.subtract(Duration(days: (date.weekday + 6) % 7 - 3));
  final firstThursday = DateTime(date.year, 1, 4);
  final diff = thursday.difference(firstThursday).inDays ~/ 7;
  return 1 + diff;
}

Future<void> exportAndSendExcel(BuildContext context, {int? year, int? month}) async {
  try {
    final now = DateTime.now();
    final reportYear = year ?? now.year;
    final reportMonth = month ?? now.month;
    final monthStart = DateTime(reportYear, reportMonth, 1);
    final monthEnd = DateTime(reportYear, reportMonth + 1, 1);
    final daysInMonth = monthEnd.difference(monthStart).inDays;

    final formsSnap = await FirebaseFirestore.instance
        .collection('dailyform')
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
        .where('timestamp', isLessThan: Timestamp.fromDate(monthEnd))
        .get();

    final usersSnap = await FirebaseFirestore.instance.collection('users').get();
    final userMap = {for (var doc in usersSnap.docs) doc.id: doc.data()};
    final branchMap = <String, Map<String, List<Map<String, dynamic>>>>{};

    for (var doc in formsSnap.docs) {
      final data = doc.data();
      final user = userMap[data['userId']] ?? {};
      final branch = user['branch'] ?? 'Unknown';
      branchMap.putIfAbsent(branch, () => {});
      branchMap[branch]!.putIfAbsent(data['userId'], () => []);
      branchMap[branch]![data['userId']]!.add(data);
    }

    final excel = ex.Excel.createExcel();
    branchMap.forEach((branch, users) {
      final sheet = excel[branch];
      int rowIdx = 0;
      users.forEach((userId, forms) {
        final username = forms.first['userName'] ?? 'User';
        sheet.cell(ex.CellIndex.indexByString("A${rowIdx + 1}")).value = ex.TextCellValue(username);
        rowIdx += 2;

        // DETAILED DAILY TABLES
        final dateRow = [ex.TextCellValue('Date')];
        for (int d = 0; d < daysInMonth; d++) {
          final date = monthStart.add(Duration(days: d));
          dateRow.add(ex.TextCellValue('${date.day}-${date.month < 10 ? '0' : ''}${date.month}'));
        }

        Map<String, dynamic>? getFormForDate(List<Map<String, dynamic>> forms, DateTime date) {
          return forms.firstWhere(
            (form) {
              final ts = form['timestamp'];
              final formDate = ts is Timestamp ? ts.toDate() : DateTime.parse(ts.toString());
              return formDate.year == date.year && formDate.month == date.month && formDate.day == date.day;
            },
            orElse: () => {},
          );
        }

        // ATTENDANCE TABLE
        sheet.appendRow([ex.TextCellValue('Attendance'), ...dateRow.skip(1)]);
        for (int i = 0; i < dateRow.length; i++) {
          final cell = sheet.cell(ex.CellIndex.indexByColumnRow(rowIndex: sheet.maxRows - 1, columnIndex: i));
          cell.cellStyle = ex.CellStyle(
            bold: true,
            backgroundColorHex: ex.ExcelColor.fromHexString("#CFE2F3"),
          );
        }
        final attendanceRow = [ex.TextCellValue('Status')];
        for (int d = 0; d < daysInMonth; d++) {
          final date = monthStart.add(Duration(days: d));
          final form = getFormForDate(forms, date);
          String status = '-';
          if (form != null && form.isNotEmpty) {
            status = form['attendanceStatus'] ?? form['attendance'] ?? '-';
          }
          attendanceRow.add(ex.TextCellValue(status));
        }
        sheet.appendRow(attendanceRow);

        // DRESS CODE TABLE
        sheet.appendRow([ex.TextCellValue('Dress Code'), ...dateRow.skip(1)]);
        for (int i = 0; i < dateRow.length; i++) {
          final cell = sheet.cell(ex.CellIndex.indexByColumnRow(rowIndex: sheet.maxRows - 1, columnIndex: i));
          cell.cellStyle = ex.CellStyle(
            bold: true,
            backgroundColorHex: ex.ExcelColor.fromHexString("#FCE5CD"),
          );
        }
        final dressCats = ['Clean Uniform', 'Keep Inside', 'Neat Hair'];
        for (final cat in dressCats) {
          final row = [ex.TextCellValue(cat)];
          for (int d = 0; d < daysInMonth; d++) {
            final date = monthStart.add(Duration(days: d));
            final form = getFormForDate(forms, date);
            if (form == null || form.isEmpty) {
              row.add(ex.TextCellValue('-')); // Not entered
            } else {
              bool value = false;
              if (cat == 'Clean Uniform') value = form['dressCode']?['cleanUniform'] ?? false;
              if (cat == 'Keep Inside') value = form['dressCode']?['keepInside'] ?? false;
              if (cat == 'Neat Hair') value = form['dressCode']?['neatHair'] ?? false;
              row.add(ex.TextCellValue(value ? '✔' : '✘'));
            }
          }
          sheet.appendRow(row);
        }

        // ATTITUDE TABLE (updated for "Good")
        sheet.appendRow([ex.TextCellValue('Attitude'), ...dateRow.skip(1)]);
        for (int i = 0; i < dateRow.length; i++) {
          final cell = sheet.cell(ex.CellIndex.indexByColumnRow(rowIndex: sheet.maxRows - 1, columnIndex: i));
          cell.cellStyle = ex.CellStyle(
            bold: true,
            backgroundColorHex: ex.ExcelColor.fromHexString("#D9EAD3"),
          );
        }
        final attitudeCats = [
          'Greet with a warm smile',
          'Ask about their needs',
          'Help find the right product',
          'Confirm the purchase',
          'Offer carry or delivery help'
        ];
        for (final cat in attitudeCats) {
          final row = [ex.TextCellValue(cat)];
          for (int d = 0; d < daysInMonth; d++) {
            final date = monthStart.add(Duration(days: d));
            final form = getFormForDate(forms, date);
            String rating = '-';
            String reason = '';
            if (form == null || form.isEmpty) {
              row.add(ex.TextCellValue('-'));
              continue;
            }
            String key;
            if (cat.trim() == 'Greet with a warm smile') key = 'greetSmile';
            else if (cat.trim() == 'Ask about their needs') key = 'askNeeds';
            else if (cat.trim() == 'Help find the right product') key = 'helpFindProduct';
            else if (cat.trim() == 'Confirm the purchase') key = 'confirmPurchase';
            else if (cat.trim() == 'Offer carry or delivery help') key = 'offerHelp';
            else key = '';

            rating = form['attitude']?['${key}Level'] ?? '-';
            reason = form['attitude']?['${key}Reason'] ?? '';

            String cellText;
            if (rating == 'excellent') {
              cellText = '✔ (Excellent${reason.isNotEmpty ? ': $reason' : ''})';
            } else if (rating == 'good') {
              cellText = '✔ (Good${reason.isNotEmpty ? ': $reason' : ''})';
            } else if (rating == 'average') {
              cellText = '✔ (Average${reason.isNotEmpty ? ': $reason' : ''})';
            } else {
              cellText = '✘ (-)';
            }

            row.add(ex.TextCellValue(cellText));
          }
          final rowIdxAtti = sheet.maxRows;
          sheet.appendRow(row);
          for (int col = 1; col < row.length; col++) {
            final cell = sheet.cell(ex.CellIndex.indexByColumnRow(rowIndex: rowIdxAtti, columnIndex: col));
            final val = (row[col] as ex.TextCellValue).value;
            if (val is String && val.toString().startsWith('✔')) {
              cell.cellStyle = ex.CellStyle(
                fontColorHex: ex.ExcelColor.fromHexString('#38761D'),
              );
            } else if (val is String && val.toString().startsWith('✘')) {
              cell.cellStyle = ex.CellStyle(
                fontColorHex: ex.ExcelColor.fromHexString('#CC0000'),
              );
            }
          }
        }

        // MEETING TABLE
        sheet.appendRow([ex.TextCellValue('Meeting'), ...dateRow.skip(1)]);
        for (int i = 0; i < dateRow.length; i++) {
          final cell = sheet.cell(ex.CellIndex.indexByColumnRow(rowIndex: sheet.maxRows - 1, columnIndex: i));
          cell.cellStyle = ex.CellStyle(
            bold: true,
            backgroundColorHex: ex.ExcelColor.fromHexString("#EAD1DC"),
          );
        }
        final meetingRow = [ex.TextCellValue('Attended')];
        for (int d = 0; d < daysInMonth; d++) {
          final date = monthStart.add(Duration(days: d));
          final form = getFormForDate(forms, date);
          String meetingCell = '-';
          if (form != null && form.isNotEmpty) {
            final meeting = form['meeting'];
            if (meeting?['noMeeting'] == true) {
              meetingCell = 'ⓘ No meeting';
            } else if (meeting?['attended'] == true) {
              meetingCell = '✔';
            } else {
              meetingCell = '✘';
            }
          }
          meetingRow.add(ex.TextCellValue(meetingCell));
        }
        sheet.appendRow(meetingRow);

        rowIdx = sheet.maxRows + 2;
        // --- NEW QUESTIONS TABLES ---
        // 5) Time taken to complete other tasks
        sheet.appendRow([ex.TextCellValue('Time Taken for Other Tasks (min)'), ...dateRow.skip(1)]);
        for (int i = 0; i < dateRow.length; i++) {
          final cell = sheet.cell(ex.CellIndex.indexByColumnRow(rowIndex: sheet.maxRows - 1, columnIndex: i));
          cell.cellStyle = ex.CellStyle(
            bold: true,
            backgroundColorHex: ex.ExcelColor.fromHexString("#D0E0E3"),
          );
        }
        final timeRow = [ex.TextCellValue('Minutes')];
        for (int d = 0; d < daysInMonth; d++) {
          final date = monthStart.add(Duration(days: d));
          final form = getFormForDate(forms, date);
          String value = '-';
          if (form != null && form.isNotEmpty) {
            value = (form['timeTakenOtherTasks'] ?? '').toString();
            if (value.isEmpty) value = '-';
          }
          timeRow.add(ex.TextCellValue(value));
        }
        sheet.appendRow(timeRow);

        // 6) Old stock offer given to customers?
        sheet.appendRow([ex.TextCellValue('Old Stock Offer Given?'), ...dateRow.skip(1)]);
        for (int i = 0; i < dateRow.length; i++) {
          final cell = sheet.cell(ex.CellIndex.indexByColumnRow(rowIndex: sheet.maxRows - 1, columnIndex: i));
          cell.cellStyle = ex.CellStyle(
            bold: true,
            backgroundColorHex: ex.ExcelColor.fromHexString("#FFF2CC"),
          );
        }
        final oldStockRow = [ex.TextCellValue('Yes/No')];
        for (int d = 0; d < daysInMonth; d++) {
          final date = monthStart.add(Duration(days: d));
          final form = getFormForDate(forms, date);
          String value = '-';
          if (form != null && form.isNotEmpty) {
            final v = form['oldStockOfferGiven'];
            if (v == true) value = 'Yes';
            else if (v == false) value = 'No';
          }
          oldStockRow.add(ex.TextCellValue(value));
        }
        sheet.appendRow(oldStockRow);

        // 7) Cross-selling and upselling?
        sheet.appendRow([ex.TextCellValue('Cross-selling & Upselling?'), ...dateRow.skip(1)]);
        for (int i = 0; i < dateRow.length; i++) {
          final cell = sheet.cell(ex.CellIndex.indexByColumnRow(rowIndex: sheet.maxRows - 1, columnIndex: i));
          cell.cellStyle = ex.CellStyle(
            bold: true,
            backgroundColorHex: ex.ExcelColor.fromHexString("#EAD1DC"),
          );
        }
        final crossSellRow = [ex.TextCellValue('Yes/No')];
        for (int d = 0; d < daysInMonth; d++) {
          final date = monthStart.add(Duration(days: d));
          final form = getFormForDate(forms, date);
          String value = '-';
          if (form != null && form.isNotEmpty) {
            final v = form['crossSellingUpselling'];
            if (v == true) value = 'Yes';
            else if (v == false) value = 'No';
          }
          crossSellRow.add(ex.TextCellValue(value));
        }
        sheet.appendRow(crossSellRow);

        // 8) Product complaints?
        sheet.appendRow([ex.TextCellValue('Product Complaints?'), ...dateRow.skip(1)]);
        for (int i = 0; i < dateRow.length; i++) {
          final cell = sheet.cell(ex.CellIndex.indexByColumnRow(rowIndex: sheet.maxRows - 1, columnIndex: i));
          cell.cellStyle = ex.CellStyle(
            bold: true,
            backgroundColorHex: ex.ExcelColor.fromHexString("#F4CCCC"),
          );
        }
        final complaintsRow = [ex.TextCellValue('Yes/No')];
        for (int d = 0; d < daysInMonth; d++) {
          final date = monthStart.add(Duration(days: d));
          final form = getFormForDate(forms, date);
          String value = '-';
          if (form != null && form.isNotEmpty) {
            final v = form['productComplaints'];
            if (v == true) value = 'Yes';
            else if (v == false) value = 'No';
          }
          complaintsRow.add(ex.TextCellValue(value));
        }
        sheet.appendRow(complaintsRow);

        // 9) Achieved daily target?
        sheet.appendRow([ex.TextCellValue('Achieved Daily Target?'), ...dateRow.skip(1)]);
        for (int i = 0; i < dateRow.length; i++) {
          final cell = sheet.cell(ex.CellIndex.indexByColumnRow(rowIndex: sheet.maxRows - 1, columnIndex: i));
          cell.cellStyle = ex.CellStyle(
            bold: true,
            backgroundColorHex: ex.ExcelColor.fromHexString("#D9EAD3"),
          );
        }
        final targetRow = [ex.TextCellValue('Yes/No')];
        for (int d = 0; d < daysInMonth; d++) {
          final date = monthStart.add(Duration(days: d));
          final form = getFormForDate(forms, date);
          String value = '-';
          if (form != null && form.isNotEmpty) {
            final v = form['achievedDailyTarget'];
            if (v == true) value = 'Yes';
            else if (v == false) value = 'No';
          }
          targetRow.add(ex.TextCellValue(value));
        }
        sheet.appendRow(targetRow);
      });
    });

    final dir = await getTemporaryDirectory();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final filePath = '${dir.path}/performance_${reportYear}_${reportMonth}.xlsx';
    final fileBytes = await excel.encode();
    final file = File(filePath)..writeAsBytesSync(fileBytes!);

    final smtpServer = gmail('crmmalabar@gmail.com', 'rhmo laoh qara qrnd');
    final message = Message()
      ..from = Address('crmmalabar@gmail.com', 'MTC Sync')
      ..recipients.addAll(['crmmalabar@gmail.com','performancemtc@gmail.com' ])
      ..subject = 'Monthly Sales Performance Report'
      ..text = 'Please find attached the monthly sales performance report.'
      ..attachments = [FileAttachment(file)];

    await send(message, smtpServer);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Excel file sent to crmmalabar@gmail.com')),
    );
  } catch (e, stack) {
    print('Excel send error: $e\n$stack');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Failed to send Excel: $e')),
    );
  }
}