import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../Misc/theme_notifier.dart';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../DME/temporary.dart';
import '../Navigation/user_cache_service.dart';

import 'dart:async';

class SettingsPage extends StatefulWidget {
  final String userRole;
  final ThemeProvider themeProvider;

  const SettingsPage(
      {super.key, required this.userRole, required this.themeProvider});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with WidgetsBindingObserver {
  String? _generatedCode;
  Timer? _codeTimer;

  // Permission statuses
  bool _loadingPermissions = true;
  bool _isPermissionsExpanded = false;
  Map<Permission, PermissionStatus> _permissionStatuses = {};

  static const List<Map<String, dynamic>> _appPermissions = [
    {
      'permission': Permission.notification,
      'title': 'Notifications',
      'description': 'Required for reminders, call alerts and updates',
      'icon': Icons.notifications_active_outlined,
    },
    {
      'permission': Permission.phone,
      'title': 'Phone & Call Log',
      'description': 'Used for customer call logging and direct dialing',
      'icon': Icons.phone_outlined,
    },
    {
      'permission': Permission.contacts,
      'title': 'Contacts',
      'description': 'Used to access contacts for lead creation',
      'icon': Icons.contacts_outlined,
    },
    {
      'permission': Permission.camera,
      'title': 'Camera',
      'description': 'Used for marketing photos and document uploads',
      'icon': Icons.camera_alt_outlined,
    },
    {
      'permission': Permission.location,
      'title': 'Location',
      'description': 'Used for geotagging marketing visits and maps',
      'icon': Icons.location_on_outlined,
    },
    {
      'permission': Permission.storage,
      'title': 'Storage / Photos',
      'description': 'Used to save and export Excel files and documents',
      'icon': Icons.folder_open_outlined,
    },
    {
      'permission': Permission.scheduleExactAlarm,
      'title': 'Exact Alarms',
      'description': 'Ensures reminders and follow-ups fire on time',
      'icon': Icons.alarm_outlined,
    },
    {
      'permission': Permission.ignoreBatteryOptimizations,
      'title': 'Battery Optimization Exclusion',
      'description': 'Prevents Android from killing background reminder syncing',
      'icon': Icons.battery_charging_full_outlined,
    },
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissions();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
    }
  }

  Future<void> _checkPermissions() async {
    final Map<Permission, PermissionStatus> updatedStatuses = {};
    for (final item in _appPermissions) {
      final perm = item['permission'] as Permission;
      try {
        if (perm == Permission.storage) {
          // On Android 13+ (API 33+), Permission.storage is deprecated and replaces with photos/videos.
          // Check storage, photos, or manageExternalStorage
          final storageStatus = await Permission.storage.status;
          final photosStatus = await Permission.photos.status;
          if (storageStatus.isGranted || photosStatus.isGranted) {
            updatedStatuses[perm] = PermissionStatus.granted;
          } else if (photosStatus.isPermanentlyDenied || storageStatus.isPermanentlyDenied) {
            updatedStatuses[perm] = PermissionStatus.permanentlyDenied;
          } else {
            updatedStatuses[perm] = storageStatus.isDenied ? storageStatus : photosStatus;
          }
        } else {
          final status = await perm.status;
          updatedStatuses[perm] = status;
        }
      } catch (e) {
        debugPrint('Error checking permission $perm: $e');
      }
    }
    if (mounted) {
      setState(() {
        _permissionStatuses = updatedStatuses;
        _loadingPermissions = false;
      });
    }
  }

