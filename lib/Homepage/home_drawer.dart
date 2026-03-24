import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';

import '../Login/login.dart';
import 'settings.dart';
import '../Navigation/user_cache_service.dart';
import 'manageusers.dart';
import '../Performance/dailyform.dart';

import '../Instructions/instructions.dart';
import '../Misc/theme_notifier.dart';
import '../Sync Head/sync_head_performance_drawer.dart';
import '../Performance/my_performance_page.dart';

/// Builds the drawer widget for the home page.
class HomeDrawer extends StatelessWidget {
  final String? role;
  final String? username;
  final String? branch;
  final File? profileImage;
  final VoidCallback onPickProfileImage;

  const HomeDrawer({
    super.key,
    required this.role,
    required this.username,
    required this.branch,
    required this.profileImage,
    required this.onPickProfileImage,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _buildDrawerHeader(context),
          _buildSettingsTile(context),
          if (role == 'admin' || role == 'sync_head' || role == 'Sync Head') _buildManageUsersTile(context),
          if (role == 'manager') _buildDailyFormTile(context),
          if (role == 'sales' || role == 'asst_manager') _buildMyPerformanceTile(context),

          if (role == 'admin') _buildAdminPerformanceTile(context),
          if (role == 'sync_head' || role == 'Sync Head') _buildSyncHeadPerformanceTile(context),
          _buildInstructionsTile(context),
          _buildLogoutTile(context),
        ],
      ),
    );
  }

  Widget _buildDrawerHeader(BuildContext context) {
    return DrawerHeader(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF005BAC), Color(0xFF3383C7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Profile',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: onPickProfileImage,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: Colors.white,
                  backgroundImage:
                      (profileImage != null) ? FileImage(profileImage!) : null,
                  child: (profileImage == null)
                      ? const Icon(Icons.account_circle,
                          size: 38, color: Color(0xFF005BAC))
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        username ?? '',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        branch ?? '',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTile(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: const Icon(Icons.settings, color: Color(0xFF005BAC)),
      title: const Text('Settings'),
      onTap: () {
        final themeProvider =
            Provider.of<ThemeProvider>(context, listen: false);
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SettingsPage(
                userRole: role ?? '', themeProvider: themeProvider),
          ),
        );
      },
    );
  }

  Widget _buildManageUsersTile(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: const Icon(Icons.manage_accounts, color: Colors.deepPurple),
      title: const Text('Manage Users'),
      onTap: () {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (context) => ManageUsersPage(userRole: role ?? 'admin')),
        );
      },
    );
  }

  Widget _buildDailyFormTile(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: const Icon(Icons.assignment_turned_in, color: Colors.orange),
      title: const Text('Daily Form'),
      onTap: () {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => PerformanceForm()),
        );
      },
    );
  }

  Widget _buildMyPerformanceTile(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: const Icon(Icons.bar_chart_rounded, color: Color(0xFF005BAC)),
      title: const Text('My Performance'),
      onTap: () {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const MyPerformancePage()),
        );
      },
    );
  }

  Widget _buildSyncHeadPerformanceTile(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: const Icon(Icons.bar_chart_rounded, color: Color(0xFF005BAC)),
      title: const Text('Performance'),
      onTap: () {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (context) => const SyncHeadPerformancePage()),
        );
      },
    );
  }

  Widget _buildAdminPerformanceTile(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: const Icon(Icons.bar_chart_rounded, color: Color(0xFF005BAC)),
      title: const Text('Performance'),
      onTap: () {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (context) => const SyncHeadPerformancePage()),
        );
      },
    );
  }

  Widget _buildInstructionsTile(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: const Icon(Icons.info_outline, color: Colors.blueAccent),
      title: const Text('Instructions'),
      onTap: () {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const InstructionsPage()),
        );
      },
    );
  }

  Widget _buildLogoutTile(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: const Icon(Icons.logout, color: Colors.red),
      title: const Text('Log Out'),
      onTap: () async {
        UserCacheService.instance.clear();
        await FirebaseAuth.instance.signOut();
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const LoginPage()),
          (Route<dynamic> route) => false,
        );
      },
    );
  }
}
