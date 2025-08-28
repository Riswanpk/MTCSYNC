import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'constant.dart';
import 'login.dart';
import 'home.dart';
import 'splash_screen.dart';
import 'theme_notifier.dart';
import 'presentfollowup.dart';
import 'todo.dart'; // <-- Add this import if not present

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Request camera and location permissions
  await Permission.camera.request();
  await Permission.location.request();

  // Initialize Firebase
  await Firebase.initializeApp(
    options: FirebaseOptions(
      apiKey: firebaseApiKey,
      appId: firebaseAppId,
      messagingSenderId: firebaseMessagingSenderId,
      projectId: firebaseProjectId,
      authDomain: firebaseAuthDomain,
      storageBucket: firebaseStorageBucket,
      measurementId: firebaseMeasurementId,
    ),
  );

  // Initialize Awesome Notifications
  await AwesomeNotifications().initialize(
    null,
    [
      NotificationChannel(
        channelKey: 'basic_channel',
        channelName: 'Basic Notifications',
        channelDescription: 'Notification channel for basic tests',
        defaultColor: const Color(0xFF005BAC),
        ledColor: Colors.white,
        importance: NotificationImportance.High,
        channelShowBadge: true,
      ),
      NotificationChannel(
        channelKey: 'reminder_channel', // <-- ADD THIS
        channelName: 'Reminder Notifications',
        channelDescription: 'Channel for task reminders',
        defaultColor: const Color(0xFF8CC63F),
        ledColor: Colors.green,
        importance: NotificationImportance.High,
        channelShowBadge: true,
      ),
    ],
    debug: true,
  );

  // Initialize Flutter Local Notifications
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initSettings =
      InitializationSettings(android: androidSettings);
  await flutterLocalNotificationsPlugin.initialize(initSettings);

  // Request notification permissions
  bool isAllowed = await AwesomeNotifications().isNotificationAllowed();
  if (!isAllowed) {
    await AwesomeNotifications().requestPermissionToSendNotifications();
  }

  await Permission.notification.request();
  await Permission.manageExternalStorage.request();
  await Permission.scheduleExactAlarm.request();
  await Permission.reminders.request();
  if (await Permission.storage.isDenied) {
    await Permission.storage.request();
  }

  // ✅ Setup notification listeners
  AwesomeNotifications().setListeners(
    onActionReceivedMethod: NotificationController.onActionReceivedMethod,
    onNotificationCreatedMethod: NotificationController.onNotificationCreatedMethod,
    onNotificationDisplayedMethod: NotificationController.onNotificationDisplayedMethod,
    onDismissActionReceivedMethod: NotificationController.onDismissActionReceivedMethod,
  );

  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeNotifier(),
      child: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaleFactor: 1.0),
          child: const MyApp(),
        ),
      ),
    ),
  );
}

final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

ReceivedAction? initialNotificationAction;

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeNotifier>(
      builder: (context, themeNotifier, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'MTC Sync',
          theme: themeNotifier.currentTheme,
          navigatorObservers: [routeObserver],
          navigatorKey: navigatorKey,

          /// ✅ Handle deep links and splash properly
          onGenerateRoute: (settings) {
            // If app launched from a notification
            if (initialNotificationAction != null &&
                initialNotificationAction!.payload?['docId'] != null) {
              final docId = initialNotificationAction!.payload!['docId']!;
              final isEdit = initialNotificationAction!.buttonKeyPressed == 'EDIT_FOLLOWUP';
              final channelKey = initialNotificationAction!.channelKey;
              initialNotificationAction = null; // Clear after handling

              // If it's a follow-up edit
              if (isEdit) {
                return MaterialPageRoute(
                  builder: (context) => PresentFollowUp(docId: docId, editMode: true),
                  settings: settings,
                );
              }
              // If it's a todo reminder
              if (channelKey == 'reminder_channel') {
                return MaterialPageRoute(
                  builder: (context) => TaskDetailPageFromId(docId: docId),
                  settings: settings,
                );
              }
              // Default: fallback to PresentFollowUp view
              return MaterialPageRoute(
                builder: (context) => PresentFollowUp(docId: docId),
                settings: settings,
              );
            }

            // Otherwise → go through SplashScreen
            return MaterialPageRoute(
              builder: (context) => const SplashScreen(),
              settings: settings,
            );
          },
        );
      },
    );
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

class NotificationController {
  @pragma("vm:entry-point")
  static Future<void> onActionReceivedMethod(ReceivedAction receivedAction) async {
    // Handle todo reminder notification tap
    if (receivedAction.channelKey == 'reminder_channel' &&
        receivedAction.payload?['docId'] != null) {
      final docId = receivedAction.payload!['docId']!;
      // Use navigatorKey to push the detail page
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (context) => TaskDetailPageFromId(docId: docId),
        ),
      );
      return;
    }

    // If it's a reminder notification for a todo
    if (receivedAction.channelKey == 'reminder_channel' &&
        receivedAction.payload?['docId'] != null) {
      initialNotificationAction = receivedAction;
      return;
    }

    // Existing logic for followup/edit, etc.
    if (receivedAction.buttonKeyPressed == null &&
        receivedAction.payload?['docId'] != null) {
      initialNotificationAction = receivedAction;
      // Navigation will be handled by SplashScreen/MyApp
    } else if (receivedAction.buttonKeyPressed == 'EDIT_FOLLOWUP' &&
        receivedAction.payload?['docId'] != null) {
      initialNotificationAction = receivedAction;
      // Navigation will be handled by SplashScreen/MyApp
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
    debugPrint("Notification dismissed: ${receivedAction.id}");

    // 🔄 Reschedule in 30 mins if user swipes it away
    if (receivedAction.payload?['docId'] != null) {
      final docId = receivedAction.payload!['docId']!;
      await AwesomeNotifications().createNotification(
        content: NotificationContent(
          id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
          channelKey: 'basic_channel',
          title: 'Reminder',
          body: 'Follow-up reminder for $docId',
          payload: {'docId': docId},
        ),
        actionButtons: [
          NotificationActionButton(
            key: 'EDIT_FOLLOWUP',
            label: 'Edit',
            autoDismissible: true,
          ),
        ],
        schedule: NotificationCalendar.fromDate(
          date: DateTime.now().add(const Duration(minutes: 30)),
        ),
      );
    }
  }
}
