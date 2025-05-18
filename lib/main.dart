import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';

import 'constant.dart';
import 'login.dart';
import 'home.dart'; // Your HomePage screen

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase with your options
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

  // Initialize timezone database
  tz.initializeTimeZones();

  // Initialize notifications plugin
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  final InitializationSettings initializationSettings =
      InitializationSettings(android: initializationSettingsAndroid);

  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse:
        (NotificationResponse notificationResponse) async {
      final docId = notificationResponse.payload;
      if (docId != null) {
        // Mark the follow-up as acknowledged in Firestore
        await FirebaseFirestore.instance
            .collection('follow_ups')
            .doc(docId)
            .update({'acknowledged': true});
      }
    },
  );

  // Only initialize AndroidAlarmManager if running on Android and NOT on Web
  if (!kIsWeb && Platform.isAndroid) {
    await AndroidAlarmManager.initialize();

    // Schedule periodic background check every 30 minutes
    await AndroidAlarmManager.periodic(
      const Duration(minutes: 30),
      0,
      checkReminders,
      wakeup: true,
      exact: true,
      rescheduleOnReboot: true,
    );
  } else {
    print('AndroidAlarmManager not initialized: Not running on Android device.');
  }

  // Run the app
  runApp(const MyApp());
}

// Main App widget with auth state routing
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: FirebaseAuth.instance.currentUser == null
          ? const LoginPage()
          : const HomePage(),
    );
  }
}

// Background task: check reminders periodically
Future<void> checkReminders() async {
  // Must initialize Firebase in the background isolate
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

  final now = DateTime.now();
  final todayStr =
      "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

  final querySnapshot = await FirebaseFirestore.instance
      .collection('follow_ups')
      .where('reminder', isEqualTo: todayStr)
      .where('acknowledged', isEqualTo: false)
      .get();

  for (var doc in querySnapshot.docs) {
    final data = doc.data();

    // Example reminder time is 9 AM today
    final reminderTime = DateTime(now.year, now.month, now.day, 9);

    if (now.isAfter(reminderTime)) {
      await showReminderNotification(doc.id, data['name'] ?? 'Customer');
    }
  }
}

// Show local notification for a reminder
Future<void> showReminderNotification(String docId, String name) async {
  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'reminder_channel',
    'Reminders',
    channelDescription: 'Reminder notifications',
    importance: Importance.max,
    priority: Priority.high,
    ongoing: true,
  );

  const NotificationDetails notificationDetails =
      NotificationDetails(android: androidDetails);

  await flutterLocalNotificationsPlugin.show(
    docId.hashCode,
    'Follow-up Reminder',
    'Follow up with $name today.',
    notificationDetails,
    payload: docId,
  );
}