  Future<void> _requestPermission(
      Permission permission, String title, BuildContext context) async {
    // 1. Always attempt an in-app request first.
    PermissionStatus newStatus;
    if (permission == Permission.storage) {
      // On Android 13+, requesting Permission.storage returns permanentlyDenied immediately
      // unless Permission.photos (READ_MEDIA_IMAGES) is requested!
      final photosStatus = await Permission.photos.request();
      if (photosStatus.isGranted || photosStatus.isLimited) {
        newStatus = photosStatus;
      } else {
        newStatus = await Permission.storage.request();
        if (!newStatus.isGranted && photosStatus.isPermanentlyDenied) {
          newStatus = photosStatus;
        }
      }
    } else {
      newStatus = await permission.request();
    }

    if (mounted) {
      setState(() {
        _permissionStatuses[permission] = newStatus;
      });

      if (newStatus.isGranted || newStatus.isLimited) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text('$title permission granted'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
        return;
      }

      // 2. If it's permanently denied or restricted, Android blocks in-app prompts.
      // Explain clearly and provide a direct 1-tap button to the app settings.
      if (newStatus.isPermanentlyDenied || newStatus.isRestricted) {
        _showOpenSettingsDialog(context, title);
      } else {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text('$title permission not granted'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _showOpenSettingsDialog(BuildContext context, String title) {
    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: Text('$title Permission Required'),
          content: Text(
            '$title permission was denied. Please enable it in the system App Settings to use this feature properly.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                openAppSettings();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF005BAC),
                foregroundColor: Colors.white,
              ),
              child: const Text('Open Settings'),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _codeTimer?.cancel();
    super.dispose();
  }

  Future<void> _generateRegistrationCode() async {
    final code = (Random().nextInt(9000) + 1000).toString();
    await FirebaseFirestore.instance
        .collection('registration_codes')
        .doc('active')
        .set({
      'code': code,
      'createdAt': FieldValue.serverTimestamp(),
    });
    _codeTimer?.cancel();
    if (mounted) {
      setState(() {
        _generatedCode = code;
      });
      _codeTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) {
          setState(() {
            _generatedCode = null;
          });
        }
      });
    }
  }

  Future<String?> getUserRole() async {
    final cachedRole = UserCacheService.instance.role;
    if (cachedRole != null && cachedRole.isNotEmpty) {
      return cachedRole.toLowerCase();
    }
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
                            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                              const SnackBar(
                                content: Text('Configuration saved successfully'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
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
                          final role = (snapshot.data ?? widget.userRole).toLowerCase().trim();
                          if (role.isEmpty) return const SizedBox.shrink();
                          final isAdmin = role == 'admin';
                          final isSyncHead = role == 'sync_head';

                          if (isAdmin || isSyncHead) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: _generateRegistrationCode,
                                  icon: const Icon(Icons.key_rounded),
                                  label:
                                      const Text('Generate Registration Code'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF005BAC),
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                                if (_generatedCode != null) ...[
                                  const SizedBox(height: 12),
                                  Center(
                                    child: SelectableText(
                                      'Code: $_generatedCode',
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                  ),
                                ],
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
                      _buildPermissionsSection(context, theme),
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

  Widget _buildPermissionsSection(BuildContext context, ThemeData theme) {
    if (_loadingPermissions) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24.0),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final grantedList = <Map<String, dynamic>>[];
    final notGrantedList = <Map<String, dynamic>>[];

    for (final item in _appPermissions) {
      final perm = item['permission'] as Permission;
      final status = _permissionStatuses[perm];
      final isGranted = status != null &&
          (status.isGranted || status.isLimited);

      if (isGranted) {
        grantedList.add(item);
      } else {
        notGrantedList.add(item);
      }
    }

    final int missingCount = notGrantedList.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            setState(() {
              _isPermissionsExpanded = !_isPermissionsExpanded;
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Row(
              children: [
                const Icon(
                  Icons.security_outlined,
                  color: Color(0xFF005BAC),
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'App Permissions',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (missingCount > 0) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: Colors.orange.withOpacity(0.4)),
                              ),
                              child: Text(
                                '$missingCount missing',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.deepOrange,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        missingCount == 0
                            ? 'All required permissions are granted'
                            : '$missingCount permission${missingCount > 1 ? 's' : ''} not yet granted',
                        style: TextStyle(
                          fontSize: 12,
                          color: missingCount == 0
                              ? Colors.green
                              : theme.textTheme.bodyMedium?.color
                                  ?.withOpacity(0.65),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_isPermissionsExpanded)
                  IconButton(
                    tooltip: 'Refresh permissions',
                    icon: const Icon(Icons.refresh,
                        color: Color(0xFF005BAC), size: 20),
                    onPressed: _checkPermissions,
                  ),
                AnimatedRotation(
                  turns: _isPermissionsExpanded ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(
                    Icons.keyboard_arrow_down,
                    color: Color(0xFF005BAC),
                    size: 28,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_isPermissionsExpanded) ...[
          const SizedBox(height: 8),
          Text(
            'Tap any missing permission to grant it or open settings.',
            style: TextStyle(
              fontSize: 13,
              color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 16),

        // Not Granted Section (Prioritized on top)
        if (notGrantedList.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.warning_amber_rounded,
                    size: 18, color: Colors.deepOrange),
                const SizedBox(width: 6),
                Text(
                  'Missing Permissions (${notGrantedList.length})',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.deepOrange,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Card(
            elevation: 1,
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.orange.shade200, width: 1),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: notGrantedList.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = notGrantedList[index];
                final perm = item['permission'] as Permission;
                final title = item['title'] as String;
                final desc = item['description'] as String;
                final icon = item['icon'] as IconData;
                final status = _permissionStatuses[perm];
                final isDeniedForever = status != null &&
                    (status.isPermanentlyDenied || status.isRestricted);

                return ListTile(
                  onTap: () => _requestPermission(perm, title, context),
                  leading: CircleAvatar(
                    backgroundColor: Colors.orange.withOpacity(0.15),
                    child: Icon(icon, color: Colors.deepOrange, size: 22),
                  ),
                  title: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    desc,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.textTheme.bodyMedium?.color?.withOpacity(0.65),
                    ),
                  ),
                  trailing: ElevatedButton(
                    onPressed: () => _requestPermission(perm, title, context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF005BAC),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      isDeniedForever ? 'Settings' : 'Grant',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
        ],

        // Granted Section
        if (grantedList.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle_outline,
                    size: 18, color: Colors.green),
                const SizedBox(width: 6),
                Text(
                  'Granted Permissions (${grantedList.length})',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Card(
            elevation: 1,
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                  color: theme.dividerColor.withOpacity(0.2), width: 1),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: grantedList.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = grantedList[index];
                final title = item['title'] as String;
                final desc = item['description'] as String;
                final icon = item['icon'] as IconData;

                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.green.withOpacity(0.12),
                    child: Icon(icon, color: Colors.green, size: 22),
                  ),
                  title: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    desc,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.textTheme.bodyMedium?.color?.withOpacity(0.65),
                    ),
                  ),
                  trailing: const Icon(Icons.check_circle,
                      color: Colors.green, size: 22),
                );
              },
            ),
          ),
        ],

        const SizedBox(height: 24),
      ],
    ],
  );
  }
}
