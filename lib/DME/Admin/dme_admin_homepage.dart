import 'package:flutter/material.dart';
import 'dme_user_management_page.dart';
import 'Customer Directory/dme_admin_customers_page.dart';
import 'Dashboard/dme_admin_dashboard_page.dart';
import 'Reminder/dme_admin_reminders_page.dart';
import 'Reminder/dme_admin_reminder_assign_page.dart';
import '../Complaints/Admin/dme_admin_complaints_page.dart';
import '../../Homepage/home_widgets.dart';
import '../../Navigation/loading_page.dart';

const Color primaryBlue = Color(0xFF005BAC);
const Color primaryGreen = Color(0xFF8CC63F);

class DmeAdminHomePage extends StatelessWidget {
  const DmeAdminHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return buildDmeAdminTiles(context);
  }
}

/// Builds the DME Admin tiles:
/// Row 1: Customers (Primary Green), Dashboard (Primary Blue)
/// Row 2: Complaints (Primary Green), Manage Users (Primary Blue)
/// Row 3: Reminders (Primary Green), Reminder Assign (Primary Blue)
Widget buildDmeAdminTiles(BuildContext context) {
  final List<Widget> buttons = [
    // 1. Customers
    NeumorphicButton(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const LoadingOverlayPage(
              child: DmeAdminCustomersPage(),
            ),
          ),
        );
      },
      text: 'Customers',
      color: primaryGreen,
      textColor: Colors.white,
      icon: Icons.people_alt_rounded,
    ),

    // 2. Dashboard
    NeumorphicButton(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const LoadingOverlayPage(
              child: DmeAdminDashboardPage(),
            ),
          ),
        );
      },
      text: 'Dashboard',
      color: primaryBlue,
      textColor: Colors.white,
      icon: Icons.dashboard_rounded,
    ),

    // 3. Complaints
    NeumorphicButton(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const LoadingOverlayPage(
              child: DmeAdminComplaintsPage(),
            ),
          ),
        );
      },
      text: 'Complaints',
      color: primaryGreen,
      textColor: Colors.white,
      icon: Icons.feedback_rounded,
    ),

    // 4. User Management (Assign Branches)
    NeumorphicButton(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const LoadingOverlayPage(
              child: DmeUserManagementPage(),
            ),
          ),
        );
      },
      text: 'Manage Users',
      color: primaryBlue,
      textColor: Colors.white,
      icon: Icons.manage_accounts_rounded,
    ),

    // 5. Reminders Management (By Branch / By User)
    NeumorphicButton(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const LoadingOverlayPage(
              child: DmeAdminRemindersPage(),
            ),
          ),
        );
      },
      text: 'Reminders',
      color: primaryGreen,
      textColor: Colors.white,
      icon: Icons.notifications_active_rounded,
    ),

    // 6. Reminder Assign (Daily User Selection & Division)
    NeumorphicButton(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const LoadingOverlayPage(
              child: DmeAdminReminderAssignPage(),
            ),
          ),
        );
      },
      text: 'Reminder Assign',
      color: primaryBlue,
      textColor: Colors.white,
      icon: Icons.assignment_ind_rounded,
    ),
  ];

  return Column(
    children: [
      Row(
        children: [
          Expanded(child: buttons[0]),
          const SizedBox(width: 16),
          Expanded(child: buttons[1]),
        ],
      ),
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(child: buttons[2]),
          const SizedBox(width: 16),
          Expanded(child: buttons[3]),
        ],
      ),
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(child: buttons[4]),
          const SizedBox(width: 16),
          Expanded(child: buttons[5]),
        ],
      ),
    ],
  );
}
