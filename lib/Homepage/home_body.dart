import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math';
import '../Login/auth_wrapper.dart';
import '../Navigation/navigation_state.dart';
import '../Navigation/user_cache_service.dart';
import '../Customer Calling/customer_manager_view.dart';
import '../Todo/todo.dart';
import '../Leads/leads.dart';
import '../Orders/orders.dart';
import '../Dashboard/dashboard.dart';
import '../Marketing/marketing.dart';
import '../Marketing/viewer_marketing.dart';
import '../Customer Calling/customer_list_target.dart';
import '../Customer Calling/customer_admin_viewer.dart';
import '../Navigation/loading_page.dart';
import 'home_widgets.dart';
import '../Sync Head/sync_head_leads_page.dart';
import '../Sync Head/sync_head_todos_page.dart';
import '../Sync Head/sync_head_report_todo.dart';
import '../Sync Head/sync_head_customer_list_deletion_approval.dart';
import '../Sync Head/sync_head_yupulse_data.dart';
import '../Sync Head/transfer_call_list_page.dart';
import '../SME/sme_leads_page.dart';
import '../SME/sme_dashboard.dart';
import '../SME/sme_ads_page.dart';
import '../SME/sme_deletion_approval.dart';
import '../Supersale/supersale_admin.dart';
import '../Supersale/supersale_admin_dashboard.dart';
import '../Supersale/supersale_user_mainpage.dart';
import '../SME/sme_assigned_leads_page.dart';
import '../Task/task_admin.dart';
import '../Task/task_sales.dart';
import '../DME/User/dme_user_homepage.dart';
import '../DME/Admin/dme_admin_homepage.dart';

/// App brand colors
const Color primaryBlue = Color(0xFF005BAC);
const Color primaryGreen = Color(0xFF8CC63F);

/// Builds the decorative background with gradient using logo colors.
class HomeBackground extends StatelessWidget {
  final bool isDark;

  const HomeBackground({super.key, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? [
                  const Color(0xFF0A1628), // Dark blue base
                  const Color(0xFF0D2137), // Slightly lighter
                  const Color(0xFF0A1628), // Back to dark
                ]
              : [
                  primaryBlue.withValues(alpha: 0.05),
                  Colors.white,
                  primaryGreen.withValues(alpha: 0.08),
                ],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
    );
  }
}

/// Menu button with glass effect.
class HomeMenuButton extends StatelessWidget {
  final bool isDark;

