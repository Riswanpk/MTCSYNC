import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme_notifier.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'dart:io';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../Performance/excel_performance_report.dart'; // <-- Import here

class SettingsPage extends StatelessWidget {
  final String userRole;
  final ThemeProvider themeProvider;
  final String _appVersion = 'Version 1.2.86';

  const SettingsPage({super.key, required this.userRole, required this.themeProvider});

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
                                '${monthShort(m)}', // <-- Use helper from excel_performance_report.dart
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
        exportAndSendExcel(context, year: result['year'], month: result['month']); // <-- Call from imported file
      }
    });
  }

  // Remove exportAndSendExcel, _monthShort, isoWeekNumber from this file

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final theme = Theme.of(context);

    return Theme(
      data: theme,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Settings'),
          backgroundColor: const Color(0xFF005BAC),
          foregroundColor: Colors.white,
        ),
        body: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Appearance',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      ListTile(
                        title: const Text('Theme'),
                        trailing: DropdownButton<ThemeMode>(
                          value: themeProvider.themeMode,
                          items: const [
                            DropdownMenuItem(
                              value: ThemeMode.system,
                              child: Text('System'),
                            ),
                            DropdownMenuItem(
                              value: ThemeMode.light,
                              child: Text('Light'),
                            ),
                            DropdownMenuItem(
                              value: ThemeMode.dark,
                              child: Text('Dark'),
                            ),
                          ],
                          onChanged: (ThemeMode? newMode) {
                            if (newMode != null) {
                              themeProvider.setTheme(newMode);
                            }
                          },
                        ),
                        leading: Icon(
                          themeProvider.themeMode == ThemeMode.dark
                              ? Icons.dark_mode
                              : themeProvider.themeMode == ThemeMode.light
                                  ? Icons.light_mode
                                  : Icons.settings_system_daydream,
                          color: const Color(0xFF005BAC),
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
                          if (snapshot.data == true) {
                            return ElevatedButton(
                              onPressed: () => _pickMonthAndSendExcel(context),
                              child: const Text('Send Monthly Excel Report'),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                _appVersion,
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}