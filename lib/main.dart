import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'Misc/constant.dart';
import 'login.dart';
import 'home.dart';
import 'Misc/splash_screen.dart';
import 'Misc/theme_notifier.dart'; // Now imports ThemeProvider
import 'Misc/auth_wrapper.dart';
import 'Leads/presentfollowup.dart';
import 'Todo/todo.dart'; // <-- Already present
import 'package:showcaseview/showcaseview.dart';
import 'Misc/user_version_helper.dart'; // <-- Add this import

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase and SharedPreferences in parallel (both required before UI)
  final results = await Future.wait([
    Firebase.initializeApp(
      options: FirebaseOptions(
        apiKey: firebaseApiKey,
        appId: firebaseAppId,
        messagingSenderId: firebaseMessagingSenderId,
        projectId: firebaseProjectId,
        authDomain: firebaseAuthDomain,
        storageBucket: firebaseStorageBucket,
        measurementId: firebaseMeasurementId,
      ),
    ),
    SharedPreferences.getInstance(),
  ]);

  final prefs = results[1] as SharedPreferences;

  // Enable Firestore offline persistence
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
  );

  // CRITICAL: Initialize AwesomeNotifications BEFORE runApp() 
  // This ensures scheduled notifications work even when app is killed
  await _initializeNotifications();

  // Run the app
  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(prefs: prefs),
      child: ShowCaseWidget(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaleFactor: 1.0),
          child: const MyApp(),
        ),
      ),
    ),
  );

  // Deferred services init (non-blocking)
  _initializeDeferredServices(prefs);
}

/// Initialize AwesomeNotifications - MUST be called before runApp for scheduled notifications
Future<void> _initializeNotifications() async {
  await AwesomeNotifications().initialize(
    null, // Use default app icon
    [
      NotificationChannel(
        channelKey: 'basic_channel',
        channelName: 'Basic Notifications',
        channelDescription: 'Notification channel for basic tests',
        defaultColor: const Color(0xFF005BAC),
        ledColor: Colors.white,
        soundSource: 'resource://raw/leadsreminder',
        importance: NotificationImportance.High,
        channelShowBadge: true,
        criticalAlerts: true,
      ),
      NotificationChannel(
        channelKey: 'reminder_channel',
        channelName: 'Reminder Notifications',
        channelDescription: 'Channel for task reminders',
        defaultColor: const Color(0xFF8CC63F),
        ledColor: Colors.green,
        soundSource: 'resource://raw/taskreminder',
        importance: NotificationImportance.High,
        channelShowBadge: true,
        criticalAlerts: true,
      ),
    ],
    debug: false, // Set to false for production
  );

  // Setup notification listeners - required for background handling
  AwesomeNotifications().setListeners(
    onActionReceivedMethod: NotificationController.onActionReceivedMethod,
    onNotificationCreatedMethod: NotificationController.onNotificationCreatedMethod,
    onNotificationDisplayedMethod: NotificationController.onNotificationDisplayedMethod,
    onDismissActionReceivedMethod: NotificationController.onDismissActionReceivedMethod,
  );

  // Get initial notification action (for when app is opened from notification)
  initialNotificationAction = await AwesomeNotifications().getInitialNotificationAction();
}

/// All non-essential initialization that can happen after UI is visible
void _initializeDeferredServices(SharedPreferences prefs) {
  Future.microtask(() async {
    // Initialize Flutter Local Notifications (for assignment notifications etc.)
    _initializeFlutterLocalNotifications();

    // Listen for auth state changes
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        updateUserVersionInfo();
      }
    });
  });
}

final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

ReceivedAction? initialNotificationAction;

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'MTC Sync',
          themeMode: themeProvider.themeMode,
          theme: ThemeData(
            brightness: Brightness.light,
            primarySwatch: Colors.blue,
            // Define other light theme properties
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            // Define other dark theme properties
          ),
          navigatorObservers: [routeObserver],
          navigatorKey: navigatorKey,
          // Ensure content stays above system navigation bar
          builder: (context, child) {
            return SafeArea(
              top: false, // keep existing top behaviour, but protect bottom
              bottom: true,
              child: child ?? const SizedBox.shrink(),
            );
          },

          home: const AuthWrapper(child: SplashScreen()),
        );
      },
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  Widget build(BuildContext context) {
    return const Placeholder();
  }
}

class UpdateGate extends StatefulWidget {
  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> {
  @override
  void initState() {
    super.initState();
    _checkForUpdate();
  }

  Future<void> _checkForUpdate() async {
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability == UpdateAvailability.updateAvailable) {
        await InAppUpdate.performImmediateUpdate();
      }
    } catch (e) {
      print('Update check failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('App Content Here')),
    );
  }
}

// Helper to mark notification as opened
Future<void> markNotificationOpened(String docId) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('lead_opened_$docId', true);
}

Future<bool> isNotificationOpened(String docId) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool('lead_opened_$docId') ?? false;
}

// Helper to clear notification opened status
Future<void> clearNotificationOpened(String docId) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove('lead_opened_$docId');
}

