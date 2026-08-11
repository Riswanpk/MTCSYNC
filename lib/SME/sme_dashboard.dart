import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'sme_daily_dashboard.dart';
import 'sme_user_stats_dashboard.dart';
import 'sme_dashboard_total_leads_page.dart';
import 'sme_report.dart';
import 'sme_ad_wise_report.dart';

const Color _primaryBlue = Color(0xFF005BAC);

const List<List<Color>> _cardGradients = [
  [Color(0xFF4A90D9), Color(0xFF005BAC)], // Total
  [Color(0xFF26A69A), Color(0xFF00695C)], // Today
  [Color(0xFF66BB6A), Color(0xFF2E7D32)], // Promoted
  [Color(0xFFEF5350), Color(0xFFC62828)], // Rejected
  [Color(0xFF42A5F5), Color(0xFF1565C0)], // Sold
  [Color(0xFFFFA726), Color(0xFFE65100)], // Cancelled
];

const List<List<Color>> _cardGradientsDark = [
  [Color(0xFF1565C0), Color(0xFF0D47A1)],
  [Color(0xFF00897B), Color(0xFF004D40)],
  [Color(0xFF2E7D32), Color(0xFF1B5E20)],
  [Color(0xFFC62828), Color(0xFF8E0000)],
  [Color(0xFF1565C0), Color(0xFF0D47A1)],
  [Color(0xFFE65100), Color(0xFFBF360C)],
];

class SmeDashboard extends StatefulWidget {
  const SmeDashboard({super.key});

  @override
  State<SmeDashboard> createState() => _SmeDashboardState();
}

class _SmeDashboardState extends State<SmeDashboard>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeIn;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeIn = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _fetchCounts() async {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final monthEnd = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('follow_ups')
          .where('source', whereIn: ['sme', 'SME'])
          .where('created_at', isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
          .where('created_at', isLessThanOrEqualTo: Timestamp.fromDate(monthEnd))
          .get();

      int totalLeads = snapshot.docs.length;
      int todayLeads = 0;
      int promotedLeads = 0;
      int rejectedLeads = 0;
      int soldLeads = 0;
      int cancelledLeads = 0;

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final branch = (data['branch'] ?? '').toString().trim().toLowerCase();
        if (branch == 'admin') {
          totalLeads--;
          continue;
        }

        final createdAt = data['created_at'] as Timestamp?;
        final screeningStatus = (data['screening_status'] ?? '').toString();
        final status = (data['status'] ?? '').toString();

        if (createdAt != null) {
          final createdDate = createdAt.toDate();
          if (createdDate.isAfter(todayStart) && createdDate.isBefore(todayEnd)) {
            todayLeads++;
          }
        }

        if (screeningStatus == 'promoted') {
          promotedLeads++;
        } else if (screeningStatus == 'rejected') {
          rejectedLeads++;
        }

        if (status == 'Sale') {
          soldLeads++;
        } else if (status == 'Cancelled') {
          cancelledLeads++;
        }
      }

      final conversionRate =
          totalLeads > 0 ? (soldLeads / totalLeads * 100).toStringAsFixed(1) : '0.0';

