import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../models/dme_complaint.dart';
import '../services/dme_complaint_service.dart';
import '../services/dme_supabase_service.dart';
import '../../Misc/voice_file_upload_widget.dart';

const Color _primary = Color(0xFF005BAC);

/// Detail page for a complaint.
///
/// [isDmeUser]      – true when opened by the user who raised the complaint.
/// [isAssignedUser] – true when the current user is the one assigned to resolve it.
class DmeComplaintDetailPage extends StatefulWidget {
  final DmeComplaint complaint;
  final bool isDmeUser;
  final bool isAssignedUser;
  final VoidCallback onUpdate;

  const DmeComplaintDetailPage({
    super.key,
    required this.complaint,
    required this.isDmeUser,
    required this.isAssignedUser,
    required this.onUpdate,
  });

  @override
  State<DmeComplaintDetailPage> createState() => _DmeComplaintDetailPageState();
}

class _DmeComplaintDetailPageState extends State<DmeComplaintDetailPage> {
  final _svc = DmeComplaintService.instance;
  final _remarksCtrl = TextEditingController();
  bool _submitting = false;
  late DmeComplaint _complaint;
  String? _assignedToUsername;
  String? _voiceFileUrl;

  @override
  void initState() {
    super.initState();
    _complaint = widget.complaint;
    _assignedToUsername = _complaint.assignedToUsername;
    // Pre-fill remarks field for assigned user so they can update
    if (widget.isAssignedUser) {
      _remarksCtrl.text = _complaint.remarks ?? '';
    }
    // Ensure Supabase is initialized
    _initSupabase();
    _fetchAssignedToUsername();
  }

  Future<void> _fetchAssignedToUsername() async {
    if (_assignedToUsername != null && _assignedToUsername!.isNotEmpty) return;
    try {
      final username = await _svc.getUsernameById(_complaint.assignedToId);
      if (mounted && username != null && username.isNotEmpty) {
        setState(() {
          _assignedToUsername = username;
        });
      }
    } catch (e) {
      // ignore error, fallback to ID
    }
  }

