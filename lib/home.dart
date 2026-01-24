import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'dart:convert';
import 'package:permission_handler/permission_handler.dart';

import 'main.dart';
import 'Todo & Leads/todoform.dart';
import 'widgets/home_widgets.dart';
import 'widgets/home_drawer.dart';
import 'widgets/home_body.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with TickerProviderStateMixin, RouteAware {
  late AnimationController _swingController;
  late Animation<double> _swingAnimation;

  File? _profileImage;
  String? _profileImagePath;
  bool _showTodoWarning = false;
  int _logoTapCount = 0;
  List<Contact>? _cachedContacts;
  bool _contactsLoaded = false;

  @override
  void initState() {
    super.initState();
    _initSwingAnimation();
    _checkForUpdate();
    _loadProfileImage();
    _checkTodoWarning();
    _checkPendingTodosReminder();
    _setupPerformanceNotifications();
    _fetchAndCacheContacts();
    _printCustomClaims();
    _showTodoLeadTimingChangeMessageIfNeeded();
  }

  void _initSwingAnimation() {
    _swingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _swingAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _swingController, curve: Curves.linear),
    );
  }

  void _setupPerformanceNotifications() {
    FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user != null) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        final role = userDoc.data()?['role'];
        if (role == 'sales') {
          _checkAndShowPerformanceDeductionNotification();
        }
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }
    _checkTodoWarning();
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _swingController.dispose();
    super.dispose();
  }

  @override
  void didPopNext() => _checkTodoWarning();

  @override
  void didPush() {
    _fetchAndCacheContacts();
    _checkTodoWarning();
  }

  // ==================== Helper Methods ====================

  Future<void> _checkAndShowPerformanceDeductionNotification() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final monthEnd = DateTime(now.year, now.month + 1, 1);

    final formsSnapshot = await FirebaseFirestore.instance
        .collection('dailyform')
        .where('userId', isEqualTo: user.uid)
        .where('timestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
        .where('timestamp', isLessThan: Timestamp.fromDate(monthEnd))
        .get();

    final forms = formsSnapshot.docs
        .map((doc) => doc.data() as Map<String, dynamic>)
        .toList();

    final today = DateTime(now.year, now.month, now.day);
    final currentWeekNum = _isoWeekNumber(today);
    final weekForms = forms.where((form) {
      final ts = form['timestamp'];
      final date =
          ts is Timestamp ? ts.toDate() : DateTime.parse(ts.toString());
      return _isoWeekNumber(date) == currentWeekNum && date.year == today.year;
    }).toList();

    bool deduction = _hasDeduction(weekForms);

    final prefs = await SharedPreferences.getInstance();
    final lastNotified = prefs.getString('last_perf_deduction_notify');
    final todayStr = "${now.year}-${now.month}-${now.day}";
    if (deduction && lastNotified != todayStr) {
      await AwesomeNotifications().createNotification(
        content: NotificationContent(
          id: 2002,
          channelKey: 'reminder_channel',
          title: 'Performance Deduction',
          body:
              'Your performance score was reduced. Check the Performance page for details.',
          notificationLayout: NotificationLayout.Default,
        ),
      );
      await prefs.setString('last_perf_deduction_notify', todayStr);
    }
  }

  bool _hasDeduction(List<Map<String, dynamic>> weekForms) {
    for (var form in weekForms) {
      final att = form['attendance'];
      if (att == 'late' || att == 'notApproved') return true;
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
          return true;
        }
      }
    }
    return false;
  }

  int _isoWeekNumber(DateTime date) {
    final thursday = date.subtract(Duration(days: (date.weekday + 6) % 7 - 3));
    final firstThursday = DateTime(date.year, 1, 4);
    final diff = thursday.difference(firstThursday).inDays ~/ 7;
    return 1 + diff;
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

    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final role = userDoc.data()?['role'];
    final email = userDoc.data()?['email'];
    if (role != 'sales') {
      setState(() => _showTodoWarning = false);
      return;
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final windowStart = today.add(const Duration(hours: 12));
    final windowEnd = today.add(const Duration(days: 1, hours: 12));

    final todosSnapshot = await FirebaseFirestore.instance
        .collection('todo')
        .where('email', isEqualTo: email)
        .where('timestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(windowStart))
        .where('timestamp', isLessThan: Timestamp.fromDate(windowEnd))
        .get();

    setState(() => _showTodoWarning = todosSnapshot.docs.isEmpty);
  }

  Future<void> _checkPendingTodosReminder() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final role = userDoc.data()?['role'];
    if (role != 'sales') return;

    final now = DateTime.now();
    final pendingTodosSnapshot = await FirebaseFirestore.instance
        .collection('todo')
        .where('email', isEqualTo: user.email)
        .where('status', isEqualTo: 'pending')
        .get();

    bool hasOverdueTask = false;
    for (var doc in pendingTodosSnapshot.docs) {
      final timestamp = doc.data()['timestamp'] as Timestamp?;
      if (timestamp != null &&
          now.difference(timestamp.toDate()).inHours >= 24) {
        hasOverdueTask = true;
        break;
      }
    }

    if (hasOverdueTask) {
      await AwesomeNotifications().createNotification(
        content: NotificationContent(
          id: 2003,
          channelKey: 'reminder_channel',
          title: 'Overdue Tasks!',
          body:
              'You have pending tasks that are more than a day old. Please complete them.',
          payload: {'page': 'todo'},
        ),
      );
    }
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

  Future<void> _fetchAndCacheContacts() async {
    var status = await Permission.contacts.status;
    if (!status.isGranted) return;

    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('contacts_cache');
    if (cached != null) {
      final List<dynamic> decoded = jsonDecode(cached);
      _cachedContacts = decoded.map((c) => Contact.fromJson(c)).toList();
      setState(() => _contactsLoaded = true);
    }

    final contacts = await FlutterContacts.getContacts(
        withProperties: true, withThumbnail: false);
    final encoded = jsonEncode(contacts.map((c) => c.toJson()).toList());
    await prefs.setString('contacts_cache', encoded);

    setState(() {
      _cachedContacts = contacts;
      _contactsLoaded = true;
    });
  }

  Future<void> _printCustomClaims() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print("No user signed in.");
    } else {
      final idTokenResult = await user.getIdTokenResult();
      print("Custom claims: ${idTokenResult.claims}");
    }
  }

  Future<void> _showTodoLeadTimingChangeMessageIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final shownCount = prefs.getInt('todo_lead_timing_change_show') ?? 0;
    if (shownCount < 2) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Notice'),
            content: const Text(
              'ToDo, Lead സമയക്രമങ്ങളിൽ മാറ്റം വന്നിരിക്കുന്നു!\n\n'
              'ഇന്ന് ഉച്ചയ്ക്ക് 12:00 മുതൽ നാളെ ഉച്ചയ്ക്ക് 12:00 വരെ ക്രിയേറ്റ് ചെയ്യുന്ന ToDo & Lead നാളത്തെ കണക്കിലാകും ഉൾപ്പെടുത്തുക. '
              'അതനുസരിച്ച് പ്ലാൻ ചെയ്യുക',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      });
      await prefs.setInt('todo_lead_timing_change_show', shownCount + 1);
    }
  }

  void _handleLogoTap() {
    _swingController.forward(from: 0.0);
    _logoTapCount++;
    if (_logoTapCount > 5) {
      _logoTapCount = 0;
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
  }

  Future<void> _handleTodoWarningTap() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const TodoFormPage()),
    );
    _checkTodoWarning();
  }

  // ==================== Build ====================

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser?.uid)
          .get(),
      builder: (context, snapshot) {
        String? role;
        String? username;
        String? branch;
        if (snapshot.hasData) {
          role = snapshot.data?.get('role');
          username = snapshot.data?.get('username') ??
              snapshot.data?.get('email') ??
              'User';
          branch = snapshot.data?.get('branch');
        }

        return WillPopScope(
          onWillPop: () async => false,
          child: Scaffold(
            endDrawer: HomeDrawer(
              role: role,
              username: username,
              branch: branch,
              profileImage: _profileImage,
              onPickProfileImage: _pickProfileImage,
            ),
            body: Stack(
              children: [
                HomeBackground(isDark: isDark),
                HomeMenuButton(isDark: isDark),
                if (_showTodoWarning)
                  TodoWarningBanner(onTap: _handleTodoWarningTap),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SwingingLogo(
                          swingAnimation: _swingAnimation,
                          onTap: _handleLogoTap,
                          isDark: isDark,
                        ),
                        const SizedBox(height: 8),
                        HomeButtonsContainer(role: role, isDark: isDark),
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