      return {
        'totalLeads': totalLeads,
        'todayLeads': todayLeads,
        'promotedLeads': promotedLeads,
        'rejectedLeads': rejectedLeads,
        'soldLeads': soldLeads,
        'cancelledLeads': cancelledLeads,
        'conversionRate': conversionRate,
      };
    } catch (e) {
      return {
        'totalLeads': 0,
        'todayLeads': 0,
        'promotedLeads': 0,
        'rejectedLeads': 0,
        'soldLeads': 0,
        'cancelledLeads': 0,
        'conversionRate': '0.0'
      };
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? const Color(0xFF1A1B22) : const Color(0xFFF5F7FA);

    return Scaffold(
      backgroundColor: surfaceColor,
      body: FadeTransition(
        opacity: _fadeIn,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverAppBar(
              expandedHeight: 120,
              floating: false,
              pinned: true,
              elevation: 0,
              backgroundColor: isDark ? const Color(0xFF1A1B22) : Colors.white,
              surfaceTintColor: Colors.transparent,
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
                title: Text(
                  'SME Dashboard',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF1A1B22),
                    letterSpacing: -0.3,
                  ),
                ),
                background: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isDark
                          ? [const Color(0xFF1A1B22), const Color(0xFF23242B)]
                          : [Colors.white, const Color(0xFFF0F4FF)],
                    ),
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  const SizedBox(height: 8),

                  // Stat Cards Grid
                  FutureBuilder<Map<String, dynamic>>(
                    future: _fetchCounts(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const SizedBox(
                          height: 200,
                          child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
                        );
                      }
                      final counts = snapshot.data!;
                      final cards = [
                        _CardData('Total Leads', counts['totalLeads'].toString(), Icons.leaderboard_rounded, 0,
                            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SmeAllLeadsPage()))),
                        _CardData('Today Leads', counts['todayLeads'].toString(), Icons.today_rounded, 1,
                            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SmeDailyDashboard()))),
                        _CardData('Promoted', counts['promotedLeads'].toString(), Icons.check_circle_rounded, 2, null),
                        _CardData('Rejected', counts['rejectedLeads'].toString(), Icons.cancel_rounded, 3, null),
                        _CardData('Sold (${counts['conversionRate']}%)', counts['soldLeads'].toString(), Icons.shopping_bag_rounded, 4, null),
                        _CardData('Cancelled', counts['cancelledLeads'].toString(), Icons.remove_circle_rounded, 5, null),
                      ];

                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 1.35,
                        ),
                        itemCount: cards.length,
                        itemBuilder: (context, index) {
                          final card = cards[index];
                          final gradient = isDark ? _cardGradientsDark[card.colorIndex] : _cardGradients[card.colorIndex];

                          return ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: card.onTap,
                                splashColor: Colors.white.withValues(alpha: 0.15),
                                highlightColor: Colors.white.withValues(alpha: 0.08),
                                child: Ink(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: gradient,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: gradient[1].withValues(alpha: 0.3),
                                        blurRadius: 10,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(6),
                                              decoration: BoxDecoration(
                                                color: Colors.white.withValues(alpha: 0.2),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Icon(card.icon, color: Colors.white, size: 18),
                                            ),
                                            const Spacer(),
                                            if (card.onTap != null)
                                              Icon(Icons.arrow_forward_ios_rounded,
                                                  color: Colors.white.withValues(alpha: 0.6), size: 12),
                                          ],
                                        ),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              card.value,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 22,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: -0.5,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              card.title,
                                              style: TextStyle(
                                                color: Colors.white.withValues(alpha: 0.9),
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 20),

                  // Navigation buttons
                  _navButton(
                    context,
                    'User Assignment Stats',
                    Icons.people_alt_rounded,
                    'Check leads per user with sold/cancelled breakdown',
                    isDark,
                    () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SmeUserStatsDashboard())),
                  ),
                  const SizedBox(height: 12),
                  _navButton(
                    context,
                    'Ad-Wise Reports',
                    Icons.bar_chart_rounded,
                    'View lead analytics and stats based on Ad campaigns',
                    isDark,
                    () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SmeAdWiseReportPage())),
                  ),
                  const SizedBox(height: 12),
                  _navButton(
                    context,
                    'SME Reports & Exports',
                    Icons.assessment_rounded,
                    'Generate and share detailed Excel reports branchwise',
                    isDark,
                    () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SmeReportPage())),
                  ),
                  const SizedBox(height: 24),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _navButton(BuildContext context, String title, IconData icon, String subtitle, bool isDark, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF23242B) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: isDark ? Colors.black26 : Colors.black.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _primaryBlue.withValues(alpha: isDark ? 0.2 : 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: _primaryBlue, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: isDark ? Colors.white : const Color(0xFF1A1B22),
                          )),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white54 : Colors.black45,
                          )),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: isDark ? Colors.white30 : Colors.black26),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CardData {
  final String title;
  final String value;
  final IconData icon;
  final int colorIndex;
  final VoidCallback? onTap;

  _CardData(this.title, this.value, this.icon, this.colorIndex, this.onTap);
}
