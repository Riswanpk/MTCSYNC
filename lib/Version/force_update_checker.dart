import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Checks Firestore for the minimum required app version.
///
/// Firestore path: `config/app_config`
/// Required field:  `min_version_code` (int)  — matches Android versionCode
///
/// To force all users below versionCode 130 to update, set:
///   config/app_config → { min_version_code: 130 }
class ForceUpdateChecker {
  static Future<bool> isUpdateRequired() async {
    try {
      // Get the current app version code (build number)
      final packageInfo = await PackageInfo.fromPlatform();
      final currentBuildNumber = int.tryParse(packageInfo.buildNumber) ?? 0;

      // Fetch the minimum required version from Firestore
      final doc = await FirebaseFirestore.instance
          .collection('config')
          .doc('app_config')
          .get()
          .timeout(const Duration(seconds: 10));

      if (!doc.exists) return false; // No config → don't block

      final minVersionCode = doc.data()?['min_version_code'];
      if (minVersionCode == null) return false; // Field missing → don't block

      final required = (minVersionCode as num).toInt();
      return currentBuildNumber < required;
    } catch (e) {
      // On any error (network, Firestore, etc.) → don't block the user
      return false;
    }
  }
}
