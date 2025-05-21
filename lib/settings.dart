import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme_notifier.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({Key? key}) : super(key: key);

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
            ],
          ),
        ),
      ),
    );
  }
}