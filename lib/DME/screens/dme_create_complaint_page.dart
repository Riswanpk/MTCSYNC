import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/dme_complaint.dart';
import '../models/dme_customer.dart';
import '../models/dme_user.dart';
import '../services/dme_complaint_service.dart';
import '../services/dme_supabase_service.dart';
import '../../Misc/voice_file_upload_widget.dart';

const Color _primary = Color(0xFF005BAC);

/// Full-page form for creating complaints with optional pre-filled customer data.
/// Designed for use from reminders/calls page with auto-filled customer info.
class DmeCreateComplaintPage extends StatefulWidget {
  final DmeUser dmeUser;
  final VoidCallback onSubmitted;
  
  // Optional pre-fill data from reminders
  final int? prefilledCustomerId;
  final String? prefilledCustomerName;
  final String? prefilledCustomerPhone;
  final int? prefilledBranchId;
  final String? prefilledBranchName;

  const DmeCreateComplaintPage({
    super.key,
    required this.dmeUser,
    required this.onSubmitted,
    this.prefilledCustomerId,
    this.prefilledCustomerName,
    this.prefilledCustomerPhone,
    this.prefilledBranchId,
    this.prefilledBranchName,
  });

  @override
  State<DmeCreateComplaintPage> createState() =>
      _DmeCreateComplaintPageState();
}

class _DmeCreateComplaintPageState extends State<DmeCreateComplaintPage> {
  final _supabase = DmeSupabaseService.instance;
  final _svc = DmeComplaintService.instance;

  final _searchCtrl = TextEditingController();
  final _complaintCtrl = TextEditingController();

  List<DmeCustomer> _customers = [];
  bool _searchingCustomers = false;
  DmeCustomer? _selectedCustomer;

  List<DmeUser> _assignableUsers = [];
  bool _loadingUsers = false;
  DmeUser? _selectedAssignee;

  bool _submitting = false;
  List<int> _myBranchIds = [];
  Set<String> _selectedComplaintTypes = <String>{};
  String? _voiceNoteUrl;
  bool _voiceUploading = false;

