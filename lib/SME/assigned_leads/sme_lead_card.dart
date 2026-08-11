import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'sme_lead_helpers.dart';
import 'sme_lead_detail_page.dart';

class SmeLeadCard extends StatelessWidget {
  final DocumentSnapshot doc;
  final Map<String, dynamic> data;
  final bool isDark;
  final String assignerName;
  final String currentUid;
  final VoidCallback onRefreshNeeded;

  const SmeLeadCard({
    super.key,
    required this.doc,
    required this.data,
    required this.isDark,
    required this.assignerName,
    required this.currentUid,
    required this.onRefreshNeeded,
  });

  @override
  Widget build(BuildContext context) {
    final name = data['name'] ?? 'No Name';
    final phone = data['phone'] ?? '';
    final priority = data['priority'] ?? 'High';
    final branch = data['branch'] ?? '';
    final screeningStatus = data['screening_status'] ?? 'pending';

    String formattedDate = 'No Date';
    final date = data['date'];
    if (date is Timestamp) {
      formattedDate = DateFormat('dd-MM-yyyy').format(date.toDate());
    } else if (date is DateTime) {
      formattedDate = DateFormat('dd-MM-yyyy').format(date);
    }

    final statusColor = getScreeningStatusColor(screeningStatus);
    final priorityColor = getPriorityColor(priority);

    return GestureDetector(
      onTap: () async {
        final needRefresh = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => SmeLeadDetailPage(
              doc: doc,
              data: data,
              assignerName: assignerName,
              currentUid: currentUid,
            ),
          ),
        );
        if (needRefresh == true) onRefreshNeeded();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C2C3C) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.07),
                blurRadius: 10,
                offset: const Offset(0, 3))
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 5, color: statusColor),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(name,
                                  style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: isDark
                                          ? Colors.white
                                          : const Color(0xFF0D2B40),
                                      height: 1.3)),
                            ),
                            const SizedBox(width: 8),
                            if (data['pendingDeletion'] == true) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.red.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text(
                                  'PENDING DELETION',
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.red),
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(20)),
                              child: Text(
                                  screeningStatusLabel(screeningStatus),
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: statusColor,
                                      letterSpacing: 0.2)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        if (phone.isNotEmpty)
                          Row(children: [
                            Icon(Icons.phone_rounded,
                                size: 12, color: Colors.grey.shade400),
                            const SizedBox(width: 4),
                            Text(phone,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? Colors.grey.shade400
                                        : Colors.grey.shade600,
                                    fontWeight: FontWeight.w500)),
                          ]),
                        const SizedBox(height: 4),
                        Row(children: [
                          Icon(Icons.calendar_today_rounded,
                              size: 11, color: Colors.grey.shade400),
                          const SizedBox(width: 4),
                          Text(formattedDate,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? Colors.grey.shade400
                                      : Colors.grey.shade500)),
                          const SizedBox(width: 12),
                          Icon(Icons.person_outline_rounded,
                              size: 12, color: Colors.grey.shade400),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text('by $assignerName',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade500,
                                    fontStyle: FontStyle.italic),
                                overflow: TextOverflow.ellipsis),
                          ),
                        ]),
                        const SizedBox(height: 8),
                        Row(children: [
                          if (branch.isNotEmpty) ...[
                            _infoChip(
                                icon: Icons.business_rounded,
                                value: branch,
                                isDark: isDark),
                            const SizedBox(width: 6),
                          ],
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 5),
                            decoration: BoxDecoration(
                                color: priorityColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10)),
                            child:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.flag_rounded,
                                  size: 12, color: priorityColor),
                              const SizedBox(width: 3),
                              Text(priority,
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: priorityColor)),
                            ]),
                          ),
                          const Spacer(),
                          Icon(Icons.chevron_right_rounded,
                              size: 18, color: Colors.grey.shade400),
                        ]),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoChip(
      {required IconData icon, required String value, required bool isDark}) {
    const brandPrimary = Color(0xFF005BAC);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: brandPrimary),
        const SizedBox(width: 4),
        Text(value,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87)),
      ]),
    );
  }
}