  Future<void> _initSupabase() async {
    try {
      await DmeSupabaseService.instance.ensureInitialized();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Init error: $e')));
      }
    }
  }

  @override
  void dispose() {
    _remarksCtrl.dispose();
    super.dispose();
  }

  // ─── ACTIONS ────────────────────────────────────────────────────────────────

  Future<void> _submitRemarks() async {
    if (_remarksCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a remark')),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw Exception('Not authenticated');
      await _svc.addRemarks(
        complaintId: _complaint.id!,
        remarks: _remarksCtrl.text.trim(),
        userId: uid,
        voiceFileUrl: _voiceFileUrl,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Remarks submitted successfully'),
            backgroundColor: Colors.green,
          ),
        );
        widget.onUpdate();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _closeComplaint() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Close Complaint'),
        content:
            Text('Close this complaint for ${_complaint.customerName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Close',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _submitting = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw Exception('Not authenticated');
      await _svc.updateComplaintStatus(
        complaintId: _complaint.id!,
        newStatus: 'verified_closed',
        userId: uid,
      );
      await _svc.markRemarksAsRead(complaintId: _complaint.id!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Complaint closed successfully'),
            backgroundColor: Colors.green,
          ),
        );
        widget.onUpdate();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _reopenComplaint() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Re-open Complaint'),
        content: Text(
            'Re-open this complaint for ${_complaint.customerName}? It will be sent back to the assigned user to add more remarks.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Re-open',
                style: TextStyle(color: Colors.orange)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _submitting = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw Exception('Not authenticated');
      await _svc.updateComplaintStatus(
        complaintId: _complaint.id!,
        newStatus: 'raised',
        userId: uid,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Complaint re-opened successfully'),
            backgroundColor: Colors.orange,
          ),
        );
        widget.onUpdate();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ─── BUILD ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd MMM yyyy, hh:mm a');
    final hasRemarks =
        _complaint.remarks != null && _complaint.remarks!.isNotEmpty;
    final isResolved = _complaint.status == 'case_resolved';
    final isClosed = _complaint.status == 'verified_closed';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Complaint Details',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600)),
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status chip
            _buildStatusChip(),
            const SizedBox(height: 16),

            // Customer info
            _buildSection(
              title: 'Customer',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_complaint.customerName,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(_complaint.customerPhone,
                      style: TextStyle(color: Colors.grey[600])),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Complaint text
            _buildSection(
              title: 'Complaint',
              child: Text(_complaint.complaintText,
                  style: const TextStyle(fontSize: 14, height: 1.5)),
            ),
            const SizedBox(height: 12),

            // Branch + Assigned To
            Row(
              children: [
                Expanded(
                  child: _buildSection(
                    title: 'Branch',
                    child: Text(_complaint.branchName,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSection(
                    title: 'Assigned To',
                    child: Text(
                      _assignedToUsername ?? _complaint.assignedToId,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Raised on
            _buildSection(
              title: 'Raised On',
              child: Text(fmt.format(_complaint.createdAt),
                  style: const TextStyle(fontSize: 13)),
            ),
            const SizedBox(height: 24),

            // ─── RESOLUTION SECTION (DME USER) ───────────────────────
            if (widget.isDmeUser) ...[
              _buildSectionHeader('Resolution'),
              const SizedBox(height: 8),
              if (!hasRemarks)
                _buildInfoBanner(
                  icon: Icons.pending_actions,
                  color: Colors.orange,
                  label: 'Not Resolved',
                  subtitle:
                      'Waiting for the assigned user to add remarks.',
                )
              else ...[
                _buildRemarksBanner(
                  title:
                      'Remarks from ${_complaint.remarkedByUsername ?? "Assigned User"}',
                  body: _complaint.remarks!,
                  date: _complaint.remarkedAt != null
                      ? fmt.format(_complaint.remarkedAt!)
                      : null,
                  color: Colors.green,
                ),
                if (isResolved && !isClosed) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _buildActionButton(
                          label: 'Re-open',
                          icon: Icons.refresh,
                          color: Colors.orange,
                          onPressed: _submitting ? null : _reopenComplaint,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildActionButton(
                          label: 'Close Complaint',
                          icon: Icons.check_circle_outline,
                          color: Colors.green,
                          onPressed: _submitting ? null : _closeComplaint,
                        ),
                      ),
                    ],
                  ),
                ],
                if (isClosed) ...[
                  const SizedBox(height: 12),
                  _buildInfoBanner(
                    icon: Icons.verified,
                    color: Colors.green,
                    label: 'Complaint Closed',
                    subtitle: null,
                  ),
                ],
              ],
            ],

            // ─── REMARKS SECTION (STAFF) ─────────────────────────────
            if (!widget.isDmeUser) ...[
              _buildSectionHeader('Remarks'),
              const SizedBox(height: 8),

              // Existing remarks display
              if (hasRemarks) ...[
                _buildRemarksBanner(
                  title:
                      'Remarked by ${_complaint.remarkedByUsername ?? "User"}',
                  body: _complaint.remarks!,
                  date: _complaint.remarkedAt != null
                      ? fmt.format(_complaint.remarkedAt!)
                      : null,
                  color: Colors.blue,
                ),
                const SizedBox(height: 16),
              ],

              // Add/update remarks — only assigned user, only if not closed
              if (widget.isAssignedUser && !isClosed && !isResolved) ...[
                Text(
                  hasRemarks ? 'Update Remarks' : 'Add Remarks',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _remarksCtrl,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: 'Enter remarks here...',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
                const SizedBox(height: 12),
                // Voice File Upload Widget
                VoiceFileUploadWidget(
                  onFileUploaded: (fileUrl) {
                    setState(() => _voiceFileUrl = fileUrl);
                  },
                  enabled: true,
                  uploadPath: 'dme_complaints/${FirebaseAuth.instance.currentUser?.email ?? "unknown"}/${_complaint.id}',
                ),
                const SizedBox(height: 12),
                _buildActionButton(
                  label: 'Submit Remarks',
                  icon: Icons.send,
                  color: _primary,
                  onPressed: _submitting ? null : _submitRemarks,
                ),
              ] else if (!widget.isAssignedUser && !hasRemarks) ...[
                _buildInfoBanner(
                  icon: Icons.info_outline,
                  color: Colors.grey,
                  label: 'No remarks yet',
                  subtitle: 'Only the assigned user can add remarks.',
                ),
              ] else if (isClosed) ...[
                _buildInfoBanner(
                  icon: Icons.verified,
                  color: Colors.green,
                  label: 'Complaint Closed',
                  subtitle: null,
                ),
              ],
            ],

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ─── HELPERS ────────────────────────────────────────────────────────────────

  Widget _buildStatusChip() {
    Color color;
    String label;
    IconData icon;
    switch (_complaint.status) {
      case 'raised':
        color = Colors.red;
        label = 'Raised';
        icon = Icons.report_problem_outlined;
        break;
      case 'case_resolved':
        color = Colors.orange;
        label = 'Resolved – Awaiting Closure';
        icon = Icons.pending_actions;
        break;
      case 'verified_closed':
        color = Colors.green;
        label = 'Closed';
        icon = Icons.check_circle_outline;
        break;
      default:
        color = Colors.grey;
        label = _complaint.status;
        icon = Icons.help_outline;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(
      {required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Colors.grey[500],
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title.toUpperCase(),
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: _primary,
        letterSpacing: 0.8,
      ),
    );
  }

  Widget _buildInfoBanner({
    required IconData icon,
    required Color color,
    required String label,
    required String? subtitle,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style: TextStyle(
                          color: color.withValues(alpha: 0.7),
                          fontSize: 12)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRemarksBanner({
    required String title,
    required String body,
    required String? date,
    required Color color,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color.withValues(alpha: 0.8))),
          const SizedBox(height: 8),
          Text(body,
              style: const TextStyle(fontSize: 14, height: 1.5)),
          if (date != null) ...[
            const SizedBox(height: 6),
            Text(date,
                style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          ],
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: _submitting
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : Icon(icon, color: Colors.white, size: 18),
        label: Text(label,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }
}
