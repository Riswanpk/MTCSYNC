import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'app_constants.dart';

Future<void> updateUserVersionInfo() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user != null) {
    try {
      await _updateUserVersionInfoWithRetry(user);
    } catch (e, stackTrace) {
      // Log the error to Crashlytics but don't crash the app
      await FirebaseCrashlytics.instance.recordError(
        e,
        stackTrace,
        reason: 'Failed to update user version info after retries',
      );
      print('Error updating user version info: $e');
    }
  }
}

/// Attempts to update user version info with exponential backoff retry logic
Future<void> _updateUserVersionInfoWithRetry(User user) async {
  const maxAttempts = 3;
  const initialDelayMs = 1000; // 1 second

  for (int attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      // Fetch username from Firestore user document
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final username = userDoc.data()?['username'] ?? user.email ?? '';

      final docRef =
          FirebaseFirestore.instance.collection('user_version').doc(user.uid);
      await docRef.set({
        'email': user.email,
        'username': username,
        'appVersion': appVersion,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return; // Success, exit the retry loop
    } on FirebaseException catch (e) {
      // Check if it's a transient error
      if (e.code == 'unavailable' && attempt < maxAttempts) {
        // Calculate exponential backoff: 1s, 2s, 4s
        final delayMs = initialDelayMs * (1 << (attempt - 1));
        print(
            'Firestore unavailable (attempt $attempt/$maxAttempts). Retrying in ${delayMs}ms...');
        await Future.delayed(Duration(milliseconds: delayMs));
      } else {
        // Non-transient error or last attempt failed
        rethrow;
      }
    }
  }
}