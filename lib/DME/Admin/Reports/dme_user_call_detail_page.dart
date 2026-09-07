import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../dme_constants.dart';
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

  @override
  void initState() {
    super.initState();
    _days = widget.userStat.activeDays;
    if (_days.isEmpty) {
      _days = [widget.startDate.day];
    }
    _tabController = TabController(length: _days.length, vsync: this);
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
                          ),
                          Text(
                            widget.userStat.email,
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                    // Total Action Pill
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _primaryBlue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _primaryBlue.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        'Total: ${widget.userStat.totalActions}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _primaryBlue,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Action Breakdown (Calls vs WhatsApp) & Branches
                Row(
                  children: [
                    // Calls pill
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.phone_in_talk_rounded, size: 14, color: _primaryBlue),
                          const SizedBox(width: 4),
                          Text(
                            'Calls: ${widget.userStat.totalCalls}',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _primaryBlue),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),

                    // WhatsApp pill
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _whatsappGreen.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _whatsappGreen.withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.chat_bubble_rounded, size: 14, color: Color(0xFF1EBE5D)),
                          const SizedBox(width: 4),
                          Text(
                            'WhatsApp: ${widget.userStat.totalWhatsApp}',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0E7A38)),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),

                    // Assigned Branches count / list
                    if (widget.userStat.assignedBranches.isNotEmpty)
                      Flexible(
                        child: Text(
                          'Branches: ${widget.userStat.assignedBranches.map((b) => DmeConstants.getBranchName(b)).join(', ')}',
                          style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
                  Row(
                    children: [
                      const Icon(Icons.phone_android, size: 12, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        item.customerPhone.isNotEmpty ? item.customerPhone : 'No Mobile',
                        style: TextStyle(fontSize: 12, color: Colors.grey[800], fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(width: 8),
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
                              item.formattedTime,
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
            const SizedBox(width: 10),

            // Right Action Indicator (Call or WhatsApp Icon Badge)
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
                    item.isWhatsApp ? Icons.chat_bubble_rounded : Icons.phone_in_talk_rounded,
                    size: 20,
                    color: item.isWhatsApp ? const Color(0xFF1EBE5D) : _primaryBlue,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.isWhatsApp ? 'WhatsApp' : 'Call',
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
