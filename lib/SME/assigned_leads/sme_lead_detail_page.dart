import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../Navigation/user_cache_service.dart';
import '../../Leads/leadsform.dart';
import '../sme_call_scanner_service.dart';
import 'sme_lead_helpers.dart';

class SmeLeadDetailPageFromId extends StatelessWidget {
  final String docId;
  const SmeLeadDetailPageFromId({super.key, required this.docId});

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return FutureBuilder<DocumentSnapshot>(
      future:
          FirebaseFirestore.instance.collection('follow_ups').doc(docId).get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        final doc = snapshot.data;
        if (doc == null || !doc.exists) {
          return Scaffold(
            appBar: AppBar(title: const Text('Lead Not Found')),
            body: const Center(child: Text('Lead document does not exist.')),
          );
        }
        final data = doc.data() as Map<String, dynamic>;
        final assignedByUid = data['assigned_by'] as String? ?? '';

        return FutureBuilder<DocumentSnapshot>(
          future: assignedByUid.isNotEmpty
              ? FirebaseFirestore.instance
                  .collection('users')
                  .doc(assignedByUid)
                  .get()
              : null,
          builder: (context, userSnap) {
            String assignerName = 'System';
            if (userSnap.hasData &&
                userSnap.data != null &&
                userSnap.data!.exists) {
              assignerName = (userSnap.data!.data()
                      as Map<String, dynamic>?)?['username'] ??
                  'Unknown';
            }
            return SmeLeadDetailPage(
              doc: doc,
              data: data,
              assignerName: assignerName,
              currentUid: currentUid,
            );
          },
        );
      },
    );
  }
}

class SmeLeadDetailPage extends StatefulWidget {
  final DocumentSnapshot doc;
  final Map<String, dynamic> data;
  final String assignerName;
  final String currentUid;

  const SmeLeadDetailPage({
    super.key,
    required this.doc,
    required this.data,
    required this.assignerName,
    required this.currentUid,
  });

  @override
  State<SmeLeadDetailPage> createState() => _SmeLeadDetailPageState();
}

class _SmeLeadDetailPageState extends State<SmeLeadDetailPage> {
  static const Color _brandPrimary = Color(0xFF005BAC);
  static const Color _brandAccent = Color(0xFF008BD6);
  static const Color _teal = Color(0xFF00897B);

  late Map<String, dynamic> _data;
  bool _needRefresh = false;

  @override
  void initState() {
    super.initState();
    _data = Map<String, dynamic>.from(widget.data);
    _refreshData();
  }

  Future<void> _refreshData() async {
    final snap = await FirebaseFirestore.instance
        .collection('follow_ups')
        .doc(widget.doc.id)
        .get();
    if (snap.exists && mounted) {
      setState(() => _data = snap.data() as Map<String, dynamic>);
    }
  }

