import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme_notifier.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'dart:io';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
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

      final excel = Excel.createExcel();
      branchMap.forEach((branch, users) {
        final sheet = excel[branch];
        int rowIdx = 0;
        users.forEach((userId, forms) {
          final username = forms.first['userName'] ?? 'User';
          sheet.cell(CellIndex.indexByString("A${rowIdx + 1}")).value = TextCellValue(username);
          rowIdx++;

          // Table headers with borders
          final headers = [
            TextCellValue(''),
            TextCellValue('Attendance'),
            TextCellValue('Dress Code'),
            TextCellValue('Attitude'),
            TextCellValue('Performance'),
            TextCellValue('Meeting'),
            TextCellValue('Total'),
          ];
          for (int i =0 ; i < headers.length; i++) {
            final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: rowIdx));
            cell.value = headers[i];
            cell.cellStyle = CellStyle(
              bold: true,
              backgroundColorHex: ExcelColor.fromHexString("#D9EAD3"),
              
            );
          }
          rowIdx++;

          // Each day's row
          for (var form in forms) {
            int attendance = 20, dress = 20, attitude = 20, performance = 0;
            // Deductions for the month
            if (form['attendance'] == 'late') attendance -= 5;
            else if (form['attendance'] == 'notApproved') attendance -= 10;
            else if (form['attendance'] == 'approved') attendance -= 20;
            if (form['dressCode']?['cleanUniform'] == false) dress -= 20;
            if (form['attitude']?['greetSmile'] == false) attitude -= 20;
            if (form['performance']?['target'] == true) performance += 15;
            if (form['performance']?['otherPerformance'] == true) performance += 15;
            if (attendance < 0) attendance = 0;
            if (dress < 0) dress = 0;
            if (attitude < 0) attitude = 0;
            int meeting = 10;
            if (form['meeting']?['attended'] == false) meeting -= 1;
            if (meeting < 0) meeting = 0;
            int total = attendance + dress + attitude + performance + meeting;

            final row = [
              TextCellValue(''),
              IntCellValue(attendance),
              IntCellValue(dress),
              IntCellValue(attitude),
              IntCellValue(performance),
              IntCellValue(meeting),
              IntCellValue(total),
            ];

            for (int i = 0; i < row.length; i++) {
              final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: rowIdx));
              cell.value = row[i];
              cell.cellStyle = CellStyle(
                backgroundColorHex: i == 0
                    ? ExcelColor.fromHexString("#FFFFFF")
                    : ExcelColor.fromHexString(_getScoreColorHex(i, row[i] is IntCellValue ? (row[i] as IntCellValue).value : 0)),
              );
            }
            rowIdx++;
          }
          rowIdx += 2;
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