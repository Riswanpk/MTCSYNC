import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class SmeAdWiseReportPage extends StatefulWidget {
  const SmeAdWiseReportPage({super.key});

  @override
  State<SmeAdWiseReportPage> createState() => _SmeAdWiseReportPageState();
}

class _SmeAdWiseReportPageState extends State<SmeAdWiseReportPage> {
  static const Color _primaryBlue = Color(0xFF005BAC);

  String? _selectedAdFilter; // 'ALL' or specific ad name
  DateTimeRange? _selectedDateRange;

  Future<Map<String, dynamic>> _fetchAdWiseReport() async {
    try {
      Query query = FirebaseFirestore.instance
          .collection('follow_ups')
          .where('source', whereIn: ['sme', 'SME']);

      if (_selectedDateRange != null) {
        final start = Timestamp.fromDate(_selectedDateRange!.start);
        final end = Timestamp.fromDate(
            _selectedDateRange!.end.add(const Duration(days: 1)).subtract(const Duration(seconds: 1)));
        query = query
            .where('created_at', isGreaterThanOrEqualTo: start)
            .where('created_at', isLessThanOrEqualTo: end);
      }

      final snapshot = await query.get();

      // Map of adName -> StatMap
      // StatMap: { 'total': 0, 'promoted': 0, 'rejected': 0, 'sold': 0, 'cancelled': 0, 'in_progress': 0 }
      final Map<String, Map<String, int>> adStats = {};

      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        String adName = (data['ad_name'] ?? '').toString().trim();
        if (adName.isEmpty) {
          adName = 'Unspecified / No Ad';
        }

        if (_selectedAdFilter != null &&
            _selectedAdFilter != 'ALL' &&
            _selectedAdFilter != adName) {
          continue;
        }

        final screeningStatus = (data['screening_status'] ?? '').toString().toLowerCase();
        final status = (data['status'] ?? '').toString();

        adStats.putIfAbsent(adName, () => {
          'total': 0,
          'promoted': 0,
          'rejected': 0,
          'sold': 0,
          'cancelled': 0,
          'in_progress': 0,
        });

        final stats = adStats[adName]!;
        stats['total'] = (stats['total'] ?? 0) + 1;

        if (screeningStatus == 'promoted') {
          stats['promoted'] = (stats['promoted'] ?? 0) + 1;
        } else if (screeningStatus == 'rejected') {
          stats['rejected'] = (stats['rejected'] ?? 0) + 1;
        }

        if (status == 'Sale') {
          stats['sold'] = (stats['sold'] ?? 0) + 1;
        } else if (status == 'Cancelled') {
          stats['cancelled'] = (stats['cancelled'] ?? 0) + 1;
        } else {
          stats['in_progress'] = (stats['in_progress'] ?? 0) + 1;
        }
      }

      return {
        'adStats': adStats,
        'totalCount': snapshot.docs.length,
      };
    } catch (e) {
      debugPrint('Error fetching ad report: $e');
      return {'adStats': <String, Map<String, int>>{}, 'totalCount': 0};
    }
  }

  Future<List<String>> _fetchRegisteredAdNames() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('sme_ads').orderBy('name').get();
      return snap.docs.map((doc) => (doc.data()['name'] ?? '').toString()).where((n) => n.isNotEmpty).toList();
    } catch (e) {
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? const Color(0xFF1A1B22) : const Color(0xFFF5F7FA);

    return Scaffold(
      backgroundColor: surfaceColor,
      appBar: AppBar(
        title: const Text('Ad-Wise Reports', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: isDark ? const Color(0xFF1A1B22) : Colors.white,
        foregroundColor: isDark ? Colors.white : const Color(0xFF1A1B22),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.date_range_rounded),
            tooltip: 'Filter by Date',
            onPressed: () async {
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2020),
                lastDate: DateTime(2030),
                initialDateRange: _selectedDateRange,
              );
              if (picked != null) {
                setState(() => _selectedDateRange = picked);
              }
            },
          ),
          if (_selectedDateRange != null)
            IconButton(
              icon: const Icon(Icons.clear_rounded),
              tooltip: 'Clear Date Filter',
              onPressed: () => setState(() => _selectedDateRange = null),
            ),
        ],
      ),
      body: Column(
        children: [
          // Filter Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: isDark ? const Color(0xFF23242B) : Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FutureBuilder<List<String>>(
                  future: _fetchRegisteredAdNames(),
                  builder: (context, snapshot) {
                    final adNames = snapshot.data ?? [];
                    final filterOptions = ['ALL', ...adNames, 'Unspecified / No Ad'];

                    return DropdownButtonFormField<String>(
                      value: _selectedAdFilter ?? 'ALL',
                      decoration: InputDecoration(
                        labelText: 'Filter by Ad Name',
                        prefixIcon: const Icon(Icons.filter_alt_rounded, color: _primaryBlue),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      items: filterOptions.map((ad) {
                        return DropdownMenuItem<String>(
                          value: ad,
                          child: Text(
                            ad == 'ALL' ? 'All Ads' : ad,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setState(() {
                          _selectedAdFilter = val;
                        });
                      },
                    );
                  },
                ),
                if (_selectedDateRange != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.calendar_today_rounded, size: 14, color: _primaryBlue),
                      const SizedBox(width: 6),
                      Text(
                        'Date: ${DateFormat('dd MMM yyyy').format(_selectedDateRange!.start)} - ${DateFormat('dd MMM yyyy').format(_selectedDateRange!.end)}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          // Main Stats List
          Expanded(
            child: FutureBuilder<Map<String, dynamic>>(
              future: _fetchAdWiseReport(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error loading report: ${snapshot.error}'));
                }

                final adStats = snapshot.data?['adStats'] as Map<String, Map<String, int>>? ?? {};

                if (adStats.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.analytics_outlined, size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 12),
                        Text(
                          'No lead data found for the selected criteria',
                          style: TextStyle(fontSize: 15, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  );
                }

                final sortedKeys = adStats.keys.toList()
                  ..sort((a, b) => (adStats[b]!['total'] ?? 0).compareTo(adStats[a]!['total'] ?? 0));

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: sortedKeys.length,
                  itemBuilder: (context, index) {
                    final adName = sortedKeys[index];
                    final stats = adStats[adName]!;
                    final total = stats['total'] ?? 0;
                    final sold = stats['sold'] ?? 0;
                    final promoted = stats['promoted'] ?? 0;
                    final rejected = stats['rejected'] ?? 0;
                    final cancelled = stats['cancelled'] ?? 0;
                    final inProgress = stats['in_progress'] ?? 0;

                    final convRate = total > 0 ? (sold / total * 100).toStringAsFixed(1) : '0.0';

                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF23242B) : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: isDark ? Colors.black26 : Colors.black.withValues(alpha: 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header: Ad Name & Total Leads Badge
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: _primaryBlue.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.campaign_rounded, color: _primaryBlue, size: 20),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    adName,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? Colors.white : const Color(0xFF1A1B22),
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _primaryBlue,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    '$total Leads',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            const Divider(height: 1),
                            const SizedBox(height: 16),

                            // Grid Breakdown Stats
                            Row(
                              children: [
                                _statChip('Promoted', '$promoted', const Color(0xFF26A69A), isDark),
                                const SizedBox(width: 8),
                                _statChip('Rejected', '$rejected', const Color(0xFFEF5350), isDark),
                                const SizedBox(width: 8),
                                _statChip('Sold', '$sold', const Color(0xFF42A5F5), isDark),
                                const SizedBox(width: 8),
                                _statChip('Cancelled', '$cancelled', const Color(0xFFFFA726), isDark),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // Summary Bar (Conversion rate & In Progress)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'In Progress: $inProgress',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: isDark ? Colors.white70 : Colors.black87,
                                    ),
                                  ),
                                  Text(
                                    'Conversion Rate: $convRate%',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: _primaryBlue,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _statChip(String label, String value, Color color, bool isDark) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: isDark ? 0.15 : 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
