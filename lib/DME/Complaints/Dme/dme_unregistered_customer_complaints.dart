import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mtcsync/DME/Misc/dme_constants.dart';
import '../services/dme_complaints_service.dart';
import '../widgets/dme_complaint_voice_widget.dart';

/// Page to create complaints for customers not registered in the database.
/// Manually captures customer name, phone, address (optional), branch, and assigns a user.
/// Stored in 'dme_unregistered_customer_complaints' without polluting 'dme_customers'.
class DmeUnregisteredCustomerComplaintsPage extends StatefulWidget {
  const DmeUnregisteredCustomerComplaintsPage({super.key});

  @override
  State<DmeUnregisteredCustomerComplaintsPage> createState() =>
      _DmeUnregisteredCustomerComplaintsPageState();
}

class _DmeUnregisteredCustomerComplaintsPageState
    extends State<DmeUnregisteredCustomerComplaintsPage> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  String _selectedBranch = 'CLT';
  String? _selectedAudioUrl;
  bool _isUploadingAudio = false;

  List<Map<String, dynamic>> _eligibleUsers = [];
  Map<String, dynamic>? _selectedUser;
  bool _isLoadingUsers = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadBranchUsers();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadBranchUsers() async {
    setState(() => _isLoadingUsers = true);
    try {
      final usersSnap = await FirebaseFirestore.instance.collection('users').get();
      final users = <Map<String, dynamic>>[];

      for (var doc in usersSnap.docs) {
        final data = doc.data();
        final role = (data['role'] as String? ?? '').toLowerCase();
        if (role != 'sales' && role != 'manager' && role != 'asst_manager') continue;

        final userBranch = (data['branch'] as String? ?? '').toUpperCase().trim();
        if (_selectedBranch.isNotEmpty && userBranch == _selectedBranch.toUpperCase().trim()) {
          users.add({
            'uid': doc.id,
            'username': data['username'] ?? data['name'] ?? data['email'] ?? 'User',
            'email': data['email'] ?? '',
            'role': role,
            'branch': userBranch,
          });
        }
      }

      // Fallback if no exact branch match found
      if (users.isEmpty) {
        for (var doc in usersSnap.docs) {
          final data = doc.data();
          final role = (data['role'] as String? ?? '').toLowerCase();
          if (role == 'sales' || role == 'manager' || role == 'asst_manager') {
            users.add({
              'uid': doc.id,
              'username': data['username'] ?? data['name'] ?? data['email'] ?? 'User',
              'email': data['email'] ?? '',
              'role': role,
              'branch': (data['branch'] as String? ?? '').toUpperCase().trim(),
            });
          }
        }
      }

      users.sort((a, b) => (a['username'] as String).compareTo(b['username'] as String));

      if (mounted) {
        setState(() {
          _eligibleUsers = users;
          _isLoadingUsers = false;
          _selectedUser = _eligibleUsers.isNotEmpty ? _eligibleUsers.first : null;
        });
      }
    } catch (e) {
      debugPrint('Error loading branch users: $e');
      if (mounted) setState(() => _isLoadingUsers = false);
    }
  }

  Future<void> _registerUnregisteredComplaint() async {
    if (!_formKey.currentState!.validate()) return;

    if (_isUploadingAudio) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please wait for audio upload to complete.')),
      );
      return;
    }

    if (_selectedUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an assigned user.')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      final creatorUid = currentUser?.uid ?? 'unknown';
      final creatorEmail = currentUser?.email ?? '';

      String creatorName = 'DME User';
      try {
        final uDoc = await FirebaseFirestore.instance.collection('users').doc(creatorUid).get();
        if (uDoc.exists) {
          creatorName = uDoc.data()?['username'] ??
              uDoc.data()?['name'] ??
              currentUser?.email?.split('@').first ??
              'DME User';
        }
      } catch (_) {}

      final complaintId = await DmeComplaintsService.instance.registerUnregisteredComplaint(
        customerName: _nameController.text.trim(),
        customerPhone: _phoneController.text.trim(),
        customerAddress: _addressController.text.trim().isNotEmpty
            ? _addressController.text.trim()
            : null,
        branch: _selectedBranch,
        description: _descriptionController.text.trim(),
        createdByUid: creatorUid,
        createdByName: creatorName,
        createdByEmail: creatorEmail,
        assignedToUid: _selectedUser!['uid'],
        assignedToName: _selectedUser!['username'],
        assignedToEmail: _selectedUser!['email'],
        assignedToRole: _selectedUser!['role'],
        initialAudioUrl: _selectedAudioUrl,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Unregistered Complaint #$complaintId registered successfully and assigned to ${_selectedUser!['username']}!',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('Error registering unregistered complaint: $e');
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to register complaint: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Unregistered Customer Complaint'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Notice banner
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amber.shade700.withValues(alpha: 0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded, color: Colors.amber.shade800, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'This customer is not in the database. Enter details manually to raise and track this complaint without adding a new customer record.',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          color: isDark ? Colors.amber.shade200 : Colors.amber.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 1. Customer Details Card
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.person_outline_rounded, color: Color(0xFF005BAC), size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Customer Details',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Customer Name
                      TextFormField(
                        controller: _nameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          labelText: 'Customer Name *',
                          hintText: 'Enter customer full name',
                          prefixIcon: const Icon(Icons.person_rounded),
                          filled: true,
                          fillColor: isDark ? const Color(0xFF16253B) : const Color(0xFFF3F4F6),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Please enter customer name';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),

                      // Phone
                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          labelText: 'Customer Phone *',
                          hintText: 'e.g. 9876543210',
                          prefixIcon: const Icon(Icons.phone_rounded),
                          filled: true,
                          fillColor: isDark ? const Color(0xFF16253B) : const Color(0xFFF3F4F6),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Please enter customer phone number';
                          }
                          final clean = val.replaceAll(RegExp(r'\D'), '');
                          if (clean.length < 7) {
                            return 'Please enter a valid phone number';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),

                      // Address (Optional)
                      TextFormField(
                        controller: _addressController,
                        maxLines: 2,
                        decoration: InputDecoration(
                          labelText: 'Customer Address (Optional)',
                          hintText: 'Enter place, city, or delivery address...',
                          prefixIcon: const Icon(Icons.location_on_outlined),
                          filled: true,
                          fillColor: isDark ? const Color(0xFF16253B) : const Color(0xFFF3F4F6),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Branch Dropdown
                      DropdownButtonFormField<String>(
                        value: _selectedBranch,
                        decoration: InputDecoration(
                          labelText: 'Branch *',
                          prefixIcon: const Icon(Icons.store_mall_directory_outlined),
                          filled: true,
                          fillColor: isDark ? const Color(0xFF16253B) : const Color(0xFFF3F4F6),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        items: DmeConstants.branches.map((b) {
                          return DropdownMenuItem<String>(
                            value: b.name,
                            child: Text(
                              b.name,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null && val != _selectedBranch) {
                            setState(() => _selectedBranch = val);
                            _loadBranchUsers();
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 2. Assign User Card
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.assignment_ind_rounded, color: Color(0xFF005BAC), size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Assign To User (Branch: $_selectedBranch) *',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_isLoadingUsers)
                        const Center(child: CircularProgressIndicator(strokeWidth: 2))
                      else if (_eligibleUsers.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'No active sales, manager, or asst. manager users found for this branch.',
                            style: TextStyle(color: Colors.orange, fontSize: 13),
                          ),
                        )
                      else
                        DropdownButtonFormField<Map<String, dynamic>>(
                          value: _selectedUser,
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: isDark ? const Color(0xFF16253B) : const Color(0xFFF3F4F6),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          ),
                          items: _eligibleUsers.map((user) {
                            final role = (user['role'] as String? ?? '').toUpperCase();
                            return DropdownMenuItem<Map<String, dynamic>>(
                              value: user,
                              child: Row(
                                children: [
                                  Text(
                                    user['username'] ?? 'Unknown',
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF005BAC).withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      role,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Color(0xFF005BAC),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: (val) => setState(() => _selectedUser = val),
                          validator: (val) {
                            if (val == null) return 'Please select an assigned user';
                            return null;
                          },
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 3. Complaint Description & Audio Card
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.report_problem_rounded, color: Colors.deepOrange, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Complaint Description *',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _descriptionController,
                        maxLines: 4,
                        decoration: InputDecoration(
                          hintText: 'Enter detailed customer complaint / feedback...',
                          filled: true,
                          fillColor: isDark ? const Color(0xFF16253B) : const Color(0xFFF3F4F6),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Please enter complaint description';
                          }
                          if (val.trim().length < 5) {
                            return 'Please provide more details in description';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      // Audio recording option
                      DmeComplaintVoiceWidget(
                        initialAudioUrl: _selectedAudioUrl,
                        onAudioChanged: (url) => setState(() => _selectedAudioUrl = url),
                        onUploadStateChanged: (uploading) =>
                            setState(() => _isUploadingAudio = uploading),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Submit Button
              ElevatedButton.icon(
                onPressed: _isSaving ? null : _registerUnregisteredComplaint,
                icon: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send_rounded),
                label: Text(
                  _isSaving ? 'Submitting Complaint...' : 'Register & Assign Complaint',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF005BAC),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 2,
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
