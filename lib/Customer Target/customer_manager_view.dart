import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../Misc/user_cache_service.dart';
import 'customer_admin_viewer.dart';

class CustomerManagerViewerPage extends StatelessWidget {
  const CustomerManagerViewerPage({super.key});

  Future<String?> _getManagerBranch() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    await UserCacheService.instance.ensureLoaded();
    return UserCacheService.instance.branch;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _getManagerBranch(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final branch = snapshot.data;
        return CustomerAdminViewerPage(
          forceBranch: branch,
          hideBranchDropdown: true,
        );
      },
    );
  }
}