  @override
  void initState() {
    super.initState();
    _loadBranchIds();
    _preFillIfAvailable();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _complaintCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadBranchIds() async {
    try {
      final ids = await _supabase.getUserBranchIds(widget.dmeUser.id);
      if (mounted) setState(() => _myBranchIds = ids);
    } catch (e) {
      debugPrint('[CreateComplaint] Error loading branch IDs: $e');
    }
  }

  /// Pre-fill customer and branch info if provided from reminder
  Future<void> _preFillIfAvailable() async {
    if (widget.prefilledCustomerName == null ||
        widget.prefilledBranchId == null) {
      return;
    }

    try {
      // Create a synthetic customer object from pre-filled data
      final customer = DmeCustomer(
        id: widget.prefilledCustomerId ?? 0,
        name: widget.prefilledCustomerName!,
        phone: widget.prefilledCustomerPhone ?? '',
        branchId: widget.prefilledBranchId,
        branchName: widget.prefilledBranchName,
      );

      setState(() {
        _selectedCustomer = customer;
        _searchCtrl.text = customer.name;
        _customers = [];
      });

      // Load assignable users for this branch
      if (widget.prefilledBranchName != null &&
          widget.prefilledBranchName!.isNotEmpty) {
        await _loadAssignableUsers(widget.prefilledBranchName!);
      }
    } catch (e) {
      debugPrint('[CreateComplaint] Error pre-filling: $e');
    }
  }

  Future<void> _searchCustomers(String query) async {
    if (query.trim().length < 2) {
      setState(() => _customers = []);
      return;
    }
    setState(() => _searchingCustomers = true);
    try {
      final results = await _supabase.getCustomers(
        branchIds: _myBranchIds.isEmpty ? null : _myBranchIds,
        search: query.trim(),
        limit: 20,
      );
      if (mounted) setState(() => _customers = results);
    } catch (e) {
      debugPrint('[CreateComplaint] Customer search error: $e');
    } finally {
      if (mounted) setState(() => _searchingCustomers = false);
    }
  }

  Future<void> _onCustomerSelected(DmeCustomer customer) async {
    setState(() {
      _selectedCustomer = customer;
      _customers = [];
      _searchCtrl.text = customer.name;
      _assignableUsers = [];
      _selectedAssignee = null;
    });

    // Load users for this customer's branch from Firestore
    final branchName = customer.branchName;
    if (branchName == null || branchName.isEmpty) return;

    await _loadAssignableUsers(branchName);
  }

  Future<void> _loadAssignableUsers(String branchName) async {
    setState(() => _loadingUsers = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('branch', isEqualTo: branchName)
          .where('role',
              whereIn: ['manager', 'asst_manager', 'sales', 'dme_user'])
          .get();

      final users = snapshot.docs.map((doc) {
        final data = doc.data();
        return DmeUser(
          id: data['uid'] as String? ?? doc.id,
          firebaseUid: data['uid'] as String? ?? doc.id,
          email: data['email'] as String? ?? '',
          username: data['username'] as String? ??
              data['email'] as String? ??
              'Unknown',
          role: data['role'] as String? ?? '',
        );
      }).toList();

      if (mounted) setState(() => _assignableUsers = users);
    } catch (e) {
      debugPrint('[CreateComplaint] Error loading branch users: $e');
    } finally {
      if (mounted) setState(() => _loadingUsers = false);
    }
  }

  void _toggleComplaintType(String type) {
    setState(() {
      if (_selectedComplaintTypes.contains(type)) {
        _selectedComplaintTypes.remove(type);
      } else {
        _selectedComplaintTypes.add(type);
      }
    });
  }

  Future<void> _submit() async {
    if (_selectedCustomer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a customer')));
      return;
    }
    if (_complaintCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter complaint details')));
      return;
    }
    if (_selectedAssignee == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Please assign the complaint to a user')));
      return;
    }

    debugPrint(
        '[CreateComplaint] Submitting complaint with voiceNoteUrl: $_voiceNoteUrl');
    setState(() => _submitting = true);
    try {
      final branchId = _selectedCustomer!.branchId ?? 0;
      debugPrint(
          '[CreateComplaint] Creating complaint for customer: ${_selectedCustomer!.name}');
      final complaintId = await _svc.createComplaint(
        customerName: _selectedCustomer!.name,
        customerPhone: _selectedCustomer!.phone,
        branchId: branchId,
        complaintText: _complaintCtrl.text.trim(),
        createdById: widget.dmeUser.id,
        assignedToId: _selectedAssignee!.id,
        complaintTypes: _selectedComplaintTypes.toList(),
        voiceNoteUrl: _voiceNoteUrl,
      );

      debugPrint(
          '[CreateComplaint] Complaint created successfully with ID: $complaintId');

      if (mounted) {
        // Call callback first to refresh parent data
        widget.onSubmitted();
        // Show snackbar
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Complaint raised successfully')),
          );
        }
        // Navigate back
        await Future.delayed(const Duration(milliseconds: 100));
        if (mounted && Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      }
    } catch (e) {
      debugPrint('[CreateComplaint] Error submitting complaint: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        title: const Text('Raise Complaint',
            style: TextStyle(fontWeight: FontWeight.w600)),
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Customer Search ──────────────────────────────────
              _sectionLabel('Customer'),
              const SizedBox(height: 8),
              TextField(
                controller: _searchCtrl,
                enabled: _selectedCustomer == null,
                decoration: InputDecoration(
                  hintText: 'Search by name or phone…',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchingCustomers
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                              width: 16,
                              height: 16,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2)))
                      : (_searchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() {
                                  _customers = [];
                                  _selectedCustomer = null;
                                  _assignableUsers = [];
                                  _selectedAssignee = null;
                                });
                              },
                            )
                          : null),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                  filled: _selectedCustomer != null,
                  fillColor: Colors.grey[100],
                ),
                onChanged: (v) {
                  if (_selectedCustomer != null &&
                      v != _selectedCustomer!.name) {
                    setState(() {
                      _selectedCustomer = null;
                      _assignableUsers = [];
                      _selectedAssignee = null;
                    });
                  }
                  _searchCustomers(v);
                },
              ),

              // Customer search results
              if (_customers.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: _customers.take(6).map((c) {
                      return InkWell(
                        onTap: () => _onCustomerSelected(c),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          child: Row(
                            children: [
                              const Icon(Icons.person_outline,
                                  size: 18, color: _primary),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(c.name,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13)),
                                    Text(
                                        '${c.phone}${c.branchName != null ? ' · ${c.branchName}' : ''}',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey[600])),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),

              // Selected customer info card
              if (_selectedCustomer != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _primary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _primary.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _infoRow(Icons.person, _selectedCustomer!.name),
                      const SizedBox(height: 6),
                      _infoRow(Icons.phone, _selectedCustomer!.phone),
                      if (_selectedCustomer!.branchName != null) ...[
                        const SizedBox(height: 6),
                        _infoRow(Icons.location_on_outlined,
                            _selectedCustomer!.branchName!),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),

              // ── Complaint Type ──────────────────────────────────
              _sectionLabel('Complaint Type'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildComplaintTypeTile(
                      type: 'product',
                      label: 'Product',
                      icon: Icons.inventory_2_outlined,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildComplaintTypeTile(
                      type: 'service',
                      label: 'Service',
                      icon: Icons.support_agent_outlined,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Complaint Text ───────────────────────────────────
              _sectionLabel('Complaint Details'),
              const SizedBox(height: 8),
              TextField(
                controller: _complaintCtrl,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: 'Describe the issue…',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
              const SizedBox(height: 20),

              // ── Voice Note ───────────────────────────────────────
              _sectionLabel('Voice Note (Optional)'),
              const SizedBox(height: 8),
              VoiceFileUploadWidget(
                onFileUploaded: (url) =>
                    setState(() => _voiceNoteUrl = url),
                onUploadStateChanged: (isUploading) =>
                    setState(() => _voiceUploading = isUploading),
                enabled: true,
                uploadPath:
                    'dme_complaints/voice_notes/${widget.dmeUser.id}',
              ),
              const SizedBox(height: 16),

              // ── Assign To ────────────────────────────────────────
              _sectionLabel('Assign To'),
              const SizedBox(height: 8),
              if (_selectedCustomer == null)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Text('Select a customer first',
                      style: TextStyle(
                          color: Colors.grey[500], fontSize: 13)),
                )
              else if (_loadingUsers)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 14),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                      child:
                          CircularProgressIndicator(strokeWidth: 2)),
                )
              else if (_assignableUsers.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange[200]!),
                  ),
                  child: Text('No users found for this branch',
                      style: TextStyle(
                          color: Colors.orange[800], fontSize: 13)),
                )
              else
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: DropdownButton<DmeUser>(
                    value: _selectedAssignee,
                    isExpanded: true,
                    underline: const SizedBox(),
                    hint: const Text('Select a user…',
                        style: TextStyle(fontSize: 13)),
                    items: _assignableUsers
                        .map((u) => DropdownMenuItem(
                          value: u,
                          child: Text(
                            '${u.username} (${u.role})',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ))
                        .toList(),
                    onChanged: (u) =>
                        setState(() => _selectedAssignee = u),
                  ),
                ),
              const SizedBox(height: 28),

              // ── Submit ───────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed:
                      (_submitting || _voiceUploading) ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: (_submitting || _voiceUploading)
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Submit Complaint',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String label) {
    return Text(label,
        style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.grey[700]));
  }

  Widget _buildComplaintTypeTile({
    required String type,
    required String label,
    required IconData icon,
  }) {
    final selected = _selectedComplaintTypes.contains(type);
    return InkWell(
      onTap: () => _toggleComplaintType(type),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? _primary.withValues(alpha: 0.08) : Colors.white,
          border: Border.all(
            color: selected ? _primary : Colors.grey[300]!,
            width: selected ? 1.6 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: selected ? _primary : Colors.grey[600]),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? _primary : Colors.grey[700],
                ),
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle, size: 18, color: _primary),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 15, color: _primary),
        const SizedBox(width: 8),
        Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 13),
                overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}
