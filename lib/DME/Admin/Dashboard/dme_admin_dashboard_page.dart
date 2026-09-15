import 'package:flutter/material.dart';
import 'pages/dme_visit_analytics_page.dart';
import 'widgets/dashboard_option_card.dart';
import 'Reports/dme_new_customers_report_page.dart';
import 'Reports/dme_call_report_page.dart';
import 'Reports/dme_excel_upload_report_page.dart';

const Color _primaryBlue = Color(0xFF005BAC);
const Color _primaryGreen = Color(0xFF8CC63F);
const Color _whatsappGreen = Color(0xFF25D366);

class DmeAdminDashboardPage extends StatelessWidget {
  final List<int>? userAssignedBranches;

  const DmeAdminDashboardPage({
    super.key,
    this.userAssignedBranches,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'DME Dashboard',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: _primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome / Description Banner
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _primaryBlue,
                    _primaryBlue.withValues(alpha: 0.82),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: _primaryBlue.withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.dashboard_rounded,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'DME Dashboard & Reports',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Access visit analytics, new customer lists, and live calling & WhatsApp statistics.',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            Text(
              'Dashboard Modules',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 14),

            // 1. Visit Analytics Card Button
            DashboardOptionCard(
              title: 'Visit Analytics',
              subtitle:
                  'Comprehensive overview of customer visits, branch performance, category trends, and completed reminders.',
              icon: Icons.analytics_rounded,
              accentColor: _primaryBlue,
              badgeText: 'Overview & Charts',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DmeVisitAnalyticsPage(
                      userAssignedBranches: userAssignedBranches,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),

            // 2. New Customers Report Card Button
            DashboardOptionCard(
              title: 'New Customers',
              subtitle:
                  'Generate and share customized Excel reports of newly visited customers across branches with purchase dates, categories, and types.',
              icon: Icons.table_chart_rounded,
              accentColor: _primaryGreen,
              badgeText: 'Excel Export',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DmeNewCustomersReportPage(
                      userAssignedBranches: userAssignedBranches,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),

            // 3. DME Call Report Card Button
            DashboardOptionCard(
              title: 'DME Call Report',
              subtitle:
                  'View call statistics & WhatsApp message volume of DME users within any time interval. Inspect day-by-day customer calling breakdowns.',
              icon: Icons.phone_in_talk_rounded,
              accentColor: _primaryBlue,
              secondaryIcon: Icons.chat_bubble_rounded,
              secondaryColor: _whatsappGreen,
              badgeText: 'Live Statistics',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DmeCallReportPage(
                      userAssignedBranches: userAssignedBranches,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),

            // 4. Excel Upload Report Card Button
            DashboardOptionCard(
              title: 'Excel Upload Report',
              subtitle:
                  'Audit and inspect every uploaded Excel transaction batch. View file hashes, dates, uploader details, synced sales & raw row volumes.',
              icon: Icons.upload_file_rounded,
              accentColor: Colors.deepPurple,
              badgeText: 'Upload Logs & Audit',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const DmeExcelUploadReportPage(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
