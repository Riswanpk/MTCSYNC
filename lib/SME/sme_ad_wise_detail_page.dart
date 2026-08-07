import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SmeAdWiseDetailPage extends StatefulWidget {
  final String adName;
  final DateTimeRange? dateRange;

  const SmeAdWiseDetailPage({
    super.key,
    required this.adName,
    this.dateRange,
  });

  @override
  State<SmeAdWiseDetailPage> createState() => _SmeAdWiseDetailPageState();
}

class _SmeAdWiseDetailPageState extends State<SmeAdWiseDetailPage> {
  static const Color _primaryBlue = Color(0xFF005BAC);

  Future<Map<String, dynamic>> _fetchBranchClassification() async {
    try {
      Query query = FirebaseFirestore.instance
          .collection('follow_ups')
          .where('source', whereIn: ['sme', 'SME']);

      if (widget.dateRange != null) {
        final start = Timestamp.fromDate(widget.dateRange!.start);
        final end = Timestamp.fromDate(
            widget.dateRange!.end.add(const Duration(days: 1)).subtract(const Duration(seconds: 1)));
        query = query
            .where('created_at', isGreaterThanOrEqualTo: start)
            .where('created_at', isLessThanOrEqualTo: end);
      }

      final snapshot = await query.get();

      // Branch -> Stats & Leads List
      // Stat: { 'total': 0, 'promoted': 0, 'rejected': 0, 'sold': 0, 'cancelled': 0, 'in_progress': 0 }
      final Map<String, Map<String, dynamic>> branchData = {};

      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        String docAdName = (data['ad_name'] ?? '').toString().trim();
        if (docAdName.isEmpty) {
          docAdName = 'Unspecified / No Ad';
        }

        // Match ad name
        if (widget.adName != docAdName) {
          continue;
        }

        String branch = (data['branch'] ?? '').toString().trim();
        if (branch.isEmpty) {
          branch = 'Unassigned Branch';
        }

        final screeningStatus = (data['screening_status'] ?? '').toString().toLowerCase();
        final status = (data['status'] ?? '').toString();

        branchData.putIfAbsent(branch, () => {
          'total': 0,
          'promoted': 0,
          'rejected': 0,
          'sold': 0,
          'cancelled': 0,
          'in_progress': 0,
          'leads': <Map<String, dynamic>>[],
        });

        final bStats = branchData[branch]!;
        bStats['total'] = (bStats['total'] as int) + 1;

        if (screeningStatus == 'promoted') {
          bStats['promoted'] = (bStats['promoted'] as int) + 1;
        } else if (screeningStatus == 'rejected') {
          bStats['rejected'] = (bStats['rejected'] as int) + 1;
        }

        if (status == 'Sale') {
          bStats['sold'] = (bStats['sold'] as int) + 1;
        } else if (status == 'Cancelled') {
          bStats['cancelled'] = (bStats['cancelled'] as int) + 1;
        } else {
          bStats['in_progress'] = (bStats['in_progress'] as int) + 1;
        }

        (bStats['leads'] as List<Map<String, dynamic>>).add({
          'id': doc.id,
          'name': data['name'] ?? 'Unknown',
          'phone': data['phone'] ?? '',
          'assigned_to_name': data['assigned_to_name'] ?? '',
          'status': status,
          'screening_status': screeningStatus,
          'created_at': data['created_at'],
        });
      }

      return branchData;
    } catch (e) {
      debugPrint('Error fetching branch classification: $e');
      return {};
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? const Color(0xFF1A1B22) : const Color(0xFFF5F7FA);

    return Scaffold(
      backgroundColor: surfaceColor,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.adName,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const Text(
              'Branch Classification',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        backgroundColor: isDark ? const Color(0xFF1A1B22) : Colors.white,
        foregroundColor: isDark ? Colors.white : const Color(0xFF1A1B22),
        elevation: 0,
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _fetchBranchClassification(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error loading details: ${snapshot.error}'));
          }

          final branchData = snapshot.data ?? {};

          if (branchData.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.location_off_rounded, size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  Text(
                    'No branch lead data available for this Ad',
                    style: TextStyle(fontSize: 15, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            );
          }

          final sortedBranches = branchData.keys.toList()
            ..sort((a, b) => (branchData[b]!['total'] as int).compareTo(branchData[a]!['total'] as int));

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: sortedBranches.length,
            itemBuilder: (context, index) {
              final branchName = sortedBranches[index];
              final data = branchData[branchName]!;
              final total = data['total'] as int;
              final sold = data['sold'] as int;
              final promoted = data['promoted'] as int;
              final rejected = data['rejected'] as int;
              final cancelled = data['cancelled'] as int;
              final leads = data['leads'] as List<Map<String, dynamic>>;

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
                child: Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _primaryBlue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.business_rounded, color: _primaryBlue, size: 22),
                    ),
                    title: Text(
                      branchName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : const Color(0xFF1A1B22),
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: _primaryBlue.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '$total Leads',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: _primaryBlue,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Conv: $convRate%',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                    children: [
                      const Divider(height: 1),
                      const SizedBox(height: 12),

                      // Stat Chips
                      Row(
                        children: [
                          _chip('Promoted', '$promoted', const Color(0xFF26A69A), isDark),
                          const SizedBox(width: 6),
                          _chip('Rejected', '$rejected', const Color(0xFFEF5350), isDark),
                          const SizedBox(width: 6),
                          _chip('Sold', '$sold', const Color(0xFF42A5F5), isDark),
                          const SizedBox(width: 6),
                          _chip('Cancelled', '$cancelled', const Color(0xFFFFA726), isDark),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Lead list expansion
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Lead Breakdown (${leads.length})',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...leads.map((lead) {
                        final name = lead['name'];
                        final phone = lead['phone'];
                        final assigned = lead['assigned_to_name'];
                        final status = lead['status'];

                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                            ),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 14,
                                backgroundColor: _primaryBlue.withValues(alpha: 0.15),
                                child: Text(
                                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: _primaryBlue,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: isDark ? Colors.white : Colors.black87,
                                      ),
                                    ),
                                    if (phone.isNotEmpty || assigned.isNotEmpty)
                                      Text(
                                        '${phone.isNotEmpty ? phone : ''} ${assigned.isNotEmpty ? '• Assigned: $assigned' : ''}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isDark ? Colors.white54 : Colors.black54,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: status == 'Sale'
                                      ? Colors.green.withValues(alpha: 0.15)
                                      : (status == 'Cancelled'
                                          ? Colors.orange.withValues(alpha: 0.15)
                                          : Colors.blue.withValues(alpha: 0.15)),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  status.isEmpty ? 'In Progress' : status,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: status == 'Sale'
                                        ? Colors.green
                                        : (status == 'Cancelled' ? Colors.orange : Colors.blue),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _chip(String label, String value, Color color, bool isDark) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: isDark ? 0.15 : 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
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
