import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../Misc/theme_notifier.dart';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';

class SettingsPage extends StatelessWidget {
  final String userRole;
  final ThemeProvider themeProvider;

  const SettingsPage(
      {super.key, required this.userRole, required this.themeProvider});

  Future<void> _generateRegistrationCode(BuildContext context) async {
    final code = (Random().nextInt(9000) + 1000).toString();
    await FirebaseFirestore.instance
        .collection('registration_codes')
        .doc('active')
        .set({
      'code': code,
      'createdAt': FieldValue.serverTimestamp(),
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Registration code generated: $code')),
    );
  }

  Future<void> _showForceUpdateDialog(BuildContext context) async {
    // Fetch current value first
    int? currentMin;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('config')
          .doc('app_config')
          .get();
      if (doc.exists) {
        currentMin = (doc.data()?['min_version_code'] as num?)?.toInt();
      }
    } catch (_) {}

    if (!context.mounted) return;

    final controller = TextEditingController(
      text: currentMin != null ? '$currentMin' : '',
    );

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Force Update Config'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Users with a build number BELOW this value will be forced to update before using the app.',
              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Minimum Build Number (versionCode)',
                border: OutlineInputBorder(),
                hintText: 'e.g. 183',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final value = int.tryParse(controller.text.trim());
              if (value == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Please enter a valid build number.')),
                );
                return;
              }
              try {
                await FirebaseFirestore.instance
                    .collection('config')
                    .doc('app_config')
                    .set({'min_version_code': value}, SetOptions(merge: true));
                if (ctx.mounted) Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content:
                        Text('Force update threshold set to build $value.'),
                    backgroundColor: Colors.green,
                  ),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to save: $e')),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    controller.dispose();
  }

  Future<String?> getUserRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final roleRaw = doc.data()?['role'];
    if (roleRaw == null) return null;
    return roleRaw.toString().toLowerCase().replaceAll('_', ' ').trim();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
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
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold),
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
                      FutureBuilder<String?>(
                        future: getUserRole(),
                        builder: (context, snapshot) {
                          final role = snapshot.data;
                          if (role == null) return const SizedBox.shrink();
                          final isAdmin = role == 'admin';
                          final isSyncHead = role == 'sync head' ||
                              role == 'synchead' ||
                              role == 'sync-head';
                          if (isAdmin || isSyncHead) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: () =>
                                      _generateRegistrationCode(context),
                                  icon: const Icon(Icons.key_rounded),
                                  label:
                                      const Text('Generate Registration Code'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF005BAC),
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                                if (isAdmin) ...[
                                  const SizedBox(height: 16),
                                  ElevatedButton.icon(
                                    onPressed: () =>
                                        _showForceUpdateDialog(context),
                                    icon: const Icon(
                                        Icons.system_update_alt_rounded),
                                    label: const Text('Force Update Config'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF005BAC),
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 32),
                              ],
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
          ],
        ),
      ),
    );
  }
}
