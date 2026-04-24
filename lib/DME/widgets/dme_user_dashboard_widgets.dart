import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../services/dme_user_dashboard_service.dart';

// -- Premium palette ----------------------------------------------------------
const List<Color> _palette = [
  Color(0xFF2979FF), // electric blue
  Color(0xFF00C853), // vivid green
  Color(0xFFFFB300), // vibrant amber
  Color(0xFFFF3D57), // punchy red
  Color(0xFF7C4DFF), // saturated violet
  Color(0xFF00B8D4), // bright cyan
  Color(0xFFFF6D00), // tangerine
  Color(0xFFFF2D95), // hot pink
];

const Color _primaryBlue = Color(0xFF005BAC);

// -- Stat Card ----------------------------------------------------------------

class DashboardStatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? subtitle;

  const DashboardStatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: isDark ? const Color(0xFF1A2332) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(isDark ? 0.18 : 0.16),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 4,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [color, color.withOpacity(0.35)],
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label.toUpperCase(),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                                color: isDark ? Colors.white38 : Colors.black38,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              value,
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                height: 1.0,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            if (subtitle != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                subtitle!,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark ? Colors.white38 : Colors.black38,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: Icon(icon, color: color, size: 22),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -- Shared pie stat model ----------------------------------------------------

class _PieStat {
  final String label;
  final int count;
  const _PieStat({required this.label, required this.count});
}

// -- Public wrappers ----------------------------------------------------------

/// Pie chart for category breakdown.
class CategoryPieCard extends StatelessWidget {
  final List<CategoryPurchaseStat> stats;
  final int totalUniqueCustomers;
  const CategoryPieCard({
    super.key,
    required this.stats,
    required this.totalUniqueCustomers,
  });

  @override
  Widget build(BuildContext context) {
    return _PieCard(
      title: 'Category Mix',
      accentColor: const Color(0xFF2979FF),
      totalUniqueCustomers: totalUniqueCustomers,
      stats: stats
          .map((s) => _PieStat(label: s.categoryName, count: s.uniqueCustomers))
          .toList(),
    );
  }
}

/// Pie chart for customer type breakdown.
class CustomerTypePieCard extends StatelessWidget {
  final List<CustomerTypeStat> stats;
  final int totalUniqueCustomers;
  const CustomerTypePieCard({
    super.key,
    required this.stats,
    required this.totalUniqueCustomers,
  });

  @override
  Widget build(BuildContext context) {
    return _PieCard(
      title: 'Customer Type Mix',
      accentColor: const Color(0xFF7C4DFF),
      totalUniqueCustomers: totalUniqueCustomers,
      stats: stats
          .map((s) => _PieStat(label: s.typeName, count: s.uniqueCustomers))
          .toList(),
    );
  }
}

// -- Generic premium pie card -------------------------------------------------

class _PieCard extends StatefulWidget {
  final String title;
  final Color accentColor;
  final int totalUniqueCustomers;
  final List<_PieStat> stats;

  const _PieCard({
    required this.title,
    required this.accentColor,
    required this.totalUniqueCustomers,
    required this.stats,
  });

  @override
  State<_PieCard> createState() => _PieCardState();
}

class _PieCardState extends State<_PieCard> {
  int _touched = -1;

  // Group slices with < 2 % of total into a single "Others" bucket
  List<_PieStat> _mergeSmall(List<_PieStat> input, int total) {
    if (total <= 0) return input;
    const threshold = 2.0;
    final List<_PieStat> main = [];
    int othersCount = 0;
    for (final s in input) {
      if (s.count / total * 100 < threshold) {
        othersCount += s.count;
      } else {
        main.add(s);
      }
    }
    if (othersCount > 0) {
      main.add(_PieStat(label: 'Others', count: othersCount));
    }
    return main;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final rawTotal = widget.stats.fold(0, (s, e) => s + e.count);
    if (rawTotal == 0) return const SizedBox.shrink();

    final sections = _mergeSmall(widget.stats, rawTotal);
    // Clamp touch index after merging (sections list may be shorter)
    if (_touched >= sections.length) _touched = -1;

    final total = sections.fold(0, (s, e) => s + e.count);
    final selectedStat =
        _touched >= 0 && _touched < sections.length ? sections[_touched] : null;
    final accent = widget.accentColor;

    // Unique border color that matches card background for clean slice edges
    final borderColor = isDark ? const Color(0xFF172334) : Colors.white;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF172334), const Color(0xFF1C2F4A)]
              : [Colors.white, const Color(0xFFF5F8FF)],
        ),
        border: Border.all(
          color: accent.withOpacity(isDark ? 0.18 : 0.13),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withOpacity(isDark ? 0.22 : 0.12),
            blurRadius: 30,
            spreadRadius: 0,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row ──────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _sectionTitle(widget.title, isDark),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: accent.withOpacity(0.28), width: 1),
                  ),
                  child: Text(
                    '${widget.totalUniqueCustomers} customers',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isDark ? accent.withOpacity(0.9) : accent,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            // ── Pie chart ────────────────────────────────────────────────
            SizedBox(
              height: 300,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PieChart(
                    PieChartData(
                      pieTouchData: PieTouchData(
                        touchCallback: (FlTouchEvent event, PieTouchResponse? r) {
                          setState(() {
                            if (!event.isInterestedForInteractions ||
                                r?.touchedSection == null) {
                              _touched = -1;
                            } else {
                              _touched =
                                  r!.touchedSection!.touchedSectionIndex;
                            }
                          });
                        },
                      ),
                      centerSpaceRadius: 72,
                      sectionsSpace: 2.5,
                      sections: sections.asMap().entries.map((entry) {
                        final i = entry.key;
                        final stat = entry.value;
                        final color = _palette[i % _palette.length];
                        final isTouched = i == _touched;
                        final pct = total > 0
                            ? (stat.count / total * 100).round()
                            : 0;
                        return PieChartSectionData(
                          value: stat.count.toDouble(),
                          color: color,
                          radius: isTouched ? 80 : 64,
                          title: isTouched ? '$pct%' : '',
                          titleStyle: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            shadows: [
                              Shadow(
                                color: Colors.black26,
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          titlePositionPercentageOffset: 0.65,
                          borderSide: BorderSide(
                            color: borderColor,
                            width: 2.5,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  // Center content
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    transitionBuilder: (child, anim) =>
                        FadeTransition(opacity: anim, child: child),
                    child: selectedStat != null
                        ? _buildCenterSelected(
                            selectedStat, total, isDark)
                        : _buildCenterDefault(rawTotal, isDark),
                  ),
                ],
              ),
            ),
            Center(
              child: Text(
                'Tap a segment to explore',
                style: TextStyle(
                  fontSize: 10,
                  fontStyle: FontStyle.italic,
                  color: isDark ? Colors.white24 : Colors.black26,
                ),
              ),
            ),
            const SizedBox(height: 18),
            // ── Legend grid ──────────────────────────────────────────────
            ...() {
              final rows = <Widget>[];
              for (int i = 0; i < sections.length; i += 2) {
                rows.add(Row(
                  children: [
                    Expanded(child: _legendTile(sections[i], i, total, isDark)),
                    const SizedBox(width: 8),
                    if (i + 1 < sections.length)
                      Expanded(
                          child: _legendTile(sections[i + 1], i + 1, total, isDark))
                    else
                      const Expanded(child: SizedBox()),
                  ],
                ));
                if (i + 2 < sections.length) rows.add(const SizedBox(height: 8));
              }
              return rows;
            }(),
          ],
        ),
      ),
    );
  }

  Widget _buildCenterSelected(_PieStat stat, int total, bool isDark) {
    final color = _palette[_touched % _palette.length];
    final pct = total > 0 ? (stat.count / total * 100).toStringAsFixed(1) : '0.0';
    return Column(
      key: ValueKey(_touched),
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(height: 6),
        Text(
          '${stat.count}',
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w900,
            height: 1.0,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          '$pct%',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        const SizedBox(height: 3),
        SizedBox(
          width: 88,
          child: Text(
            stat.label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white54 : Colors.black54,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCenterDefault(int total, bool isDark) {
    return Column(
      key: const ValueKey(-1),
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$total',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w900,
            height: 1.0,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'customers',
          style: TextStyle(
            fontSize: 11,
            color: isDark ? Colors.white38 : Colors.black38,
          ),
        ),
      ],
    );
  }

  Widget _legendTile(_PieStat stat, int index, int total, bool isDark) {
    final color = _palette[index % _palette.length];
    final pct =
        total > 0 ? (stat.count / total * 100).toStringAsFixed(1) : '0.0';
    final isSelected = index == _touched;

    return GestureDetector(
      onTap: () => setState(() => _touched = isSelected ? -1 : index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: isSelected
              ? color.withOpacity(0.13)
              : (isDark
                  ? Colors.white.withOpacity(0.04)
                  : Colors.black.withOpacity(0.03)),
          border: Border.all(
            color: isSelected ? color.withOpacity(0.5) : Colors.transparent,
            width: 1.5,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withOpacity(0.22),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                stat.label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withOpacity(0.07)
                    : Colors.black.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${stat.count}',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 42,
              child: Text(
                '$pct%',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -- Category Breakdown --------------------------------------------------------

class CategoryBreakdownCard extends StatelessWidget {
  final List<CategoryPurchaseStat> stats;

  const CategoryBreakdownCard({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (stats.isEmpty) return const SizedBox.shrink();

    final maxVal = stats.fold(0, (m, s) => s.uniqueCustomers > m ? s.uniqueCustomers : m);

    return _premiumCard(
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Category Breakdown', isDark),
          const SizedBox(height: 18),
          ...stats.asMap().entries.map((entry) {
            final i = entry.key;
            final stat = entry.value;
            final color = _palette[i % _palette.length];
            final frac = maxVal > 0 ? stat.uniqueCustomers / maxVal : 0.0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          stat.categoryName,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                      ),
                      Text(
                        '${stat.uniqueCustomers}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: LinearProgressIndicator(
                      value: frac,
                      minHeight: 6,
                      backgroundColor: isDark
                          ? Colors.white.withOpacity(0.08)
                          : Colors.black.withOpacity(0.06),
                      valueColor: AlwaysStoppedAnimation(color),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// -- Branch Performance with rank badges ---------------------------------------

class BranchBreakdownCard extends StatelessWidget {
  final List<BranchPurchaseStat> stats;

  const BranchBreakdownCard({super.key, required this.stats});

  static const _rankColors = [
    Color(0xFFFFD700),
    Color(0xFFB0B8C1),
    Color(0xFFCD7F32),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (stats.isEmpty) return _emptyCard('No branch data for this period', isDark);

    final maxVal = stats.fold(0, (m, b) => b.totalPurchases > m ? b.totalPurchases : m);

    return _premiumCard(
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Branch Performance', isDark),
          const SizedBox(height: 18),
          ...stats.asMap().entries.map((entry) {
            final i = entry.key;
            final b = entry.value;
            final frac = maxVal > 0 ? b.totalPurchases / maxVal : 0.0;
            final rankColor = i < 3 ? _rankColors[i] : _primaryBlue.withOpacity(0.5);
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: rankColor.withOpacity(0.15),
                      shape: BoxShape.circle,
                      border: Border.all(color: rankColor.withOpacity(0.4), width: 1.5),
                    ),
                    child: Center(
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: rankColor,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                b.branchName,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white70 : Colors.black87,
                                ),
                              ),
                            ),
                            Text(
                              '${b.uniqueCustomers} cust.',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? Colors.white38 : Colors.black38,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: LinearProgressIndicator(
                            value: frac,
                            minHeight: 7,
                            backgroundColor: isDark
                                ? Colors.white.withOpacity(0.08)
                                : Colors.black.withOpacity(0.07),
                            valueColor: AlwaysStoppedAnimation(_primaryBlue),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${b.totalPurchases}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// -- Daily Trend with gradient line + gradient fill ----------------------------

class DailyTrendCard extends StatelessWidget {
  final Map<String, int> dailyTrend;

  const DailyTrendCard({super.key, required this.dailyTrend});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (dailyTrend.isEmpty) return _emptyCard('No trend data for this period', isDark);

    final dates = dailyTrend.keys.toList()..sort();
    final maxVal = dailyTrend.values.fold(0, (m, v) => v > m ? v : m).toDouble();
    final dateFmt = DateFormat('dd/MM');

    final spots = dates.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), dailyTrend[e.value]!.toDouble());
    }).toList();

    final hInterval =
        maxVal > 0 ? (maxVal / 4).ceilToDouble().clamp(1.0, double.infinity) : 1.0;

    return _premiumCard(
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _sectionTitle('Daily Trend', isDark),
              Text(
                '${dates.length} days',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          SizedBox(
            height: 175,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: maxVal <= 0 ? 5 : maxVal * 1.25,
                clipData: const FlClipData.all(),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: hInterval,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: isDark
                        ? Colors.white.withOpacity(0.07)
                        : Colors.black.withOpacity(0.06),
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      getTitlesWidget: (v, _) => Text(
                        v.toInt().toString(),
                        style: TextStyle(
                          fontSize: 9,
                          color: isDark ? Colors.white30 : Colors.black26,
                        ),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      interval: (dates.length / 5)
                          .ceilToDouble()
                          .clamp(1.0, double.infinity),
                      getTitlesWidget: (v, _) {
                        final idx = v.toInt();
                        if (idx < 0 || idx >= dates.length) return const SizedBox.shrink();
                        try {
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              dateFmt.format(DateTime.parse(dates[idx])),
                              style: TextStyle(
                                fontSize: 9,
                                color: isDark ? Colors.white30 : Colors.black38,
                              ),
                            ),
                          );
                        } catch (_) {
                          return const SizedBox.shrink();
                        }
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.35,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF005BAC), Color(0xFF38BDF8)],
                    ),
                    barWidth: 3,
                    dotData: FlDotData(
                      show: dates.length <= 16,
                      getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                        radius: 4,
                        color: const Color(0xFF005BAC),
                        strokeWidth: 2,
                        strokeColor: Colors.white,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          const Color(0xFF005BAC).withOpacity(0.28),
                          const Color(0xFF005BAC).withOpacity(0.0),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -- Shared helpers ------------------------------------------------------------

Widget _premiumCard({required bool isDark, required Widget child}) {
  return Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      color: isDark ? const Color(0xFF1A2332) : Colors.white,
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(isDark ? 0.28 : 0.07),
          blurRadius: 22,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: child,
    ),
  );
}

Widget _emptyCard(String message, bool isDark) {
  return Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      color: isDark ? const Color(0xFF1A2332) : Colors.white,
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(isDark ? 0.2 : 0.05),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    padding: const EdgeInsets.all(32),
    child: Center(
      child: Text(
        message,
        style: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
      ),
    ),
  );
}

Text _sectionTitle(String title, bool isDark) => Text(
      title,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: isDark ? Colors.white : Colors.black87,
      ),
    );
