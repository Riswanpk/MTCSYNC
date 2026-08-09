import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:mtcsync/Navigation/user_cache_service.dart';
import 'package:mtcsync/Misc/sound_service.dart';
import 'package:provider/provider.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'Misc/constant.dart';
import 'Misc/notification_permission_service.dart';
import 'Navigation/splash_screen.dart';
import 'Misc/theme_notifier.dart'; // Now imports ThemeProvider
import 'Login/auth_wrapper.dart';
import 'Leads/presentfollowup.dart';
import 'Todo/todo.dart'; // <-- Already present
import 'SME/sme_assigned_leads_page.dart';
import 'package:showcaseview/showcaseview.dart';
import 'Version/user_version_helper.dart'; // <-- Add this import
import 'DME/screens/dme_customer_tile_viewer.dart';
import 'DME/models/dme_reminder.dart';
import 'DME/services/dme_supabase_service.dart';
import 'Task/task_sales.dart';
import 'Task/task_admin.dart';
import 'Supersale/supersale_user_mainpage.dart';

/// Top-level background message handler for FCM Push Notifications
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
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
  } on FirebaseException catch (e) {
    if (e.code != 'duplicate-app') rethrow;
  }
  debugPrint("FCM Background Message received: ${message.messageId}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase — guard against duplicate-app from google-services auto-init on Android
  try {
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
  } on FirebaseException catch (e) {
    if (e.code != 'duplicate-app') rethrow;
  }

  // Register FCM background message handler BEFORE runApp()
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  final prefs = await SharedPreferences.getInstance();

  // Enable Firebase Crashlytics
  try {
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);
    
    // Pass all uncaught errors from the Flutter framework to Crashlytics
    FlutterError.onError = (errorDetails) {
      FirebaseCrashlytics.instance.recordFlutterError(errorDetails);
    };
    
    // Pass all uncaught asynchronous errors that aren't handled by the Flutter framework
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  } catch (e) {
    debugPrint('Crashlytics init error: $e');
  }

  // Enable Firestore offline persistence
  try {
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
    );
  } catch (e) {
    debugPrint('Firestore settings error: $e');
  }

  // CRITICAL: Initialize AwesomeNotifications BEFORE runApp() 
  try {
    await _initializeNotifications();
  } catch (e) {
    debugPrint('Notification init error: $e');
  }

  // Request AwesomeNotifications permissions (exact alarms + POST_NOTIFICATIONS)
  try {
    await NotificationPermissionService.instance.requestNotificationPermission();
  } catch (e) {
    debugPrint('Notification permission error: $e');
  }

  // Request FCM permissions & listen to foreground messages
  try {
    await _setupFirebaseMessaging();
  } catch (e) {
    debugPrint('FirebaseMessaging setup error: $e');
  }

  // Initialize SoundService for audio playback
  try {
    await SoundService.instance.initialize();
  } catch (e) {
    debugPrint('SoundService init error: $e');
  }

  // Run the app
  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(prefs: prefs),
      child: ShowCaseWidget(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
          child: const MyApp(),
        ),
      ),
    ),
  );

  // Deferred services init & reliability prompts (non-blocking)
  _initializeDeferredServices(prefs);
}

/// Setup FCM permissions and foreground listeners
Future<void> _setupFirebaseMessaging() async {
  final messaging = FirebaseMessaging.instance;
  await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
    provisional: false,
  );

  // Foreground notification handler: display banner via awesome_notifications
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    final notification = message.notification;
    if (notification != null) {
      AwesomeNotifications().createNotification(
        content: NotificationContent(
          id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
          channelKey: 'basic_channel',
          title: notification.title ?? 'Notification',
          body: notification.body ?? '',
          payload: message.data.map((key, value) => MapEntry(key, value.toString())),
        ),
      );
    }
  });
}

