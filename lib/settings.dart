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
  final String userRole; // Add this line

  const SettingsPage({Key? key, required this.userRole}) : super(key: key); // Update constructor

  void _openNotificationSettings() {
    AwesomeNotifications().showNotificationConfigPage();
  }

  void _openNotificationToneSettings(BuildContext context) async {
    if (Platform.isAndroid) {
      const channelId = 'reminder_channel'; // Use your actual channelKey
      final intent = AndroidIntent(
        action: 'android.settings.CHANNEL_NOTIFICATION_SETTINGS',
        arguments: <String, dynamic>{
          'android.provider.extra.APP_PACKAGE': 'com.mtc.mtcsync', // <-- Replace with your app's package name
          'android.provider.extra.CHANNEL_ID': channelId,
        },
      );
      await intent.launch();
    } else {
      // For iOS, show a dialog or guide user to system settings manually
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please change notification sound from iOS Settings.')),
      );
    }
  }

  Future<void> _generateRegistrationCode(BuildContext context) async {
    final code = (Random().nextInt(9000) + 1000).toString(); // 4-digit code
    await FirebaseFirestore.instance.collection('registration_codes').doc('active').set({
      'code': code,
      'createdAt': FieldValue.serverTimestamp(),
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Registration code generated: $code')),
    );
  }

  // Helper to check if current user is admin
  Future<bool> isAdmin() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    return doc.data()?['role'] == 'admin';
  }

  // Export and send Excel
  Future<void> exportAndSendExcel(BuildContext context) async {
    try {
      // 1. Fetch all dailyform docs for the month
      final now = DateTime.now();
      final monthStart = DateTime(now.year, now.month, 1);
      final monthEnd = DateTime(now.year, now.month + 1, 1);

      final formsSnap = await FirebaseFirestore.instance
          .collection('dailyform')
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
          .where('timestamp', isLessThan: Timestamp.fromDate(monthEnd))
          .get();

      // 2. Group by branch and user
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

      // 3. Create Excel
      final excel = Excel.createExcel();
      branchMap.forEach((branch, users) {
        final sheet = excel[branch];
        int rowIdx = 0;
        users.forEach((userId, forms) {
          final username = forms.first['userName'] ?? 'User';
          sheet
            .cell(CellIndex.indexByString("A${rowIdx + 1}"))
            .value = username;
          rowIdx++;
          sheet.appendRow([
            'Attendance', 'Dress Code', 'Attitude', 'Performance', 'Meeting', 'Total'
          ]);
          // Calculate monthly scores (simple sum, adjust as needed)
          int attendance = 0, dress = 0, attitude = 0, performance = 0;
          for (var form in forms) {
            // Attendance
            if (form['attendance'] == 'late') attendance += 15;
            else if (form['attendance'] == 'notApproved') attendance += 10;
            else attendance += 20;
            // Dress Code
            if (form['dressCode']?['cleanUniform'] == false) dress += 0;
            else dress += 20;
            // Attitude
            if (form['attitude']?['greetSmile'] == false) attitude += 0;
            else attitude += 20;
            // Performance
            if (form['performance']?['target'] == true) performance += 15;
            if (form['performance']?['otherPerformance'] == true) performance += 15;
          }
          // Meeting score logic
          int meeting = 10;
          for (var form in forms) {
            if (form['meeting']?['attended'] == false) meeting -= 1;
          }
          if (meeting < 0) meeting = 0;
          sheet.appendRow([
            attendance, dress, attitude, performance, meeting,
            attendance + dress + attitude + performance + meeting
          ]);
          rowIdx += 2;
        });
      });

      // 4. Save to file
      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/performance_${now.year}_${now.month}.xlsx';
      final fileBytes = excel.encode();
      final file = File(filePath)..writeAsBytesSync(fileBytes!);

      // 5. Send email (using SMTP, e.g. Gmail app password)
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
    } catch (e) {
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
                if (userRole == 'admin') // Only show for admin
                  ElevatedButton(
                    onPressed: () => _generateRegistrationCode(context),
                    child: const Text('Generate Registration Code'),
                  ),
                const SizedBox(height: 32),
                // Admin-specific settings
                FutureBuilder<bool>(
                  future: isAdmin(),
                  builder: (context, snapshot) {
                    final isAdminUser = snapshot.data ?? false;
                    return Column(
                      children: [
                        if (isAdminUser)
                          ElevatedButton(
                            onPressed: () => exportAndSendExcel(context),
                            child: Text('Send Monthly Excel Report'),
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