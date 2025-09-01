import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme_notifier.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'dart:io';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart' as ex;
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path_provider/path_provider.dart';

class SettingsPage extends StatelessWidget {
  final String userRole;

  const SettingsPage({Key? key, required this.userRole}) : super(key: key);

  void _openNotificationToneSettings(BuildContext context) async {
    if (Platform.isAndroid) {
      const channelId = 'reminder_channel';
      final intent = AndroidIntent(
        action: 'android.settings.CHANNEL_NOTIFICATION_SETTINGS',
        arguments: <String, dynamic>{
          'android.provider.extra.APP_PACKAGE': 'com.mtc.mtcsync',
          'android.provider.extra.CHANNEL_ID': channelId,
        },
      );
      await intent.launch();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please change notification sound from iOS Settings.')),
      );
    }
  }

  Future<void> _generateRegistrationCode(BuildContext context) async {
    final code = (Random().nextInt(9000) + 1000).toString();
    await FirebaseFirestore.instance.collection('registration_codes').doc('active').set({
      'code': code,
      'createdAt': FieldValue.serverTimestamp(),
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Registration code generated: $code')),
    );
  }

  Future<bool> isAdmin() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    return doc.data()?['role'] == 'admin';
  }

  String _getScoreColorHex(int column, int value) {
    // column: 1=Attendance, 2=Dress, 3=Attitude, 4=Performance, 5=Meeting
    if (column == 4) { // Performance
      if (value >= 25) return "#93C47D"; // green
      if (value >= 15) return "#FFE599"; // yellow
      if (value >= 10) return "#EA9999"; // red
      return "#CCCCCC"; // grey
    } else if (column > 0 && column < 4) { // Attendance, Dress, Attitude,
      if (value >= 16) return "#93C47D"; // green
      if (value >= 11) return "#FFE599"; // yellow
      if (value >= 5) return "#EA9999"; // red
      return "#CCCCCC"; // grey
    } else if (column == 5) { // Meeting
      if (value >= 9) return "#93C47D"; // green
      if (value >= 5) return "#FFE599"; // yellow
      if (value >= 1) return "#EA9999"; // red
      return "#CCCCCC"; // grey
    }
    return "#FFFFFF";
  }

  Future<void> _pickMonthAndSendExcel(BuildContext context) async {
    DateTime now = DateTime.now();
    int selectedYear = now.year;
    int selectedMonth = now.month;

    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Select Month'),
          content: StatefulBuilder(
            builder: (context, setState) {
              return Row(
                children: [
                  DropdownButton<int>(
                    value: selectedMonth,
                    items: List.generate(12, (i) => i + 1)
                        .map((m) => DropdownMenuItem(
                              value: m,
                              child: Text(
                                '${_monthShort(m)}',
                                style: TextStyle(fontSize: 16),
                              ),
                            ))
                        .toList(),
                    onChanged: (val) => setState(() => selectedMonth = val!),
                  ),
                  SizedBox(width: 16),
                  DropdownButton<int>(
                    value: selectedYear,
                    items: [now.year - 1, now.year, now.year + 1]
                        .map((y) => DropdownMenuItem(
                              value: y,
                              child: Text('$y'),
                            ))
                        .toList(),
                    onChanged: (val) => setState(() => selectedYear = val!),
                  ),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx, {'year': selectedYear, 'month': selectedMonth});
              },
              child: Text('Send'),
            ),
          ],
        );
      },
    ).then((result) {
      if (result != null && result is Map) {
        exportAndSendExcel(context, year: result['year'], month: result['month']);
      }
    });
  }

  // Modify exportAndSendExcel to accept year/month:
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
          // USER NAME HEADER
          sheet.cell(ex.CellIndex.indexByString("A${rowIdx + 1}")).value = ex.TextCellValue(username);
          rowIdx += 2;

          // WEEKLY SUMMARY TABLE HEADER
          final headers = [
            ex.TextCellValue('Week'),
            ex.TextCellValue('Attendance'),
            ex.TextCellValue('Dress Code'),
            ex.TextCellValue('Attitude'),
            ex.TextCellValue('Meeting'),
            ex.TextCellValue('Total'),
          ];
          for (int i = 0; i < headers.length; i++) {
            final cell = sheet.cell(ex.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: rowIdx));
            cell.value = headers[i];
            cell.cellStyle = ex.CellStyle(
              bold: true,
              backgroundColorHex: ex.ExcelColor.fromHexString("#D9EAD3"),
            );
          }
          rowIdx++;

          // WEEKLY DATA
          Map<int, List<Map<String, dynamic>>> weekMap = {};
          Map<int, String> weekLabels = {};

          for (var form in forms) {
            final ts = form['timestamp'];
            final date = ts is Timestamp ? ts.toDate() : DateTime.parse(ts.toString());
            int weekOfMonth = ((date.day - 1) ~/ 7) + 1;
            weekMap.putIfAbsent(weekOfMonth, () => []);
            weekMap[weekOfMonth]!.add(form);
            final weekStart = DateTime(date.year, date.month, (weekOfMonth - 1) * 7 + 1);
            final weekEnd = DateTime(date.year, date.month, min(weekOfMonth * 7, DateUtils.getDaysInMonth(date.year, date.month)));
            weekLabels[weekOfMonth] = "${weekStart.day}-${_monthShort(weekStart.month)} to ${weekEnd.day}-${_monthShort(weekEnd.month)}";
          }

          final sortedWeekNums = weekMap.keys.toList()..sort();
          double totalSum = 0;
          int weekCount = 0;

          for (int i = 0; i < sortedWeekNums.length; i++) {
            final weekNum = sortedWeekNums[i];
            final weekForms = weekMap[weekNum]!;

            int attendance = 20, dress = 20, attitude = 20, meeting = 10;

            // Group forms by day (yyyy-mm-dd)
            final formsByDay = <String, Map<String, dynamic>>{};
            for (var form in weekForms) {
              final ts = form['timestamp'];
              final date = ts is Timestamp ? ts.toDate() : DateTime.parse(ts.toString());
              final key = "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
              formsByDay[key] = form;
            }

            for (var form in formsByDay.values) {
              final att = form['attendance'];
              if (att == 'late') {
                attendance -= 5;
              } else if (att == 'notApproved') {
                attendance -= 10;
              }
              // No deduction for 'punching' or 'approved'

              // Dress
              if (att == 'approved' || att == 'notApproved') {
                // skip deduction for any leave
              } else {
                if (form['dressCode']?['cleanUniform'] == false) dress -= 5;
                if (form['dressCode']?['keepInside'] == false) dress -= 5;
                if (form['dressCode']?['neatHair'] == false) dress -= 5;
              }

              // Attitude
              if (att == 'approved' || att == 'notApproved') {
                // skip deduction for any leave
              } else {
                if (form['attitude']?['greetSmile'] == false) attitude -= 2;
                if (form['attitude']?['askNeeds'] == false) attitude -= 2;
                if (form['attitude']?['helpFindProduct'] == false) attitude -= 2;
                if (form['attitude']?['confirmPurchase'] == false) attitude -= 2;
                if (form['attitude']?['offerHelp'] == false) attitude -= 2;
              }

              // Meeting
              if (att == 'approved' || att == 'notApproved') {
                // skip deduction for any leave
              } else {
                if (form['meeting']?['attended'] == false) meeting -= 1;
              }
            }

            if (attendance < 0) attendance = 0;
            if (dress < 0) dress = 0;
            if (attitude < 0) attitude = 0;
            if (meeting < 0) meeting = 0;

            int weekTotal = attendance + dress + attitude + meeting;
            totalSum += weekTotal;
            weekCount++;

            // --- Color logic for summary cells
            Color getCellColor(int col, int value) {
              if (col == 1 || col == 2 || col == 3) {
                if (value >= 16) return Color(0xFF93C47D); // green
                if (value >= 11) return Color(0xFFFFE599); // yellow
                if (value >= 5) return Color(0xFFEA9999); // red
                return Color(0xFFCCCCCC); // grey
              } else if (col == 4) {
                if (value >= 9) return Color(0xFF93C47D); // green
                if (value >= 6) return Color(0xFFFFE599); // yellow
                if (value >= 3) return Color(0xFFEA9999); // red
                return Color(0xFFCCCCCC); // grey
              }
              return Colors.white;
            }

            final row = [
              ex.TextCellValue('Week $weekNum\n${weekLabels[weekNum]}'),
              ex.IntCellValue(attendance),
              ex.IntCellValue(dress),
              ex.IntCellValue(attitude),
              ex.IntCellValue(meeting),
              ex.IntCellValue(weekTotal),
            ];
            for (int j = 0; j < row.length; j++) {
              final cell = sheet.cell(ex.CellIndex.indexByColumnRow(columnIndex: j, rowIndex: rowIdx));
              cell.value = row[j];
              // --- Apply color for value columns
              if (j >= 1 && j <= 4) {
                int val = row[j] is ex.IntCellValue ? (row[j] as ex.IntCellValue).value : 0;
                cell.cellStyle = ex.CellStyle(
                  backgroundColorHex: ex.ExcelColor.fromHexString(
                    '#${getCellColor(j, val).value.toRadixString(16).substring(2).toUpperCase()}',
                  ),
                  bold: false,
                );
              }
            }
            rowIdx++;
          }

          // AVERAGE ROW
          final avg = weekCount > 0 ? totalSum / weekCount : 0;
          final avgRow = [
            ex.TextCellValue(''),
            ex.TextCellValue(''),
            ex.TextCellValue(''),
            ex.TextCellValue('Average'),
            ex.TextCellValue(''),
            ex.DoubleCellValue(avg.toDouble()),
          ];
          for (int i = 0; i < avgRow.length; i++) {
            final cell = sheet.cell(ex.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: rowIdx));
            cell.value = avgRow[i];
            cell.cellStyle = ex.CellStyle(
              bold: i == 3,
              backgroundColorHex: i == 3
                  ? ex.ExcelColor.fromHexString("#D9EAD3")
                  : ex.ExcelColor.fromHexString("#FFFFFF"),
            );
          }
          rowIdx += 2; // <-- Leave at least 2 rows space before monthly table

          // DETAILED DAILY TABLES (like your image)
          final monthStart = DateTime(now.year, now.month, 1);
          final monthEnd = DateTime(now.year, now.month + 1, 1);
          final daysInMonth = monthEnd.difference(monthStart).inDays;
          final dateRow = [ex.TextCellValue('Date')];
          for (int d = 0; d < daysInMonth; d++) {
            final date = monthStart.add(Duration(days: d));
            dateRow.add(ex.TextCellValue('${date.day}-${date.month < 10 ? '0' : ''}${date.month}'));
          }

          // Helper to get form for a specific date
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

          // --- Helper for tick/cross with color
          ex.TextCellValue coloredTick(bool? value) {
            if (value == null) return ex.TextCellValue('-');
            if (value) {
              return ex.TextCellValue('✔'); // Will color cell green below
            } else {
              return ex.TextCellValue('✘'); // Will color cell red below
            }
          }

          // ATTENDANCE TABLE
          sheet.appendRow([ex.TextCellValue('ATTENDANCE (OUT OF 20)')]);
          // Color header cell
          final attHeaderCell = sheet.cell(ex.CellIndex.indexByColumnRow(rowIndex: sheet.maxRows - 1, columnIndex: 0));
          attHeaderCell.cellStyle = ex.CellStyle(
            bold: true,
            backgroundColorHex: ex.ExcelColor.fromHexString("#D9EAD3"),
          );

          sheet.appendRow([ex.TextCellValue('CATEGORY '), ...dateRow.skip(1)]);
          // Color sub-header row
          for (int i = 0; i < dateRow.length; i++) {
            final cell = sheet.cell(ex.CellIndex.indexByColumnRow(rowIndex: sheet.maxRows - 1, columnIndex: i));
            cell.cellStyle = ex.CellStyle(
              bold: true,
              backgroundColorHex: ex.ExcelColor.fromHexString("#D9EAD3"),
            );
          }
          final attendanceCats = ['Punching Time', 'Late time', 'Approved Leave', 'Unapproved Leave'];
          for (final cat in attendanceCats) {
            final row = [ex.TextCellValue(cat)];
            for (int d = 0; d < daysInMonth; d++) {
              final date = monthStart.add(Duration(days: d));
              final form = getFormForDate(forms, date);
              bool? value;
              if (form == null || form.isEmpty) {
                row.add(ex.TextCellValue('-'));
                continue;
              }
              if (cat == 'Punching Time') value = form['attendance'] == 'punching';
              if (cat == 'Late time') value = form['attendance'] == 'late';
              if (cat == 'Approved Leave') value = form['attendance'] == 'approved';
              if (cat == 'Unapproved Leave') value = form['attendance'] == 'notApproved';
              row.add(coloredTick(value));
            }
            final rowIdxAtt = sheet.maxRows;
            sheet.appendRow(row);
            // --- Color tick/cross cells
            for (int col = 1; col < row.length; col++) {
              final cell = sheet.cell(ex.CellIndex.indexByColumnRow(rowIndex: rowIdxAtt, columnIndex: col));
              if (row[col] is ex.TextCellValue) {
                final val = (row[col] as ex.TextCellValue).value;
                if (val == '✔') {
                  cell.cellStyle = ex.CellStyle(
                    fontColorHex: ex.ExcelColor.fromHexString('#38761D'), // green
                  );
                } else if (val == '✘') {
                  cell.cellStyle = ex.CellStyle(
                    fontColorHex: ex.ExcelColor.fromHexString('#CC0000'), // red
                  );
                }
              }
            }
          }
          rowIdx += attendanceCats.length + 2;

          // DRESS CODE TABLE
          sheet.appendRow([ex.TextCellValue('DRESS CODE (OUT OF 20)')]);
          // Color header cell
          final dressHeaderCell = sheet.cell(ex.CellIndex.indexByColumnRow(rowIndex: sheet.maxRows - 1, columnIndex: 0));
          dressHeaderCell.cellStyle = ex.CellStyle(
            bold: true,
            backgroundColorHex: ex.ExcelColor.fromHexString("#D9EAD3"),
          );

          sheet.appendRow([ex.TextCellValue('CATEGORY '), ...dateRow.skip(1)]);
          // Color sub-header row
          for (int i = 0; i < dateRow.length; i++) {
            final cell = sheet.cell(ex.CellIndex.indexByColumnRow(rowIndex: sheet.maxRows - 1, columnIndex: i));
            cell.cellStyle = ex.CellStyle(
              bold: true,
              backgroundColorHex: ex.ExcelColor.fromHexString("#D9EAD3"),
            );
          }
          final dressCats = ['Wear clean uniform', 'Keep inside', 'Keep your hair neat'];
          for (final cat in dressCats) {
            final row = [ex.TextCellValue(cat)];
            for (int d = 0; d < daysInMonth; d++) {
              final date = monthStart.add(Duration(days: d));
              final form = getFormForDate(forms, date);
              bool? value;
              if (form == null || form.isEmpty) {
                row.add(ex.TextCellValue('-'));
                continue;
              }
              if (cat == 'Wear clean uniform') value = form['dressCode']?['cleanUniform'] != false;
              if (cat == 'Keep inside') value = form['dressCode']?['keepInside'] != false;
              if (cat == 'Keep your hair neat') value = form['dressCode']?['neatHair'] != false;
              row.add(coloredTick(value));
            }
            final rowIdxDress = sheet.maxRows;
            sheet.appendRow(row);
            for (int col = 1; col < row.length; col++) {
              final cell = sheet.cell(ex.CellIndex.indexByColumnRow(rowIndex: rowIdxDress, columnIndex: col));
              if (row[col] is ex.TextCellValue) {
                final val = (row[col] as ex.TextCellValue).value;
                if (val == '✔') {
                  cell.cellStyle = ex.CellStyle(
                    fontColorHex: ex.ExcelColor.fromHexString('#38761D'),
                  );
                } else if (val == '✘') {
                  cell.cellStyle = ex.CellStyle(
                    fontColorHex: ex.ExcelColor.fromHexString('#CC0000'),
                  );
                }
              }
            }
          }
          rowIdx += dressCats.length + 2;

          // ATTITUDE TABLE
          sheet.appendRow([ex.TextCellValue('CATEGORY '), ...dateRow.skip(1)]);
          // Color sub-header row
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
            'Offer carry or delivery help' // Pad with spaces
          ];
          for (final cat in attitudeCats) {
            final row = [ex.TextCellValue(cat)];
            for (int d = 0; d < daysInMonth; d++) {
              final date = monthStart.add(Duration(days: d));
              final form = getFormForDate(forms, date);
              bool? value;
              if (form == null || form.isEmpty) {
                row.add(ex.TextCellValue('-'));
                continue;
              }
              if (cat.trim() == 'Greet with a warm smile') value = form['attitude']?['greetSmile'] != false;
              if (cat.trim() == 'Ask about their needs') value = form['attitude']?['askNeeds'] != false;
              if (cat.trim() == 'Help find the right product') value = form['attitude']?['helpFindProduct'] != false;
              if (cat.trim() == 'Confirm the purchase') value = form['attitude']?['confirmPurchase'] != false;
              if (cat.trim() == 'Offer carry or delivery help') value = form['attitude']?['offerHelp'] != false;
              row.add(coloredTick(value));
            }
            final rowIdxAtti = sheet.maxRows;
            sheet.appendRow(row);
            for (int col = 1; col < row.length; col++) {
              final cell = sheet.cell(ex.CellIndex.indexByColumnRow(rowIndex: rowIdxAtti, columnIndex: col));
              if (row[col] is ex.TextCellValue) {
                final val = (row[col] as ex.TextCellValue).value;
                if (val == '✔') {
                  cell.cellStyle = ex.CellStyle(
                    fontColorHex: ex.ExcelColor.fromHexString('#38761D'),
                  );
                } else if (val == '✘') {
                  cell.cellStyle = ex.CellStyle(
                    fontColorHex: ex.ExcelColor.fromHexString('#CC0000'),
                  );
                }
              }
            }
          }
          rowIdx += attitudeCats.length + 2;

          // MEETING TABLE
          sheet.appendRow([ex.TextCellValue('MEETING (OUT OF 10)')]);
          // Color header cell
          final meetHeaderCell = sheet.cell(ex.CellIndex.indexByColumnRow(rowIndex: sheet.maxRows - 1, columnIndex: 0));
          meetHeaderCell.cellStyle = ex.CellStyle(
            bold: true,
            backgroundColorHex: ex.ExcelColor.fromHexString("#D9EAD3"),
          );

          sheet.appendRow([ex.TextCellValue('CATEGORY '), ...dateRow.skip(1)]);
          // Color sub-header row
          for (int i = 0; i < dateRow.length; i++) {
            final cell = sheet.cell(ex.CellIndex.indexByColumnRow(rowIndex: sheet.maxRows - 1, columnIndex: i));
            cell.cellStyle = ex.CellStyle(
              bold: true,
              backgroundColorHex: ex.ExcelColor.fromHexString("#D9EAD3"),
            );
          }
          final meetingCats = ['Meeting'];
          for (final cat in meetingCats) {
            final row = [ex.TextCellValue(cat)];
            for (int d = 0; d < daysInMonth; d++) {
              final date = monthStart.add(Duration(days: d));
              final form = getFormForDate(forms, date);
              bool? value;
              if (form == null || form.isEmpty) {
                row.add(ex.TextCellValue('-'));
                continue;
              }
              if (cat == 'Meeting') value = form['meeting']?['attended'] == true;
              row.add(coloredTick(value));
            }
            final rowIdxMeet = sheet.maxRows;
            sheet.appendRow(row);
            for (int col = 1; col < row.length; col++) {
              final cell = sheet.cell(ex.CellIndex.indexByColumnRow(rowIndex: rowIdxMeet, columnIndex: col));
              if (row[col] is ex.TextCellValue) {
                final val = (row[col] as ex.TextCellValue).value;
                if (val == '✔') {
                  cell.cellStyle = ex.CellStyle(
                    fontColorHex: ex.ExcelColor.fromHexString('#38761D'),
                  );
                } else if (val == '✘') {
                  cell.cellStyle = ex.CellStyle(
                    fontColorHex: ex.ExcelColor.fromHexString('#CC0000'),
                  );
                }
              }
            }
          }
          rowIdx += meetingCats.length + 4; // Add some space before next user

          // --- Auto adjust column width
          for (int col = 0; col < (sheet.rows.isNotEmpty ? sheet.rows.map((r) => r.length).reduce((a, b) => a > b ? a : b) : 0); col++) {
            int maxLen = 0;
            for (var row in sheet.rows) {
              if (col < row.length) {
                final val = row[col]?.value.toString() ?? '';
                if (val.length > maxLen) maxLen = val.length;
              }
            }
            // Instead of setColWidth, pad the first column's cell values to 35 chars
            if (col == 0) {
              for (var row in sheet.rows) {
                if (row.isNotEmpty && row[0]?.value is String) {
                  String cellVal = row[0]!.value as String;
                  if (cellVal.length < 35) {
                  row[0]!.value = ex.TextCellValue(cellVal.padRight(35, ' '));
                  }
                }
              }
            }
          }
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

  String _monthShort(int month) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return months[month];
  }

  int isoWeekNumber(DateTime date) {
    // ISO week starts on Monday, week 1 is the week with the first Thursday of the year
    final thursday = date.subtract(Duration(days: (date.weekday + 6) % 7 - 3));
    final firstThursday = DateTime(date.year, 1, 4);
    final diff = thursday.difference(firstThursday).inDays ~/ 7;
    return 1 + diff;
  }

  @override
  Widget build(BuildContext context) {
    final themeNotifier = Provider.of<ThemeNotifier>(context);
    final theme = themeNotifier.currentTheme;

    return Theme(
      data: theme,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Settings'),
          backgroundColor: theme.colorScheme.primary,
          foregroundColor: Colors.white,
        ),
        body: Padding(
          padding: const EdgeInsets.all(24.0),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Appearance',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                SwitchListTile(
                  title: const Text('Dark Mode'),
                  value: themeNotifier.isDarkMode,
                  onChanged: (val) {
                    themeNotifier.toggleTheme(val);
                  },
                  secondary: Icon(
                    themeNotifier.isDarkMode ? Icons.dark_mode : Icons.light_mode,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 32),
                const Text(
                  'Notifications',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                ListTile(
                  leading: const Icon(Icons.music_note),
                  title: const Text('Notification Tone'),
                  subtitle: const Text('Change your notification sound'),
                  onTap: () => _openNotificationToneSettings(context),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                ),
                const SizedBox(height: 32),
                if (userRole == 'admin')
                  ElevatedButton(
                    onPressed: () => _generateRegistrationCode(context),
                    child: const Text('Generate Registration Code'),
                  ),
                const SizedBox(height: 32),
                FutureBuilder<bool>(
                  future: isAdmin(),
                  builder: (context, snapshot) {
                    final isAdminUser = snapshot.data ?? false;
                    return Column(
                      children: [
                        if (isAdminUser)
                          ElevatedButton(
                            onPressed: () => _pickMonthAndSendExcel(context),
                            child: const Text('Send Monthly Excel Report'),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}