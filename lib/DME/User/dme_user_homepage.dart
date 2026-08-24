import 'package:flutter/material.dart';
import '../dme_excel_uploader.dart';
import 'dme_reminders_page.dart';
import '../Admin/dme_admin_customers_page.dart';
import '../Admin/dme_admin_dashboard_page.dart';
import '../../Homepage/home_widgets.dart';
import '../../Navigation/loading_page.dart';

const Color primaryBlue = Color(0xFF005BAC);
const Color primaryGreen = Color(0xFF8CC63F);

class DmeUserHomePage extends StatelessWidget {
  const DmeUserHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return buildDmeUserTiles(context);
  }
}

/// Builds the DME User buttons: Upload, Reminders, Customers, Dashboard, Complaints, Leads
Widget buildDmeUserTiles(BuildContext context) {
  final List<Widget> buttons = [
    // 1. Upload
    NeumorphicButton(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const LoadingOverlayPage(
              child: DmeExcelUploaderPage(),
            ),
          ),
        );
      },
      text: 'Upload',
      color: primaryBlue,
      textColor: Colors.white,
      icon: Icons.cloud_upload_rounded,
    ),

    // 2. Reminders (Calls Today & Overdue)
    NeumorphicButton(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const LoadingOverlayPage(
              child: DmeRemindersPage(),
            ),
          ),
        );
      },
      text: 'Reminders',
      color: primaryGreen,
      textColor: Colors.white,
      icon: Icons.alarm_on_rounded,
    ),

    // 3. Customers (Assigned Branches only)
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
      color: primaryBlue,
      textColor: Colors.white,
      icon: Icons.people_alt_rounded,
    ),

    // 4. Dashboard (Assigned Branches only)
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
      color: primaryGreen,
      textColor: Colors.white,
      icon: Icons.dashboard_rounded,
    ),

    // 5. Complaints
    NeumorphicButton(
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Complaints module coming soon'),
            duration: Duration(seconds: 1),
          ),
        );
      },
      text: 'Complaints',
      color: primaryBlue,
      textColor: Colors.white,
      icon: Icons.feedback_rounded,
    ),

    // 6. Leads
    NeumorphicButton(
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Leads module coming soon'),
            duration: Duration(seconds: 1),
          ),
        );
      },
      text: 'Leads',
      color: const Color(0xFFFF5722), // Orange
      textColor: Colors.white,
      icon: Icons.trending_up_rounded,
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