  const HomeMenuButton({super.key, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 40,
      right: 20,
      child: Builder(
        builder: (context) => Container(
          decoration: BoxDecoration(
            color: (isDark ? Colors.white : primaryBlue).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color:
                  (isDark ? Colors.white : primaryBlue).withValues(alpha: 0.2),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: primaryBlue.withValues(alpha: 0.1),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                Scaffold.of(context).openEndDrawer();
              },
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Icon(
                  Icons.menu_rounded,
                  color: isDark ? Colors.white : primaryBlue,
                  size: 26,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Notification bell button positioned top-left, opposite the menu button.
class HomeNotificationButton extends StatelessWidget {
  final bool isDark;
  final int count;
  final VoidCallback onTap;

  const HomeNotificationButton({
    super.key,
    required this.isDark,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 40,
      left: 20,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: BoxDecoration(
              color:
                  (isDark ? Colors.white : primaryBlue).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: (isDark ? Colors.white : primaryBlue)
                    .withValues(alpha: 0.2),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: primaryBlue.withValues(alpha: 0.1),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Icon(
                    Icons.notifications_rounded,
                    color: isDark ? Colors.white : primaryBlue,
                    size: 26,
                  ),
                ),
              ),
            ),
          ),
          if (count > 0)
            Positioned(
              right: 6,
              top: 6,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(10),
                ),
                constraints: const BoxConstraints(
                  minWidth: 16,
                  minHeight: 16,
                ),
                child: Text(
                  count > 99 ? '99+' : '$count',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Warning banner shown when user hasn't created a ToDo.
class TodoWarningBanner extends StatelessWidget {
  final VoidCallback onTap;

  const TodoWarningBanner({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          color: const Color.fromARGB(255, 243, 106, 2),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          child: const Row(
            children: [
              Icon(Icons.warning, color: Colors.white),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  "You have not created a ToDo!",
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 15),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Animated logo with swing animation.
class SwingingLogo extends StatelessWidget {
  final Animation<double> swingAnimation;
  final VoidCallback onTap;
  final bool isDark;

  const SwingingLogo({
    super.key,
    required this.swingAnimation,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      margin: const EdgeInsets.only(bottom: 32),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: isDark ? 0.05 : 0.7),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: primaryBlue.withValues(alpha: isDark ? 0.2 : 0.08),
            blurRadius: 40,
            offset: const Offset(0, 16),
            spreadRadius: 0,
          ),
          BoxShadow(
            color: primaryGreen.withValues(alpha: isDark ? 0.1 : 0.05),
            blurRadius: 30,
            offset: const Offset(-10, -10),
            spreadRadius: 0,
          ),
        ],
        border: Border.all(
          color: (isDark ? Colors.white : primaryBlue).withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedBuilder(
          animation: swingAnimation,
          builder: (context, child) {
            final double maxAngle = 0.18;
            final double damping = 3.5;
            final double frequency = 3.5;
            double t = swingAnimation.value;
            double angle =
                maxAngle * exp(-damping * t) * sin(frequency * pi * t);
            return Transform.rotate(
              angle: angle,
              alignment: Alignment.topCenter,
              child: child,
            );
          },
          child: Image.asset(
            'assets/images/logo.png',
            width: 140,
            height: 140,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}

/// Container holding the main action buttons with neumorphic style.
class HomeButtonsContainer extends StatefulWidget {
  final String? role;
  final bool isDark;
  final ValueChanged<int>? onPageChanged;
  final int taskCount;
  final int complaintCount;

  const HomeButtonsContainer({
    super.key,
    required this.role,
    required this.isDark,
    this.onPageChanged,
    this.taskCount = 0,
    this.complaintCount = 0,
  });

  @override
  State<HomeButtonsContainer> createState() => _HomeButtonsContainerState();
}

class _HomeButtonsContainerState extends State<HomeButtonsContainer> {
  late PageController _pageController;
  int _currentPageIndex =
      1000; // Initialize to a large value for infinite sliding

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentPageIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _navigateToSupersale(BuildContext context) async {
    final cache = UserCacheService.instance;
    await cache.ensureLoaded();
    if (!context.mounted) return;
    final role = cache.role;

    if (role == 'supersale_admin') {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const LoadingOverlayPage(
            child: SupersalePage(),
          ),
        ),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const LoadingOverlayPage(
            child: SupersaleUserMainPage(),
          ),
        ),
      );
    }
  }

  Future<void> _navigateToSupersaleDashboard(BuildContext context) async {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const LoadingOverlayPage(
          child: SupersaleAdminDashboard(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final role = widget.role;

    if (role == 'supersale_admin') {
      return _buildSupersaleAdminTiles(context);
    }
    if (role == 'core_team') {
      return _buildCoreTeamTiles(context);
    }
    if (role == 'sme' || role == 'dme_admin' || role == 'dme_user') {
      return _buildOriginalHomePage(context);
    }

    // Height to accommodate 3 rows of buttons + spacing + shadows
    const double pageViewHeight = 280.0;

    return SizedBox(
      height: pageViewHeight,
      child: PageView.builder(
        controller: _pageController,
        clipBehavior: Clip.none,
        onPageChanged: (index) {
          setState(() {
            _currentPageIndex = index;
          });
          if (widget.onPageChanged != null) {
            widget.onPageChanged!(index);
          }
        },
        itemBuilder: (context, index) {
          final pageNum = index % 2;
          if (pageNum == 0) {
            return _buildOriginalHomePage(context);
          } else {
            return _buildSupersalePage(context);
          }
        },
      ),
    );
  }

  /// Lays out a list of button widgets in a 2-column grid.
  /// If the last row has only 1 button it takes the full width.
  Widget _buildButtonGrid(List<Widget> buttons) {
    final List<Widget> rows = [];
    for (int i = 0; i < buttons.length; i += 2) {
      final bool isLastOdd = i + 1 >= buttons.length;
      if (isLastOdd) {
        // Single button: expand full width
        rows.add(buttons[i]);
      } else {
        rows.add(Row(
          children: [
            Expanded(child: buttons[i]),
            const SizedBox(width: 14),
            Expanded(child: buttons[i + 1]),
          ],
        ));
      }
      if (i + 2 < buttons.length) {
        rows.add(const SizedBox(height: 14));
      }
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: rows),
    );
  }

  Widget _buildCoreTeamTiles(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Expanded(
            child: NeumorphicButton(
              onTap: () => _navigateToTodo(context),
              text: 'Todo List',
              color: primaryBlue,
              textColor: Colors.white,
              icon: Icons.check_circle_outline_rounded,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: NeumorphicButton(
              onTap: () => _navigateToCoreTeamTasks(context),
              text: 'Tasks',
              color: primaryGreen,
              textColor: Colors.white,
              icon: Icons.assignment_rounded,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _navigateToCoreTeamTasks(BuildContext context) async {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const LoadingOverlayPage(
          child: CoreTeamTaskPage(),
        ),
      ),
    );
  }

  Widget _buildSupersaleAdminTiles(BuildContext context) {
    final List<Widget> buttons = [
      NeumorphicButton(
        onTap: () => _navigateToSupersale(context),
        text: 'Supersale',
        color: const Color(0xFFFF5722), // Vibrant deep orange
        textColor: Colors.white,
        icon: Icons.flash_on_rounded,
      ),
      NeumorphicButton(
        onTap: () => _navigateToSupersaleDashboard(context),
        text: 'Dashboard',
        color: primaryGreen,
        textColor: Colors.white,
        icon: Icons.dashboard_rounded,
      ),
      NeumorphicButton(
        onTap: () => _navigateToMarketing(context),
        text: 'Marketing',
        color: primaryBlue.withBlue(180),
        textColor: Colors.white,
        icon: Icons.campaign_rounded,
      ),
    ];
    return _buildButtonGrid(buttons);
  }

  Widget _buildSupersalePage(BuildContext context) {
    final role = widget.role;

    final List<Widget> buttons = [
      // Button 1 (Row 1 Left): Marketing (hidden for dme_admin, dme_user, sync_head, sme)
      if (role != 'dme_admin' && role != 'dme_user' && role != 'sync_head' && role != 'sme')
        NeumorphicButton(
          onTap: () => _navigateToMarketing(context),
          text: 'Marketing',
          color: const Color(0xFFFF5722),
          textColor: Colors.white,
          icon: Icons.campaign_rounded,
        ),
      if (role == 'sales' || role == 'admin' || role == 'manager' || role == 'asst_manager')
        NeumorphicButton(
          onTap: () => _navigateToOrders(context),
          text: 'Orders',
          color: primaryGreen,
          textColor: Colors.white,
          icon: Icons.inventory_2_rounded,
        ),
      if (role == 'sync_head')
        NeumorphicButton(
          onTap: () => _navigateToTransferCallList(context),
          text: 'Transfer Call List',
          color: primaryBlue,
          textColor: Colors.white,
          icon: Icons.phone_forwarded_rounded,
        ),
      if (role == 'manager' || role == 'asst_manager')
        NeumorphicButton(
          onTap: () => _navigateToDashboard(context),
          text: 'Dashboard',
          color: primaryBlue,
          textColor: Colors.white,
          icon: Icons.dashboard_rounded,
        ),
    ];

    return _buildButtonGrid(buttons);
  }

  Widget _buildOriginalHomePage(BuildContext context) {
    final role = widget.role;

    if (role == 'sync_head') {
      return _buildSyncHeadTiles(context);
    }
    if (role == 'sme') {
      return _buildSmeTiles(context);
    }
    if (role == 'dme_user') {
      return _buildDmeUserTiles(context);
    }
    if (role == 'dme_admin') {
      return _buildDmeAdminTiles(context);
    }

    // Build button list based on role — always show 6 buttons
    // Left buttons (even indices: 0, 2, 4) will be primaryBlue
    // Right buttons (odd indices: 1, 3, 5) will be primaryGreen
    final List<Widget> buttons = [
      // Button 1 (Row 1 Left): Leads
      NeumorphicButton(
        onTap: () => _navigateToLeads(context),
        onLongPress: role == 'admin'
            ? () => _navigateToSyncHeadLeads(context)
            : null,
        text: 'Leads',
        color: primaryBlue,
        textColor: Colors.white,
        icon: Icons.people_alt_rounded,
      ),
      // Button 2 (Row 1 Right): ToDo List
      NeumorphicButton(
        onTap: () => _navigateToTodo(context),
        onLongPress: role == 'admin'
            ? () => _navigateToSyncHeadTodos(context)
            : null,
        text: 'ToDo List',
        color: primaryGreen,
        textColor: Colors.white,
        icon: Icons.check_circle_outline_rounded,
      ),
      // Button 3 (Row 2 Left): Supersale
      NeumorphicButton(
        onTap: () => _navigateToSupersale(context),
        onLongPress: role == 'admin'
            ? () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const LoadingOverlayPage(
                      child: SupersalePage(),
                    ),
                  ),
                );
              }
            : null,
        text: 'Supersale',
        color: primaryBlue,
        textColor: Colors.white,
        icon: Icons.flash_on_rounded,
      ),
      // Button 4 (Row 2 Right): Customer List
      NeumorphicButton(
        onTap: () => _navigateToCustomerList(context),
        onLongPress: role == 'manager' || role == 'asst_manager'
            ? () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const LoadingOverlayPage(
                      child: CustomerManagerViewerPage(),
                    ),
                  ),
                );
              }
            : null,
        text: 'Customer List',
        color: primaryGreen,
        textColor: Colors.white,
        icon: Icons.assignment_ind_rounded,
      ),
      // Button 5 (Row 3 Left): Dashboard (admin) or SME Leads (manager/asst_manager) or Tasks (sales)
      if (role == 'admin')
        NeumorphicButton(
          onTap: () => _navigateToDashboard(context),
          text: 'Dashboard',
          color: primaryBlue,
          textColor: Colors.white,
          icon: Icons.dashboard_rounded,
        )
      else if (role == 'manager' || role == 'asst_manager')
        NeumorphicButton(
          onTap: () => _navigateToSmeAssignedLeads(context),
          text: 'SME Leads',
          color: primaryBlue,
          textColor: Colors.white,
          icon: Icons.support_agent_rounded,
        )
      else if (role == 'sales')
        NeumorphicButton(
          onTap: () => _navigateToUserTasks(context),
          text: 'Tasks',
          color: primaryBlue,
          textColor: Colors.white,
          icon: Icons.assignment_rounded,
          badgeCount: widget.taskCount,
        ),
      // Button 6 (Row 3 Right): Tasks (admin/manager/asst_manager) or SME Leads (sales)
      if (role == 'admin' || role == 'manager' || role == 'asst_manager')
        NeumorphicButton(
          onTap: () => _navigateToUserTasks(context),
          text: 'Tasks',
          color: primaryGreen,
          textColor: Colors.white,
          icon: Icons.assignment_rounded,
          badgeCount: widget.taskCount,
        )
      else if (role == 'sales')
        NeumorphicButton(
          onTap: () => _navigateToSmeAssignedLeads(context),
          text: 'SME Leads',
          color: primaryGreen,
          textColor: Colors.white,
          icon: Icons.support_agent_rounded,
        ),
    ];

    return _buildButtonGrid(buttons);
  }

  /// Builds the Sync Head-specific home tiles.
  Widget _buildSyncHeadTiles(BuildContext context) {
    final isDark = widget.isDark;
    final List<Widget> buttons = [
      NeumorphicButton(
        onTap: () => _navigateToLeads(context),
        onLongPress: () => _navigateToSyncHeadLeads(context),
        text: 'Leads',
        color: primaryBlue,
        textColor: Colors.white,
        icon: Icons.people_alt_rounded,
      ),
      NeumorphicButton(
        onTap: () => _navigateToSyncHeadTodos(context),
        onLongPress: () => _navigateToSyncHeadReportTodo(context),
        text: 'Todos',
        color: primaryGreen,
        textColor: Colors.white,
        icon: Icons.checklist_rounded,
      ),
      NeumorphicButton(
        onTap: () => _navigateToDashboard(context),
        text: 'Dashboard',
        color: primaryBlue,
        textColor: Colors.white,
        icon: Icons.dashboard_rounded,
      ),
      StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('customer_deletion_requests')
            .where('status', isEqualTo: 'pending')
            .snapshots(),
        builder: (context, snapshot) {
          final pendingCount = snapshot.data?.docs.length ?? 0;
          return NeumorphicButton(
            onTap: () => _navigateToCustomerList(context),
            onLongPress: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const LoadingOverlayPage(
                    child: SyncHeadCustomerListDeletionApprovalPage(),
                  ),
                ),
              );
            },
            text: 'Customer Calling',
            color: primaryGreen,
            textColor: Colors.white,
            icon: Icons.phone_rounded,
            badgeCount: pendingCount > 0 ? pendingCount : null,
          );
        },
      ),
      NeumorphicButton(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const LoadingOverlayPage(
                child: YupulseSyncPage(),
              ),
            ),
          );
        },
        text: 'Yupulse Sync',
        color: isDark ? const Color(0xFF23272A) : Colors.white,
        textColor: isDark ? Colors.white70 : const Color(0xFF607D8B),
        icon: Icons.sync_rounded,
      ),
    ];
    return _buildButtonGrid(buttons);
  }



