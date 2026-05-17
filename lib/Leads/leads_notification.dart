import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:mtcsync/Misc/notification_permission_service.dart';
import '../DME/services/dme_complaint_service.dart';
import '../DME/screens/dme_complaints_management.dart';
import 'presentfollowup.dart';

// ─── Notification Types ────────────────────────────────────────────────────

enum _NotifType { transfer, leadAssignment, complaint }

class _NotifItem {
  final _NotifType type;
  final String id;
  final String title;
  final String subtitle;
  final DateTime? time;

  const _NotifItem({
    required this.type,
    required this.id,
    required this.title,
    required this.subtitle,
    this.time,
  });
}

// ─── Page ──────────────────────────────────────────────────────────────────

class LeadsNotificationPage extends StatefulWidget {
  final String userBranch;

  const LeadsNotificationPage({super.key, required this.userBranch});

  @override
  State<LeadsNotificationPage> createState() => _LeadsNotificationPageState();
}

class _LeadsNotificationPageState extends State<LeadsNotificationPage> {
  List<_NotifItem> _items = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchAll();
  }

  // ─── Data Fetching ────────────────────────────────────────────────────────

  Future<void> _fetchAll() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final uid = currentUser.uid;
    final items = <_NotifItem>[];

    // 1. Transferred leads (unseen by original owner)
    await _fetchTransferredLeads(uid, items);

    // 2. SME / DME leads assigned to current user (still In Progress)
    await _fetchAssignedLeads(uid, items);

    // 3. Complaints assigned to current user and still raised
    await _fetchAssignedComplaints(uid, items);

    // Sort newest first
    items.sort((a, b) {
      final at = a.time ?? DateTime(2000);
      final bt = b.time ?? DateTime(2000);
      return bt.compareTo(at);
    });

    if (mounted) {
      setState(() {
        _items = items;
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchTransferredLeads(
      String uid, List<_NotifItem> items) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('follow_ups')
          .where('branch', isEqualTo: widget.userBranch)
          .where('created_by', isEqualTo: uid)
          .where('transferred_at', isNull: false)
          .where('notification_seen', isEqualTo: false)
          .orderBy('transferred_at', descending: true)
          .limit(50)
          .get();

      // Batch-resolve transferredBy UIDs
      final uniqueUids = snapshot.docs
          .map((d) => d.data()['transferred_by'] as String? ?? '')
          .where((u) => u.isNotEmpty)
          .toSet();
      final Map<String, String> uidToName = {};
      for (final u in uniqueUids) {
        try {
          final doc = await FirebaseFirestore.instance
              .collection('users')
              .doc(u)
              .get();
          if (doc.exists) {
            uidToName[u] =
                doc.data()?['username'] ?? doc.data()?['email'] ?? u;
          }
        } catch (_) {
          uidToName[u] = u;
        }
      }

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final byUid = data['transferred_by'] as String? ?? '';
        final byName = uidToName[byUid] ?? 'Unknown';
        final ts = (data['transferred_at'] as Timestamp?)?.toDate();
        items.add(_NotifItem(
          type: _NotifType.transfer,
          id: doc.id,
          title: data['name'] as String? ?? 'Unknown',
          subtitle: 'Transferred by $byName',
          time: ts,
        ));
      }
    } catch (e) {
      debugPrint('Error fetching transferred leads: $e');
    }
  }

  Future<void> _fetchAssignedLeads(String uid, List<_NotifItem> items) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('follow_ups')
          .where('assigned_to', isEqualTo: uid)
          .get();

      // Batch-resolve assignedBy UIDs
      final uniqueUids = snapshot.docs
          .map((d) => d.data()['assigned_by'] as String? ?? '')
          .where((u) => u.isNotEmpty)
          .toSet();
      final Map<String, String> assignerNames = {};
      for (final u in uniqueUids) {
        try {
          final doc = await FirebaseFirestore.instance
              .collection('users')
              .doc(u)
              .get();
          if (doc.exists) {
            assignerNames[u] = doc.data()?['username'] ?? u;
          }
        } catch (_) {}
      }

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final source =
            (data['source'] as String? ?? '').toLowerCase().trim();
        final status = data['status'] as String? ?? '';
        if ((source != 'sme' && source != 'dme') || status != 'In Progress') {
          continue;
        }
        final sourceLabel = source == 'sme' ? 'SME' : 'DME';
        final assignedByUid = data['assigned_by'] as String? ?? '';
        final assignedByName = assignerNames[assignedByUid] ?? 'Unknown';
        final ts = (data['created_at'] as Timestamp?)?.toDate();

        items.add(_NotifItem(
          type: _NotifType.leadAssignment,
          id: doc.id,
          title: data['name'] as String? ?? 'Unknown',
          subtitle: '$sourceLabel lead assigned by $assignedByName',
          time: ts,
        ));
      }
    } catch (e) {
      debugPrint('Error fetching assigned leads: $e');
    }
  }

  Future<void> _fetchAssignedComplaints(
      String uid, List<_NotifItem> items) async {
    try {
      final complaints = await DmeComplaintService.instance
          .getAssignedComplaints(userId: uid, status: 'raised');
      for (final c in complaints) {
        final text = c.complaintText;
        final subtitle =
            text.length > 70 ? '${text.substring(0, 70)}...' : text;
        items.add(_NotifItem(
          type: _NotifType.complaint,
          id: c.id ?? '',
          title: c.customerName,
          subtitle: subtitle,
          time: c.createdAt,
        ));
      }
    } catch (e) {
      debugPrint('Error fetching complaints: $e');
    }
  }

  // ─── Tap Handlers ─────────────────────────────────────────────────────────

  Future<void> _handleTap(_NotifItem item) async {
    if (item.type == _NotifType.transfer) {
      try {
        await FirebaseFirestore.instance
            .collection('follow_ups')
            .doc(item.id)
            .update({'notification_seen': true});
      } catch (_) {}
      await _scheduleTransferredLeadReminder(item.id);
      if (!mounted) return;
      Navigator.of(context).pop();
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => PresentFollowUp(docId: item.id)),
      );
    } else if (item.type == _NotifType.leadAssignment) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => PresentFollowUp(docId: item.id)),
      );
    } else if (item.type == _NotifType.complaint) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const DmeComplaintsManagementPage()),
      );
    }
  }

  Future<void> _scheduleTransferredLeadReminder(String docId) async {
    try {
      final leadDoc = await FirebaseFirestore.instance
          .collection('follow_ups')
          .doc(docId)
          .get();
      final leadData = leadDoc.data();
      if (leadData == null) return;
      final reminderStr = leadData['reminder'];
      if (reminderStr is! String || reminderStr.isEmpty) return;
      final reminderDate =
          DateFormat('dd-MM-yyyy hh:mm a').tryParse(reminderStr);
      if (reminderDate == null || !reminderDate.isAfter(DateTime.now())) return;
      final notifId =
          int.tryParse(docId.hashCode.abs().toString().substring(0, 7)) ?? 0;
      await AwesomeNotifications().cancelSchedule(notifId);
      await NotificationPermissionService.instance.safeCreateNotification(
        content: NotificationContent(
          id: notifId,
          channelKey: 'basic_channel',
          title: 'Follow-Up Reminder',
          body: 'Reminder for ${leadData['name'] ?? 'lead'}',
          notificationLayout: NotificationLayout.Default,
          payload: {
            'docId': docId,
            'type': 'lead',
            'action': 'edit_followup',
          },
        ),
        schedule: NotificationCalendar(
          year: reminderDate.year,
          month: reminderDate.month,
          day: reminderDate.day,
          hour: reminderDate.hour,
          minute: reminderDate.minute,
          second: 0,
          millisecond: 0,
          repeats: false,
          preciseAlarm: true,
        ),
      );
    } catch (e) {
      debugPrint('Error scheduling reminder for transferred lead: $e');
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _fetchAll,
          ),
        ],
      ),
      backgroundColor:
          isDark ? const Color(0xFF181A20) : const Color(0xFFF6F7FB),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? _buildEmpty(isDark)
              : RefreshIndicator(
                  onRefresh: _fetchAll,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _items.length,
                    itemBuilder: (context, i) => _buildCard(_items[i], isDark),
                  ),
                ),
    );
  }

  Widget _buildEmpty(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.notifications_off_rounded,
            size: 64,
            color: isDark ? Colors.white38 : Colors.black26,
          ),
          const SizedBox(height: 16),
          Text(
            'No Notifications',
            style: TextStyle(
              fontSize: 18,
              color: isDark ? Colors.white60 : Colors.black54,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(_NotifItem item, bool isDark) {
    final timeStr = item.time != null
        ? DateFormat('dd MMM, hh:mm a').format(item.time!)
        : '';

    final Color accentColor;
    final IconData iconData;
    final String typeLabel;

    switch (item.type) {
      case _NotifType.transfer:
        accentColor = const Color(0xFF1565C0);
        iconData = Icons.swap_horiz_rounded;
        typeLabel = 'Lead Transferred';
      case _NotifType.leadAssignment:
        accentColor = const Color(0xFF2E7D32);
        iconData = Icons.person_add_alt_1_rounded;
        typeLabel = 'Lead Assigned';
      case _NotifType.complaint:
        accentColor = const Color(0xFFC62828);
        iconData = Icons.assignment_rounded;
        typeLabel = 'Complaint Assigned';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: isDark ? const Color(0xFF23272F) : Colors.white,
      elevation: 1.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side:
            BorderSide(color: accentColor.withValues(alpha: 0.25), width: 1),
      ),
      child: InkWell(
        onTap: () => _handleTap(item),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon badge
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(iconData, color: accentColor, size: 22),
              ),
              const SizedBox(width: 14),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            typeLabel,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: accentColor,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          timeStr,
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white38 : Colors.black38,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: isDark ? Colors.white30 : Colors.black26,
              ),
            ],
          ),
        ),
      ),
    );
  }
}