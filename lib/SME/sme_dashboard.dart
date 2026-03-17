import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'sme_daily_dashboard.dart';
import 'sme_user_stats_dashboard.dart';
import 'sme_all_leads_page.dart';
import 'sme_all_leads_page.dart';

const Color _primaryBlue = Color(0xFF005BAC);
const Color _primaryGreen = Color(0xFF8CC63F);

const List<List<Color>> _cardGradients = [
  [Color(0xFF4A90D9), Color(0xFF005BAC)],
  [Color(0xFF66BB6A), Color(0xFF2E7D32)],
  [Color(0xFFFFA726), Color(0xFFE65100)],
  [Color(0xFF26A69A), Color(0xFF00695C)],
];

const List<List<Color>> _cardGradientsDark = [
  [Color(0xFF1565C0), Color(0xFF0D47A1)],
  [Color(0xFF2E7D32), Color(0xFF1B5E20)],
  [Color(0xFFE65100), Color(0xFFBF360C)],
  [Color(0xFF00897B), Color(0xFF004D40)],
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
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return {'totalLeads': 0, 'monthLeads': 0, 'todayLeads': 0, 'conversionRate': '0.0'};

    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));

    final baseQuery = FirebaseFirestore.instance
        .collection('follow_ups')
        .where('assigned_by', isEqualTo: uid);

    final results = await Future.wait([
      baseQuery.count().get(),
      baseQuery
          .where('created_at', isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
          .count()
          .get(),
      baseQuery
          .where('created_at', isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart))
          .where('created_at', isLessThan: Timestamp.fromDate(todayEnd))
          .count()
          .get(),
      baseQuery
          .where('status', isEqualTo: 'Sale')
          .count()
          .get(),
    ]);

    final total = (results[0] as AggregateQuerySnapshot).count ?? 0;
    final sold = (results[3] as AggregateQuerySnapshot).count ?? 0;
    final conversionRate = total > 0 ? (sold / total * 100).toStringAsFixed(1) : '0.0';

    return {
      'totalLeads': total,
      'monthLeads': (results[1] as AggregateQuerySnapshot).count ?? 0,
      'todayLeads': (results[2] as AggregateQuerySnapshot).count ?? 0,
      'conversionRate': conversionRate,
    };
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

                  // Stat Cards
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
                        _CardData('Total Leads', counts['totalLeads'].toString(), Icons.leaderboard_rounded, 0),
                        _CardData('This Month', counts['monthLeads'].toString(), Icons.calendar_month_rounded, 1),
                        _CardData('Today', counts['todayLeads'].toString(), Icons.today_rounded, 2),
                        _CardData('Conversion', '${counts['conversionRate']}%', Icons.trending_up_rounded, 3),
                      ];

                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
                          childAspectRatio: 1.3,
                        ),
                        itemCount: cards.length,
                        itemBuilder: (context, index) {
                          final card = cards[index];
                          final gradient = isDark ? _cardGradientsDark[card.colorIndex] : _cardGradients[card.colorIndex];

                          // Determine tap action per card
                          VoidCallback? onTap;
                          if (index == 0) {
                            // Total Leads → all leads page
                            onTap = () => Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => const SmeAllLeadsPage()),
                                );
                          } else if (index == 2) {
                            // Today → daily dashboard
                            onTap = () => Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => const SmeDailyDashboard()),
                                );
                          }

                          return ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: onTap,
                                splashColor: Colors.white.withOpacity(0.15),
                                highlightColor: Colors.white.withOpacity(0.08),
                                child: Ink(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: gradient,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: gradient[1].withOpacity(0.3),
                                        blurRadius: 12,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                color: Colors.white.withOpacity(0.2),
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: Icon(card.icon, color: Colors.white, size: 20),
                                            ),
                                            const Spacer(),
                                            if (onTap != null)
                                              Icon(Icons.arrow_forward_ios_rounded,
                                                  color: Colors.white.withOpacity(0.5), size: 14),
                                          ],
                                        ),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              card.value,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 26,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: -0.5,
                                              ),
                                            ),
                                            Text(
                                              card.title,
                                              style: TextStyle(
                                                color: Colors.white.withOpacity(0.85),
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500,
                                              ),
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
                  const SizedBox(height: 24),

                  // Navigation buttons
                  _navButton(
                    context,
                    'User Assignment Stats',
                    Icons.people_alt_rounded,
                    'Check leads per user with sold/cancelled breakdown',
                    isDark,
                    () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SmeUserStatsDashboard())),
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
                color: isDark ? Colors.black26 : Colors.black.withOpacity(0.06),
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
                    color: _primaryBlue.withOpacity(isDark ? 0.2 : 0.1),
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

  _CardData(this.title, this.value, this.icon, this.colorIndex);
}
