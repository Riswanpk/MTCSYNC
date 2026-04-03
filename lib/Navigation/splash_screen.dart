import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../Login/login.dart';
import '../Version/force_update_checker.dart';
import '../Version/force_update_screen.dart';
import '../Homepage/home.dart';
import '../main.dart'; // For navigatorKey and initialNotificationAction
import '../Leads/presentfollowup.dart'; // For PresentFollowUp
import '../Todo/todo.dart'; // For TodoPage and TaskDetailPageFromId
import '../Marketing/marketing.dart'; // For MarketingFormPage
import 'loading_page.dart'; // For LoadingOverlayPage
import 'navigation_state.dart'; // For navigation state restoration
import 'package:home_widget/home_widget.dart'; // For HomeWidget

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  static const _platform = MethodChannel('com.mtc.mtcsync/deeplink');
  StreamSubscription<Uri?>? _widgetClickSub;
  bool _openedFromWidget = false; // Add this flag

  @override
  void initState() {
    super.initState();
    // Listen for widget clicks when app is already running (warm start)
    _widgetClickSub = HomeWidget.widgetClicked.listen(_handleWidgetClick);
    // Check if app was cold-started from a widget/deep link via the platform channel
    _checkInitialDeepLink();
    // Delay permission request and navigation until after first frame (UI visible)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestPermissionsAndNavigate();
    });
  }

  /// Get the initial deep link if the app was launched from a widget or deep link
  Future<void> _checkInitialDeepLink() async {
    try {
      final String? deepLink = await _platform.invokeMethod<String>('getInitialDeepLink');
      if (deepLink != null && deepLink.isNotEmpty) {
        debugPrint('Initial deep link from intent: $deepLink');
        _handleWidgetClick(Uri.parse(deepLink));
      }
    } on PlatformException catch (e) {
      debugPrint('Failed to get deep link: ${e.message}');
    }
  }

  void _handleWidgetClick(Uri? uri) {
    if (!mounted || _openedFromWidget) return;
    if (uri != null) {
      debugPrint('Widget clicked! URI: $uri');
      _openedFromWidget = true;

      // Extract the path: "mtcsync://todo/<docId>" or "mtcsync://todo" etc.
      final host = uri.host;
      final pathSegments = uri.pathSegments;

      // Bypass HomePage — go directly to the detail/list page
      if (host == 'todo') {
        if (pathSegments.isNotEmpty) {
          // Go directly to todo detail page
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => TaskDetailPageFromId(docId: pathSegments.first),
            ),
          );
        } else {
          // Go directly to todo list page
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const TodoPage()),
          );
        }
      } else if (host == 'lead' && pathSegments.isNotEmpty) {
        // Go directly to lead detail page
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => PresentFollowUp(docId: pathSegments.first),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _widgetClickSub?.cancel();
    super.dispose();
  }

  Future<void> _requestPermissionsAndNavigate() async {
    // ── Force update check ────────────────────────────────────────────────────
    // Run before anything else. If the installed build is too old, replace the
    // splash with a non-dismissible update screen and stop further navigation.
    final updateRequired = await ForceUpdateChecker.isUpdateRequired();
    if (!mounted) return;
    if (updateRequired) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ForceUpdateScreen()),
      );
      return;
    }
    // ─────────────────────────────────────────────────────────────────────────

    // Request all permissions that show dialogs
    try {
      // Request permissions sequentially so dialogs appear one at a time
      await Permission.camera.request();
      await Permission.contacts.request();
      await Permission.phone.request();
      await Permission.location.request();
      await Permission.notification.request();
      await Permission.storage.request();
      await Permission.manageExternalStorage.request();
      await Permission.scheduleExactAlarm.request();
      await Permission.reminders.request();
      await Permission.ignoreBatteryOptimizations.request();
    } catch (e) {
      debugPrint('Permission error: $e');
    }

    // Only navigate after main permissions are handled
    if (!mounted) return;
    await _checkAuthAndNavigate();
  }

  /// Robustly resolves the current Firebase Auth user.
  /// On devices with aggressive process management (e.g., Pixel 10 / Android 16),
  /// Firebase Auth may not have restored the persisted session by the time
  /// authStateChanges() first fires. This method adds a brief wait window
  /// and falls back to re-login with saved credentials if available.
  Future<User?> _resolveAuthUser() async {
    // 1. Fast synchronous check (already restored)
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) return user;

    // 2. Wait for the first auth state event
    user = await FirebaseAuth.instance.authStateChanges().first;
    if (user != null) return user;

    // 3. Session may still be restoring — wait up to 2s for a non-null event
    try {
      user = await FirebaseAuth.instance
          .authStateChanges()
          .where((u) => u != null)
          .first
          .timeout(const Duration(seconds: 2), onTimeout: () => null);
    } catch (_) {
      user = null;
    }
    if (user != null) return user;

    // 4. Last resort: if Remember Me credentials are saved, try auto-login
    try {
      final prefs = await SharedPreferences.getInstance();
      final rememberMe = prefs.getBool('remember_me_key') ?? false;
      if (rememberMe) {
        final email = prefs.getString('email_key');
        final password = prefs.getString('password_key');
        if (email != null && email.isNotEmpty && password != null && password.isNotEmpty) {
          final cred = await FirebaseAuth.instance
              .signInWithEmailAndPassword(email: email, password: password)
              .timeout(const Duration(seconds: 5));
          user = cred.user;
        }
      }
    } catch (e) {
      debugPrint('Auto-login fallback failed: $e');
      user = null;
    }

    return user;
  }

  Future<void> _checkAuthAndNavigate() async {
    final user = await _resolveAuthUser();
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