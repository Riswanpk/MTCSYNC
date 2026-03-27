import 'package:flutter/material.dart';
import '../../Homepage/home_body.dart' show primaryBlue;
import '../dme_config.dart';

class DmeBranchManagementPage extends StatelessWidget {
  const DmeBranchManagementPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Branches'),
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,
      ),
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 12),
        itemCount: kAppBranches.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final name = kAppBranches[i];
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: primaryBlue.withOpacity(0.1),
              child: Text(
                name.substring(0, name.length > 2 ? 2 : name.length),
                style: const TextStyle(
                  color: primaryBlue,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
            title: Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          );
        },
      ),
    );
  }
}
