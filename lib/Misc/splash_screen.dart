import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../login.dart';
import '../home.dart';
import '../main.dart'; // For navigatorKey and initialNotificationAction
import '../Todo & Leads/presentfollowup.dart'; // For PresentFollowUp
import '../Todo & Leads/todo.dart'; // For TodoPage and TaskDetailPageFromId
import 'package:awesome_notifications/awesome_notifications.dart'; // For ReceivedAction
import 'package:home_widget/home_widget.dart'; // For HomeWidget

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  StreamSubscription<Uri?>? _widgetClickSub;
  bool _openedFromWidget = false; // Add this flag

  @override
  void initState() {
    super.initState();
    _widgetClickSub = HomeWidget.widgetClicked.listen((Uri? uri) {
      print('Widget clicked! Navigating to TodoPage');
      _openedFromWidget = true;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const TodoPage()),
      );
    });
    // Delay navigation check until after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAuthAndNavigate();
    });
  }

  @override
  void dispose() {
    _widgetClickSub?.cancel();
    super.dispose();
  }

  Future<void> _checkAuthAndNavigate() async {
    final user = await FirebaseAuth.instance.authStateChanges().first;
    if (!mounted) return;

    if (_openedFromWidget) return; // Bypass default navigation if opened from widget

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