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

  Future<void> exportAndSendExcel(BuildContext context) async {
    try {
      final now = DateTime.now();
      final monthStart = DateTime(now.year, now.month, 1);
      final monthEnd = DateTime(now.year, now.month + 1, 1);

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
          rowIdx++;

          // Table headers
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
              leftBorder: ex.Border(borderStyle: ex.BorderStyle.Thin, borderColorHex: ex.ExcelColor.fromHexString('#000000')),
              rightBorder: ex.Border(borderStyle: ex.BorderStyle.Thin, borderColorHex: ex.ExcelColor.fromHexString('#000000')),
              topBorder: ex.Border(borderStyle: ex.BorderStyle.Thin, borderColorHex: ex.ExcelColor.fromHexString('#000000')),
              bottomBorder: ex.Border(borderStyle: ex.BorderStyle.Thin, borderColorHex: ex.ExcelColor.fromHexString('#000000')),
            );
          }
          rowIdx++;

          // Group forms by week (Sunday-Saturday, week belongs to month of its Saturday)
          Map<int, List<Map<String, dynamic>>> weekMap = {};
          Map<int, DateTime> weekEndDates = {}; // For labeling and sorting

          for (var form in forms) {
            final ts = form['timestamp'];
            final date = ts is Timestamp ? ts.toDate() : DateTime.parse(ts.toString());

            // Find the previous Sunday for this date
            final prevSunday = date.subtract(Duration(days: date.weekday % 7));
            // The Saturday of this week
            final thisSaturday = prevSunday.add(const Duration(days: 6));

            // Only include weeks whose Saturday is in the current month/year
            if (thisSaturday.month != now.month || thisSaturday.year != now.year) continue;

            // Week number: order by Saturday in month
            final weekNum = thisSaturday.day; // or use a counter if you want W1, W2, etc.

            // Use Saturday's date as key for sorting and labeling
            weekMap.putIfAbsent(weekNum, () => []);
            weekMap[weekNum]!.add(form);
            weekEndDates[weekNum] = thisSaturday;
          }

          // Sort weeks by their Saturday date
          final sortedWeekNums = weekEndDates.keys.toList()..sort();
          double totalSum = 0;
          int weekCount = 0;

          for (int i = 0; i < sortedWeekNums.length; i++) {
            final weekNum = sortedWeekNums[i];
            final weekForms = weekMap[weekNum]!;
            // Reset scores at the start of each week
            int attendance = 20, dress = 20, attitude = 20, meeting = 10;

            for (var form in weekForms) {
              // Attendance deductions (do NOT deduct for approved leave)
              if (form['attendance'] == 'late') attendance -= 5;
              else if (form['attendance'] == 'notApproved') attendance -= 10;
              // Dress Code
              if (form['dressCode']?['cleanUniform'] == false) dress -= 20;
              // Attitude
              if (form['attitude']?['greetSmile'] == false) attitude -= 20;
              // Meeting
              if (form['meeting']?['attended'] == false) meeting -= 1;

              // Clamp to zero
              if (attendance < 0) attendance = 0;
              if (dress < 0) dress = 0;
              if (attitude < 0) attitude = 0;
              if (meeting < 0) meeting = 0;
            }

            int weekTotal = attendance + dress + attitude + meeting;
            totalSum += weekTotal;
            weekCount++;

            final row = [
              ex.TextCellValue('W${i + 1}'), // Week 1, 2, ...
              ex.IntCellValue(attendance),
              ex.IntCellValue(dress),
              ex.IntCellValue(attitude),
              ex.IntCellValue(meeting),
              ex.IntCellValue(weekTotal),
            ];
            for (int j = 0; j < row.length; j++) {
              final cell = sheet.cell(ex.CellIndex.indexByColumnRow(columnIndex: j, rowIndex: rowIdx));
              cell.value = row[j];
              cell.cellStyle = ex.CellStyle(
                backgroundColorHex: j == 0
                    ? ex.ExcelColor.fromHexString("#FFFFFF")
                    : ex.ExcelColor.fromHexString(_getScoreColorHex(j, row[j] is ex.IntCellValue ? (row[j] as ex.IntCellValue).value : 0)),
                leftBorder: ex.Border(borderStyle: ex.BorderStyle.Thin, borderColorHex: ex.ExcelColor.fromHexString('#000000')),
                rightBorder: ex.Border(borderStyle: ex.BorderStyle.Thin, borderColorHex: ex.ExcelColor.fromHexString('#000000')),
                topBorder: ex.Border(borderStyle: ex.BorderStyle.Thin, borderColorHex: ex.ExcelColor.fromHexString('#000000')),
                bottomBorder: ex.Border(borderStyle: ex.BorderStyle.Thin, borderColorHex: ex.ExcelColor.fromHexString('#000000')),
              );
            }
            rowIdx++;
          }

          // Add average row (average of weekly totals)
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
              leftBorder: ex.Border(borderStyle: ex.BorderStyle.Thin, borderColorHex: ex.ExcelColor.fromHexString('#000000')),
              rightBorder: ex.Border(borderStyle: ex.BorderStyle.Thin, borderColorHex: ex.ExcelColor.fromHexString('#000000')),
              topBorder: ex.Border(borderStyle: ex.BorderStyle.Thin, borderColorHex: ex.ExcelColor.fromHexString('#000000')),
              bottomBorder: ex.Border(borderStyle: ex.BorderStyle.Thin, borderColorHex: ex.ExcelColor.fromHexString('#000000')),
            );
          }
          rowIdx++;

          // Show performance score below the average row (from last form with performance field)
          final perfForms = forms.where((f) => f['performance'] != null).toList();
          int performanceScore = 0;
          if (perfForms.isNotEmpty) {
            final perf = perfForms.last['performance'];
            if (perf?['target'] == true) performanceScore += 15;
            if (perf?['otherPerformance'] == true) performanceScore += 15;
          }
          sheet.cell(ex.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIdx)).value = ex.TextCellValue('Performance');
          sheet.cell(ex.CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: rowIdx)).value = ex.IntCellValue(performanceScore);
        });
      });

      final dir = await getTemporaryDirectory();
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final filePath = '${dir.path}/performance_${now.year}_${now.month}.xlsx';
      final fileBytes = await excel.encode();
      final file = File(filePath)..writeAsBytesSync(fileBytes!);

      final smtpServer = gmail('crmmalabar@gmail.com', 'rhmo laoh qara qrnd');
      final message = Message()
        ..from = Address('crmmalabar@gmail.com', 'MTC Sync')
        ..recipients.add('crmmalabar@gmail.com')
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
                            onPressed: () => exportAndSendExcel(context),
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