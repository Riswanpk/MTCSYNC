import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';

import '../login.dart';
import '../Misc/settings.dart';
import '../Misc/user_cache_service.dart';
import '../Feedback/feedback.dart';
import '../Feedback/feedback_admin.dart';
import '../Misc/manageusers.dart';
import '../Performance/dailyform.dart';
import '../Performance/performance_score_page.dart';
import '../Performance/admin_performance_page.dart';
import '../Performance/excel_view_performance.dart';
import '../Performance/insights_performance.dart';
import '../Performance/entry_page.dart';
import '../Instructions/instructions.dart';
import '../Misc/theme_notifier.dart';

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
          _buildFeedbackTile(context),
          if (role == 'admin') _buildManageUsersTile(context),
          if (role == 'manager') _buildDailyFormTile(context),
          if (role == 'sales') _buildPerformanceTile(context),
          if (role == 'admin') _buildEditPerformanceFormTile(context),
          if (role == 'admin') _buildPerformanceMonthlyTile(context),
          if (role == 'admin') _buildPerformanceInsightsTile(context),
          if (role == 'admin') _buildEntryPageTile(context),
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

  Widget _buildFeedbackTile(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: const Icon(Icons.feedback, color: Color(0xFF8CC63F)),
      title: const Text('Feedback'),
      onTap: () async {
        Navigator.pop(context);

        final cache = UserCacheService.instance;
        await cache.ensureLoaded();
        final userRole = cache.role;

        if (userRole == 'admin') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const FeedbackAdminPage()),
          );
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const FeedbackPage()),
          );
        }
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
              builder: (context) => const ManageUsersPage(userRole: 'admin')),
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

  Widget _buildPerformanceTile(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: const Icon(Icons.bar_chart, color: Colors.teal),
      title: const Text('Performance'),
      onTap: () {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => PerformanceScoreInnerPage()),
        );
      },
    );
  }

  Widget _buildEditPerformanceFormTile(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: const Icon(Icons.edit_note, color: Colors.deepPurple),
      title: const Text('Edit Performance Form'),
      onTap: () {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const AdminPerformancePage()),
        );
      },
    );
  }

  Widget _buildPerformanceMonthlyTile(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: const Icon(Icons.insert_chart,
          color: Color.fromARGB(255, 255, 175, 3)),
      title: const Text('Performance Monthly'),
      onTap: () {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => ExcelViewPerformancePage()),
        );
      },
    );
  }

  Widget _buildPerformanceInsightsTile(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: const Icon(Icons.insights, color: Colors.green),
      title: const Text('Performance Insights'),
      onTap: () {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => InsightsPerformancePage()),
        );
      },
    );
  }

  Widget _buildEntryPageTile(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: const Icon(Icons.add_box, color: Colors.blue),
      title: const Text('Entry Page'),
      onTap: () {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => EntryPage()),
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
