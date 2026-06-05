import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../models/dme_complaint.dart';
import '../models/dme_customer.dart';
import '../models/dme_user.dart';
import '../services/dme_complaint_service.dart';
import '../services/dme_supabase_service.dart';
import '../../Misc/voice_file_upload_widget.dart';
import 'dme_complaint_detail_page.dart';


const Color _primary = Color(0xFF005BAC);

/// Shows complaints raised by the currently logged-in DME user.
class DmeUserComplaintsPage extends StatefulWidget {
  const DmeUserComplaintsPage({super.key});

  @override
  State<DmeUserComplaintsPage> createState() => _DmeUserComplaintsPageState();
}

class _DmeUserComplaintsPageState extends State<DmeUserComplaintsPage> {
  final _svc = DmeComplaintService.instance;
  final _auth = FirebaseAuth.instance;

  List<DmeComplaint> _all = [];
  List<DmeComplaint> _filtered = [];
  bool _loading = true;
  String? _selectedStatus;
  DmeUser? _dmeUser;

  @override
  void initState() {
    super.initState();
    _initSupabaseAndLoad();
  }

  Future<void> _initSupabaseAndLoad() async {
    try {
      // Initialize Supabase before loading complaints
      await DmeSupabaseService.instance.ensureInitialized();
      await _load();
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Init error: $e')));
      }
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final firebaseUid = _auth.currentUser?.uid;
      if (firebaseUid == null) throw Exception('User not authenticated');
      
      debugPrint('[DME Complaints] Firebase UID: $firebaseUid');
      
      // Get the Supabase dme_users ID from Firebase UID
      final dmeUser = await DmeSupabaseService.instance.getCurrentUser(firebaseUid);
      if (dmeUser == null) {
        throw Exception('DME user not found in Supabase');
      }
      
      final supabaseUserId = dmeUser.id;
      debugPrint('[DME Complaints] Supabase User ID: $supabaseUserId');
      
      // Query complaints where created_by matches the Supabase user ID
      final complaints = await _svc.getMyComplaints(userId: supabaseUserId);
      debugPrint('[DME Complaints] Found ${complaints.length} complaints');
      if (complaints.isNotEmpty) {
        debugPrint('[DME Complaints] First complaint: ${complaints.first.customerName}, created_by: ${complaints.first.createdById}');
      }
      
      if (mounted) {
        setState(() {
          _dmeUser = dmeUser;
          _all = complaints;
          _applyFilter();
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[DME Complaints] Error loading: $e');
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error loading: $e')));
      }
    }
  }

  void _applyFilter() {
    if (_selectedStatus == null || _selectedStatus == 'All') {
      _filtered = _all;
    } else {
      _filtered = _all.where((c) => c.status == _selectedStatus).toList();
    }
  }

  void _openDetail(DmeComplaint complaint) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DmeComplaintDetailPage(
          complaint: complaint,
          isDmeUser: true,
          isAssignedUser: false,
          onUpdate: _load,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Complaints',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: Column(
                children: [
                  _buildFilterBar(),
                  Expanded(
                    child: _filtered.isEmpty
                        ? _buildEmpty()
                        : ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: _filtered.length,
                            itemBuilder: (_, i) => _buildCard(_filtered[i]),
                          ),
                  ),
                ],
              ),
            ),
      floatingActionButton: _dmeUser == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => _RaiseComplaintSheet(
                    dmeUser: _dmeUser!,
                    onSubmitted: _load,
                  ),
                );
              },
              backgroundColor: _primary,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text('Raise Complaint',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ),
    );
  }

  Widget _buildFilterBar() {
    final statuses = [
      {'label': 'All', 'value': null},
      {'label': 'Raised', 'value': 'raised'},
      {'label': 'Resolved', 'value': 'case_resolved'},
      {'label': 'Closed', 'value': 'verified_closed'},
    ];
    return Container(
      color: Colors.grey[100],
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: statuses.map((s) {
            final val = s['value'] as String?;
            final isSelected = _selectedStatus == val;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilterChip(
                label: Text(s['label'] as String),
                selected: isSelected,
                onSelected: (_) {
                  setState(() {
                    _selectedStatus = val;
                    _applyFilter();
                  });
                },
                backgroundColor: Colors.white,
                selectedColor: _primary.withValues(alpha: 0.15),
                labelStyle: TextStyle(
                  color: isSelected ? _primary : Colors.grey[600],
                  fontWeight:
                      isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
                side: BorderSide(
                    color: isSelected ? _primary : Colors.grey[300]!),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showDeleteConfirmation(DmeComplaint complaint) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Complaint?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to delete this complaint?',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                complaint.complaintText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Customer: ${complaint.customerName}',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await _svc.deleteComplaint(complaintId: complaint.id!);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Complaint deleted successfully'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  _load();
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error deleting: $e')),
                  );
                }
              }
            },
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(DmeComplaint c) {
    final hasRemarks = c.remarks != null && c.remarks!.isNotEmpty;
    final statusColor = _statusColor(c.status);
    final dateFormat = DateFormat('dd MMM yyyy');

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: GestureDetector(
        onLongPress: () => _showDeleteConfirmation(c),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _openDetail(c),
          child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border(left: BorderSide(color: statusColor, width: 4)),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.customerName,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(c.customerPhone,
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[600])),
                      ],
                    ),
                  ),
                  _buildStatusBadge(c.status),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                c.complaintText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF2C3E50),
                    height: 1.4),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Branch: ${c.branchName}',
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey[600])),
                  Text(dateFormat.format(c.createdAt),
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey[600])),
                ],
              ),
              const SizedBox(height: 8),
              if (hasRemarks)
                _buildRow(
                  icon: Icons.comment,
                  color: Colors.green,
                  text: c.remarks!,
                )
              else
                _buildRow(
                  icon: Icons.pending_actions,
                  color: Colors.orange,
                  text: 'Not Resolved',
                ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  Widget _buildRow(
      {required IconData icon,
      required Color color,
      required String text}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: color)),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    final color = _statusColor(status);
    final label = _statusLabel(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.assignment_outlined, size: 52, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text('No complaints found',
              style: TextStyle(fontSize: 16, color: Colors.grey[400])),
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'raised':
        return Colors.red;
      case 'case_resolved':
        return Colors.orange;
      case 'verified_closed':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'raised':
        return 'RAISED';
      case 'case_resolved':
        return 'RESOLVED';
      case 'verified_closed':
        return 'CLOSED';
      default:
        return status.toUpperCase();
    }
  }
}

