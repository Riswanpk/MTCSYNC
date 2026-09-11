import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../dme_constants.dart';
import '../../dme_config.dart';
import 'dme_call_report_models.dart';

const Color _primaryBlue = Color(0xFF005BAC);
const Color _whatsappGreen = Color(0xFF25D366);

class DmeUserCallDetailPage extends StatefulWidget {
  final DmeUserCallStat userStat;
  final DateTime startDate;
  final DateTime endDate;

  const DmeUserCallDetailPage({
    super.key,
    required this.userStat,
    required this.startDate,
    required this.endDate,
  });

  @override
  State<DmeUserCallDetailPage> createState() => _DmeUserCallDetailPageState();
}

class _DmeUserCallDetailPageState extends State<DmeUserCallDetailPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late List<int> _days;
  String _customerSearchQuery = '';
  int? _pendingCount;
  bool _isLoadingPending = false;

  @override
  void initState() {
    super.initState();
    _days = widget.userStat.activeDays;
    if (_days.isEmpty) {
      _days = [widget.startDate.day];
    }
    _tabController = TabController(length: _days.length, vsync: this);
    _fetchPendingCount();
  }

  Future<void> _fetchPendingCount() async {
    final client = DmeConfig.client;
    if (client == null) return;
    setState(() => _isLoadingPending = true);
    try {
      // Query pending reminders assigned to this user
      var query = client
          .from('dme_reminders')
          .select('id')
          .eq('status', 'pending');

      if (widget.userStat.uid != 'branch_system') {
        query = query.eq('assigned_to', widget.userStat.uid);
      } else if (widget.userStat.assignedBranches.isNotEmpty) {
        query = query.inFilter('last_purchase_branch', widget.userStat.assignedBranches);
      }

      final res = await query;
      if (mounted) {
        setState(() {
          _pendingCount = (res as List).length;
          _isLoadingPending = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching pending reminders count: $e');
      if (mounted) {
        setState(() => _isLoadingPending = false);
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final dateRangeStr =
        '${DateFormat('dd MMM yyyy').format(widget.startDate)} - ${DateFormat('dd MMM yyyy').format(widget.endDate)}';

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.userStat.username.isNotEmpty
                  ? widget.userStat.username
                  : widget.userStat.email.split('@').first,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              'Call & WhatsApp Details ($dateRangeStr)',
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
        backgroundColor: _primaryBlue,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // User Summary Header Card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[900] : Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: _primaryBlue.withValues(alpha: 0.15),
                      foregroundColor: _primaryBlue,
                      child: const Icon(Icons.person, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.userStat.username,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            widget.userStat.email,
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    if (widget.userStat.assignedBranches.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.grey.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            widget.userStat.assignedBranches
                                .map((b) => DmeConstants.getBranchName(b))
                                .join(', '),
                            style: TextStyle(fontSize: 10, color: Colors.grey[700], fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),

                // Summary KPI Cards Grid (Called, WhatsApp, Total Completed, Pending)
                Row(
                  children: [
                    // Called KPI
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.withValues(alpha: 0.25)),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.phone_in_talk_rounded, size: 13, color: _primaryBlue),
                                const SizedBox(width: 4),
                                const Text(
                                  'Called',
                                  style: TextStyle(fontSize: 11, color: _primaryBlue, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${widget.userStat.totalCalls}',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _primaryBlue),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // WhatsApp KPI
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                        decoration: BoxDecoration(
                          color: _whatsappGreen.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _whatsappGreen.withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.chat_bubble_rounded, size: 13, color: Color(0xFF1EBE5D)),
                                const SizedBox(width: 4),
                                const Text(
                                  'WhatsApp',
                                  style: TextStyle(fontSize: 11, color: Color(0xFF0E7A38), fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${widget.userStat.totalWhatsApp}',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0E7A38)),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Total Completed KPI
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                        decoration: BoxDecoration(
                          color: _primaryBlue.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _primaryBlue.withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.check_circle_outline_rounded, size: 13, color: _primaryBlue),
                                const SizedBox(width: 4),
                                const Text(
                                  'Completed',
                                  style: TextStyle(fontSize: 11, color: _primaryBlue, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${widget.userStat.totalActions}',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _primaryBlue),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Pending Reminders KPI
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.pending_actions_rounded, size: 13, color: Colors.orange),
                                const SizedBox(width: 4),
                                const Text(
                                  'Pending',
                                  style: TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            _isLoadingPending
                                ? const SizedBox(
                                    height: 16,
                                    width: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange),
                                  )
                                : Text(
                                    _pendingCount != null ? '$_pendingCount' : '-',
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.orange),
                                  ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Search Bar within user list
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search customer name, phone, or remarks...',
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true,
                filled: true,
                fillColor: isDark ? Colors.grey[850] : Colors.grey[100],
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
              onChanged: (val) => setState(() => _customerSearchQuery = val.trim().toLowerCase()),
            ),
          ),

          // Day Tabs Header
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[900] : Colors.grey[100],
              border: Border(
                bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
              ),
            ),
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: _primaryBlue,
              unselectedLabelColor: Colors.grey[600],
              indicatorColor: _primaryBlue,
              indicatorWeight: 3,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 13),
              tabs: _days.map((day) {
                final dayItems = widget.userStat.getItemsForDay(day);
                return Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Day $day'),
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: _primaryBlue.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${dayItems.length}',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _primaryBlue),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),

          // TabBarView for Days
          Expanded(
            child: widget.userStat.callItems.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.phone_missed_rounded, size: 48, color: Colors.grey[400]),
                        const SizedBox(height: 8),
                        Text(
                          'No calls or messages recorded for this user in the selected period.',
                          style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  )
                : TabBarView(
                    controller: _tabController,
                    children: _days.map((day) {
                      final dayItems = widget.userStat.getItemsForDay(day);
                      final filtered = dayItems.where((item) {
                        if (_customerSearchQuery.isEmpty) return true;
                        return item.customerName.toLowerCase().contains(_customerSearchQuery) ||
                            item.customerPhone.toLowerCase().contains(_customerSearchQuery) ||
                            item.remarks.toLowerCase().contains(_customerSearchQuery) ||
                            item.branchName.toLowerCase().contains(_customerSearchQuery);
                      }).toList();

                      if (filtered.isEmpty) {
                        return Center(
                          child: Text(
                            dayItems.isEmpty
                                ? 'No customer activity on Day $day.'
                                : 'No customers match "$_customerSearchQuery"',
                            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                          ),
                        );
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, idx) {
                          final item = filtered[idx];
                          return _buildCustomerActionCard(context, item, idx);
                        },
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerActionCard(BuildContext context, DmeCustomerCallItem item, int idx) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left Avatar index
            CircleAvatar(
              radius: 16,
              backgroundColor: item.isWhatsApp
                  ? _whatsappGreen.withValues(alpha: 0.15)
                  : _primaryBlue.withValues(alpha: 0.15),
              foregroundColor: item.isWhatsApp ? const Color(0xFF0E7A38) : _primaryBlue,
              child: Text(
                '${idx + 1}',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 10),

            // Middle Customer Information & Remarks
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.customerName,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.phone_android, size: 12, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(
                            item.customerPhone.isNotEmpty ? item.customerPhone : 'No Mobile',
                            style: TextStyle(fontSize: 12, color: Colors.grey[800], fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          item.branchName,
                          style: TextStyle(fontSize: 10, color: Colors.grey[800], fontWeight: FontWeight.bold),
                        ),
                      ),
                      // New Call Duration chip if recorded
                      if (item.formattedCallDuration != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.timer_outlined, size: 10, color: Colors.green),
                              const SizedBox(width: 3),
                              Text(
                                item.formattedCallDuration!,
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),

                  if (item.customerAddress.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.customerAddress,
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],

                  const SizedBox(height: 6),
                  // Remarks Box
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[850] : Colors.grey[100],
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              item.isWhatsApp ? Icons.chat_bubble_outline_rounded : Icons.notes_rounded,
                              size: 12,
                              color: item.isWhatsApp ? const Color(0xFF0E7A38) : _primaryBlue,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              item.isWhatsApp ? 'WhatsApp Remarks:' : 'Call Remarks:',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: item.isWhatsApp ? const Color(0xFF0E7A38) : _primaryBlue,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              item.formattedCallTime,
                              style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.remarks.isNotEmpty ? item.remarks : 'No remarks entered.',
                          style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black87),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Right Type Badge (Pure status badge, no call button)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: item.isWhatsApp
                    ? _whatsappGreen.withValues(alpha: 0.15)
                    : Colors.blue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: item.isWhatsApp
                      ? _whatsappGreen.withValues(alpha: 0.6)
                      : Colors.blue.withValues(alpha: 0.5),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    item.isWhatsApp ? Icons.chat_bubble_rounded : Icons.phone_callback_rounded,
                    size: 18,
                    color: item.isWhatsApp ? const Color(0xFF1EBE5D) : _primaryBlue,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.isWhatsApp ? 'WhatsApp' : 'Called',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: item.isWhatsApp ? const Color(0xFF0E7A38) : _primaryBlue,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
