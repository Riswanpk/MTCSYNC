import 'package:flutter/material.dart';
import '../Performance/admin_performance_page.dart';
import '../Performance/excel_view_performance.dart';
import '../Performance/insights_performance.dart';
import '../Performance/entry_page.dart';

const Color _primaryBlue = Color(0xFF005BAC);
const Color _darkSurface = Color(0xFF1E2028);
const Color _darkCard = Color(0xFF252830);

class SyncHeadPerformancePage extends StatelessWidget {
  const SyncHeadPerformancePage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final tiles = [
      _TileData(
        icon: Icons.edit_note_rounded,
        gradient: const LinearGradient(colors: [Color(0xFF6A11CB), Color(0xFF9C27B0)]),
        title: 'Edit Performance Form',
        subtitle: 'Add or edit performance fields',
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const AdminPerformancePage())),
      ),
      _TileData(
        icon: Icons.insert_chart_rounded,
        gradient: const LinearGradient(colors: [Color(0xFFFF8F00), Color(0xFFFFC107)]),
        title: 'Performance Monthly',
        subtitle: 'View monthly performance reports',
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => ExcelViewPerformancePage())),
      ),
      _TileData(
        icon: Icons.insights_rounded,
        gradient: const LinearGradient(colors: [Color(0xFF1B5E20), Color(0xFF8CC63F)]),
        title: 'Performance Insights',
        subtitle: 'Analyse performance trends',
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => InsightsPerformancePage())),
      ),
      _TileData(
        icon: Icons.add_box_rounded,
        gradient: const LinearGradient(colors: [Color(0xFF003D73), _primaryBlue]),
        title: 'Entry Page',
        subtitle: 'Submit a new performance entry',
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => EntryPage())),
      ),
    ];

    return Scaffold(
      backgroundColor: isDark ? _darkSurface : const Color(0xFFF5F7FA),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 160,
            pinned: true,
            backgroundColor: _primaryBlue,
            foregroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF003D73), _primaryBlue, Color(0xFF0078E7)],
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 36),
                      Container(
                        width: 56, height: 56,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(Icons.bar_chart_rounded, color: Colors.white, size: 32),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Performance',
                        style: TextStyle(
                          fontSize: 22, fontWeight: FontWeight.bold,
                          color: Colors.white, letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Manage & review team performance',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              collapseMode: CollapseMode.pin,
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, idx) {
                  final tile = tiles[idx];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _PerformanceTile(data: tile, isDark: isDark),
                  );
                },
                childCount: tiles.length,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TileData {
  final IconData icon;
  final LinearGradient gradient;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _TileData({
    required this.icon,
    required this.gradient,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
}

class _PerformanceTile extends StatelessWidget {
  final _TileData data;
  final bool isDark;

  const _PerformanceTile({required this.data, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isDark ? _darkCard : Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: isDark ? 0 : 2,
      shadowColor: Colors.black.withValues(alpha: 0.06),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: data.onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              // Gradient icon container
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  gradient: data.gradient,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: data.gradient.colors.first.withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(data.icon, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 18),
              // Text
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.title,
                      style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      data.subtitle,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: isDark ? Colors.white54 : Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),
              // Chevron
              Container(
                width: 30, height: 30,
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.grey.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: isDark ? Colors.white38 : Colors.grey[400],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
