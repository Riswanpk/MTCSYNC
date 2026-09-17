import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import '../models/dme_complaint_model.dart';
import '../services/dme_complaints_service.dart';
import '../widgets/dme_complaint_voice_widget.dart';

class ComplaintDetailPage extends StatefulWidget {
  final int complaintId;
  final bool readOnly;

  const ComplaintDetailPage({
    super.key,
    required this.complaintId,
    this.readOnly = false,
  });

  @override
  State<ComplaintDetailPage> createState() => _ComplaintDetailPageState();
}

class _ComplaintDetailPageState extends State<ComplaintDetailPage> {
  DmeComplaint? _complaint;
  List<DmeComplaintUpdate> _updates = [];
  bool _isLoading = true;

  final TextEditingController _actionRemarksController = TextEditingController();
  String? _actionAudioUrl;
  bool _isUploadingAudio = false;
  bool _isSubmitting = false;

  String? _currentUserUid;
  String? _currentUserRole;
  String? _currentUserName;
  String? _currentUserEmail;
  String? _currentUserBranch;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    _loadComplaintData();
  }

  @override
  void dispose() {
    _actionRemarksController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _currentUserUid = user.uid;
      _currentUserEmail = user.email;
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (doc.exists) {
          final data = doc.data()!;
          _currentUserRole = (data['role'] as String? ?? '').toLowerCase();
          _currentUserName = data['username'] ?? data['name'] ?? user.email?.split('@').first ?? 'User';
          _currentUserBranch = (data['branch'] as String? ?? '').toUpperCase().trim();
        }
      } catch (_) {}
      if (mounted) setState(() {});
    }
  }

  Future<void> _loadComplaintData() async {
    setState(() => _isLoading = true);
    try {
      final res = await DmeComplaintsService.instance.fetchComplaintWithHistory(widget.complaintId);
      if (mounted) {
        setState(() {
          _complaint = res['complaint'] as DmeComplaint;
          _updates = res['updates'] as List<DmeComplaintUpdate>;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading complaint: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading complaint: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Call customer - opens native dialer with phone pasted, NO call detection
  Future<void> _callCustomer() async {
    if (_complaint == null) return;
    final phone = _complaint!.customerPhone.trim();
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No phone number available for this customer.')),
      );
      return;
    }

    // Clean digits
    final cleanDigits = phone.replaceAll(RegExp(r'\D'), '');
    final uri = Uri.parse('tel:$cleanDigits');

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(uri);
      }
    } catch (e) {
      debugPrint('Error launching dialer: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open dialer: $e')),
        );
      }
    }
  }

  /// Assigned user submits action taken
  Future<void> _submitActionTaken() async {
    final remarks = _actionRemarksController.text.trim();
    if (remarks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter remarks detailing the action taken.')),
      );
      return;
    }

    if (_isUploadingAudio) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please wait for the audio to finish uploading.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await DmeComplaintsService.instance.submitActionTaken(
        complaintId: _complaint!.id,
        actionByUid: _currentUserUid ?? '',
        actionByName: _currentUserName ?? 'Assigned User',
        actionByRole: _currentUserRole,
        remarks: remarks,
        audioUrl: _actionAudioUrl,
        createdByUid: _complaint!.createdByUid,
        customerName: _complaint!.customerName,
      );

      _actionRemarksController.clear();
      _actionAudioUrl = null;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Action submitted successfully! Notification sent to DME.'),
            backgroundColor: Colors.green,
          ),
        );
        await _loadComplaintData();
      }
    } catch (e) {
      debugPrint('Error submitting action: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit action: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// DME user marks complaint as Resolved
  Future<void> _markResolved() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Resolution'),
        content: const Text('Are you sure you want to mark this complaint as Resolved?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            child: const Text('Mark Resolved'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isSubmitting = true);
    try {
      await DmeComplaintsService.instance.markResolved(
        complaintId: _complaint!.id,
        verifiedByUid: _currentUserUid ?? '',
        verifiedByName: _currentUserName ?? 'DME User',
        assignedToUid: _complaint!.assignedToUid,
        createdByUid: _complaint!.createdByUid,
        customerName: _complaint!.customerName,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Complaint marked as Resolved ✓'), backgroundColor: Colors.green),
        );
        await _loadComplaintData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// DME user marks complaint as Not Resolved (prompts for remarks and sends back)
  Future<void> _markNotResolved() async {
    final remarksController = TextEditingController();
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark Not Resolved'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Please provide remarks explaining why the issue is not resolved. These will be sent back to the assigned user:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: remarksController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Enter feedback/instructions for assigned user...',
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (remarksController.text.trim().isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Please enter remarks.')),
                );
                return;
              }
              Navigator.pop(ctx, true);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Send Back'),
          ),
        ],
      ),
    );

    if (proceed != true) return;

    final remarks = remarksController.text.trim();
    setState(() => _isSubmitting = true);

    try {
      await DmeComplaintsService.instance.markNotResolved(
        complaintId: _complaint!.id,
        verifiedByUid: _currentUserUid ?? '',
        verifiedByName: _currentUserName ?? 'DME User',
        remarks: remarks,
        assignedToUid: _complaint!.assignedToUid,
        customerName: _complaint!.customerName,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Complaint marked Not Resolved and sent back to assigned user.'),
            backgroundColor: Colors.orange,
          ),
        );
        await _loadComplaintData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// Manager escalates complaint to themselves
  Future<void> _escalateComplaint() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Escalate Complaint'),
        content: Text(
          'Do you want to escalate this complaint to yourself?\n\nIt will be assigned to you (${_currentUserName ?? 'Manager'}), and the former user (${_complaint!.assignedToName ?? 'User'}) will no longer see it in their assigned complaints list.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, foregroundColor: Colors.white),
            child: const Text('Escalate to Me'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isSubmitting = true);
    try {
      await DmeComplaintsService.instance.escalateComplaint(
        complaintId: _complaint!.id,
        managerUid: _currentUserUid ?? '',
        managerName: _currentUserName ?? 'Manager',
        managerEmail: _currentUserEmail ?? '',
        formerAssignedToUid: _complaint!.assignedToUid,
        formerAssignedToName: _complaint!.assignedToName ?? 'Former User',
        formerAssignedToEmail: _complaint!.assignedToEmail ?? '',
        customerName: _complaint!.customerName,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Complaint successfully escalated to you!'),
            backgroundColor: Colors.green,
          ),
        );
        await _loadComplaintData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to escalate: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// Delete complaint (available for DME creator / Admin)
  Future<void> _deleteComplaint() async {
    if (_complaint == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Complaint'),
        content: Text('Are you sure you want to delete complaint #${_complaint!.id} for "${_complaint!.customerName}"?\n\nThis action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSubmitting = true);
    try {
      await DmeComplaintsService.instance.deleteComplaint(_complaint!.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Complaint #${_complaint!.id} deleted successfully.'),
            backgroundColor: Colors.red,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('Error deleting complaint: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete complaint: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String _formatDateTime(DateTime? dt) {
    if (dt == null) return '';
    return DateFormat('dd MMM yyyy, hh:mm a').format(dt);
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'resolved':
        return Colors.green;
      case 'action_taken':
        return const Color(0xFF005BAC);
      case 'not_resolved':
        return Colors.deepOrange;
      default:
        return Colors.orange[800]!;
    }
  }

  String _getStatusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'resolved':
        return 'RESOLVED';
      case 'action_taken':
        return 'ACTION TAKEN / UNDER REVIEW';
      case 'not_resolved':
        return 'NOT RESOLVED (REOPENED)';
      default:
        return 'ASSIGNED / PENDING ACTION';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: Text('Complaint #${widget.complaintId}'),
          backgroundColor: const Color(0xFF005BAC),
          foregroundColor: Colors.white,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_complaint == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Complaint Not Found'),
          backgroundColor: const Color(0xFF005BAC),
          foregroundColor: Colors.white,
        ),
        body: const Center(child: Text('Complaint not found or has been removed.')),
      );
    }

    final c = _complaint!;
    final statusColor = _getStatusColor(c.status);
    final statusLabel = _getStatusLabel(c.status);

    // Permission flags
    final isAssignedToMe = _currentUserUid != null && _currentUserUid == c.assignedToUid;
    final isDmeRole = _currentUserRole == 'dme_user' || _currentUserRole == 'dme_admin';
    final isCreator = _currentUserUid != null && _currentUserUid == c.createdByUid;
    final isManager = _currentUserRole == 'manager';
    final isResolved = c.status == 'resolved';
    final isUnderReview = c.status == 'action_taken';
    final canEscalate = isManager && !isAssignedToMe && !isResolved && !isUnderReview && (c.branch == _currentUserBranch);
    // Submit action is ONLY for the user to whom the complaint is assigned (Sales / escalated Manager), never DME users
    final canSubmitAction = !widget.readOnly && isAssignedToMe && !isDmeRole && !isResolved && !isUnderReview;

    final canDelete = !widget.readOnly && (isDmeRole || isCreator);

    return Scaffold(
      appBar: AppBar(
        title: Text('Complaint #${c.id}'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadComplaintData,
          ),
          if (canDelete)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.white),
              tooltip: 'Delete Complaint',
              onPressed: _isSubmitting ? null : _deleteComplaint,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status & Escalation Banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: statusColor.withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  Icon(
                    c.status == 'resolved' ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                    color: statusColor,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          statusLabel,
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          'Updated ${_formatDateTime(c.updatedAt)}',
                          style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.black45),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (c.isEscalated) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Escalated to Manager ${c.assignedToName ?? ''} (Former User: ${c.formerAssignedToName ?? 'Unknown'})',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.orange),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),

            // Customer Info Card with Direct Call Button
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const CircleAvatar(
                          backgroundColor: Color(0xFF005BAC),
                          child: Icon(Icons.person, color: Colors.white),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                c.customerName,
                                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                c.customerPhone,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Color(0xFF005BAC),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (c.customerAddress != null && c.customerAddress!.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  c.customerAddress!,
                                  style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black54),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF005BAC).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Branch: ${c.branch}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF005BAC)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Call Customer Button (Disabled if resolved)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: isResolved ? null : _callCustomer,
                        icon: const Icon(Icons.call, size: 20),
                        label: Text(isResolved ? 'Complaint Resolved' : 'Call ${c.customerPhone}'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF8CC63F),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: isDark ? Colors.white12 : Colors.black12,
                          disabledForegroundColor: isDark ? Colors.white38 : Colors.black38,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Initial Complaint Details Card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.report_problem_rounded, color: Colors.deepOrange, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'Complaint Description',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        Text(
                          _formatDateTime(c.createdAt),
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF16253B) : const Color(0xFFF8F9FA),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        c.description,
                        style: const TextStyle(fontSize: 14, height: 1.4),
                      ),
                    ),
                    if (c.initialAudioUrl != null && c.initialAudioUrl!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'Initial Call Record Audio:',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
                      ),
                      const SizedBox(height: 6),
                      DmeComplaintVoiceWidget(
                        initialAudioUrl: c.initialAudioUrl,
                        readOnly: true,
                        onAudioChanged: (_) {},
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            'Raised by: ${c.createdByName ?? 'DME'}',
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Assigned: ${c.assignedToName ?? 'User'} (${c.assignedToRole ?? 'sales'})',
                            style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Manager Escalation Action
            if (canEscalate) ...[
              Card(
                color: Colors.orange.withValues(alpha: 0.1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: Colors.orange),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14.0),
                  child: Row(
                    children: [
                      const Icon(Icons.arrow_upward_rounded, color: Colors.deepOrange),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Branch Manager Action:\nYou can escalate this complaint to handle it yourself.',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                        ),
                      ),
                      ElevatedButton(
                        onPressed: _isSubmitting ? null : _escalateComplaint,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepOrange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('Escalate to Me', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Action Submission Form (Only shown to the currently assigned user when not resolved and not under review)
            if (canSubmitAction) ...[
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.edit_note_rounded, color: Color(0xFF005BAC), size: 22),
                          SizedBox(width: 8),
                          Text(
                            'Submit Action / Remarks',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _actionRemarksController,
                        maxLines: 3,
                        decoration: InputDecoration(
                          hintText: 'Enter details of discussion with customer and action taken...',
                          filled: true,
                          fillColor: isDark ? const Color(0xFF16253B) : const Color(0xFFF3F4F6),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Option to add voice record (no 'optional' text shown)
                      DmeComplaintVoiceWidget(
                        initialAudioUrl: _actionAudioUrl,
                        onAudioChanged: (url) => setState(() => _actionAudioUrl = url),
                        onUploadStateChanged: (uploading) => setState(() => _isUploadingAudio = uploading),
                      ),
                      const SizedBox(height: 14),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isSubmitting ? null : _submitActionTaken,
                          icon: _isSubmitting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.send_rounded, size: 18),
                          label: Text(_isSubmitting ? 'Submitting...' : 'Submit Action & Notify DME'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF005BAC),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ] else if (!widget.readOnly && isUnderReview && isAssignedToMe && !isDmeRole) ...[
              // Banner informing assigned user that their action is under DME review
              Card(
                elevation: 1,
                color: Colors.blue.withValues(alpha: 0.1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: Colors.blue.withValues(alpha: 0.4)),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(14.0),
                  child: Row(
                    children: [
                      Icon(Icons.hourglass_top_rounded, color: Color(0xFF005BAC), size: 22),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Action Submitted - Under Review',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF005BAC)),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Your response has been submitted to the DME team. Further actions are disabled until review is complete.',
                              style: TextStyle(fontSize: 12, color: Colors.black87),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // DME User Verification Area (Only shown when assigned user/manager has submitted action, i.e. status is 'action_taken')
            if (!widget.readOnly && (isDmeRole || isCreator) && c.status == 'action_taken') ...[
              Card(
                elevation: 2,
                color: isDark ? const Color(0xFF15263F) : const Color(0xFFF0F7FF),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: const Color(0xFF005BAC).withValues(alpha: 0.3)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.verified_user_rounded, color: Color(0xFF005BAC), size: 20),
                          SizedBox(width: 8),
                          Text(
                            'DME Resolution Verification',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Review the assigned user\'s response and confirm if the customer\'s complaint is resolved:',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _isSubmitting ? null : _markNotResolved,
                              icon: const Icon(Icons.close_rounded, color: Colors.red),
                              label: const Text('Not Resolved', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Colors.red),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _isSubmitting ? null : _markResolved,
                              icon: const Icon(Icons.check_rounded, color: Colors.white),
                              label: const Text('Resolved', style: TextStyle(fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Timeline & Updates History
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.timeline_rounded, color: Color(0xFF005BAC), size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Complaint History & Activity',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (_updates.isEmpty)
                      const Text('No updates recorded yet.', style: TextStyle(color: Colors.grey, fontSize: 13))
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _updates.length,
                        separatorBuilder: (context, i) => const Divider(height: 20),
                        itemBuilder: (context, index) {
                          final u = _updates[index];
                          final timeStr = _formatDateTime(u.createdAt);

                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildActionIcon(u.actionType),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          u.actionByName ?? 'User',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                        ),
                                        Text(
                                          timeStr,
                                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _getActionDescription(u.actionType),
                                      style: TextStyle(fontSize: 12, color: _getActionColor(u.actionType), fontWeight: FontWeight.w600),
                                    ),
                                    if (u.remarks != null && u.remarks!.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        u.remarks!,
                                        style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.black87),
                                      ),
                                    ],
                                    if (u.audioUrl != null && u.audioUrl!.isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      DmeComplaintVoiceWidget(
                                        initialAudioUrl: u.audioUrl,
                                        readOnly: true,
                                        onAudioChanged: (_) {},
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildActionIcon(String type) {
    IconData icon;
    Color color;

    switch (type.toLowerCase()) {
      case 'created':
        icon = Icons.add_circle_outline_rounded;
        color = const Color(0xFF005BAC);
        break;
      case 'action_taken':
        icon = Icons.assignment_turned_in_rounded;
        color = Colors.blue;
        break;
      case 'resolved':
        icon = Icons.check_circle_rounded;
        color = Colors.green;
        break;
      case 'not_resolved':
        icon = Icons.replay_rounded;
        color = Colors.red;
        break;
      case 'escalated':
        icon = Icons.arrow_upward_rounded;
        color = Colors.deepOrange;
        break;
      default:
        icon = Icons.circle;
        color = Colors.grey;
    }

    return CircleAvatar(
      radius: 14,
      backgroundColor: color.withValues(alpha: 0.15),
      child: Icon(icon, size: 16, color: color),
    );
  }

  String _getActionDescription(String type) {
    switch (type.toLowerCase()) {
      case 'created':
        return 'Complaint Registered';
      case 'action_taken':
        return 'Action Taken & Remarks Submitted';
      case 'resolved':
        return 'Marked as Resolved';
      case 'not_resolved':
        return 'Marked as Not Resolved';
      case 'escalated':
        return 'Complaint Escalated';
      default:
        return 'Update';
    }
  }

  Color _getActionColor(String type) {
    switch (type.toLowerCase()) {
      case 'created':
        return const Color(0xFF005BAC);
      case 'action_taken':
        return Colors.blue[800]!;
      case 'resolved':
        return Colors.green[800]!;
      case 'not_resolved':
        return Colors.red[800]!;
      case 'escalated':
        return Colors.deepOrange;
      default:
        return Colors.grey;
    }
  }
}