class NotificationController {
  @pragma("vm:entry-point")
  static Future<void> onActionReceivedMethod(ReceivedAction receivedAction) async {
    // Handle navigation for overdue tasks notification
    if (receivedAction.payload?['page'] == 'todo') {
      final navigator = navigatorKey.currentState;
      if (navigator != null) {
        navigator.push(
          MaterialPageRoute(builder: (_) => const TodoPage()),
        );
      }
      return;
    }

    // Ensure plugins are initialized in this background isolate
    WidgetsFlutterBinding.ensureInitialized();
    await Firebase.initializeApp(
        options: FirebaseOptions(
            apiKey: firebaseApiKey, appId: firebaseAppId, messagingSenderId: firebaseMessagingSenderId,
            projectId: firebaseProjectId, authDomain: firebaseAuthDomain, storageBucket: firebaseStorageBucket,
            measurementId: firebaseMeasurementId
        )
    );
    if (receivedAction.payload?['docId'] != null) {
      final docId = receivedAction.payload!['docId']!;
      // Mark as opened
      await markNotificationOpened(docId);

      Future<void> doNavigate() async {
        final navigator = navigatorKey.currentState;
        if (navigator != null) {
          final docId = receivedAction.payload!['docId']!;
          final isEdit = receivedAction.buttonKeyPressed == 'EDIT_FOLLOWUP';
          final channelKey = receivedAction.channelKey;
          final isTodo = receivedAction.payload?['type'] == 'todo';

          // Use same logic as edit followup for todo: open in view for normal, edit for edit button
          // Simple push ensures the back button works correctly.
          if (isEdit) {
            navigator.push(
              MaterialPageRoute(builder: (_) => PresentFollowUp(docId: docId, editMode: true)),
            );
          } else if ((channelKey == 'reminder_channel' || channelKey == 'basic_channel') && isTodo) {
            navigator.push(
              MaterialPageRoute(builder: (_) => TaskDetailPageFromId(docId: docId)),
            );
          } else {
            navigator.push(
              MaterialPageRoute(builder: (_) => PresentFollowUp(docId: docId)),
            );
          }
        } else {
          // If navigator is not ready, try again shortly
          await Future.delayed(const Duration(milliseconds: 300));
          await doNavigate();
        }
      }

      // Start navigation attempt
      doNavigate();
    }
  }

  @pragma("vm:entry-point")
  static Future<void> onNotificationCreatedMethod(ReceivedNotification received) async {
    debugPrint("Notification created: ${received.id}");
  }

  @pragma("vm:entry-point")
  static Future<void> onNotificationDisplayedMethod(ReceivedNotification received) async {
    debugPrint("Notification displayed: ${received.id}");
  }

  @pragma("vm:entry-point")
  static Future<void> onDismissActionReceivedMethod(ReceivedAction receivedAction) async {
    // Ensure plugins are initialized for background execution
    WidgetsFlutterBinding.ensureInitialized();
    await Firebase.initializeApp(
        options: FirebaseOptions(
            apiKey: firebaseApiKey, appId: firebaseAppId, messagingSenderId: firebaseMessagingSenderId,
            projectId: firebaseProjectId, authDomain: firebaseAuthDomain, storageBucket: firebaseStorageBucket,
            measurementId: firebaseMeasurementId
        )
    );

    debugPrint("Notification dismissed: ${receivedAction.id}");
    
    // 🔄 Reschedule in 30 mins if user swipes it away
    if (receivedAction.payload?['docId'] != null) {
      final docId = receivedAction.payload!['docId']!;
      final type = receivedAction.payload!['type'] ?? 'lead'; // Default to lead

      // Only reschedule if not opened
      if (!await isNotificationOpened(docId)) {
        String title = 'Reminder';
        String body = 'You have a pending item. Please check your app.';

        // Fetch details from Firestore to make the notification more informative
        try {
            final collection = type == 'todo' ? 'todo' : 'follow_ups';
            final doc = await FirebaseFirestore.instance.collection(collection).doc(docId).get();
            if (doc.exists) {
                title = type == 'todo' ? 'Task Reminder' : 'Follow-up Reminder';
                body = 'Reminder for: ${doc.data()?['title'] ?? doc.data()?['name'] ?? '...'}';
            }
        } catch (e) {
            debugPrint('Error fetching details for dismissed notification: $e');
            // If fetching fails (e.g., no network), we still want to reschedule a generic reminder.
            // The title and body will use the default values set above.
        }

        final channelKey = type == 'todo' ? 'reminder_channel' : 'basic_channel';
        await AwesomeNotifications().createNotification(
          content: NotificationContent(
            id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
            channelKey: channelKey,
            title: title,
            body: body,
            payload: {'docId': docId, 'type': type},
          ),
          actionButtons: [
            NotificationActionButton(
              key: 'EDIT_FOLLOWUP',
              label: 'Edit',
              autoDismissible: true,
            ),
          ],
          schedule: NotificationCalendar.fromDate(
            date: DateTime.now().add(const Duration(minutes: 1)),
          ),
        );
      }
    }
  }
}

/// Initialize Flutter Local Notifications in background (non-blocking)
void _initializeFlutterLocalNotifications() {
  Future.microtask(() async {
    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initSettings =
        InitializationSettings(android: androidSettings);
    await flutterLocalNotificationsPlugin.initialize(settings: initSettings);
  });
}