/// Initialize AwesomeNotifications - MUST be called before runApp for scheduled notifications
Future<void> _initializeNotifications() async {
  await AwesomeNotifications().initialize(
    null, // Use default app icon
    [
      NotificationChannel(
        channelKey: 'basic_channel',
        channelName: 'Leads Notifications',
        channelDescription: 'Notification channel for leads and follow-ups',
        defaultColor: const Color(0xFF005BAC),
        ledColor: Colors.white,
        soundSource: 'resource://raw/leadsreminder',
        importance: NotificationImportance.High,
        channelShowBadge: true,
        criticalAlerts: true,
        playSound: true,
      ),
      NotificationChannel(
        channelKey: 'reminder_channel',
        channelName: 'Todo & Task Reminders',
        channelDescription: 'Channel for todo and task reminders',
        defaultColor: const Color(0xFF8CC63F),
        ledColor: Colors.green,
        soundSource: 'resource://raw/todo_reminder',
        importance: NotificationImportance.High,
        channelShowBadge: true,
        criticalAlerts: true,
        playSound: true,
      ),
      NotificationChannel(
        channelKey: 'task_assignment_channel',
        channelName: 'Task Assignment Notifications',
        channelDescription: 'Channel for when you are assigned a new task',
        defaultColor: const Color(0xFF005BAC),
        ledColor: Colors.blue,
        soundSource: 'resource://raw/you_have_been_assigned_a_task',
        importance: NotificationImportance.High,
        channelShowBadge: true,
        criticalAlerts: true,
        playSound: true,
      ),
      NotificationChannel(
        channelKey: 'delivery_reminder_channel',
        channelName: 'Delivery Reminder Notifications',
        channelDescription: 'Channel for supersale delivery reminders',
        defaultColor: const Color(0xFF005BAC),
        ledColor: Colors.blue,
        soundSource: 'resource://raw/delivery_reminder',
        importance: NotificationImportance.High,
        channelShowBadge: true,
        criticalAlerts: true,
        playSound: true,
      ),
      NotificationChannel(
        channelKey: 'supersale_open_channel',
        channelName: 'Supersale Booking Open',
        channelDescription: 'Channel for supersale booking open notifications',
        defaultColor: const Color(0xFF005BAC),
        ledColor: Colors.blue,
        soundSource: 'resource://raw/supersale_bookings_open',
        importance: NotificationImportance.High,
        channelShowBadge: true,
        criticalAlerts: true,
        playSound: true,
      ),
      NotificationChannel(
        channelKey: 'supersale_closed_channel',
        channelName: 'Supersale Booking Closed',
        channelDescription: 'Channel for supersale booking closed notifications',
        defaultColor: const Color(0xFF005BAC),
        ledColor: Colors.red,
        soundSource: 'resource://raw/supersale_bookins_closed',
        importance: NotificationImportance.High,
        channelShowBadge: true,
        criticalAlerts: true,
        playSound: true,
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

bool isAppReady = false;
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
      debugPrint('Update check failed: $e');
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
    initialNotificationAction = receivedAction;

    if (isAppReady) {
      handleNotificationAction(receivedAction);
    }
  }

  static Future<void> handleNotificationAction(ReceivedAction receivedAction) async {
    final payload = receivedAction.payload;

    // Handle overdue tasks notification
    if (payload?['page'] == 'todo') {
      _doPush((_) => const TodoPage());
      return;
    }

    // Handle core tasks notifications navigation
    if (payload?['type'] == 'core_task') {
      _doPush((_) => const UserTaskPage());
      return;
    }
    if (payload?['type'] == 'core_task_complete') {
      _doPush((_) => const CoreTeamTaskPage());
      return;
    }

    // Handle DME reminder notification
    if (payload?['type'] == 'dme_reminder') {
      _handleDmeReminder(receivedAction);
      return;
    }

    // Handle supersale notifications navigation
    final channelKey = receivedAction.channelKey;
    final notifType = payload?['type'];
    final isSupersaleOpen = channelKey == 'supersale_open_channel' ||
        (notifType == 'supersale' && payload?['subType'] == 'booking_open');
    final isSupersaleClosed = channelKey == 'supersale_closed_channel' ||
        (notifType == 'supersale' && payload?['subType'] == 'booking_closed');

    if (isSupersaleClosed) {
      // No redirection for bookings closed
      return;
    }

    if (isSupersaleOpen || notifType == 'supersale') {
      _doPush((_) => const SupersaleUserMainPage());
      return;
    }

    if (payload?['docId'] != null) {
      final docId = payload!['docId']!;
      await markNotificationOpened(docId);

      final isEdit = receivedAction.buttonKeyPressed == 'EDIT_FOLLOWUP';
      final isTodo = notifType == 'todo';
      final isSmeLead = notifType == 'sme_lead' || notifType == 'sme_lead_assignment';

      if (isSmeLead) {
        _doPush((_) => const SmeAssignedLeadsPage());
      } else if (isEdit) {
        _doPush((_) => PresentFollowUp(docId: docId, editMode: true));
      } else if (isTodo || ((channelKey == 'reminder_channel' || channelKey == 'basic_channel') && isTodo)) {
        _doPush((_) => TaskDetailPageFromId(docId: docId));
      } else {
        _doPush((_) => PresentFollowUp(docId: docId));
      }
    }
  }

  static void _doPush(WidgetBuilder builder) {
    final navigator = navigatorKey.currentState;
    if (navigator != null) {
      navigator.push(MaterialPageRoute(builder: builder));
    } else {
      Future.microtask(() => _doPush(builder));
    }
  }

  static Future<void> _handleDmeReminder(ReceivedAction receivedAction) async {
    final reminderId = receivedAction.payload?['reminderId'];
    final customerId = int.tryParse(receivedAction.payload?['customerId'] ?? '');
    
    if (customerId != null && reminderId != null && reminderId.isNotEmpty) {
      try {
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
        
        final svc = DmeSupabaseService.instance;
        final reminder = await svc.getReminderDetail(int.parse(reminderId as String));
        
        if (reminder != null) {
          final userCache = UserCacheService.instance;
          final firebaseUid = userCache.uid;
          
          if (firebaseUid != null) {
            final user = await svc.getCurrentUser(firebaseUid);
            if (user != null) {
              _doPush((_) => DmeCustomerTileViewer(
                reminder: reminder,
                dmeUser: user,
              ));
            }
          }
        }
      } catch (e) {
        debugPrint('Error handling DME reminder notification: $e');
      }
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
    
    // 🔄 Reschedule notification logic for dismissed notifications
    if (receivedAction.payload?['docId'] != null) {
      final docId = receivedAction.payload!['docId']!;
      final type = receivedAction.payload!['type'] ?? 'lead'; // Default to lead

      // Only reschedule if not opened
      if (!await isNotificationOpened(docId)) {
        String title = 'Reminder';
        String body = 'You have a pending item. Please check your app.';
        Duration rescheduleDelay = const Duration(minutes: 30); // Default to 30 mins

        // Fetch details from Firestore
        try {
            final collection = type == 'todo' ? 'todo' : 'follow_ups';
            final doc = await FirebaseFirestore.instance.collection(collection).doc(docId).get();
            if (doc.exists) {
                title = type == 'todo' ? 'Task Reminder' : 'Follow-up Reminder';
                body = 'Reminder for: ${doc.data()?['title'] ?? doc.data()?['name'] ?? '...'}';
                
                // For leads: implement 7-day cycle rescheduling
                // Logic: 30 mins same-day rescheduling, then 7-day cycles
                if (type == 'lead') {
                  final docData = doc.data();
                  final status = docData?['status'] as String? ?? 'In Progress';
                  final originalReminderDate = docData?['original_reminder_date']; // When reminder was first set
                  final reminderDateChanged = docData?['reminder_date_changed'] ?? false; // Manual reschedule flag
                  
                  // If status is still "In Progress" and reminder hasn't been manually changed
                  if (status == 'In Progress' && originalReminderDate != null && reminderDateChanged != true) {
                    final originalDateTime = originalReminderDate is Timestamp 
                        ? originalReminderDate.toDate() 
                        : originalReminderDate is String 
                            ? DateTime.tryParse(originalReminderDate) 
                            : null;
                    
                    if (originalDateTime != null) {
                      final now = DateTime.now();
                      // Calculate the 7-day cycle point (original reminder + 7 days)
                      final nextCycleDateTime = originalDateTime.add(const Duration(days: 7));
                      
                      // If we've reached or passed the 7-day cycle threshold
                      if (now.isAfter(nextCycleDateTime) || now.isAtSameMomentAs(nextCycleDateTime)) {
                        // Schedule for the next 7-day cycle
                        rescheduleDelay = nextCycleDateTime.difference(now);
                        debugPrint('Lead at/past 7-day threshold. Rescheduling to ${nextCycleDateTime}. Delay: $rescheduleDelay');
                      } else {
                        // Still within the cycle: use 30-min same-day rescheduling
                        rescheduleDelay = const Duration(minutes: 30);
                        debugPrint('Lead within current cycle. Rescheduling for 30 minutes.');
                      }
                    }
                  }
                }
            }
        } catch (e) {
            debugPrint('Error fetching details for dismissed notification: $e');
            // If fetching fails (e.g., no network), reschedule with default 30 mins
        }

        final channelKey = type == 'todo' ? 'reminder_channel' : 'basic_channel';
        await NotificationPermissionService.instance.safeCreateNotification(
          content: NotificationContent(
            id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
            channelKey: channelKey,
            title: title,
            body: body,
            payload: {'docId': docId, 'type': type},
          ),
          schedule: NotificationCalendar.fromDate(
            date: DateTime.now().add(rescheduleDelay),
          ),
        );
      }
    }
  }
}
