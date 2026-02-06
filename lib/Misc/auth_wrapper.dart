import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../login.dart';

/// A global auth state wrapper that redirects to login when the user session
/// becomes invalid (e.g., token expired, account disabled, signed out elsewhere).
class AuthWrapper extends StatefulWidget {
  final Widget child;

  const AuthWrapper({super.key, required this.child});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  StreamSubscription<User?>? _authSubscription;
  bool _initialCheckDone = false;

  @override
  void initState() {
    super.initState();
    _setupAuthListener();
  }

  void _setupAuthListener() {
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      // Skip the initial null state on app start (splash screen handles initial auth)
      if (!_initialCheckDone) {
        _initialCheckDone = true;
        return;
      }

      // If user becomes null after initial check, session was invalidated
      if (user == null && mounted) {
        _redirectToLogin();
      }
    });
  }

  void _redirectToLogin() {
    // Navigate to login and clear the navigation stack
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

/// Helper function to handle Firebase permission errors globally.
/// Call this in catch blocks when making Firestore calls.
/// Returns true if the error was an auth-related error that was handled.
bool handleFirebaseAuthError(BuildContext context, dynamic error) {
  if (error is FirebaseException) {
    final code = error.code;
    // Handle permission-denied or unauthenticated errors
    if (code == 'permission-denied' ||
        code == 'unauthenticated' ||
        code == 'UNAUTHENTICATED') {
      _showAuthErrorAndRedirect(context);
      return true;
    }
  }
  return false;
}

void _showAuthErrorAndRedirect(BuildContext context) {
  // Show a message and redirect to login
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Session expired. Please log in again.'),
      duration: Duration(seconds: 2),
    ),
  );

  // Delay slightly to show the message, then redirect
  Future.delayed(const Duration(milliseconds: 500), () {
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (route) => false,
      );
    }
  });
}
