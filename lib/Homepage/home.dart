import 'dart:async';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:convert';
import 'package:permission_handler/permission_handler.dart';
import 'package:home_widget/home_widget.dart';
import 'package:mtcsync/Misc/notification_permission_service.dart';
import '../main.dart';
import '../Todo/todo.dart';
import '../Todo/todoform.dart';
import '../Todo/todo_widget_updater.dart';
import '../Leads/presentfollowup.dart';
import '../Homepage/home_widgets.dart';
import '../Homepage/home_drawer.dart';
import '../Homepage/home_body.dart';
import '../Misc/battery_optimization_helper.dart';
import '../Navigation/user_cache_service.dart';
import '../SME/sme_notification_service.dart';
import '../Leads/leads_notification.dart';
import '../DME/services/dme_complaint_service.dart';
import '../DME/services/dme_supabase_service.dart';
import '../Task/task_sales.dart' show syncTaskReminders;

// Top-level function for compute to decode contacts JSON
List<dynamic> decodeContactsJson(String json) {
  return jsonDecode(json) as List<dynamic>;
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with TickerProviderStateMixin, RouteAware {
  late AnimationController _swingController;
  late Animation<double> _swingAnimation;
  StreamSubscription<String>? _fcmTokenSubscription;
  StreamSubscription<Uri?>? _widgetClickSub;

  File? _profileImage;
  String? _profileImagePath;
  bool _showTodoWarning = false;
  int _logoTapCount = 0;
  List<Contact>? _cachedContacts;
  bool _contactsLoaded = false;
  DateTime? _lastTodoWarningCheck;

  final _userCache = UserCacheService.instance;
  String? _role;
  String? _username;
  String? _branch;

  int _transferredCount = 0;
  int _otherCount = 0;
  int _taskCount = 0;
  StreamSubscription? _notificationListener;
  StreamSubscription? _assignedLeadsListener;
  StreamSubscription? _complaintsListener;
  StreamSubscription? _coreTasksListener;

  @override
  void initState() {
    super.initState();
    _initSwingAnimation();
    // Initialize Supabase early so notification dot shows on app startup
    DmeSupabaseService.instance.ensureInitialized().catchError((_) {});
    _userCache.ensureLoaded().then((_) {
      if (mounted) {
        setState(() {
          _role = _userCache.role;
          _username = _userCache.username;
          _branch = _userCache.branch;
        });
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null && (_role == 'sales' || _role == 'manager' || _role == 'asst_manager')) {
          syncTaskReminders(uid).catchError((e) {
            debugPrint('Failed to sync tasks reminders: $e');
          });
        }
        _listenForTransferredLeads();
        _listenForAssignedLeadsAndComplaints();
      }
    });
    _checkForUpdate();
    _loadProfileImage();
    _checkTodoWarning();
    _checkPendingTodosReminder();
    _setupFcmTokenSync();
    _startSmeNotificationService();
    _fetchAndCacheContacts();
    _checkBatteryOptimization();
    // Listen for widget taps when app is warm (already running)
    try {
      _widgetClickSub = HomeWidget.widgetClicked.listen(_handleWidgetDeepLink);
    } catch (_) {
      // Platform may not have an active stream — safe to ignore
    }
    // Refresh widget data on every home screen visit
    updateTodoWidgetFromFirestore().catchError((_) {});
  }

  /// Check and prompt for battery optimization after first frame
  void _checkBatteryOptimization() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (await BatteryOptimizationHelper.shouldShowPrompt()) {
        // Add small delay to let the home screen settle
        await Future.delayed(const Duration(seconds: 2));
        if (!mounted) return;
        await BatteryOptimizationHelper.showBatteryOptimizationDialog(context);
      }
    });
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



  void _startSmeNotificationService() {
    SmeNotificationService.instance.startListening();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }
    // Note: _checkTodoWarning removed here — it runs via initState, didPopNext, didPush.
    // didChangeDependencies fires on InheritedWidget changes (e.g. theme), so it was over-triggering.
  }

  @override
  void dispose() {
    _fcmTokenSubscription?.cancel();
    _widgetClickSub?.cancel().catchError((_) {});
    _notificationListener?.cancel();
    _assignedLeadsListener?.cancel();
    _complaintsListener?.cancel();
    _coreTasksListener?.cancel();
    SmeNotificationService.instance.stopListening();
    routeObserver.unsubscribe(this);
    _swingController.dispose();
    super.dispose();
  }

  void _listenForTransferredLeads() {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final branch = _userCache.branch ?? '';
    if (currentUserId == null || branch.isEmpty) return;

    _notificationListener?.cancel();
    _notificationListener = FirebaseFirestore.instance
        .collection('follow_ups')
        .where('branch', isEqualTo: branch)
        .where('created_by', isEqualTo: currentUserId)
        .where('transferred_at', isNull: false)
        .snapshots()
        .listen((snapshot) async {
      if (!mounted) return;
      
      // Count only transferred leads that haven't been seen by this user
      int unseenCount = 0;
      for (final doc in snapshot.docs) {
        try {
          final userSeenDoc = await FirebaseFirestore.instance
              .collection('user_seen_leads')
              .doc('${doc.id}__${currentUserId}')
              .get();
          if (!userSeenDoc.exists) {
            unseenCount++;
          }
        } catch (_) {
          // If there's an error, assume it hasn't been seen
          unseenCount++;
        }
      }
      
      if (mounted) {
        setState(() {
          _transferredCount = unseenCount;
        });
      }
    });
  }

  void _listenForAssignedLeadsAndComplaints() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // Listen for assigned SME/DME leads
    _assignedLeadsListener?.cancel();
    _assignedLeadsListener = FirebaseFirestore.instance
        .collection('follow_ups')
        .where('assigned_to', isEqualTo: uid)
        .snapshots()
        .listen((snapshot) async {
      if (!mounted) return;
      await _updateOtherCountFromListeners();
    });

    // Listen for Core Tasks in realtime
    _coreTasksListener?.cancel();
    if (_role == 'sales' || _role == 'manager' || _role == 'asst_manager') {
      _coreTasksListener = FirebaseFirestore.instance
          .collection('core_tasks')
          .where('assigned_to', isEqualTo: uid)
          .snapshots()
          .listen((_) {
        if (mounted) _updateOtherCountFromListeners();
      });
    } else if (_role == 'core_team') {
      _coreTasksListener = FirebaseFirestore.instance
          .collection('core_tasks')
          .where('assigned_by', isEqualTo: uid)
          .snapshots()
          .listen((_) {
        if (mounted) _updateOtherCountFromListeners();
      });
    }

    // Listen for complaints using Supabase
    _listenForComplaintsRealtime(uid);
  }

  void _listenForComplaintsRealtime(String uid) {
    _complaintsListener?.cancel();
    // Set up a periodic check for complaints since Supabase doesn't have easy Dart listeners
    // Check every 3 seconds for new/updated complaints
    _complaintsListener = Stream.periodic(const Duration(seconds: 3)).listen((_) {
      if (mounted) {
        _updateOtherCountFromListeners();
      }
    });
  }

  Future<void> _updateOtherCountFromListeners() async {
    if (!mounted) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    int count = 0;

    // Count SME / DME leads assigned to this user that are still In Progress (excluding seen ones)
    try {
      final snap = await FirebaseFirestore.instance
          .collection('follow_ups')
          .where('assigned_to', isEqualTo: uid)
          .get();
      
      for (final doc in snap.docs) {
        final source =
            (doc.data()['source'] as String? ?? '').toLowerCase().trim();
        final status = doc.data()['status'] as String? ?? '';
        
        if ((source != 'sme' && source != 'dme') || status != 'In Progress') {
          continue;
        }
        
        // Check if this user has seen this lead
        try {
          final userSeenDoc = await FirebaseFirestore.instance
              .collection('user_seen_leads')
              .doc('${doc.id}__${uid}')
              .get();
          if (!userSeenDoc.exists) {
            count++;
          }
        } catch (_) {
          // If there's an error, assume it hasn't been seen
          count++;
        }
      }
    } catch (_) {}

    // Count complaints assigned to this user that are still raised (excluding seen ones)
    List<String> countedComplaintIds = [];
    try {
      final complaints = await DmeComplaintService.instance
          .getAssignedComplaints(userId: uid, status: 'raised');
      
      // Filter out complaints that have been marked as seen by this user
      for (final complaint in complaints) {
        final isSeen = await DmeComplaintService.instance
            .isComplaintSeen(complaintId: complaint.id ?? '', userId: uid);
        if (!isSeen) {
          count++;
          countedComplaintIds.add(complaint.id ?? '');
        }
      }
    } catch (_) {}

    // Also count branch complaints for managers (avoid duplicates)
    try {
      if (_role == 'manager' || _role == 'asst_manager') {
        final branchName = _userCache.branch ?? '';
        if (branchName.isNotEmpty) {
          final branchId = await DmeComplaintService.instance
              .getBranchIdByName(branchName);
          
          if (branchId != null) {
            final branchComplaints = await DmeComplaintService.instance
                .getComplaintsForBranch(branchId: branchId, status: 'raised');
            
            for (final complaint in branchComplaints) {
              // Skip if already counted in assigned complaints
              if (countedComplaintIds.contains(complaint.id)) continue;
              
              // Only count if not already in assigned complaints and not seen by this user
              final isSeen = await DmeComplaintService.instance
                  .isComplaintSeen(complaintId: complaint.id ?? '', userId: uid);
              if (!isSeen) {
                count++;
              }
            }
          }
        }
      }
    } catch (_) {}

    int taskCount = 0;
    // Count core tasks (pending for assigned users, completed-unseen for core team)
    try {
      if (_role == 'sales' || _role == 'manager' || _role == 'asst_manager' || _role == 'admin') {
        final tasksSnap = await FirebaseFirestore.instance
            .collection('core_tasks')
            .where('assigned_to', isEqualTo: uid)
            .where('status', isEqualTo: 'pending')
            .get();
        taskCount = tasksSnap.docs.length;
        count += taskCount;
      } else if (_role == 'core_team') {
        final tasksSnap = await FirebaseFirestore.instance
            .collection('core_tasks')
            .where('assigned_by', isEqualTo: uid)
            .where('status', isEqualTo: 'completed')
            .get();

        int unseenTasks = 0;
        for (final doc in tasksSnap.docs) {
          try {
            final userSeenDoc = await FirebaseFirestore.instance
                .collection('user_seen_leads')
                .doc('${doc.id}__${uid}')
                .get();
            if (!userSeenDoc.exists) {
              unseenTasks++;
            }
          } catch (_) {
            unseenTasks++;
          }
        }
        taskCount = unseenTasks;
        count += taskCount;
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _otherCount = count;
        _taskCount = taskCount;
      });
    }
  }

  Future<void> _openNotifications() async {
    final branch = _userCache.branch ?? '';
    if (branch.isEmpty) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LeadsNotificationPage(userBranch: branch),
      ),
    );
    // Refresh notification counts after returning from notifications page
    if (mounted) {
      _listenForTransferredLeads();
      await _updateOtherCountFromListeners();
    }
  }

  void _handleWidgetDeepLink(Uri? uri) {
    if (!mounted || uri == null) return;
    final host = uri.host;
    final segments = uri.pathSegments;
    if (host == 'todo') {
      if (segments.isNotEmpty) {
        // Navigate to the specific todo detail
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TaskDetailPageFromId(docId: segments.first),
          ),
        );
      } else {
        // Navigate to the todo list
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const TodoPage()),
        );
      }
    } else if (host == 'lead' && segments.isNotEmpty) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PresentFollowUp(docId: segments.first),
        ),
      );
    }
  }

  Future<void> _setupFcmTokenSync() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final token = await FirebaseMessaging.instance.getToken();
        await _saveFcmToken(user.uid, token);
      } catch (e) {
        debugPrint('Failed to get FCM token: $e');
      }
    }

    _fcmTokenSubscription =
        FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      await _saveFcmToken(uid, token);
    });
  }

  Future<void> _saveFcmToken(String? uid, String? token) async {
    if (uid == null || token == null || token.isEmpty) return;

    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'fcm_token': token,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Failed to save FCM token: $e');
    }
  }

  @override
  void didPopNext() {
    _checkTodoWarning();
    _updateOtherCountFromListeners();
  }

  @override
  void didPush() {
    _fetchAndCacheContacts();
    _checkTodoWarning();
    _updateOtherCountFromListeners();
  }

  // ==================== Helper Methods ====================



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

  bool _isPickingImage = false;

  Future<void> _pickProfileImage() async {
    if (_isPickingImage) return;
    _isPickingImage = true;
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);
      if (pickedFile != null) {
        if (!mounted) return;
        setState(() {
          _profileImage = File(pickedFile.path);
          _profileImagePath = pickedFile.path;
        });
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('profile_image_path', pickedFile.path);
      }
    } catch (e) {
      debugPrint('Image picker error: $e');
    } finally {
      _isPickingImage = false;
    }
  }

  Future<void> _checkTodoWarning() async {
    // Debounce: skip if checked less than 2 minutes ago
    if (_lastTodoWarningCheck != null &&
        DateTime.now().difference(_lastTodoWarningCheck!) <
            const Duration(minutes: 2)) {
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await _userCache.ensureLoaded();
    final role = _userCache.role;
    final email = _userCache.email;
    if (role != 'sales' && role != 'manager' && role != 'asst_manager') {
      setState(() => _showTodoWarning = false);
      return;
    }

    final window = getCurrentISTWindow();
    final windowStart = window[0];
    final windowEnd = window[1];

    final todosSnapshot = await FirebaseFirestore.instance
        .collection('todo')
        .where('email', isEqualTo: email)
        .where('timestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(windowStart))
        .where('timestamp', isLessThan: Timestamp.fromDate(windowEnd))
        .get();

    _lastTodoWarningCheck = DateTime.now();
    setState(() => _showTodoWarning = todosSnapshot.docs.isEmpty);
  }

  Future<void> _checkPendingTodosReminder() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await _userCache.ensureLoaded();
    if (_userCache.role != 'sales') return;

    final now = DateTime.now();
    final pendingTodosSnapshot = await FirebaseFirestore.instance
        .collection('todo')
        .where('email', isEqualTo: user.email)
        .where('status', isEqualTo: 'pending')
        .limit(20)
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
      try {
        await NotificationPermissionService.instance.safeCreateNotification(
          content: NotificationContent(
            id: 2003,
            channelKey: 'reminder_channel',
            title: 'Overdue Tasks!',
            body:
                'You have pending tasks that are more than a day old. Please complete them.',
            payload: {'page': 'todo'},
          ),
        );
      } catch (_) {
        // Notification channel may be disabled by user; ignore silently.
      }
    }
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

  Future<void> _fetchAndCacheContacts() async {
    var status = await Permission.contacts.status;
    if (!status.isGranted) return;

    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('contacts_cache');
    if (cached != null) {
      final List<dynamic> decoded = await compute(decodeContactsJson, cached);
      _cachedContacts = decoded.map((c) => Contact.fromJson(c)).toList();
      setState(() => _contactsLoaded = true);
    }

    final contacts = await FlutterContacts.getContacts(
        withProperties: true, withThumbnail: false);
    final encoded = await compute(
        (List<Map<String, dynamic>> list) => jsonEncode(list),
        contacts.map((c) => c.toJson()).toList());
    await prefs.setString('contacts_cache', encoded);

    if (mounted) {
      setState(() {
        _cachedContacts = contacts;
        _contactsLoaded = true;
      });
    }
  }

  Future<void> _printCustomClaims() async {
    if (!kDebugMode) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint("No user signed in.");
    } else {
      final idTokenResult = await user.getIdTokenResult();
      debugPrint("Custom claims: ${idTokenResult.claims}");
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

  int _currentPageIndex = 0;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final role = _role;
    final username = _username;
    final branch = _branch;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {},
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
            HomeNotificationButton(
              isDark: isDark,
              count: _transferredCount + _otherCount,
              onTap: _openNotifications,
            ),
            if (_showTodoWarning)
              TodoWarningBanner(onTap: _handleTodoWarningTap),
            // Page scroll indicator dots kept near the bottom just above the todo warning banner
            Positioned(
              bottom: _showTodoWarning ? 54 : 16,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(2, (index) {
                  final active = (_currentPageIndex % 2) == index;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    height: 8,
                    width: active ? 22 : 8,
                    decoration: BoxDecoration(
                      color: active
                          ? const Color(0xFF005BAC)
                          : (isDark ? Colors.white30 : Colors.black26),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: SwingingLogo(
                      swingAnimation: _swingAnimation,
                      onTap: _handleLogoTap,
                      isDark: isDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  HomeButtonsContainer(
                    role: role,
                    isDark: isDark,
                    taskCount: _taskCount,
                    onPageChanged: (index) {
                      setState(() {
                        _currentPageIndex = index;
                      });
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