  /// Builds the SME-specific home tiles.
  Widget _buildSmeTiles(BuildContext context) {
    final List<Widget> buttons = [
      NeumorphicButton(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const LoadingOverlayPage(
                child: SmeLeadsPage(),
              ),
            ),
          );
        },
        text: 'Leads',
        color: primaryBlue,
        textColor: Colors.white,
        icon: Icons.people_alt_rounded,
      ),
      StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('sme_deletion_requests')
            .where('status', isEqualTo: 'pending')
            .snapshots(),
        builder: (context, snapshot) {
          final pendingCount = snapshot.data?.docs.length ?? 0;
          return NeumorphicButton(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const LoadingOverlayPage(
                    child: SmeDashboard(),
                  ),
                ),
              );
            },
            onLongPress: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const LoadingOverlayPage(
                    child: SmeDeletionApprovalPage(),
                  ),
                ),
              );
            },
            text: 'Dashboard',
            color: Colors.teal,
            textColor: Colors.white,
            icon: Icons.dashboard_rounded,
            badgeCount: pendingCount > 0 ? pendingCount : null,
          );
        },
      ),
      NeumorphicButton(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const LoadingOverlayPage(
                child: SmeAdsPage(),
              ),
            ),
          );
        },
        text: 'Ads',
        color: primaryGreen,
        textColor: Colors.white,
        icon: Icons.campaign_rounded,
      ),
    ];
    return _buildButtonGrid(buttons);
  }

  /// Builds the DME User-specific home tiles (Upload, Customers, Complaints, Leads).
  Widget _buildDmeUserTiles(BuildContext context) {
    return buildDmeUserTiles(context);
  }

  /// Builds the DME Admin-specific home tiles.
  Widget _buildDmeAdminTiles(BuildContext context) {
    return buildDmeAdminTiles(context);
  }

  Future<void> _navigateToSyncHeadLeads(BuildContext context) async {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const LoadingOverlayPage(
          child: SyncHeadLeadsPage(),
        ),
      ),
    );
  }

  Future<void> _navigateToSyncHeadTodos(BuildContext context) async {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const LoadingOverlayPage(
          child: SyncHeadTodosPage(),
        ),
      ),
    );
  }

  Future<void> _navigateToTransferCallList(BuildContext context) async {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const LoadingOverlayPage(
          child: TransferCallListPage(),
        ),
      ),
    );
  }

  Future<void> _navigateToSyncHeadReportTodo(BuildContext context) async {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const LoadingOverlayPage(
          child: SyncHeadReportTodoPage(),
        ),
      ),
    );
  }

  Future<void> _navigateToLeads(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      handleFirebaseAuthError(context,
          FirebaseException(plugin: 'firestore', code: 'unauthenticated'));
      return;
    }

    String? branch;
    try {
      final cache = UserCacheService.instance;
      await cache.ensureLoaded();
      branch = cache.branch;
    } catch (e) {
      if (handleFirebaseAuthError(context, e)) return;
      rethrow;
    }

    if (branch != null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => LoadingOverlayPage(
            child: LeadsPage(branch: branch!),
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Branch not found for user')),
      );
    }
  }

  Future<void> _navigateToOrders(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      handleFirebaseAuthError(context,
          FirebaseException(plugin: 'firestore', code: 'unauthenticated'));
      return;
    }

    String? branch;
    try {
      final cache = UserCacheService.instance;
      await cache.ensureLoaded();
      branch = cache.branch;
    } catch (e) {
      if (handleFirebaseAuthError(context, e)) return;
      rethrow;
    }

    if (branch != null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => LoadingOverlayPage(
            child: OrdersPage(branch: branch!),
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Branch not found for user')),
      );
    }
  }

  Future<void> _navigateToTodo(BuildContext context) async {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const LoadingOverlayPage(
          child: TodoPage(),
        ),
      ),
    );
  }

  Future<void> _navigateToUserTasks(BuildContext context) async {
    final cache = UserCacheService.instance;
    await cache.ensureLoaded();
    if (!context.mounted) return;
    final role = cache.role;

    if (role == 'admin' || role == 'core_team') {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const LoadingOverlayPage(
            child: CoreTeamTaskPage(),
          ),
        ),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const LoadingOverlayPage(
            child: UserTaskPage(),
          ),
        ),
      );
    }
  }

  Future<void> _navigateToMarketing(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      handleFirebaseAuthError(context,
          FirebaseException(plugin: 'firestore', code: 'unauthenticated'));
      return;
    }

    String? branch, username, userid, role;
    try {
      final cache = UserCacheService.instance;
      await cache.ensureLoaded();
      branch = cache.branch;
      username = cache.username;
      userid = user.uid;
      role = cache.role;
    } catch (e) {
      if (handleFirebaseAuthError(context, e)) return;
      rethrow;
    }

    if (role == 'admin' || role == 'Sync Head' || role == 'sync_head' || role == 'supersale_admin') {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const LoadingOverlayPage(
            child: ViewerMarketingPage(),
          ),
        ),
      );
    } else if (branch != null && username != null && userid != null) {
      // Save navigation state for activity recreation recovery
      await NavigationState.saveState('marketing', userData: {
        'username': username,
        'userid': userid,
        'branch': branch,
      });
      Navigator.of(context)
          .push(
        MaterialPageRoute(
          builder: (_) => LoadingOverlayPage(
            child: MarketingFormPage(
              username: username ?? '',
              userid: userid ?? '',
              branch: branch ?? '',
            ),
          ),
        ),
      )
          .then((_) {
        // Clear navigation state when user returns from marketing
        NavigationState.clearState();
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User info not found')),
      );
    }
  }

  Future<void> _navigateToCustomerList(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      handleFirebaseAuthError(context,
          FirebaseException(plugin: 'firestore', code: 'unauthenticated'));
      return;
    }

    String? role;
    try {
      final cache = UserCacheService.instance;
      await cache.ensureLoaded();
      role = cache.role;
    } catch (e) {
      if (handleFirebaseAuthError(context, e)) return;
      rethrow;
    }

    if (role == 'admin' || role == 'Sync Head' || role == 'sync_head') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const LoadingOverlayPage(
            child: CustomerAdminViewerPage(),
          ),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const LoadingOverlayPage(
            child: CustomerListTarget(),
          ),
        ),
      );
    }
  }

  Future<void> _navigateToDashboard(BuildContext context) async {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const LoadingOverlayPage(
          child: DashboardPage(),
        ),
      ),
    );
  }

  Future<void> _navigateToSmeAssignedLeads(BuildContext context) async {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const LoadingOverlayPage(
          child: SmeAssignedLeadsPage(),
        ),
      ),
    );
  }
}
