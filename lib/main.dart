import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:permission_handler/permission_handler.dart';

import 'constant.dart';
import 'login.dart';
import 'home.dart';

// Global FlutterLocalNotificationsPlugin instance
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

// Background message handler for Firebase Messaging
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  _showNotification(message);
}

// Show notification helper method
void _showNotification(RemoteMessage message) async {
  const AndroidNotificationDetails androidPlatformChannelSpecifics =
      AndroidNotificationDetails(
    'reminder_channel',
    'Reminder Notifications',
    channelDescription: 'Channel for follow-up reminders',
    importance: Importance.max,
    priority: Priority.high,
    playSound: true,
  );

  const NotificationDetails platformChannelSpecifics =
      NotificationDetails(android: androidPlatformChannelSpecifics);

  await flutterLocalNotificationsPlugin.show(
    0,
    message.notification?.title ?? 'Reminder',
    message.notification?.body ?? 'It\'s time for your follow-up!',
    platformChannelSpecifics,
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  // Initialize timezone data for scheduling alarms
  tz.initializeTimeZones();

  // Firebase messaging background handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Initialize Flutter Local Notifications plugin
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initializationSettings =
      InitializationSettings(android: initializationSettingsAndroid);
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  // Request notification permission on Android 13+ and iOS
  if (await Permission.notification.isDenied ||
      await Permission.notification.isRestricted) {
    await Permission.notification.request();
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Show local notification when a foreground message is received
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      _showNotification(message);
    });

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: FirebaseAuth.instance.currentUser == null
          ? const LoginPage()
          : const HomePage(),
    );
  }
}
