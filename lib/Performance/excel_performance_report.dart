import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../Navigation/user_cache_service.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;
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

    final cachedUsers = await UserCacheService.instance.getAllUsers();
    final userMap = {for (var u in cachedUsers) u['uid'] as String: u};
    final branchMap = <String, Map<String, List<Map<String, dynamic>>>>{};

    for (var doc in formsSnap.docs) {
      final data = doc.data();
      final user = userMap[data['userId']] ?? {};
      final branch = user['branch'] ?? 'Unknown';
      branchMap.putIfAbsent(branch, () => {});
      branchMap[branch]!.putIfAbsent(data['userId'], () => []);
      branchMap[branch]![data['userId']]!.add(data);
    }

    final workbook = xlsio.Workbook();
    bool firstSheet = true;
    branchMap.forEach((branch, users) {
      final sheet = firstSheet
          ? workbook.worksheets[0]
          : workbook.worksheets.addWithName(branch);
      if (firstSheet) {
        sheet.name = branch;
        firstSheet = false;
      }
      int rowIdx = 1;

      // Build date strings for column headers
      final dateStrings = <String>[];
      for (int d = 0; d < daysInMonth; d++) {
        final date = monthStart.add(Duration(days: d));
        dateStrings.add('${date.day}-${date.month < 10 ? '0' : ''}${date.month}');
      }
      final totalCols = daysInMonth + 1; // label col + one col per day

      users.forEach((userId, forms) {
        final username = forms.first['userName'] ?? 'User';
        sheet.getRangeByIndex(rowIdx, 1).setText(username);
        rowIdx += 2;

        Map<String, dynamic>? getFormForDate(List<Map<String, dynamic>> fms, DateTime date) {
          return fms.firstWhere(
            (form) {
              final ts = form['timestamp'];
              final fd = ts is Timestamp ? ts.toDate() : DateTime.parse(ts.toString());
              return fd.year == date.year && fd.month == date.month && fd.day == date.day;
            },
            orElse: () => {},
          );
        }

        void writeHeaderRow(String label, String hexColor) {
          sheet.getRangeByIndex(rowIdx, 1).setText(label);
          for (int d = 0; d < daysInMonth; d++) {
            sheet.getRangeByIndex(rowIdx, d + 2).setText(dateStrings[d]);
          }
          for (int i = 1; i <= totalCols; i++) {
            sheet.getRangeByIndex(rowIdx, i).cellStyle.bold = true;
            sheet.getRangeByIndex(rowIdx, i).cellStyle.backColor = hexColor;
          }
          rowIdx++;
        }

        // ── ATTENDANCE ──────────────────────────────────────────────────────
        writeHeaderRow('Attendance', '#CFE2F3');
        sheet.getRangeByIndex(rowIdx, 1).setText('Status');
        for (int d = 0; d < daysInMonth; d++) {
          final form = getFormForDate(forms, monthStart.add(Duration(days: d)));
          final status = (form != null && form.isNotEmpty)
              ? (form['attendanceStatus'] ?? form['attendance'] ?? '-')
              : '-';
          sheet.getRangeByIndex(rowIdx, d + 2).setText(status.toString());
        }
        rowIdx++;

        // ── DRESS CODE ───────────────────────────────────────────────────────
        writeHeaderRow('Dress Code', '#FCE5CD');
        final dressCats = ['Clean Uniform', 'Keep Inside', 'Neat Hair'];
        final dressKeys = ['cleanUniform', 'keepInside', 'neatHair'];
        for (int ci = 0; ci < dressCats.length; ci++) {
          sheet.getRangeByIndex(rowIdx, 1).setText(dressCats[ci]);
          for (int d = 0; d < daysInMonth; d++) {
            final form = getFormForDate(forms, monthStart.add(Duration(days: d)));
            final val = (form != null && form.isNotEmpty)
                ? ((form['dressCode']?[dressKeys[ci]] as bool?) == true ? '✔' : '✘')
                : '-';
            sheet.getRangeByIndex(rowIdx, d + 2).setText(val);
          }
          rowIdx++;
        }

        // ── ATTITUDE ─────────────────────────────────────────────────────────
        writeHeaderRow('Attitude', '#D9EAD3');
        final attitudeCats = [
          'Greet with a warm smile',
          'Ask about their needs',
          'Help find the right product',
          'Confirm the purchase',
          'Offer carry or delivery help',
        ];
        final attitudeKeys = ['greetSmile', 'askNeeds', 'helpFindProduct', 'confirmPurchase', 'offerHelp'];
        for (int ci = 0; ci < attitudeCats.length; ci++) {
          sheet.getRangeByIndex(rowIdx, 1).setText(attitudeCats[ci]);
          for (int d = 0; d < daysInMonth; d++) {
            final form = getFormForDate(forms, monthStart.add(Duration(days: d)));
            if (form == null || form.isEmpty) {
              sheet.getRangeByIndex(rowIdx, d + 2).setText('-');
              continue;
            }
            final key = attitudeKeys[ci];
            final rating = form['attitude']?['${key}Level'] ?? '-';
            final reason = form['attitude']?['${key}Reason'] ?? '';
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
            final cell = sheet.getRangeByIndex(rowIdx, d + 2);
            cell.setText(cellText);
            if (cellText.startsWith('✔')) {
              cell.cellStyle.fontColor = '#38761D';
            } else if (cellText.startsWith('✘')) {
              cell.cellStyle.fontColor = '#CC0000';
            }
          }
          rowIdx++;
        }

        // ── MEETING ───────────────────────────────────────────────────────────
        writeHeaderRow('Meeting', '#EAD1DC');
        sheet.getRangeByIndex(rowIdx, 1).setText('Attended');
        for (int d = 0; d < daysInMonth; d++) {
          final form = getFormForDate(forms, monthStart.add(Duration(days: d)));
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
          sheet.getRangeByIndex(rowIdx, d + 2).setText(meetingCell);
        }
        rowIdx += 3; // meeting row + 2 blank rows

        // Helper: writes a Yes/No + Description pair for a boolean question
        void writeYesNoTable(String label, String hexColor, String yesNoKey, String descKey) {
          writeHeaderRow(label, hexColor);
          sheet.getRangeByIndex(rowIdx, 1).setText('Yes/No');
          sheet.getRangeByIndex(rowIdx + 1, 1).setText('Description');
          for (int d = 0; d < daysInMonth; d++) {
            final form = getFormForDate(forms, monthStart.add(Duration(days: d)));
            String value = '-';
            String desc = '-';
            if (form != null && form.isNotEmpty) {
              value = form[yesNoKey] == true ? 'Yes' : (form[yesNoKey] == false ? 'No' : '-');
              desc = form[descKey]?.toString() ?? '-';
            }
            sheet.getRangeByIndex(rowIdx, d + 2).setText(value);
            sheet.getRangeByIndex(rowIdx + 1, d + 2).setText(desc);
          }
          rowIdx += 2;
        }

        writeYesNoTable('Completed Other Tasks?', '#D0E0E3', 'timeTakenOtherTasks', 'timeTakenOtherTasksDescription');
        writeYesNoTable('Old Stock Offer Given?', '#FFF2CC', 'oldStockOfferGiven', 'oldStockOfferDescription');
        writeYesNoTable('Cross-selling & Upselling?', '#EAD1DC', 'crossSellingUpselling', 'crossSellingUpsellingDescription');
        writeYesNoTable('Product Complaints?', '#F4CCCC', 'productComplaints', 'productComplaintsDescription');
        writeYesNoTable('Achieved Daily Target?', '#D9EAD3', 'achievedDailyTarget', 'achievedDailyTargetDescription');
      });
    });

    final dir = await getTemporaryDirectory();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final filePath = '${dir.path}/performance_${reportYear}_${reportMonth}.xlsx';
    final List<int> fileBytes = workbook.saveAsStream();
    workbook.dispose();
    final file = File(filePath)..writeAsBytesSync(fileBytes);

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
    debugPrint('Excel send error: $e\n$stack');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Failed to send Excel: $e')),
    );
  }
}