
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mtcsync/DME/screens/dme_user_complaints.dart';
import 'package:mtcsync/DME/screens/dme_customer_variants_page.dart';
import 'package:provider/provider.dart';

import '../Login/login.dart';
import 'settings.dart';
import '../Navigation/user_cache_service.dart';
import 'manageusers.dart';

import '../Instructions/instructions.dart';
import '../Misc/theme_notifier.dart';

import '../DME/screens/dme_user_management.dart';
import '../SME/sme_lead_form.dart';

/// Builds the drawer widget for the home page.
class HomeDrawer extends StatelessWidget {
  final String? role;
  final String? username;
  final String? branch;

  const HomeDrawer({
    super.key,
    required this.role,
    required this.username,
    required this.branch,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _buildDrawerHeader(context),
          _buildSettingsTile(context),
          // DME users: 'My Complaints' showing only their own raised complaints
          if (role == 'dme_user') _buildDmeUserComplaintsTile(context),
          if (role == 'dme_user') _buildDmeUserAddLeadTile(context),
          if (role == 'dme_user') _buildDmeUserVariantsTile(context),
          if (role == 'admin' || role == 'sync_head' || role == 'Sync Head')
            _buildManageUsersTile(context),
          if (role == 'dme_admin') _buildDmeUsersTile(context),
          _buildSyncSmeUserNamesTile(context),

          _buildInstructionsTile(context),
          _buildLogoutTile(context),
        ],
      ),
    );
  }

  Widget _buildSyncSmeUserNamesTile(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: const Icon(Icons.sync_alt_rounded, color: Color(0xFF005BAC)),
      title: const Text('Fix SME Unassigned Names'),
      subtitle: const Text('One-time sync assigned_to_name from users collection',
          style: TextStyle(fontSize: 10)),
      onTap: () async {
        Navigator.pop(context);
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Expanded(child: Text('Syncing assigned user names...')),
              ],
            ),
          ),
        );

        int updatedCount = 0;
        try {
          // Query all SME follow_ups
          final snap = await FirebaseFirestore.instance
              .collection('follow_ups')
              .where('source', whereIn: ['sme', 'SME'])
              .get();

          final userCache = <String, String>{};

          for (final doc in snap.docs) {
            final data = doc.data();
            final assignedTo = data['assigned_to'] as String?;
            final currentName = data['assigned_to_name'] as String?;

            if (assignedTo != null &&
                assignedTo.isNotEmpty &&
                (currentName == null || currentName.isEmpty || currentName == 'Unknown')) {
              
              if (!userCache.containsKey(assignedTo)) {
                final userSnap = await FirebaseFirestore.instance
                    .collection('users')
                    .doc(assignedTo)
                    .get();
                if (userSnap.exists) {
                  final udata = userSnap.data();
                  userCache[assignedTo] =
                      udata?['username'] as String? ?? udata?['name'] as String? ?? '';
                }
              }

              final nameToSet = userCache[assignedTo];
              if (nameToSet != null && nameToSet.isNotEmpty) {
                await doc.reference.update({'assigned_to_name': nameToSet});
                updatedCount++;
              }
            }
          }

          if (context.mounted) {
            Navigator.pop(context); // Dismiss loading dialog
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Successfully updated $updatedCount SME leads with assigned names!'),
                backgroundColor: const Color(0xFF4CAF50),
              ),
            );
          }
        } catch (e) {
          if (context.mounted) {
            Navigator.pop(context); // Dismiss loading dialog
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error syncing user names: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      },
    );
  }

  Widget _buildDmeUserComplaintsTile(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: const Icon(Icons.assignment_rounded, color: Colors.redAccent),
      title: const Text('My Complaints'),
      onTap: () {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (context) => const DmeUserComplaintsPage()),
        );
      },
    );
  }

  Widget _buildDmeUserAddLeadTile(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: const Icon(Icons.person_add_rounded, color: Colors.teal),
      title: const Text('Add Lead'),
      onTap: () {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (context) => const SmeLeadForm(source: 'DME')),
        );
      },
    );
  }

  Widget _buildDmeUserVariantsTile(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: const Icon(Icons.category_rounded, color: Colors.purpleAccent),
      title: const Text('Multi-Category Customers'),
      subtitle:
          const Text('2+ categories or types', style: TextStyle(fontSize: 10)),
      onTap: () {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (context) => const DmeCustomerVariantsPage()),
        );
      },
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
          const SizedBox(height: 8),
          Row(
            children: [
              const CircleAvatar(
                radius: 22,
                backgroundColor: Colors.white,
                child: Icon(Icons.account_circle,
                    size: 38, color: Color(0xFF005BAC)),
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
        final themeProvider = context.read<ThemeProvider>();
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

  Widget _buildDmeUsersTile(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: const Icon(Icons.manage_accounts, color: Colors.indigo),
      title: const Text('DME Users'),
      onTap: () {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (context) => const DmeUserManagementPage()),
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
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          try {
            await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
              'fcm_token': FieldValue.delete(),
            });
          } catch (e) {
            debugPrint('Failed to clear FCM token on logout: $e');
          }
        }
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
