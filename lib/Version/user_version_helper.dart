import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'app_constants.dart';

Future<void> updateUserVersionInfo() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user != null) {
    // Fetch username from Firestore user document
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final username = userDoc.data()?['username'] ?? user.email ?? '';

    final docRef = FirebaseFirestore.instance.collection('user_version').doc(user.uid);
    await docRef.set({
      'email': user.email,
      'username': username,
      'appVersion': appVersion,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}