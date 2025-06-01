import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme_notifier.dart';
import 'package:awesome_notifications/awesome_notifications.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({Key? key}) : super(key: key);

  void _openNotificationSettings() {
    AwesomeNotifications().showNotificationConfigPage();
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
                onTap: _openNotificationSettings,
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}