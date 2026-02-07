import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import '../login.dart';
import '../home.dart';
import '../main.dart'; // For navigatorKey and initialNotificationAction
import '../Todo & Leads/presentfollowup.dart'; // For PresentFollowUp
import '../Todo & Leads/todo.dart'; // For TodoPage and TaskDetailPageFromId
import '../Marketing/marketing.dart'; // For MarketingFormPage
import '../Misc/loading_page.dart'; // For LoadingOverlayPage
import '../Misc/navigation_state.dart'; // For navigation state restoration
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
    // Delay permission request and navigation until after first frame (UI visible)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestPermissionsAndNavigate();
    });
  }

  @override
  void dispose() {
    _widgetClickSub?.cancel();
    super.dispose();
  }

  Future<void> _requestPermissionsAndNavigate() async {
    // Request permissions that show dialogs first
    // Some permissions auto-grant or require Settings - don't await those blocking
    try {
      // These show actual permission dialogs
      await Permission.camera.request();
      await Permission.contacts.request();
      await Permission.phone.request();
      await Permission.location.request();
      await Permission.notification.request();
      
      // These may auto-grant or not show dialogs - request without blocking
      Permission.storage.request();
      Permission.manageExternalStorage.request();
      Permission.scheduleExactAlarm.request();
      Permission.reminders.request();
      
      // Request to ignore battery optimizations for reliable notifications
      // This helps notifications show even when app is in background
      Permission.ignoreBatteryOptimizations.request();
    } catch (e) {
      debugPrint('Permission error: $e');
    }

    // Only navigate after main permissions are handled
    if (!mounted) return;
    await _checkAuthAndNavigate();
  }

  Future<void> _checkAuthAndNavigate() async {
    final user = await FirebaseAuth.instance.authStateChanges().first;
    if (!mounted) return;

    if (_openedFromWidget) return; // Bypass default navigation if opened from widget

    if (user == null) {
      await NavigationState.clearState(); // Clear any pending state for logged out users
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (context) => const LoginPage()));
    } else {
      // Handle initial notification action if the app was opened from a notification.
      if (initialNotificationAction != null) {
        _handleInitialNotification(initialNotificationAction!);
        initialNotificationAction = null; // Clear after handling
      }
      
      // Check for pending navigation state (activity recreation recovery)
      final pendingState = await NavigationState.getState();
      if (pendingState == 'marketing') {
        final userData = await NavigationState.getUserData();
        if (userData != null && 
            userData['username'] != null && 
            userData['userid'] != null && 
            userData['branch'] != null) {
          // Restore user to marketing form
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const HomePage()),
          );
          // Then push marketing on top (with slight delay to ensure home is loaded)
          Future.delayed(const Duration(milliseconds: 100), () {
            if (mounted) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => LoadingOverlayPage(
                    child: MarketingFormPage(
                      username: userData['username'] ?? '',
                      userid: userData['userid'] ?? '',
                      branch: userData['branch'] ?? '',
                    ),
                  ),
                ),
              ).then((_) {
                NavigationState.clearState();
              });
            }
          });
          return;
        }
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
    // Show empty screen during permission requests - avoids flashing loading circle
    return const Scaffold(
      backgroundColor: Colors.white,
      body: SizedBox.shrink(),
    );
  }
}