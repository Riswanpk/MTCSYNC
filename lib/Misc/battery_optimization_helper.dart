import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';

/// Helper class to manage battery optimization settings for reliable notifications.
/// Many Android OEMs (Xiaomi, Oppo, Vivo, Huawei, Samsung) have aggressive battery
/// management that can prevent background notifications from showing.
class BatteryOptimizationHelper {
  static const String _promptShownKey = 'battery_optimization_prompt_shown';
  static const String _promptDismissedKey = 'battery_optimization_dismissed';

  /// Check if we should show the battery optimization prompt
  static Future<bool> shouldShowPrompt() async {
    if (!Platform.isAndroid) return false;

    final prefs = await SharedPreferences.getInstance();

    // Don't show if user already dismissed
    if (prefs.getBool(_promptDismissedKey) ?? false) return false;

    // Don't show if already prompted recently (within 30 days)
    final lastPrompt = prefs.getInt(_promptShownKey) ?? 0;
    final daysSincePrompt =
        DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(lastPrompt)).inDays;
    if (lastPrompt > 0 && daysSincePrompt < 30) return false;

    // Check if battery optimization is already disabled
    final status = await Permission.ignoreBatteryOptimizations.status;
    if (status.isGranted) return false;

    return true;
  }

  /// Mark prompt as shown
  static Future<void> markPromptShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_promptShownKey, DateTime.now().millisecondsSinceEpoch);
  }

  /// Mark prompt as dismissed (don't show again)
  static Future<void> markPromptDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_promptDismissedKey, true);
  }

  /// Open battery optimization settings
  static Future<void> openBatterySettings() async {
    await openAppSettings();
  }

  /// Request to ignore battery optimizations
  static Future<bool> requestIgnoreBatteryOptimizations() async {
    final status = await Permission.ignoreBatteryOptimizations.request();
    return status.isGranted;
  }

  /// Get device manufacturer for targeted instructions
  static Future<String> getDeviceManufacturer() async {
    if (!Platform.isAndroid) return '';
    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;
    return androidInfo.manufacturer.toLowerCase();
  }

  /// Show the battery optimization dialog
  static Future<void> showBatteryOptimizationDialog(BuildContext context) async {
    final manufacturer = await getDeviceManufacturer();
    String additionalInstructions = '';

    // Add manufacturer-specific instructions
    if (manufacturer.contains('xiaomi') || manufacturer.contains('redmi')) {
      additionalInstructions =
          '\n\nFor Xiaomi/Redmi: Also enable "Autostart" in Settings > Apps > Manage apps > MTC Sync > Autostart';
    } else if (manufacturer.contains('oppo') || manufacturer.contains('realme')) {
      additionalInstructions =
          '\n\nFor Oppo/Realme: Also add app to "App Quick Freeze" exceptions in Battery settings';
    } else if (manufacturer.contains('vivo')) {
      additionalInstructions =
          '\n\nFor Vivo: Also enable "Allow background activity" in Settings > Battery > Background power consumption';
    } else if (manufacturer.contains('huawei') || manufacturer.contains('honor')) {
      additionalInstructions =
          '\n\nFor Huawei/Honor: Also enable "Launch automatically" in Settings > Apps > MTC Sync > Battery';
    } else if (manufacturer.contains('samsung')) {
      additionalInstructions =
          '\n\nFor Samsung: Also add to "Never sleeping apps" in Settings > Battery > Background usage limits';
    }

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.notifications_active, color: Colors.orange),
            SizedBox(width: 8),
            Expanded(child: Text('Enable Notifications')),
          ],
        ),
        content: SingleChildScrollView(
          child: Text(
            'To receive notifications reliably (even when the app is closed), '
            'please disable battery optimization for MTC Sync.'
            '$additionalInstructions',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              markPromptDismissed();
              Navigator.of(context).pop();
            },
            child: const Text("Don't show again"),
          ),
          TextButton(
            onPressed: () {
              markPromptShown();
              Navigator.of(context).pop();
            },
            child: const Text('Later'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await requestIgnoreBatteryOptimizations();
              markPromptShown();
            },
            child: const Text('Enable'),
          ),
        ],
      ),
    );
  }
}
