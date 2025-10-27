import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../login.dart';
import '../home.dart';
import '../main.dart'; // For navigatorKey and initialNotificationAction
import '../Todo & Leads/presentfollowup.dart'; // For PresentFollowUp
import '../Todo & Leads/todo.dart'; // For TodoPage and TaskDetailPageFromId
import 'package:awesome_notifications/awesome_notifications.dart'; // For ReceivedAction

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuthAndNavigate();
  }

  Future<void> _checkAuthAndNavigate() async {
    // Wait for Firebase Auth to determine the initial user state.
    // This stream emits null if no user is logged in, or a User object if logged in.
    // It emits the *initial* state immediately after Firebase is ready.
    FirebaseAuth.instance.authStateChanges().listen((User? user) {
      if (mounted) {
        if (user == null) {
          // No user logged in, go to login page
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const LoginPage()),
          );
        } else {
          // User is logged in, go to home page
          // Handle initial notification action if present
          if (initialNotificationAction != null) {
            _handleInitialNotification(initialNotificationAction!);
            initialNotificationAction = null; // Clear after handling
          }
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const HomePage()),
          );
        }
      }
    });
  }

  void _handleInitialNotification(ReceivedAction action) {
    final payload = action.payload;
    final docId = payload?['docId'];
    final page = payload?['page'];
    final isTodo = payload?['type'] == 'todo';

    final navigator = navigatorKey.currentState;
    if (navigator == null) return;

    if (page == 'todo') {
      navigator.push(MaterialPageRoute(builder: (_) => const TodoPage()));
    } else if (docId != null) {
      final isEdit = action.buttonKeyPressed == 'EDIT_FOLLOWUP';
      if (isEdit) {
        navigator.push(MaterialPageRoute(builder: (_) => PresentFollowUp(docId: docId, editMode: true)));
      } else if (isTodo) {
        navigator.push(MaterialPageRoute(builder: (_) => TaskDetailPageFromId(docId: docId)));
      } else {
        navigator.push(MaterialPageRoute(builder: (_) => PresentFollowUp(docId: docId)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Display a loading indicator while checking auth state
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}