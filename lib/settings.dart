import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme_notifier.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'dart:io';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';

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
              ],
            ),
          ),
        ),
      ),
    );
  }
}