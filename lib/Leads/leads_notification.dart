import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:mtcsync/Misc/notification_permission_service.dart';
import 'presentfollowup.dart';

class LeadsNotificationPage extends StatefulWidget {
  final String userBranch;

  const LeadsNotificationPage({super.key, required this.userBranch});

  @override
  State<LeadsNotificationPage> createState() => _LeadsNotificationPageState();
}

class _LeadsNotificationPageState extends State<LeadsNotificationPage> {
  List<Map<String, dynamic>> _transferredLeads = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchTransferredLeads();
  }

  Future<void> _fetchTransferredLeads() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      final snapshot = await FirebaseFirestore.instance
          .collection('follow_ups')
          .where('branch', isEqualTo: widget.userBranch)
          .where('created_by', isEqualTo: currentUser.uid)
          .where('transferred_at', isNull: false)
          .where('notification_seen', isEqualTo: false)
          .orderBy('transferred_at', descending: true)
          .limit(50)
          .get();

      final leads = <Map<String, dynamic>>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        leads.add({
          'docId': doc.id,
          'name': data['name'] ?? 'Unknown',
          'phone': data['phone'] ?? 'N/A',
          'originalBranch': data['original_branch'] ?? 'Unknown',
          'transferredAt': data['transferred_at'],
          'transferredBy': data['transferred_by'] ?? 'Unknown',
        });
      }

      if (mounted) {
        setState(() {
          _transferredLeads = leads;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading notifications: $e')),
        );
      }
    }
  }

  Future<void> _openLead(String docId) async {
    // Mark notification as seen in Firestore
    try {
      await FirebaseFirestore.instance
          .collection('follow_ups')
          .doc(docId)
          .update({'notification_seen': true});
    } catch (e) {
      // Optionally handle error
    }

    // Schedule the reminder on this device (the new owner's device) so they
    // receive the notification at the right time.
    try {
      final leadDoc = await FirebaseFirestore.instance
          .collection('follow_ups')
          .doc(docId)
          .get();
      final leadData = leadDoc.data();
      if (leadData != null) {
        final reminderStr = leadData['reminder'];
        if (reminderStr is String && reminderStr.isNotEmpty) {
          final reminderDate =
              DateFormat('dd-MM-yyyy hh:mm a').tryParse(reminderStr);
          if (reminderDate != null && reminderDate.isAfter(DateTime.now())) {
            final notifId = int.tryParse(
                    docId.hashCode.abs().toString().substring(0, 7)) ??
                0;
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
          }
        }
      }
    } catch (e) {
      debugPrint('Error scheduling reminder for transferred lead: $e');
    }

    if (!mounted) return;
    Navigator.of(context).pop(); // Close notification page
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PresentFollowUp(docId: docId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lead Transfer Notifications'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      backgroundColor: isDark ? const Color(0xFF181A20) : const Color(0xFFF6F7FB),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _transferredLeads.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.notifications_off,
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
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _transferredLeads.length,
                  itemBuilder: (context, index) {
                    final lead = _transferredLeads[index];
                    final transferredAt =
                        (lead['transferredAt'] as Timestamp?)?.toDate();
                    final timeStr = transferredAt != null
                        ? DateFormat('dd MMM, hh:mm a').format(transferredAt)
                        : 'Unknown';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      color: isDark
                          ? const Color(0xFF23272F)
                          : Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: InkWell(
                        onTap: () => _openLead(lead['docId']),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.send,
                                    color: Colors.blue[700],
                                    size: 24,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Lead Transferred',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: isDark
                                                ? Colors.white70
                                                : Colors.black54,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          timeStr,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: isDark
                                                ? Colors.white54
                                                : Colors.black45,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    Icons.arrow_forward_ios,
                                    size: 16,
                                    color: isDark
                                        ? Colors.white38
                                        : Colors.black26,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? const Color(0xFF181A20)
                                      : const Color(0xFFF0F2F5),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      lead['name'] ?? 'Unknown',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: isDark
                                            ? Colors.white
                                            : Colors.black,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Phone: ${lead['phone']}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isDark
                                            ? Colors.white70
                                            : Colors.black87,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Original Branch: ${lead['originalBranch']}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isDark
                                            ? Colors.white60
                                            : Colors.black54,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: () => _openLead(lead['docId']),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue[700],
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                  ),
                                  child: const Text('View Lead'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
