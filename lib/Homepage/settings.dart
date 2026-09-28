import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../Misc/theme_notifier.dart';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../DME/temporary.dart';

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
      SnackBar(
        content: Text('Generated Registration Code: $code'),
        duration: const Duration(seconds: 5),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<String?> getUserRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      return (doc.data()?['role'] as String?)?.toLowerCase();
    }
    return null;
  }

  void _showForceUpdateDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance
              .collection('app_config')
              .doc('version_info')
              .get(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final data = snapshot.data?.data() as Map<String, dynamic>?;
            final isForceUpdateEnabled =
                data?['force_update_enabled'] as bool? ?? false;
            final minVersion = data?['min_version'] as String? ?? '1.0.0';
            final updateMessage = data?['update_message'] as String? ?? '';
            final appUrl = data?['app_url'] as String? ?? '';

            final minVersionController =
                TextEditingController(text: minVersion);
            final updateMessageController =
                TextEditingController(text: updateMessage);
            final appUrlController = TextEditingController(text: appUrl);
            bool forceUpdate = isForceUpdateEnabled;

            return StatefulBuilder(
              builder: (context, setState) {
                return AlertDialog(
                  title: const Text('Force Update Configuration'),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SwitchListTile(
                          title: const Text('Enable Force Update'),
                          value: forceUpdate,
                          onChanged: (bool value) {
                            setState(() {
                              forceUpdate = value;
                            });
                          },
                        ),
                        TextField(
                          controller: minVersionController,
                          decoration: const InputDecoration(
                            labelText: 'Minimum Required Version',
                            hintText: 'e.g., 1.0.0',
                          ),
                        ),
                        TextField(
                          controller: updateMessageController,
                          decoration: const InputDecoration(
                            labelText: 'Update Message',
                            hintText: 'Message to show to users',
                          ),
                          maxLines: 3,
                        ),
                        TextField(
                          controller: appUrlController,
                          decoration: const InputDecoration(
                            labelText: 'App Download URL',
                            hintText: 'URL to download the update',
                          ),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        try {
                          await FirebaseFirestore.instance
                              .collection('app_config')
                              .doc('version_info')
                              .set({
                            'force_update_enabled': forceUpdate,
                            'min_version': minVersionController.text.trim(),
                            'update_message':
                                updateMessageController.text.trim(),
                            'app_url': appUrlController.text.trim(),
                            'updated_at': FieldValue.serverTimestamp(),
                          }, SetOptions(merge: true));

                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Configuration saved successfully'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Error saving configuration: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF005BAC),
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Save'),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
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
                                  const SizedBox(height: 16),
                                  ElevatedButton.icon(
                                    onPressed: () =>
                                        OldLeadsRemover.showOldLeadsCleanupDialog(context),
                                    icon: const Icon(
                                        Icons.auto_delete_rounded),
                                    label: const Text('Delete Leads Older Than 2 Months'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.redAccent,
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
