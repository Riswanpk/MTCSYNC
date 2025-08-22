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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
              initialNotificationAction = null; // Clear after handling
              return MaterialPageRoute(
                builder: (context) => PresentFollowUp(docId: docId, editMode: isEdit),
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
    // If user taps the notification (not Edit button), go to PresentFollowUp
    if (receivedAction.buttonKeyPressed == null &&
        receivedAction.payload?['docId'] != null) {
      initialNotificationAction = receivedAction;
      // Navigation will be handled by SplashScreen/MyApp
    }
    // If user taps Edit button, also go to PresentFollowUp in edit mode
    else if (receivedAction.buttonKeyPressed == 'EDIT_FOLLOWUP' &&
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
