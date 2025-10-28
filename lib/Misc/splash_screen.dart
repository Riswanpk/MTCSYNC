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
    // Await the first authentication state and then navigate.
    // Using `first` ensures we only get one event and the subscription is closed,
    // preventing calls on a disposed widget.
    final user = await FirebaseAuth.instance.authStateChanges().first;

    // Ensure the widget is still mounted before navigating.
    if (!mounted) return;

    if (user == null) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (context) => const LoginPage()));
    } else {
      // Handle initial notification action if the app was opened from a notification.
      if (initialNotificationAction != null) {
        _handleInitialNotification(initialNotificationAction!);
        initialNotificationAction = null; // Clear after handling
      }
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (context) => const HomePage()));
    }
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