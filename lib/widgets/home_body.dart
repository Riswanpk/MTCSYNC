import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math';
import '../Misc/auth_wrapper.dart';
import '../Misc/navigation_state.dart';
import '../Misc/user_cache_service.dart';
import '../Customer Target/customer_manager_view.dart';
import '../Todo/todo.dart';
import '../Leads/leads.dart';
import '../Todo/todoform.dart';
import '../Dashboard/dashboard.dart';
import '../Marketing/marketing.dart';
import '../Marketing/viewer_marketing.dart';
import '../Customer Target/customer_list_target.dart';
import '../Customer Target/customer_admin_viewer.dart';
import '../Misc/loading_page.dart';
import '../Todo/todo_widget_updater.dart';
import 'home_widgets.dart';
import '../Sync Head/sync_head_leads_page.dart';
import '../Sync Head/sync_head_todos_page.dart';

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
                  primaryBlue.withOpacity(0.05),
                  Colors.white,
                  primaryGreen.withOpacity(0.08),
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
            color: (isDark ? Colors.white : primaryBlue).withOpacity(0.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: (isDark ? Colors.white : primaryBlue).withOpacity(0.2),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: primaryBlue.withOpacity(0.1),
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
        color: Colors.white.withOpacity(isDark ? 0.05 : 0.7),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: primaryBlue.withOpacity(isDark ? 0.2 : 0.08),
            blurRadius: 40,
            offset: const Offset(0, 16),
            spreadRadius: 0,
          ),
          BoxShadow(
            color: primaryGreen.withOpacity(isDark ? 0.1 : 0.05),
            blurRadius: 30,
            offset: const Offset(-10, -10),
            spreadRadius: 0,
          ),
        ],
        border: Border.all(
          color: (isDark ? Colors.white : primaryBlue).withOpacity(0.1),
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
class HomeButtonsContainer extends StatelessWidget {
  final String? role;
  final bool isDark;

  const HomeButtonsContainer({
    super.key,
    required this.role,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    // Sync Head has a completely different homepage
    if (role == 'sync_head') {
      return _buildSyncHeadTiles(context);
    }

    return Column(
      children: [
        // Row 1: Leads & ToDo (logo colors)
        Row(
          children: [
            Expanded(
              child: NeumorphicButton(
                onTap: () => _navigateToLeads(context),
                text: 'Leads',
                color: primaryBlue,
                textColor: Colors.white,
                icon: Icons.people_alt_rounded,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: NeumorphicButton(
                onTap: () => _navigateToTodo(context),
                text: 'ToDo List',
                color: primaryGreen,
                textColor: Colors.white,
                icon: Icons.check_circle_outline_rounded,
              ),
            ),
          ],
        ),
        // Sales-specific buttons
        if (role == 'sales') ...[
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: NeumorphicButton(
                  onTap: () => _navigateToMarketing(context),
                  text: 'Marketing',
                  color: primaryBlue.withBlue(180), // Lighter blue variant
                  textColor: Colors.white,
                  icon: Icons.campaign_rounded,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: NeumorphicButton(
                  onTap: () => _navigateToCustomerList(context),
                  text: 'Customer List',
                  color: primaryGreen.withGreen(220), // Lighter green variant
                  textColor: Colors.white,
                  icon: Icons.assignment_ind_rounded,
                  textStyle: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    letterSpacing: 0.6,
                    color: Colors.white,
                    fontFamily: 'Montserrat',
                    shadows: [
                      Shadow(
                        color: Colors.black.withOpacity(0.25),
                        offset: const Offset(0, 1),
                        blurRadius: 3,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
        // Admin/Manager buttons
        if (role == 'admin' || role == 'manager') ...[
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: NeumorphicButton(
                  onTap: () => _navigateToDashboard(context),
                  text: 'Dashboard',
                  color: primaryGreen, // Green like ToDo List
                  textColor: Colors.white,
                  icon: Icons.dashboard_rounded,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: NeumorphicButton(
                  onTap: () => _navigateToMarketing(context),
                  text: 'Marketing',
                  color: primaryBlue.withBlue(180),
                  textColor: Colors.white,
                  icon: Icons.campaign_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          NeumorphicButton(
            onTap: () => _navigateToCustomerList(context),
            onLongPress: role == 'manager'
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
            color: isDark ? const Color(0xFF23272A) : Colors.white,
            textColor: isDark ? Colors.white : primaryBlue,
            icon: Icons.assignment_ind_rounded,
          ),
        ],
      ],
    );
  }

  /// Builds the Sync Head-specific home tiles.
  Widget _buildSyncHeadTiles(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: NeumorphicButton(
                onTap: () => _navigateToSyncHeadLeads(context),
                text: 'Leads',
                color: primaryBlue,
                textColor: Colors.white,
                icon: Icons.bar_chart_rounded,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: NeumorphicButton(
                onTap: () => _navigateToSyncHeadTodos(context),
                text: 'Todos',
                color: primaryGreen,
                textColor: Colors.white,
                icon: Icons.checklist_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        NeumorphicButton(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const LoadingOverlayPage(
                  child: CustomerAdminViewerPage(hideActions: true),
                ),
              ),
            );
          },
          text: 'Customer Calling',
          color: isDark ? const Color(0xFF23272A) : Colors.white,
          textColor: isDark ? Colors.white70 : const Color(0xFF607D8B),
          icon: Icons.phone_rounded,
        ),
      ],
    );
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

  Future<void> _navigateToLeads(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      handleFirebaseAuthError(context, FirebaseException(plugin: 'firestore', code: 'unauthenticated'));
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

  Future<void> _navigateToTodo(BuildContext context) async {
    await updateTodoWidgetFromFirestore();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const LoadingOverlayPage(
          child: TodoPage(),
        ),
      ),
    );
  }

  Future<void> _navigateToMarketing(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      handleFirebaseAuthError(context, FirebaseException(plugin: 'firestore', code: 'unauthenticated'));
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

    if (role == 'admin') {
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
        'username': username ?? '',
        'userid': userid ?? '',
        'branch': branch ?? '',
      });
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => LoadingOverlayPage(
            child: MarketingFormPage(
              username: username ?? '',
              userid: userid ?? '',
              branch: branch ?? '',
            ),
          ),
        ),
      ).then((_) {
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
      handleFirebaseAuthError(context, FirebaseException(plugin: 'firestore', code: 'unauthenticated'));
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

    if (role == 'admin') {
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
}
