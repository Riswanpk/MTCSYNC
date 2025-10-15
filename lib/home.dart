import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'Todo & Leads/todo.dart';
import 'Todo & Leads/leads.dart';
import 'login.dart';
import 'Misc/settings.dart'; // Import the settings page
import 'Feedback/feedback.dart'; // Add this import
import 'Feedback/feedback_admin.dart'; // Add this import
import 'Dashboard/dashboard.dart'; // Import the dashboard page
import 'Misc/manageusers.dart'; // Add this import
import 'Todo & Leads/customer_list.dart'; // Import the customer list page
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'Misc/loading_page.dart'; // Make sure you have a loading_page.dart file with LoadingPage class
import 'main.dart'; // <-- Import where your routeObserver is defined
import 'Todo & Leads/todoform.dart';
import 'Performance/dailyform.dart';
import 'dart:math';
import 'Performance/performance_score_page.dart'; // Make sure this import exists and the file exports PerformanceScorePage
import 'Performance/admin_performance_page.dart'; // <-- Add this import if AdminPerformancePage exists in this file
import 'package:in_app_update/in_app_update.dart'; // Import the in_app_update package
import 'Performance/entry_page.dart'; // Import the entry page
import 'Marketing/marketing.dart'; // Import marketing page
import 'Marketing/viewer_marketing.dart'; // Import viewer marketing page
import 'Performance/excel_view_performance.dart'; // <-- Add this import
import 'Performance/insights_performance.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'dart:convert';
import 'package:permission_handler/permission_handler.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin, RouteAware {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  // Add swing animation variables
  late AnimationController _swingController;
  late Animation<double> _swingAnimation;

  File? _profileImage;
  String? _profileImagePath;

  bool _showTodoWarning = false;
  int _logoTapCount = 0; // Add this line

  // Add these fields to _HomePageState:
  List<Contact>? _cachedContacts;
  bool _contactsLoaded = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000), // Slower bubbles (was 500)
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    // Update swing controller and animation for left-right-center swing
    _swingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800), // Longer for visible damping
    );
    // Damped sine curve: amplitude decreases over time
    _swingAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _swingController,
        curve: Curves.linear,
      ),
    );

    _checkForUpdate();
    _loadProfileImage();
    _checkTodoWarning();
    _checkPendingTodosReminder();
    // Only send report if today is the 1st of the month
    final now = DateTime.now();
    _checkAndSendMonthlyReport();
    

    // Show performance deduction notification for sales user
    FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user != null) {
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        final role = userDoc.data()?['role'];
        if (role == 'sales') {
          _checkAndShowPerformanceDeductionNotification();
        }
      }
    });

    _fetchAndCacheContacts();
  }

  Future<void> _loadProfileImage() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString('profile_image_path');
    if (path != null && File(path).existsSync()) {
      setState(() {
        _profileImagePath = path;
        _profileImage = File(path);
      });
    } else if (path != null) {
      // If file doesn't exist, remove the path from prefs
      await prefs.remove('profile_image_path');
      setState(() {
        _profileImagePath = null;
        _profileImage = null;
      });
    }
  }

  Future<void> _pickProfileImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _profileImage = File(pickedFile.path);
        _profileImagePath = pickedFile.path;
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('profile_image_path', pickedFile.path);
    }
  }

  Future<void> _checkTodoWarning() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final role = userDoc.data()?['role'];
    final email = userDoc.data()?['email'];
    if (role != 'sales') {
      setState(() {
        _showTodoWarning = false;
      });
      return;
    }

    // The window for "today's" ToDo is from 12:00 PM today to 11:59 AM tomorrow.
    DateTime windowStart;
    DateTime windowEnd;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Today 12:00 PM
    windowStart = today.add(const Duration(hours: 12));
    // Tomorrow 11:59:59 AM
    windowEnd = today.add(const Duration(days: 1, hours: 12));

    final todosSnapshot = await FirebaseFirestore.instance
        .collection('todo')
        .where('email', isEqualTo: email)
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(windowStart))
        .where('timestamp', isLessThan: Timestamp.fromDate(windowEnd))
        .get();

    setState(() {
      _showTodoWarning = todosSnapshot.docs.isEmpty;
    });
  }

  Future<void> _checkPendingTodosReminder() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Only for sales users
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final role = userDoc.data()?['role'];
    if (role != 'sales') return;

    final now = DateTime.now();

    // Query for pending todos
    final pendingTodosSnapshot = await FirebaseFirestore.instance
        .collection('todo')
        .where('email', isEqualTo: user.email)
        .where('status', isEqualTo: 'pending')
        .get();

    bool hasOverdueTask = false;
    for (var doc in pendingTodosSnapshot.docs) {
      final timestamp = doc.data()['timestamp'] as Timestamp?;
      if (timestamp != null) {
        if (now.difference(timestamp.toDate()).inHours >= 24) {
          hasOverdueTask = true;
          break; // Found one, no need to check more
        }
      }
    }

    if (hasOverdueTask) {
      await AwesomeNotifications().createNotification(
        content: NotificationContent(
          id: 2003, // A unique ID for this type of notification
          channelKey: 'reminder_channel',
          title: 'Overdue Tasks!',
          body: 'You have pending tasks that are more than a day old. Please complete them.',
          payload: {'page': 'todo'}, // Navigate to TodoPage
        ),
      );
    }
  }

  Future<void> _scheduleScoreUpdateNotificationIfNeeded() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Get user role
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final role = userDoc.data()?['role'];
    if (role != 'sales') return;

    // Get today's date range
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    // Query dailyform for today
    final formsSnapshot = await FirebaseFirestore.instance
        .collection('dailyform')
        .where('userId', isEqualTo: user.uid)
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where('timestamp', isLessThan: Timestamp.fromDate(endOfDay))
        .get();

    if (formsSnapshot.docs.isNotEmpty) {
      // Schedule notification for next day 9 AM
      final nextDay = now.add(const Duration(days: 1));
      final scheduledTime = DateTime(nextDay.year, nextDay.month, nextDay.day, 9, 0, 0);

      await AwesomeNotifications().createNotification(
        content: NotificationContent(
          id: 2001, // Use a unique id or random if you want
          channelKey: 'reminder_channel',
          title: 'Your score has been updated!',
          body: 'Check performance page to review',
          notificationLayout: NotificationLayout.Default,
        ),
        schedule: NotificationCalendar(
          year: scheduledTime.year,
          month: scheduledTime.month,
          day: scheduledTime.day,
          hour: scheduledTime.hour,
          minute: scheduledTime.minute,
          second: 0,
          millisecond: 0,
          repeats: false,
          preciseAlarm: true,
        ),
      );
    }
  }

  Future<void> _checkForUpdate() async {
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability == UpdateAvailability.updateAvailable) {
        // Flexible update (shows a download bar, user can continue using app)
        await InAppUpdate.performImmediateUpdate();
        // For flexible update, use: await InAppUpdate.startFlexibleUpdate();
        // Then: await InAppUpdate.completeFlexibleUpdate();
      }
    } catch (e) {
      // Optionally show a snackbar or log error
      print('Update check failed: $e');
    }
  }

  Future<void> _checkAndSendMonthlyReport() async {
    try {
      final now = DateTime.now();

      // Calculate previous month safely
      int prevMonth = now.month - 1;
      int prevYear = now.year;
      if (prevMonth == 0) {
        prevMonth = 12;
        prevYear -= 1;
      }
      final prevMonthKey = '$prevYear-$prevMonth';

      final trackingDocRef = FirebaseFirestore.instance
          .collection('reportTracking')
          .doc('global');

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final trackingDoc = await transaction.get(trackingDocRef);
        final lastSentMonth = trackingDoc.data()?['lastSentMonth'];

        if (lastSentMonth != prevMonthKey) {
          // Only send if not already sent for this month
          await _sendMonthlyExcelReport(year: prevYear, month: prevMonth);

          transaction.set(trackingDocRef, {
            'lastSentMonth': prevMonthKey,
            'lastUpdated': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      });
    } catch (e) {
      print('Error checking monthly report: $e');
    }
  }

  Future<void> _sendMonthlyExcelReport({int? year, int? month}) async {
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final role = userDoc.data()?['role']?.toString().toLowerCase() ?? 'unknown';
      final settingsPage = SettingsPage(userRole: role);
      await settingsPage.exportAndSendExcel(context, year: year, month: month);
      print('Monthly Excel Report Sent!');
    } catch (e) {
      print('Error sending monthly report: $e');
    }
  }

  Future<void> _checkAndShowPerformanceDeductionNotification() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Fetch this week's forms
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final monthEnd = DateTime(now.year, now.month + 1, 1);

    final formsSnapshot = await FirebaseFirestore.instance
        .collection('dailyform')
        .where('userId', isEqualTo: user.uid)
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
        .where('timestamp', isLessThan: Timestamp.fromDate(monthEnd))
        .get();

    final forms = formsSnapshot.docs.map((doc) => doc.data() as Map<String, dynamic>).toList();

    // Get only current week forms
    final today = DateTime(now.year, now.month, now.day);
    final currentWeekNum = isoWeekNumber(today);
    final weekForms = forms.where((form) {
      final ts = form['timestamp'];
      final date = ts is Timestamp ? ts.toDate() : DateTime.parse(ts.toString());
      return isoWeekNumber(date) == currentWeekNum && date.year == today.year;
    }).toList();

    bool deduction = false;
    for (var form in weekForms) {
      final att = form['attendance'];
      if (att == 'late' || att == 'notApproved') deduction = true;
      if (att != 'approved' && att != 'notApproved') {
        if (form['dressCode']?['cleanUniform'] == false ||
            form['dressCode']?['keepInside'] == false ||
            form['dressCode']?['neatHair'] == false ||
            form['attitude']?['greetSmile'] == false ||
            form['attitude']?['askNeeds'] == false ||
            form['attitude']?['helpFindProduct'] == false ||
            form['attitude']?['confirmPurchase'] == false ||
            form['attitude']?['offerHelp'] == false ||
            form['meeting']?['attended'] == false) {
          deduction = true;
        }
      }
    }

    // Only show notification if deduction and not already shown today
    final prefs = await SharedPreferences.getInstance();
    final lastNotified = prefs.getString('last_perf_deduction_notify');
    final todayStr = "${now.year}-${now.month}-${now.day}";
    if (deduction && lastNotified != todayStr) {
      await AwesomeNotifications().createNotification(
        content: NotificationContent(
          id: 2002,
          channelKey: 'reminder_channel',
          title: 'Performance Deduction',
          body: 'Your performance score was reduced. Check the Performance page for details.',
          notificationLayout: NotificationLayout.Default,
        ),
      );
      await prefs.setString('last_perf_deduction_notify', todayStr);
    }
  }

  int isoWeekNumber(DateTime date) {
    final thursday = date.subtract(Duration(days: (date.weekday + 6) % 7 - 3));
    final firstThursday = DateTime(date.year, 1, 4);
    final diff = thursday.difference(firstThursday).inDays ~/ 7;
    return 1 + diff;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Subscribe to route changes
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }
    // Optionally, check once here too
    _checkTodoWarning();
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _controller.dispose();
    _swingController.dispose(); // Dispose swing controller
    super.dispose();
  }

  @override
  void didPopNext() {
    // Called when coming back to this page
    _checkTodoWarning();
  }

  @override
  void didPush() {
    _fetchAndCacheContacts();
    // Called when this page is pushed
    _checkTodoWarning();
  }

  Future<void> _fetchAndCacheContacts() async {
    var status = await Permission.contacts.status;
    if (!status.isGranted) {
      await Permission.contacts.request();
      status = await Permission.contacts.status;
    }
    if (!status.isGranted) return;

    final prefs = await SharedPreferences.getInstance();

    // Load cached contacts first
    final cached = prefs.getString('contacts_cache');
    if (cached != null) {
      final List<dynamic> decoded = jsonDecode(cached);
      _cachedContacts = decoded.map((c) => Contact.fromJson(c)).toList();
      setState(() {
        _contactsLoaded = true;
      });
    }

    // Fetch latest contacts in background
    final contacts = await FlutterContacts.getContacts(withProperties: true, withThumbnail: false);
    // Save to cache
    final encoded = jsonEncode(contacts.map((c) => c.toJson()).toList());
    await prefs.setString('contacts_cache', encoded);

    setState(() {
      _cachedContacts = contacts;
      _contactsLoaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    const Color primaryBlue = Color(0xFF005BAC);
    const Color primaryGreen = Color(0xFF8CC63F);

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(FirebaseAuth.instance.currentUser?.uid).get(),
      builder: (context, snapshot) {
        String? role;
        String? username;
        String? branch;
        if (snapshot.hasData) {
          role = snapshot.data?.get('role');
          username = snapshot.data?.get('username') ?? snapshot.data?.get('email') ?? 'User';
          branch = snapshot.data?.get('branch');
        }
        return WillPopScope(
          onWillPop: () async => false, // Disable back button
          child: Scaffold(
            // Remove the appBar entirely
            endDrawer: Drawer(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  DrawerHeader(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF005BAC), Color(0xFF3383C7)], // Profile blue gradient
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Profile',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                          ),
                        ),
                        const SizedBox(height: 12),
                        GestureDetector(
                          onTap: _pickProfileImage,
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 22,
                                backgroundColor: Colors.white,
                                backgroundImage: (_profileImage != null)
                                    ? FileImage(_profileImage!)
                                    : null,
                                child: (_profileImage == null)
                                    ? const Icon(Icons.account_circle, size: 38, color: Color(0xFF005BAC))
                                    : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      username ?? '',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      branch ?? '',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w400,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    leading: const Icon(Icons.settings, color: Color(0xFF005BAC)),
                    title: const Text('Settings'),
                    onTap: () {
                      Navigator.pop(context); // Close the drawer
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => SettingsPage(userRole: role ?? ''),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    leading: const Icon(Icons.feedback, color: Color(0xFF8CC63F)), // Green for Feedback
                    title: const Text('Feedback'),
                    onTap: () async {
                      Navigator.pop(context); // Close the drawer

                      // Get current user role
                      final user = FirebaseAuth.instance.currentUser;
                      String? role;
                      if (user != null) {
                        final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
                        role = userDoc.data()?['role'];
                      }

                      if (role == 'admin') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const FeedbackAdminPage()),
                        );
                      } else {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const FeedbackPage()),
                        );
                      }
                    },
                  ),
                  // Add Manage Users option for admin
                  if (role == 'admin')
                    ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      leading: const Icon(Icons.manage_accounts, color: Colors.deepPurple), // Purple for Manage Users
                      title: const Text('Manage Users'),
                      onTap: () {
                        Navigator.pop(context); // Close the drawer
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const ManageUsersPage()),
                        );
                      },
                    ),
                  // Add Daily Form option for manager
                  if (role == 'manager')
                    ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      leading: const Icon(Icons.assignment_turned_in, color: Colors.orange), // Orange for Daily Form
                      title: const Text('Daily Form'),
                      onTap: () {
                        Navigator.pop(context); // Close the drawer
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => PerformanceForm()),
                        );
                      },
                    ),
                  // Add Performance option for sales
                  if (role == 'sales')
                    ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      leading: const Icon(Icons.bar_chart, color: Colors.teal),
                      title: const Text('Performance'),
                      onTap: () {
                        Navigator.pop(context); // Close the drawer
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => PerformanceScoreInnerPage()),
                        );
                      },
                    ),
                  // Add Performance option for admin
                  if (role == 'admin')
                    ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      leading: const Icon(Icons.edit_note, color: Colors.deepPurple),
                      title: const Text('Edit Performance Form'),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const AdminPerformancePage()),
                        );
                      },
                    ),
                  // Add Performance Insights for admin
                  if (role == 'admin')
                    ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      leading: const Icon(Icons.insert_chart, color: Color.fromARGB(255, 255, 175, 3)),
                      title: const Text('Performance Monthly'),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => ExcelViewPerformancePage()),
                        );
                      },
                    ),
                  if (role == 'admin')
                    ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      leading: const Icon(Icons.insights, color: Colors.green),
                      title: const Text('Performance Insights'),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => InsightsPerformancePage()),
                        );
                      },
                    ),  
                  // Add Entry Page option for admin
                  if (role == 'admin')
                    ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      leading: const Icon(Icons.add_box, color: Colors.blue),
                      title: const Text('Entry Page'),
                      onTap: () {
                        Navigator.pop(context); // Close the drawer
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => EntryPage()),
                        );
                      },
                    ),
                  ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    leading: const Icon(Icons.logout, color: Colors.red), // Red for Log Out
                    title: const Text('Log Out'),
                    onTap: () async {
                      await FirebaseAuth.instance.signOut();
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(builder: (context) => const LoginPage()),
                        (Route<dynamic> route) => false,
                      );
                    },
                  ),
                ],
              ),
            ),
            body: Stack(
              children: [
                // Animated top-right bubble
                Positioned(
                  top: -120,
                  right: -120,
                  child: ScaleTransition(
                    scale: _scaleAnimation,
                    child: Container(
                      width: 260,
                      height: 260,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [Color(0xFF8CC63F), Color(0xFFB2E85F)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                    ),
                  ),
                ),

                // Animated bottom-left bubble
                Positioned(
                  bottom: -120,
                  left: -120,
                  child: ScaleTransition(
                    scale: _scaleAnimation,
                    child: Container(
                      width: 260,
                      height: 260,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [Color(0xFF005BAC), Color(0xFF3383C7)],
                          begin: Alignment.topRight,
                          end: Alignment.bottomLeft,
                        ),
                      ),
                    ),
                  ),
                ),

                // Burger button (top right)
                Positioned(
                  top: 24,
                  right: 16,
                  child: Builder(
                    builder: (context) => IconButton(
                      icon: Icon(Icons.menu, color: primaryBlue, size: 32),
                      onPressed: () {
                        Scaffold.of(context).openEndDrawer();
                      },
                      tooltip: 'Menu',
                    ),
                  ),
                ),

                // --- WARNING BANNER FOR SALES ---
                if (_showTodoWarning)
                  Positioned(
                    bottom: 0, // <-- Changed from top: 0 to bottom: 0
                    left: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const TodoFormPage()),
                        );
                        // Re-check after returning from ToDo form
                        _checkTodoWarning();
                      },
                      child: Container(
                        color: const Color.fromARGB(255, 243, 106, 2),
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                        child: Row(
                          children: [
                            const Icon(Icons.warning, color: Colors.white),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                "You have not created a ToDo!",
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Main content (unchanged)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Logo with swing animation on tap
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16.0),
                          child: GestureDetector(
                            onTap: () {
                              _swingController.forward(from: 0.0);
                              _logoTapCount++;
                              if (_logoTapCount > 5) {
                                _logoTapCount = 0; // Reset counter after showing dialog
                                showDialog(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text("Hey!"),
                                    content: const Text("Don't you have anything else to do??"),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.of(context).pop(),
                                        child: const Text("OK"),
                                      ),
                                    ],
                                  ),
                                );
                              }
                            },
                            child: AnimatedBuilder(
                              animation: _swingAnimation,
                              builder: (context, child) {
                                // Damped oscillation: amplitude decreases, frequency controls swings
                                final double maxAngle = 0.18; // ~10 degrees
                                final double damping = 3.5;   // Higher = faster damping
                                final double frequency = 3.5; // Number of swings

                                double t = _swingAnimation.value; // 0.0 to 1.0
                                double angle = maxAngle * exp(-damping * t) * sin(frequency * pi * t);

                                return Transform.rotate(
                                  angle: angle,
                                  alignment: Alignment.topCenter,
                                  child: child,
                                );
                              },
                              child: Image.asset(
                                'assets/images/logo.png',
                                width: 160,
                                height: 160,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        // Responsive grid of buttons
                        Wrap(
                          spacing: 16,
                          runSpacing: 16,
                          alignment: WrapAlignment.center,
                          children: [
                            SizedBox(
                              width: 140,
                              height: 56, // Set a fixed height for all cards
                              child: NeumorphicButton(
                                onTap: () async {
                                  // 1. Instantly show the loading page (no fade-in)
                                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LoadingPage()));

                                  // Fetch branch for current user
                                  final user = FirebaseAuth.instance.currentUser;
                                  String? branch;
                                  if (user != null) {
                                    final userDoc = await FirebaseFirestore.instance
                                        .collection('users')
                                        .doc(user.uid)
                                        .get();
                                    branch = userDoc.data()?['branch'];
                                  }
                                  await Future.delayed(const Duration(milliseconds: 800)); // Ensure loading animation is visible

                                  if (branch != null) {
                                    Navigator.of(context).pushReplacement(fadeRoute(LeadsPage(branch: branch)));
                                  } else {
                                    Navigator.of(context).pop(); // Remove loading page
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Branch not found for user')),
                                    );
                                  }
                                },
                                text: 'Leads',
                                color: primaryBlue,
                                textColor: Colors.white,
                                icon: Icons.people_alt_rounded,
                                textStyle: const TextStyle(
                                  fontFamily: 'Montserrat',
                                  fontWeight: FontWeight.normal,
                                  fontSize: 17,
                                  letterSpacing: 1.1,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 140,
                              height: 56, // Set a fixed height for all cards
                              child: NeumorphicButton(
                                onTap: () async {
                                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LoadingPage()));
                                  await Future.delayed(const Duration(milliseconds: 800)); // Simulate loading
                                  Navigator.of(context).pushReplacement(fadeRoute(const TodoPage()));
                                },
                                text: 'ToDo List',
                                color: primaryGreen,
                                textColor: Colors.white,
                                icon: Icons.check_circle_outline_rounded,
                                textStyle: const TextStyle(
                                  fontFamily: 'Montserrat',
                                  fontWeight: FontWeight.normal,
                                  fontSize: 17, // Match Leads button font size
                                  letterSpacing: 1.1,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            // For Dashboard button (admin or manager)
                            if (role == 'admin' || role == 'manager')
                              SizedBox(
                                width: 80,
                                height: 56,
                                child: NeumorphicButton(
                                  onTap: () async {
                                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LoadingPage()));
                                    await Future.delayed(const Duration(milliseconds: 800)); // Simulate loading
                                    Navigator.of(context).pushReplacement(
                                      MaterialPageRoute(builder: (_) => const DashboardPage()),
                                    );
                                  },
                                  text: '',
                                  color: Colors.deepPurple,
                                  textColor: Colors.white,
                                  icon: Icons.dashboard_rounded,
                                ),
                              ),
                            // REMOVE Customer List button for all roles here
                            // Add Marketing button
                            SizedBox(
                              width: 200,
                              height: 56,
                              child: NeumorphicButton(
                                onTap: () async {
                                  // Show loading page for 1 second before navigating to Marketing
                                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LoadingPage()));
                                  await Future.delayed(const Duration(milliseconds: 1000)); // Reduced to 1 second

                                  // Fetch branch, username, userid for current user
                                  final user = FirebaseAuth.instance.currentUser;
                                  String? branch, username, userid, role;
                                  if (user != null) {
                                    final userDoc = await FirebaseFirestore.instance
                                        .collection('users')
                                        .doc(user.uid)
                                        .get();
                                    branch = userDoc.data()?['branch'];
                                    username = userDoc.data()?['username'] ?? userDoc.data()?['email'] ?? '';
                                    userid = user.uid;
                                    role = userDoc.data()?['role'];
                                  }
                                  if (role == 'admin') {
                                    Navigator.of(context).pushReplacement(
                                      MaterialPageRoute(
                                        builder: (_) => const ViewerMarketingPage(),
                                      ),
                                    );
                                  } else if (branch != null && username != null && userid != null) {
                                    Navigator.of(context).pushReplacement(
                                      MaterialPageRoute(
                                        builder: (_) => MarketingFormPage(
                                          username: username ?? '',
                                          userid: userid?? '',
                                          branch: branch?? '',
                                        ),
                                      ),
                                    );
                                  } else {
                                    Navigator.of(context).pop(); // Remove loading page
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('User info not found')),
                                    );
                                  }
                                },
                                text: 'Marketing',
                                color: const Color.fromARGB(255, 192, 25, 14),
                                textColor: Colors.white,
                                icon: Icons.campaign,
                                textStyle: const TextStyle(
                                  fontFamily: 'Montserrat',
                                  fontWeight: FontWeight.normal,
                                  fontSize: 17,
                                  letterSpacing: 1.1,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// Add this widget in your file (above your _HomePageState class or in a separate file)
class NeumorphicButton extends StatelessWidget {
  final VoidCallback onTap;
  final String text;
  final Color color;
  final Color textColor;
  final IconData? icon;
  final TextStyle? textStyle;

  const NeumorphicButton({
    super.key,
    required this.onTap,
    required this.text,
    required this.color,
    required this.textColor,
    this.icon,
    this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14), // Slightly reduced padding
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.18),
              offset: const Offset(4, 4),
              blurRadius: 14,
            ),
            BoxShadow(
              color: Colors.white.withOpacity(0.10),
              offset: const Offset(-4, -4),
              blurRadius: 14,
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, color: textColor, size: 20), // Slightly smaller icon
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                text,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: textStyle ??
                    TextStyle(
                      fontWeight: FontWeight.normal,
                      fontSize: 15, // Reduced font size
                      letterSpacing: 1.1,
                      color: textColor,
                      fontFamily: 'Montserrat',
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showLoadingDialog(BuildContext context) async {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) {
      return const _RotatingLogoDialog();
    },
  );
  await Future.delayed(const Duration(milliseconds: 800)); // 1.5 seconds
  Navigator.of(context, rootNavigator: true).pop();
}

class _RotatingLogoDialog extends StatelessWidget {
  const _RotatingLogoDialog();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: isDark ? const Color(0xFF181A20) : Colors.white, // Dark for dark theme
      child: const Center(
        child: _RotatingLogo(),
      ),
    );
  }
}

class _RotatingLogo extends StatefulWidget {
  const _RotatingLogo();

  @override
  State<_RotatingLogo> createState() => _RotatingLogoState();
}

class _RotatingLogoState extends State<_RotatingLogo> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800), // Slow rotation
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001) // perspective
            ..rotateY(_controller.value * 2 * 3.1415926535), // Y-axis rotation
          child: child,
        );
      },
      child: Image.asset(
        'assets/images/logo.png',
        width: 200,
        height: 200,
      ),
    );
  }
}

// Add this anywhere above your _HomePageState class or in a utils file
Route fadeRoute(Widget page) {
  return PageRouteBuilder(
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: animation,
        child: child,
      );
    },
    transitionDuration: const Duration(milliseconds: 400),
  );
}
