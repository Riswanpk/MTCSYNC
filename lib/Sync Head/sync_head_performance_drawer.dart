import 'package:flutter/material.dart';
import '../Performance/admin_performance_page.dart';
import '../Performance/excel_view_performance.dart';
import '../Performance/insights_performance.dart';
import '../Performance/entry_page.dart';

class SyncHeadPerformancePage extends StatelessWidget {
  const SyncHeadPerformancePage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Performance'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            _PerformanceTile(
              icon: Icons.edit_note,
              iconColor: Colors.deepPurple,
              title: 'Edit Performance Form',
              subtitle: 'Add or edit performance fields',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const AdminPerformancePage()),
              ),
              isDark: isDark,
            ),
            const SizedBox(height: 16),
            _PerformanceTile(
              icon: Icons.insert_chart,
              iconColor: const Color.fromARGB(255, 255, 175, 3),
              title: 'Performance Monthly',
              subtitle: 'View monthly performance reports',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => ExcelViewPerformancePage()),
              ),
              isDark: isDark,
            ),
            const SizedBox(height: 16),
            _PerformanceTile(
              icon: Icons.insights,
              iconColor: Colors.green,
              title: 'Performance Insights',
              subtitle: 'Analyse performance trends',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => InsightsPerformancePage()),
              ),
              isDark: isDark,
            ),
            const SizedBox(height: 16),
            _PerformanceTile(
              icon: Icons.add_box,
              iconColor: Colors.blue,
              title: 'Entry Page',
              subtitle: 'Submit a new performance entry',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => EntryPage()),
              ),
              isDark: isDark,
            ),
          ],
        ),
      ),
    );
  }
}

class _PerformanceTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isDark;

  const _PerformanceTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isDark ? const Color(0xFF1E2A3A) : Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 2,
      shadowColor: Colors.black.withOpacity(0.08),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white54 : Colors.black45,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios,
                  size: 14,
                  color: isDark ? Colors.white38 : Colors.black26),
            ],
          ),
        ),
      ),
    );
  }
}
