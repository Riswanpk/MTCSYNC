import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:mtcsync/DME/dme_constants.dart';
import '../services/dme_complaints_service.dart';
import '../widgets/dme_complaint_voice_widget.dart';

class DmeRegisterComplaintPage extends StatefulWidget {
  final Map<String, dynamic>? reminder;
  final Map<String, dynamic>? customer;
  final List<Map<String, dynamic>>? initialSalesHistory;

  const DmeRegisterComplaintPage({
    super.key,
    this.reminder,
    this.customer,
    this.initialSalesHistory,
  });

  @override
  State<DmeRegisterComplaintPage> createState() => _DmeRegisterComplaintPageState();
}

class _DmeRegisterComplaintPageState extends State<DmeRegisterComplaintPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _descriptionController = TextEditingController();

  String _customerName = '';
  String _customerPhone = '';
  String? _customerAddress;
  String _branch = '';
  int? _customerId;
  int? _reminderId;

  String? _selectedAudioUrl;
  bool _isUploadingAudio = false;

  List<Map<String, dynamic>> _eligibleUsers = [];
  Map<String, dynamic>? _selectedUser;
  bool _isLoadingUsers = true;

  List<Map<String, dynamic>> _salesHistory = [];
  bool _isLoadingSales = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _initCustomerData();
    _loadBranchUsers();
    _loadSalesHistory();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  void _initCustomerData() {
    if (widget.reminder != null) {
      final r = widget.reminder!;
      _reminderId = int.tryParse(r['id']?.toString() ?? '');
      _customerId = int.tryParse(r['customer_id']?.toString() ?? '');
      _customerName = r['customer_name']?.toString() ?? 'Unknown Customer';
      _customerPhone = r['customer_phone']?.toString() ?? '';
      _customerAddress = r['customer_address']?.toString() ?? r['address']?.toString();

      // Branch can be last_purchase_branch or primary_branch
      final branchRaw = r['last_purchase_branch']?.toString() ?? r['branch']?.toString() ?? '';
      _branch = _normalizeBranch(branchRaw);
    } else if (widget.customer != null) {
      final c = widget.customer!;
      _customerId = int.tryParse(c['id']?.toString() ?? '');
      _customerName = c['name']?.toString() ?? 'Unknown Customer';
      _customerPhone = c['phone']?.toString() ?? '';
      _customerAddress = c['address']?.toString();

      final branchRaw = c['primary_branch']?.toString() ?? c['branch']?.toString() ?? '';
      _branch = _normalizeBranch(branchRaw);
    }
  }

  String _normalizeBranch(String raw) {
    if (raw.isEmpty) return 'CLT';
    final branchId = int.tryParse(raw);
    if (branchId != null) {
      return DmeConstants.getBranchName(branchId);
    }
    final byName = DmeConstants.getBranchIdByName(raw);
    if (byName != null) {
      return DmeConstants.getBranchName(byName);
    }
    return raw.toUpperCase().trim();
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
        if (_branch.isNotEmpty && userBranch == _branch.toUpperCase().trim()) {
          users.add({
            'uid': doc.id,
            'username': data['username'] ?? data['name'] ?? data['email'] ?? 'User',
            'email': data['email'] ?? '',
            'role': role,
            'branch': userBranch,
          });
        }
      }

      // If no exact branch match found, fallback to include all sales/managers with their branch in label
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
          if (_eligibleUsers.isNotEmpty) {
            _selectedUser = _eligibleUsers.first;
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading branch users: $e');
      if (mounted) setState(() => _isLoadingUsers = false);
    }
  }

  Future<void> _loadSalesHistory() async {
    if (widget.initialSalesHistory != null && widget.initialSalesHistory!.isNotEmpty) {
      setState(() => _salesHistory = widget.initialSalesHistory!);
      return;
    }

    if (_customerId == null) return;
    setState(() => _isLoadingSales = true);
    try {
      final history = await DmeComplaintsService.fetchCustomerSales(_customerId!);
      if (mounted) {
        setState(() {
          _salesHistory = history;
          _isLoadingSales = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading sales history: $e');
      if (mounted) setState(() => _isLoadingSales = false);
    }
  }

  Future<void> _submitComplaint() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a user to assign the complaint to.')),
      );
      return;
    }

    if (_isUploadingAudio) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please wait for the audio to finish uploading.')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      final creatorUid = currentUser?.uid ?? 'unknown';
      final creatorEmail = currentUser?.email ?? '';

      // Get creator username from Firestore
      String creatorName = 'DME User';
      try {
        final uDoc = await FirebaseFirestore.instance.collection('users').doc(creatorUid).get();
        if (uDoc.exists) {
          creatorName = uDoc.data()?['username'] ?? uDoc.data()?['name'] ?? currentUser?.email?.split('@').first ?? 'DME User';
        }
      } catch (_) {}

      final complaintId = await DmeComplaintsService.instance.registerComplaint(
        reminderId: _reminderId,
        customerId: _customerId,
        customerName: _customerName,
        customerPhone: _customerPhone,
        customerAddress: _customerAddress,
        branch: _branch,
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
            content: Text('Complaint #$complaintId registered successfully and assigned to ${_selectedUser!['username']}!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('Error submitting complaint: $e');
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to register complaint: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _formatDate(dynamic d) {
    if (d == null) return 'N/A';
    if (d is DateTime) return DateFormat('dd-MM-yyyy').format(d);
    final str = d.toString();
    final parsed = DateTime.tryParse(str);
    return parsed != null ? DateFormat('dd-MM-yyyy').format(parsed) : str;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Raise Complaint'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Customer Details Card
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
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
                                  _customerName,
                                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _customerPhone,
                                  style: const TextStyle(fontSize: 14, color: Color(0xFF005BAC), fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF8CC63F).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFF8CC63F)),
                            ),
                            child: Text(
                              'Branch: $_branch',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF8CC63F),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_customerAddress != null && _customerAddress!.isNotEmpty) ...[
                        const Divider(height: 20),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.location_on_outlined, size: 18, color: Colors.grey),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _customerAddress!,
                                style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.black87),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 2. Purchase History Collapsible Card
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    leading: const Icon(Icons.history_rounded, color: Color(0xFF005BAC)),
                    title: const Text(
                      'Purchase History',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    subtitle: Text(
                      _isLoadingSales
                          ? 'Loading history...'
                          : '${_salesHistory.length} previous purchase(s)',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    children: [
                      if (_isLoadingSales)
                        const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      else if (_salesHistory.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text('No previous purchase records found.', style: TextStyle(color: Colors.grey)),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          itemCount: _salesHistory.length,
                          separatorBuilder: (context, i) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final sale = _salesHistory[i];
                            final dateStr = _formatDate(sale['date']);
                            final branch = sale['purchased_branch']?.toString() ?? 'N/A';
                            final salesman = sale['salesman']?.toString() ?? 'N/A';

                            // Extract products
                            String productsStr = '';
                            final dt = sale['dme_sales_detail'];
                            if (dt is List && dt.isNotEmpty) {
                              final pList = dt.first['products'];
                              if (pList != null) productsStr = pList.toString();
                            }

                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Date: $dateStr',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                      Text(
                                        'Branch: $branch',
                                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Salesman: $salesman',
                                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                                  ),
                                  if (productsStr.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      'Products: $productsStr',
                                      style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.black87),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 3. User Assignment Section
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.assignment_ind_rounded, color: Color(0xFF005BAC), size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Assign To (Branch: $_branch)',
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
                                      style: const TextStyle(fontSize: 10, color: Color(0xFF005BAC), fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: (val) => setState(() => _selectedUser = val),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 4. Complaint Description (Mandatory)
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.edit_note_rounded, color: Color(0xFF005BAC), size: 22),
                          const SizedBox(width: 8),
                          const Text(
                            'Complaint Description *',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 4),
                          const Text('(Mandatory)', style: TextStyle(color: Colors.red, fontSize: 12)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _descriptionController,
                        maxLines: 4,
                        decoration: InputDecoration(
                          hintText: 'Enter complete customer complaint details...',
                          filled: true,
                          fillColor: isDark ? const Color(0xFF16253B) : const Color(0xFFF3F4F6),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Please enter a description for the complaint.';
                          }
                          if (val.trim().length < 5) {
                            return 'Description must be at least 5 characters.';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 5. Voice Record Audio Widget
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
                          Icon(Icons.mic_rounded, color: Color(0xFF005BAC), size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Call Record Audio',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      DmeComplaintVoiceWidget(
                        initialAudioUrl: _selectedAudioUrl,
                        onAudioChanged: (url) {
                          setState(() => _selectedAudioUrl = url);
                        },
                        onUploadStateChanged: (uploading) {
                          setState(() => _isUploadingAudio = uploading);
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // 6. Submit Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _submitComplaint,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded, size: 20),
                  label: Text(
                    _isSaving ? 'Submitting Complaint...' : 'Register Complaint & Notify',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF005BAC),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 3,
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
