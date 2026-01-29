import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'customer_admin_viewer.dart';

class CustomerManagerViewerPage extends StatelessWidget {
  const CustomerManagerViewerPage({super.key});

  Future<String?> _getManagerBranch() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    // You may want to handle errors here in real app
    final querySnapshot = user.email != null
        ? await FirebaseFirestore.instance.collection('users').where('email', isEqualTo: user.email).get()
        : null;
    if (querySnapshot != null && querySnapshot.docs.isNotEmpty) {
      return querySnapshot.docs.first['branch'] as String?;
    }
    return null;
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