  Future<void> _scanCurrentLeadCallLog() async {
    var status = await Permission.phone.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Phone permission denied')),
        );
      }
      return;
    }

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );
    }

    try {
      final map = Map<String, dynamic>.from(_data);
      map['docId'] = widget.doc.id;

      final matched = await SmeCallScannerService.scanTodayCallLog([map], currentUid: widget.currentUid);

      if (mounted) Navigator.of(context).pop();

      if (matched.isNotEmpty) {
        _needRefresh = true;
        await _refreshData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Call detected! Lead marked as Called.'),
              backgroundColor: Color(0xFF4CAF50),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No call detected for today.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      debugPrint('Error scanning lead call log: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error scanning call log: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _addScreeningNotes() async {
    final existingNotes = _data['screening_notes'] ?? '';
    final controller = TextEditingController(text: existingNotes);
    final notes = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(children: [
          Icon(Icons.edit_note_rounded, color: _brandPrimary, size: 24),
          SizedBox(width: 8),
          Text('Screening Notes',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        ]),
        content: TextField(
          controller: controller,
          maxLines: 5,
          decoration: InputDecoration(
            hintText: 'Add your notes about this lead...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: Colors.grey.shade50,
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            style: ElevatedButton.styleFrom(
                backgroundColor: _brandPrimary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (notes != null && mounted) {
      await FirebaseFirestore.instance
          .collection('follow_ups')
          .doc(widget.doc.id)
          .update({'screening_notes': notes});
      _needRefresh = true;
      await _refreshData();
    }
  }

  Future<void> _requestDeletion() async {
    if (_data['pendingDeletion'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Deletion request is already pending approval.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final reasonController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final reason = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_forever_rounded, color: Colors.red, size: 24),
            SizedBox(width: 8),
            Text('Request Lead Deletion',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you sure you want to request deletion of this lead? It will require approval from an SME team lead.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: reasonController,
                autofocus: true,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Enter reason for deletion...',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Reason is required'
                    : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(ctx).pop(reasonController.text.trim());
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Submit Request',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (reason == null || reason.isEmpty || !mounted) return;

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      final cache = UserCacheService.instance;
      await cache.ensureLoaded();

      final leadRef = FirebaseFirestore.instance
          .collection('follow_ups')
          .doc(widget.doc.id);
      final reqRef =
          FirebaseFirestore.instance.collection('sme_deletion_requests').doc();

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        transaction.update(leadRef, {'pendingDeletion': true});
        transaction.set(reqRef, {
          'leadId': widget.doc.id,
          'leadData': _data,
          'reason': reason,
          'requestedBy': widget.currentUid,
          'userName': cache.username ?? '',
          'userBranch': cache.branch ?? '',
          'userEmail': FirebaseAuth.instance.currentUser?.email ?? '',
          'status': 'pending',
          'requestedAt': FieldValue.serverTimestamp(),
        });
      });

      if (!mounted) return;
      Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Deletion request submitted for SME approval.'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      debugPrint('Error requesting lead deletion: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error requesting deletion: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _onCallPressed() async {
    final phone = _data['phone'] ?? '';
    if (phone.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No phone number available')));
      }
      return;
    }
    var status = await Permission.phone.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Phone permission denied')));
      }
      return;
    }
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not launch dialer')));
      }
    }
  }

  Future<void> _promoteToLead() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FollowUpForm(
          docId: widget.doc.id,
          initialName: _data['name'] ?? '',
          initialPhone: _data['phone'] ?? '',
          initialAddress: _data['address'] ?? '',
          initialPlatform: _data['platform'] ?? '',
          initialPriority: _data['priority'] ?? 'High',
          initialAdName: _data['ad_name'] ?? '',
          source: 'SME',
        ),
      ),
    );
    if (result == true && mounted) {
      final updateMap = <String, dynamic>{
        'screening_status': 'promoted',
        'screened_by': widget.currentUid,
        'screened_at': FieldValue.serverTimestamp(),
      };
      if (_data['created_at'] == null) {
        updateMap['created_at'] = FieldValue.serverTimestamp();
      }
      if (_data['assigned_to'] != null && (_data['assigned_to_name'] == null || _data['assigned_to_name'] == 'Unknown' || _data['assigned_to_name'] == '')) {
        updateMap['assigned_to'] = _data['assigned_to'];
      }
      await FirebaseFirestore.instance
          .collection('follow_ups')
          .doc(widget.doc.id)
          .update(updateMap);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Lead promoted successfully!'),
          backgroundColor: Color(0xFF4CAF50)));
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  Future<void> _rejectLead() async {
    final reason = await _showRejectDialog();
    if (reason == null || reason.isEmpty) return;
    await FirebaseFirestore.instance
        .collection('follow_ups')
        .doc(widget.doc.id)
        .update({
      'screening_status': 'rejected',
      'rejection_reason': reason,
      'screened_by': widget.currentUid,
      'screened_at': FieldValue.serverTimestamp(),
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Lead rejected'), backgroundColor: Color(0xFFF44336)));
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  Future<String?> _showRejectDialog() async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(children: [
          Icon(Icons.cancel_rounded, color: Color(0xFFF44336), size: 24),
          SizedBox(width: 8),
          Text('Reject Lead',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        ]),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Enter reason for rejection...',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Reason is required' : null,
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(ctx).pop(controller.text.trim());
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF44336),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            child: const Text('Reject', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final name = _data['name'] ?? 'No Name';
    final phone = _data['phone'] ?? '';
    final comments = _data['comments'] ?? '';
    final priority = _data['priority'] ?? 'High';
    final platform = _data['platform'] ?? '';
    final branch = _data['branch'] ?? '';
    final address = _data['address'] ?? '';
    final screeningStatus = _data['screening_status'] ?? 'pending';
    final screeningNotes = _data['screening_notes'] ?? '';
    final rejectionReason = _data['rejection_reason'] ?? '';
    final callDuration = _data['screening_call_duration'] as int?;

    String formattedDate = 'No Date';
    final date = _data['date'];
    if (date is Timestamp) {
      formattedDate = DateFormat('dd MMM yyyy').format(date.toDate());
    } else if (date is DateTime) {
      formattedDate = DateFormat('dd MMM yyyy').format(date);
    }

    String? callTimeStr;
    final callTime = _data['screening_call_time'];
    if (callTime is Timestamp) {
      callTimeStr =
          DateFormat('dd MMM yyyy, hh:mm a').format(callTime.toDate());
    }

    final statusColor = getScreeningStatusColor(screeningStatus);
    final priorityColor = getPriorityColor(priority);
    final isFinalised =
        screeningStatus == 'promoted' || screeningStatus == 'rejected';

    final mustAct = screeningStatus == 'called';

    return PopScope(
      canPop: !mustAct,
      onPopInvokedWithResult: (didPop, result) {
        if (mustAct && !didPop) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text(
                      'Please select Promote or Reject for the called lead.'),
                  backgroundColor: Color(0xFFFFA500)),
            );
          }
        }
      },
      child: Scaffold(
        backgroundColor:
            isDark ? const Color(0xFF0F1C2A) : const Color(0xFFF2F6FA),
        appBar: AppBar(
          title: Text(name,
              style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Montserrat',
                  fontSize: 17)),
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                  colors: [_brandPrimary, _brandAccent],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
            ),
          ),
          foregroundColor: Colors.white,
          elevation: 0,
          leading: mustAct
              ? const SizedBox()
              : IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded),
                  onPressed: () => Navigator.of(context).pop(_needRefresh),
                ),
          actions: mustAct ? [] : [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Check Call Log',
              onPressed: _scanCurrentLeadCallLog,
            ),
            IconButton(
              icon:
                  const Icon(Icons.delete_outline_rounded, color: Colors.white),
              tooltip: 'Delete Lead',
              onPressed: _requestDeletion,
            ),
            IconButton(
                icon: const Icon(Icons.edit_note_rounded),
                tooltip: 'Add Notes',
                onPressed: _addScreeningNotes),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                ),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.15),
                        shape: BoxShape.circle),
                    child: Icon(getStatusIcon(screeningStatus),
                        color: statusColor, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(screeningStatusLabel(screeningStatus),
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: statusColor)),
                        if (callTimeStr != null)
                          Text('Called on $callTimeStr',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: statusColor.withValues(alpha: 0.7))),
                        if (callDuration != null)
                          Text('Duration: ${callDuration}s',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: statusColor.withValues(alpha: 0.7))),
                      ]),
                ]),
              ),
              const SizedBox(height: 16),

              _sectionCard(
                  isDark: isDark,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionLabel('Contact Information', isDark),
                        const SizedBox(height: 12),
                        _detailRow(Icons.person_rounded, 'Name', name, isDark),
                        if (phone.isNotEmpty)
                          _detailRow(
                              Icons.phone_rounded, 'Phone', phone, isDark),
                        if (address.isNotEmpty)
                          _detailRow(Icons.location_on_rounded, 'Address',
                              address, isDark),
                        if (branch.isNotEmpty)
                          _detailRow(
                              Icons.business_rounded, 'Branch', branch, isDark),
                      ])),
              const SizedBox(height: 12),

              _sectionCard(
                  isDark: isDark,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionLabel('Lead Information', isDark),
                        const SizedBox(height: 12),
                        _detailRow(Icons.calendar_today_rounded, 'Date',
                            formattedDate, isDark),
                        _detailRow(Icons.person_outline_rounded, 'Assigned By',
                            widget.assignerName, isDark),
                        if (platform.isNotEmpty)
                          _detailRow(Icons.share_rounded, 'Platform', platform,
                              isDark),
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(children: [
                            Icon(Icons.flag_rounded,
                                size: 16, color: Colors.grey.shade500),
                            const SizedBox(width: 10),
                            Text('Priority',
                                style: TextStyle(
                                    fontSize: 13, color: Colors.grey.shade500)),
                            const SizedBox(width: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 5),
                              decoration: BoxDecoration(
                                  color: priorityColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(20)),
                              child: Text(priority,
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: priorityColor)),
                            ),
                          ]),
                        ),
                      ])),

              if (comments.isNotEmpty) ...[
                const SizedBox(height: 12),
                _sectionCard(
                    isDark: isDark,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionLabel('SME Notes', isDark),
                          const SizedBox(height: 10),
                          Text(comments,
                              style: TextStyle(
                                  fontSize: 13,
                                  color:
                                      isDark ? Colors.white70 : Colors.black87,
                                  height: 1.5)),
                        ])),
              ],

              if (screeningNotes.isNotEmpty) ...[
                const SizedBox(height: 12),
                _sectionCard(
                    isDark: isDark,
                    accentColor: _brandPrimary,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionLabel('Your Screening Notes', isDark,
                              color: _brandPrimary),
                          const SizedBox(height: 10),
                          Text(screeningNotes,
                              style: TextStyle(
                                  fontSize: 13,
                                  color:
                                      isDark ? Colors.white70 : Colors.black87,
                                  height: 1.5)),
                        ])),
              ],

              if (screeningStatus == 'rejected' &&
                  rejectionReason.isNotEmpty) ...[
                const SizedBox(height: 12),
                _sectionCard(
                    isDark: isDark,
                    accentColor: const Color(0xFFF44336),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionLabel('Rejection Reason', isDark,
                              color: const Color(0xFFF44336)),
                          const SizedBox(height: 10),
                          Text(rejectionReason,
                              style: TextStyle(
                                  fontSize: 13,
                                  color:
                                      isDark ? Colors.white70 : Colors.black87,
                                  height: 1.5)),
                        ])),
              ],
            ],
          ),
        ),
        bottomNavigationBar: Container(
          padding: EdgeInsets.fromLTRB(
              16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1A2A2A) : Colors.white,
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, -4))
            ],
          ),
          child: Row(children: [
            if (!isFinalised && screeningStatus != 'called')
              Expanded(
                child: GestureDetector(
                  onTap: _onCallPressed,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [_teal, Color(0xFF00BCD4)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                            color: _teal.withValues(alpha: 0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 4))
                      ],
                    ),
                    child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.phone_rounded,
                              color: Colors.white, size: 20),
                          SizedBox(width: 8),
                          Text('Call Customer',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700)),
                        ]),
                  ),
                ),
              ),
            if (screeningStatus == 'called') ...[
              Expanded(
                child: GestureDetector(
                  onTap: _promoteToLead,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4CAF50),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                            color:
                                const Color(0xFF4CAF50).withValues(alpha: 0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 4))
                      ],
                    ),
                    child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.thumb_up_rounded,
                              color: Colors.white, size: 20),
                          SizedBox(width: 8),
                          Text('Promote',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700)),
                        ]),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: _rejectLead,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF44336),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                            color:
                                const Color(0xFFF44336).withValues(alpha: 0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 4))
                      ],
                    ),
                    child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.thumb_down_rounded,
                              color: Colors.white, size: 20),
                          SizedBox(width: 8),
                          Text('Reject',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700)),
                        ]),
                  ),
                ),
              ),
            ],
            if (isFinalised)
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                    border:
                        Border.all(color: statusColor.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(getStatusIcon(screeningStatus),
                            color: statusColor, size: 20),
                        const SizedBox(width: 8),
                        Text('Lead ${screeningStatusLabel(screeningStatus)}',
                            style: TextStyle(
                                color: statusColor,
                                fontSize: 15,
                                fontWeight: FontWeight.w700)),
                      ]),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _sectionCard(
      {required Widget child, required bool isDark, Color? accentColor}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C2C3C) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: accentColor != null
            ? Border.all(color: accentColor.withValues(alpha: 0.2))
            : null,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
              blurRadius: 10,
              offset: const Offset(0, 3))
        ],
      ),
      child: child,
    );
  }

  Widget _sectionLabel(String label, bool isDark, {Color? color}) {
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
        color: color?.withValues(alpha: 0.7) ??
            (isDark ? Colors.grey.shade500 : Colors.grey.shade400),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 16, color: Colors.grey.shade400),
        const SizedBox(width: 10),
        SizedBox(
            width: 80,
            child: Text(label,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500))),
        Expanded(
            child: Text(value,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : const Color(0xFF0D2B40)))),
      ]),
    );
  }
}
