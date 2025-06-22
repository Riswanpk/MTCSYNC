import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:install_plugin/install_plugin.dart';

class UpdateChecker {
  // 🔁 Replace this with your actual Firebase Hosting version.json URL
  static const String versionUrl = 'https://your-app.web.app/version.json';

  static Future<void> checkAndUpdate(BuildContext context) async {
    try {
      final info = await PackageInfo.fromPlatform();
      final currentVersion = int.parse(info.buildNumber);

      final response = await http.get(Uri.parse(versionUrl));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final latestVersion = data['versionCode'];
        final apkUrl = data['apkUrl'];

        if (latestVersion > currentVersion) {
          await _downloadAndPromptInstall(context, apkUrl);
        }
      }
    } catch (e) {
      print("Update check failed: $e");
    }
  }

  static Future<void> _downloadAndPromptInstall(BuildContext context, String apkUrl) async {
    final dir = await getExternalStorageDirectory();
    final apkPath = '${dir!.path}/update.apk';

    final dio = Dio();
    await dio.download(apkUrl, apkPath);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text("Update Available"),
        content: Text("A new version has been downloaded. Do you want to install it now?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Later"),
          ),
          TextButton(
            onPressed: () async {
              try {
                await InstallPlugin.installApk(apkPath); // ✅ Must match your app ID
              } catch (e) {
                print("Install error: $e");
              }
            },
            child: Text("Install"),
          ),
        ],
      ),
    );
  }
}
