import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/dme_reminder.dart';
import '../models/dme_user.dart';
import '../models/dme_complaint.dart';
import '../services/dme_complaint_service.dart';
import '../services/dme_supabase_service.dart';

class ComplaintPopupDialog extends StatefulWidget {
  final DmeReminder reminder;
  final DmeUser dmeUser;
  final VoidCallback onComplaintSubmitted;

  const ComplaintPopupDialog({
    super.key,
    required this.reminder,
    required this.dmeUser,
    required this.onComplaintSubmitted,
  });

  @override
  State<ComplaintPopupDialog> createState() => _ComplaintPopupDialogState();
}

class _ComplaintPopupDialogState extends State<ComplaintPopupDialog> {
  final _svc = DmeComplaintService.instance;
  final _supabaseService = DmeSupabaseService.instance;
  final _complaintCtrl = TextEditingController();
  bool _submitting = false;
  bool _loadingUsers = false;
  List<DmeUser> _branchUsers = [];
  DmeUser? _selectedUser;
  String? _branchName; // Store branch name

  @override
  void initState() {
    super.initState();
    _loadBranchAndUsers();
  }

  Future<void> _loadBranchAndUsers() async {
    setState(() => _loadingUsers = true);
    try {
      // Debug: Log the branch ID being used
      debugPrint('Complaint Dialog: Loading branch with ID: ${widget.reminder.purchasedForBranchId}');
      debugPrint('Complaint Dialog: Fallback branch name: ${widget.reminder.purchasedForBranchName}');
      
      // Get branch name from Supabase
      String? branchName;
      if (widget.reminder.purchasedForBranchId > 0) {
        branchName = await _supabaseService.getBranchNameById(
          widget.reminder.purchasedForBranchId,
        );
        debugPrint('Complaint Dialog: Fetched branch name from Supabase: $branchName');
      } else {
        debugPrint('Complaint Dialog: Branch ID is 0 or less, using fallback');
        branchName = widget.reminder.purchasedForBranchName;
      }
      
      // If still no branch name, try to get the customer's default branch
      if ((branchName == null || branchName.isEmpty) && widget.reminder.customerId > 0) {
        debugPrint('Complaint Dialog: Trying to fetch customer default branch');
        try {
          branchName = await _supabaseService.getCustomerBranchName(
            widget.reminder.customerId,
          );
          debugPrint('Complaint Dialog: Got customer default branch: $branchName');
        } catch (e) {
          debugPrint('Complaint Dialog: Error fetching customer branch: $e');
        }
      }
      
      // Load users from Firestore for this branch
      List<DmeUser> users = [];
      if (branchName != null && branchName.isNotEmpty) {
        final db = FirebaseFirestore.instance;
        debugPrint('Complaint Dialog: Querying Firestore for users with branch: $branchName');
        
        final snapshot = await db
            .collection('users')
            .where('branch', isEqualTo: branchName)
            .where('role', whereIn: ['manager', 'asst_manager', 'sales', 'dme_user'])
            .get();

        debugPrint('Complaint Dialog: Found ${snapshot.docs.length} users for branch $branchName');

        users = snapshot.docs.map((doc) {
          final data = doc.data();
          return DmeUser(
            id: data['uid'] ?? doc.id,
            firebaseUid: data['uid'] ?? doc.id,
            email: data['email'] ?? '',
            username: data['username'] ?? data['email'] ?? 'Unknown',
            role: data['role'] ?? '',
          );
        }).toList();
      } else {
        debugPrint('Complaint Dialog: Branch name is null or empty');
      }
      
      if (mounted) {
        setState(() {
          _branchName = branchName ?? 'Unknown';
          _branchUsers = users;
          _loadingUsers = false;
        });
      }
    } catch (e) {
      debugPrint('Complaint Dialog Error: $e');
      if (mounted) {
        setState(() => _loadingUsers = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading users: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _complaintCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitComplaint() async {
    if (_complaintCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a complaint')),
      );
      return;
    }

    if (_selectedUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a user to assign this complaint')),
      );
      return;
    }

    setState(() => _submitting = true);

    try {
      await _svc.createComplaint(
        customerName: widget.reminder.customerName ?? 'Unknown',
        customerPhone: widget.reminder.customerPhone ?? '',
        branchId: widget.reminder.purchasedForBranchId,
        complaintText: _complaintCtrl.text.trim(),
        createdById: widget.dmeUser.id,
        assignedToId: _selectedUser!.id,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Complaint registered successfully'),
            duration: Duration(seconds: 2),
          ),
        );
        widget.onComplaintSubmitted();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6B6B).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.warning_rounded,
                      color: Color(0xFFFF6B6B),
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Register Complaint',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF2C3E50),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'For ${widget.reminder.customerName ?? 'Customer'}',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Customer Info Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoRow('Customer', widget.reminder.customerName ?? 'Unknown'),
                    const SizedBox(height: 8),
                    _buildInfoRow('Phone', widget.reminder.customerPhone ?? 'N/A'),
                    const SizedBox(height: 8),
                    _buildInfoRow('Branch', _branchName),
                    const SizedBox(height: 8),
                    _buildInfoRow(
                      'Date',
                      DateFormat('dd MMM yyyy').format(DateTime.now()),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Assign To User
              Text(
                'Assign To',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 8),
              if (_loadingUsers)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(child: CircularProgressIndicator()),
                )
              else
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: DropdownButton<DmeUser>(
                    value: _selectedUser,
                    isExpanded: true,
                    hint: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('Select a user...'),
                    ),
                    underline: const SizedBox(),
                    items: _branchUsers
                        .map((user) => DropdownMenuItem(
                              value: user,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                child: Text('${user.username} (${user.role ?? ""})'),
                              ),
                            ))
                        .toList(),
                    onChanged: (user) {
                      setState(() => _selectedUser = user);
                    },
                  ),
                ),
              const SizedBox(height: 20),

              // Complaint Text Field
              Text(
                'Complaint Details',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _complaintCtrl,
                maxLines: 4,
                minLines: 3,
                decoration: InputDecoration(
                  hintText: 'Describe the complaint...',
                  hintStyle: TextStyle(color: Colors.grey[400]),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: Color(0xFF005BAC),
                      width: 2,
                    ),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.all(12),
                ),
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 24),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.grey),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _submitting ? null : () => Navigator.pop(context),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF6B6B),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _submitting ? null : _submitComplaint,
                      child: _submitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text(
                              'Submit',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String? value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value ?? 'N/A',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF2C3E50),
          ),
        ),
      ],
    );
  }
}