// ─── Raise Complaint Bottom Sheet ────────────────────────────────────────────

class _RaiseComplaintSheet extends StatefulWidget {
  final DmeUser dmeUser;
  final VoidCallback onSubmitted;

  const _RaiseComplaintSheet({
    required this.dmeUser,
    required this.onSubmitted,
  });

  @override
  State<_RaiseComplaintSheet> createState() => _RaiseComplaintSheetState();
}

class _RaiseComplaintSheetState extends State<_RaiseComplaintSheet> {
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
  String? _voiceNoteUrl;
  bool _voiceUploading = false;

  @override
  void initState() {
    super.initState();
    _loadBranchIds();
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
      debugPrint('[RaiseComplaint] Error loading branch IDs: $e');
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
      debugPrint('[RaiseComplaint] Customer search error: $e');
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
      debugPrint('[RaiseComplaint] Error loading branch users: $e');
    } finally {
      if (mounted) setState(() => _loadingUsers = false);
    }
  }

  Future<void> _submit() async {
    if (_selectedCustomer == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Please select a customer')));
      return;
    }
    if (_complaintCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Please enter complaint details')));
      return;
    }
    if (_selectedAssignee == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please assign the complaint to a user')));
      return;
    }

    debugPrint('[RaiseComplaint] Submitting complaint with voiceNoteUrl: $_voiceNoteUrl');
    setState(() => _submitting = true);
    try {
      final branchId = _selectedCustomer!.branchId ?? 0;
      debugPrint('[RaiseComplaint] Creating complaint for customer: ${_selectedCustomer!.name}');
      final complaintId = await _svc.createComplaint(
        customerName: _selectedCustomer!.name,
        customerPhone: _selectedCustomer!.phone,
        branchId: branchId,
        complaintText: _complaintCtrl.text.trim(),
        createdById: widget.dmeUser.id,
        assignedToId: _selectedAssignee!.id,
        voiceNoteUrl: _voiceNoteUrl,
      );

      debugPrint('[RaiseComplaint] Complaint created successfully with ID: $complaintId');

      // Complaint saved to Supabase and will appear in notification page
      if (mounted) {
        // Call callback first to refresh parent data
        widget.onSubmitted();
        // Show snackbar while context is still valid
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Complaint raised successfully')),
          );
        }
        // Finally dismiss the modal - add a small delay to ensure everything settles
        await Future.delayed(const Duration(milliseconds: 100));
        if (mounted && Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      }
    } catch (e) {
      debugPrint('[RaiseComplaint] Error submitting complaint: $e');
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
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomPadding),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Title
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.report_problem_outlined,
                      color: _primary, size: 22),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Raise a Complaint',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2C3E50)),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ── Customer Search ──────────────────────────────────
            _sectionLabel('Customer'),
            const SizedBox(height: 6),
            TextField(
              controller: _searchCtrl,
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
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
                                crossAxisAlignment: CrossAxisAlignment.start,
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
              const SizedBox(height: 10),
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
                      _infoRow(
                          Icons.location_on_outlined,
                          _selectedCustomer!.branchName!),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),

            // ── Complaint Text ───────────────────────────────────
            _sectionLabel('Complaint Details'),
            const SizedBox(height: 6),
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
            const SizedBox(height: 16),

            // ── Voice Note ───────────────────────────────────────
            _sectionLabel('Voice Note (Optional)'),
            const SizedBox(height: 6),
            VoiceFileUploadWidget(
              onFileUploaded: (url) => setState(() => _voiceNoteUrl = url),              onUploadStateChanged: (isUploading) =>
                  setState(() => _voiceUploading = isUploading),              enabled: true,
              uploadPath: 'dme_complaints/voice_notes/${widget.dmeUser.id}',
            ),
            const SizedBox(height: 8),

            // ── Assign To ────────────────────────────────────────
            _sectionLabel('Assign To'),
            const SizedBox(height: 6),
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
                    style:
                        TextStyle(color: Colors.grey[500], fontSize: 13)),
              )
            else if (_loadingUsers)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                    child: CircularProgressIndicator(strokeWidth: 2)),
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
                    style:
                        TextStyle(color: Colors.orange[800], fontSize: 13)),
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
                  onChanged: (u) => setState(() => _selectedAssignee = u),
                ),
              ),
            const SizedBox(height: 28),

            // ── Submit ───────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: (_submitting || _voiceUploading) ? null : _submit,
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
          ],
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
