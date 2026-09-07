import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../Navigation/user_cache_service.dart';
import 'sync_head_editing_approval.dart';

const Color _primaryBlue = Color(0xFF005BAC);
const Color _primaryGreen = Color(0xFF8CC63F);

class SyncHeadCustomerListDeletionApprovalPage extends StatefulWidget {
  const SyncHeadCustomerListDeletionApprovalPage({super.key});

  @override
  State<SyncHeadCustomerListDeletionApprovalPage> createState() =>
      _SyncHeadCustomerListDeletionApprovalPageState();
}

class _SyncHeadCustomerListDeletionApprovalPageState
    extends State<SyncHeadCustomerListDeletionApprovalPage> {
  final Map<String, bool> _processingIds = {};
  List<Map<String, dynamic>> _allUsers = [];
  String _selectedType = 'All'; // 'All', 'deletion', 'editing'
  String _selectedBranch = 'All Branches';

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    try {
      final users = await UserCacheService.instance.getAllUsers();
      if (mounted) {
        setState(() {
          _allUsers = users;
        });
      }
    } catch (_) {}
  }

  String _resolveUserBranch(Map<String, dynamic> data) {
    String name = (data['userName'] as String?)?.trim() ?? '';
    String branch = (data['userBranch'] as String?)?.trim() ?? '';
    final email = (data['userEmail'] as String?)?.trim().toLowerCase() ?? '';
    final userDocId = (data['userDocId'] as String?)?.trim().toLowerCase() ?? '';

    if (_allUsers.isNotEmpty && (name.isEmpty || name.contains('@') || branch.isEmpty)) {
      final matched = _allUsers.firstWhere(
        (u) =>
            (u['email'] as String? ?? '').toLowerCase() == email ||
            (u['email'] as String? ?? '').toLowerCase() == userDocId ||
            (u['uid'] as String? ?? '').toLowerCase() == userDocId,
        orElse: () => {},
      );
      if (matched.isNotEmpty) {
        if (name.isEmpty || name.contains('@')) {
          final matchedName = (matched['username'] as String? ?? '').trim();
          if (matchedName.isNotEmpty) {
            name = matchedName;
          }
        }
        if (branch.isEmpty) {
          branch = (matched['branch'] as String? ?? '').trim();
        }
      }
    }

    if (name.isEmpty) {
      name = email.isNotEmpty ? email : 'Unknown User';
    }

    if (branch.isNotEmpty) {
      return '$name-$branch';
    }
    return name;
  }

  String _extractBranchOnly(Map<String, dynamic> data) {
    final explicitBranch = (data['userBranch'] as String?)?.trim() ?? '';
    if (explicitBranch.isNotEmpty) return explicitBranch;

    final email = (data['userEmail'] as String?)?.trim().toLowerCase() ?? '';
    final userDocId = (data['userDocId'] as String?)?.trim().toLowerCase() ?? '';

    if (_allUsers.isNotEmpty) {
      final matched = _allUsers.firstWhere(
        (u) =>
            (u['email'] as String? ?? '').toLowerCase() == email ||
            (u['email'] as String? ?? '').toLowerCase() == userDocId ||
            (u['uid'] as String? ?? '').toLowerCase() == userDocId,
        orElse: () => {},
      );
      if (matched.isNotEmpty) {
        final b = (matched['branch'] as String? ?? '').trim();
        if (b.isNotEmpty) return b;
      }
    }
    return '';
  }

  List<String> _getUniqueBranches(List<Map<String, dynamic>> allRequests) {
    final Set<String> branches = {};
    for (final u in _allUsers) {
      final b = (u['branch'] as String?)?.trim();
      if (b != null && b.isNotEmpty) {
        branches.add(b);
      }
    }
    for (final r in allRequests) {
      final b = _extractBranchOnly(r);
      if (b.isNotEmpty) {
        branches.add(b);
      }
    }
    final sorted = branches.toList()..sort();
    return ['All Branches', ...sorted];
  }

  Future<void> _approveDeletion(String reqId, Map<String, dynamic> data) async {
    setState(() => _processingIds[reqId] = true);
    try {
      final monthYear = data['monthYear'] as String?;
      final userDocId = data['userDocId'] as String?;
      final customerData = data['customerData'] as Map<String, dynamic>?;

      if (monthYear == null || userDocId == null || customerData == null) {
        throw Exception('Invalid request payload format');
      }

      final userDocRef = FirebaseFirestore.instance
          .collection('customer_target')
          .doc(monthYear)
          .collection('users')
          .doc(userDocId);

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snapshot = await transaction.get(userDocRef);
        if (snapshot.exists && snapshot.data() != null) {
          final docData = snapshot.data()!;
          final List<dynamic> customers =
              List<dynamic>.from(docData['customers'] ?? []);

          final targetName = (customerData['name'] ?? '').toString();
          final targetContact =
              (customerData['contact1'] ?? customerData['contact'] ?? '')
                  .toString();

          customers.removeWhere((c) {
            if (c is Map) {
              final cName = (c['name'] ?? '').toString();
              final cContact =
                  (c['contact1'] ?? c['contact'] ?? '').toString();
              return cName == targetName && cContact == targetContact;
            }
            return false;
          });

          transaction.update(userDocRef, {'customers': customers});
        }

        final reqRef = FirebaseFirestore.instance
            .collection('customer_deletion_requests')
            .doc(reqId);

        transaction.update(reqRef, {
          'status': 'approved',
          'approvedAt': FieldValue.serverTimestamp(),
        });
      });

      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text('Customer deletion approved & removed.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text('Error approving request: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _processingIds.remove(reqId));
      }
    }
  }

  Future<void> _rejectDeletion(String reqId, Map<String, dynamic> data) async {
    setState(() => _processingIds[reqId] = true);
    try {
      final monthYear = data['monthYear'] as String?;
      final userDocId = data['userDocId'] as String?;
      final customerData = data['customerData'] as Map<String, dynamic>?;

      if (monthYear != null && userDocId != null && customerData != null) {
        final userDocRef = FirebaseFirestore.instance
            .collection('customer_target')
            .doc(monthYear)
            .collection('users')
            .doc(userDocId);

        await FirebaseFirestore.instance.runTransaction((transaction) async {
          final snapshot = await transaction.get(userDocRef);
          if (snapshot.exists && snapshot.data() != null) {
            final docData = snapshot.data()!;
            final List<dynamic> customers =
                List<dynamic>.from(docData['customers'] ?? []);

            final targetName = (customerData['name'] ?? '').toString();
            final targetContact =
                (customerData['contact1'] ?? customerData['contact'] ?? '')
                    .toString();

            for (var c in customers) {
              if (c is Map) {
                final cName = (c['name'] ?? '').toString();
                final cContact =
                    (c['contact1'] ?? c['contact'] ?? '').toString();
                if (cName == targetName && cContact == targetContact) {
                  c['pendingDeletion'] = false;
                  break;
                }
              }
            }

            transaction.update(userDocRef, {'customers': customers});
          }

          final reqRef = FirebaseFirestore.instance
              .collection('customer_deletion_requests')
              .doc(reqId);

          transaction.update(reqRef, {
            'status': 'rejected',
            'rejectedAt': FieldValue.serverTimestamp(),
          });
        });
      }

      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text('Deletion request rejected.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text('Error rejecting request: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _processingIds.remove(reqId));
      }
    }
  }

  Future<void> _approveEditing(String reqId, Map<String, dynamic> data) async {
    setState(() => _processingIds[reqId] = true);
    try {
      await SyncHeadEditingApprovalService.approveEditing(
        reqId: reqId,
        data: data,
        context: context,
        mounted: mounted,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text('Error approving edit: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _processingIds.remove(reqId));
      }
    }
  }

  Future<void> _rejectEditing(String reqId, Map<String, dynamic> data) async {
    setState(() => _processingIds[reqId] = true);
    try {
      await SyncHeadEditingApprovalService.rejectEditing(
        reqId: reqId,
        data: data,
        context: context,
        mounted: mounted,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text('Error rejecting edit: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _processingIds.remove(reqId));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: const Text(
          'Approvals Pending',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black87,
        elevation: 1,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('customer_deletion_requests')
            .where('status', isEqualTo: 'pending')
            .snapshots(),
        builder: (context, delSnapshot) {
          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('customer_editing_requests')
                .where('status', isEqualTo: 'pending')
                .snapshots(),
            builder: (context, editSnapshot) {
              if (delSnapshot.hasError || editSnapshot.hasError) {
                final err = delSnapshot.error ?? editSnapshot.error;
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      'Error loading approvals: $err',
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }

              if (delSnapshot.connectionState == ConnectionState.waiting &&
                  editSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final delDocs = delSnapshot.data?.docs ?? [];
              final editDocs = editSnapshot.data?.docs ?? [];

              final List<Map<String, dynamic>> allRequests = [];

              for (final doc in delDocs) {
                final d = Map<String, dynamic>.from(doc.data() as Map<String, dynamic>);
                d['reqId'] = doc.id;
                d['type'] = 'deletion';
                allRequests.add(d);
              }

              for (final doc in editDocs) {
                final d = Map<String, dynamic>.from(doc.data() as Map<String, dynamic>);
                d['reqId'] = doc.id;
                d['type'] = 'editing';
                allRequests.add(d);
              }

              allRequests.sort((a, b) {
                final aTime = (a['requestedAt'] as Timestamp?)?.toDate() ??
                    DateTime.fromMillisecondsSinceEpoch(0);
                final bTime = (b['requestedAt'] as Timestamp?)?.toDate() ??
                    DateTime.fromMillisecondsSinceEpoch(0);
                return bTime.compareTo(aTime);
              });

              final branchesList = _getUniqueBranches(allRequests);

              // Apply Filters
              final filteredRequests = allRequests.where((req) {
                final type = req['type'] ?? 'deletion';
                if (_selectedType != 'All' && type != _selectedType) {
                  return false;
                }
                if (_selectedBranch != 'All Branches') {
                  final b = _extractBranchOnly(req);
                  if (b.toLowerCase() != _selectedBranch.toLowerCase()) {
                    return false;
                  }
                }
                return true;
              }).toList();

              return Column(
                children: [
                  // Top Summary Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E222A) : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.pending_actions,
                              color: Colors.orange, size: 28),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Pending Approvals',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isDark
                                      ? Colors.grey.shade400
                                      : Colors.grey.shade600,
                                ),
                              ),
                              Text(
                                '${allRequests.length} Total (${delDocs.length} Deletion, ${editDocs.length} Edit)',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Filter Controls Section
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Row(
                      children: [
                        // Type Filter Segment
                        Expanded(
                          flex: 3,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF1E222A)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isDark
                                    ? Colors.grey.shade800
                                    : Colors.grey.shade300,
                              ),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _selectedType,
                                isExpanded: true,
                                icon: const Icon(Icons.keyboard_arrow_down, size: 20),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                                dropdownColor:
                                    isDark ? const Color(0xFF1E222A) : Colors.white,
                                items: const [
                                  DropdownMenuItem(
                                      value: 'All', child: Text('Type: All')),
                                  DropdownMenuItem(
                                      value: 'deletion',
                                      child: Text('Type: Deletion')),
                                  DropdownMenuItem(
                                      value: 'editing',
                                      child: Text('Type: Editing')),
                                ],
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() => _selectedType = val);
                                  }
                                },
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Branch Filter Dropdown
                        Expanded(
                          flex: 3,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF1E222A)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isDark
                                    ? Colors.grey.shade800
                                    : Colors.grey.shade300,
                              ),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: branchesList.contains(_selectedBranch)
                                    ? _selectedBranch
                                    : 'All Branches',
                                isExpanded: true,
                                icon: const Icon(Icons.keyboard_arrow_down, size: 20),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                                dropdownColor:
                                    isDark ? const Color(0xFF1E222A) : Colors.white,
                                items: branchesList.map((branch) {
                                  return DropdownMenuItem(
                                    value: branch,
                                    child: Text(
                                      branch,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() => _selectedBranch = val);
                                  }
                                },
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // List of Pending Requests
                  Expanded(
                    child: filteredRequests.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.check_circle_outline,
                                  size: 64,
                                  color: Colors.green.withValues(alpha: 0.5),
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  allRequests.isEmpty
                                      ? 'No pending approvals'
                                      : 'No requests match selected filters',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? Colors.grey.shade400
                                        : Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            itemCount: filteredRequests.length,
                            itemBuilder: (context, index) {
                              final data = filteredRequests[index];
                              final reqId = data['reqId'] as String;
                              final type = data['type'] as String? ?? 'deletion';
                              final isEditing = type == 'editing';

                              final customerData = (data['customerData']
                                      as Map<String, dynamic>?) ??
                                  {};
                              final updatedData = (data['updatedCustomerData']
                                      as Map<String, dynamic>?) ??
                                  {};

                              final userBranchStr = _resolveUserBranch(data);
                              final monthYear = data['monthYear'] ?? '';
                              final requestedAtTS =
                                  data['requestedAt'] as Timestamp?;
                              final requestedAtStr = requestedAtTS != null
                                  ? DateFormat('MMM dd, yyyy • hh:mm a')
                                      .format(requestedAtTS.toDate())
                                  : 'Recently';

                              final isProcessing =
                                  _processingIds[reqId] == true;

                              final custName =
                                  (customerData['name'] ?? 'Unknown')
                                      .toString()
                                      .toUpperCase();
                              final custContact = (customerData['contact1'] ??
                                      customerData['contact'] ??
                                      '-')
                                  .toString();
                              final custContact2 =
                                  (customerData['contact2'] ?? '').toString();
                              final custAddress =
                                  (customerData['address'] ?? '-').toString();
                              final custArea =
                                  (customerData['area'] ?? '').toString();

                              final reason = (data['reason'] ?? '').toString();

                              return Card(
                                margin: const EdgeInsets.only(bottom: 14),
                                elevation: 2,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                color: isDark
                                    ? const Color(0xFF1E222A)
                                    : Colors.white,
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Top Header (Customer Name + Type Badge + Month Badge)
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              custName,
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: _primaryGreen,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: isEditing
                                                  ? Colors.blue.withValues(alpha: 0.15)
                                                  : Colors.red.withValues(alpha: 0.15),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              border: Border.all(
                                                color: isEditing
                                                    ? Colors.blue.withValues(alpha: 0.4)
                                                    : Colors.red.withValues(alpha: 0.4),
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  isEditing
                                                      ? Icons.edit_note
                                                      : Icons.delete_outline,
                                                  size: 13,
                                                  color: isEditing
                                                      ? Colors.blue
                                                      : Colors.red,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  isEditing ? 'EDITING' : 'DELETION',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                    color: isEditing
                                                        ? Colors.blue
                                                        : Colors.red,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: _primaryBlue
                                                  .withValues(alpha: 0.1),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              monthYear,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: _primaryBlue,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),

                                      // If Editing Request -> Show Diff
                                      if (isEditing) ...[
                                        Container(
                                          padding: const EdgeInsets.all(10),
                                          margin: const EdgeInsets.only(
                                              top: 4, bottom: 8),
                                          decoration: BoxDecoration(
                                            color: isDark
                                                ? const Color(0xFF16191F)
                                                : const Color(0xFFF0F7FF),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            border: Border.all(
                                              color: Colors.blue
                                                  .withValues(alpha: 0.2),
                                            ),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              const Text(
                                                'Requested Changes:',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                  color: _primaryBlue,
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              if (updatedData['name'] != null &&
                                                  updatedData['name'] !=
                                                      customerData['name'])
                                                _buildDiffRow(
                                                    'Name',
                                                    customerData['name'],
                                                    updatedData['name'],
                                                    isDark),
                                              if (updatedData['contact1'] != null &&
                                                  updatedData['contact1'] !=
                                                      (customerData['contact1'] ??
                                                          customerData['contact']))
                                                _buildDiffRow(
                                                    'Contact 1',
                                                    customerData['contact1'] ??
                                                        customerData['contact'],
                                                    updatedData['contact1'],
                                                    isDark),
                                              if (updatedData['contact2'] != null &&
                                                  updatedData['contact2'] !=
                                                      customerData['contact2'])
                                                _buildDiffRow(
                                                    'Contact 2',
                                                    customerData['contact2'] ??
                                                        '-',
                                                    updatedData['contact2'],
                                                    isDark),
                                              if (updatedData['address'] != null &&
                                                  updatedData['address'] !=
                                                      customerData['address'])
                                                _buildDiffRow(
                                                    'Address',
                                                    customerData['address'],
                                                    updatedData['address'],
                                                    isDark),
                                            ],
                                          ),
                                        ),
                                      ] else ...[
                                        // Deletion Request Customer Details
                                        Row(
                                          children: [
                                            const Icon(Icons.phone,
                                                size: 15, color: Colors.grey),
                                            const SizedBox(width: 6),
                                            Text(
                                              custContact,
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: isDark
                                                    ? Colors.grey.shade300
                                                    : Colors.grey.shade800,
                                              ),
                                            ),
                                            if (custContact2.isNotEmpty) ...[
                                              const SizedBox(width: 8),
                                              Text(
                                                '/ $custContact2',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: isDark
                                                      ? Colors.grey.shade400
                                                      : Colors.grey.shade600,
                                                ),
                                              ),
                                            ],
                                            if (custArea.isNotEmpty) ...[
                                              const SizedBox(width: 12),
                                              const Icon(Icons.location_on,
                                                  size: 15, color: Colors.grey),
                                              const SizedBox(width: 4),
                                              Expanded(
                                                child: Text(
                                                  custArea,
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    color: isDark
                                                        ? Colors.grey.shade300
                                                        : Colors.grey.shade800,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        if (custAddress.isNotEmpty &&
                                            custAddress != '-') ...[
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              const Icon(Icons.home,
                                                  size: 15, color: Colors.grey),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Text(
                                                  custAddress,
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    color: isDark
                                                        ? Colors.grey.shade400
                                                        : Colors.grey.shade600,
                                                  ),
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ],

                                      // Reason Section
                                      if (reason.isNotEmpty) ...[
                                        const SizedBox(height: 8),
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: isEditing
                                                ? Colors.amber
                                                    .withValues(alpha: 0.08)
                                                : Colors.red
                                                    .withValues(alpha: 0.08),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            border: Border.all(
                                              color: isEditing
                                                  ? Colors.amber
                                                      .withValues(alpha: 0.3)
                                                  : Colors.red
                                                      .withValues(alpha: 0.3),
                                              width: 1,
                                            ),
                                          ),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Icon(Icons.warning_amber_rounded,
                                                  size: 16,
                                                  color: isEditing
                                                      ? Colors.amber.shade800
                                                      : Colors.red),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Text.rich(
                                                  TextSpan(
                                                    children: [
                                                      TextSpan(
                                                        text: 'Reason: ',
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: isEditing
                                                              ? Colors.amber
                                                                  .shade900
                                                              : Colors.red,
                                                        ),
                                                      ),
                                                      TextSpan(
                                                        text: reason,
                                                        style: TextStyle(
                                                          color: isDark
                                                              ? Colors.grey
                                                                  .shade300
                                                              : Colors.black87,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  style: const TextStyle(
                                                      fontSize: 13),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],

                                      const Divider(height: 24),

                                      // Requested By user info
                                      Row(
                                        children: [
                                          CircleAvatar(
                                            radius: 12,
                                            backgroundColor:
                                                Colors.blue.shade100,
                                            child: Text(
                                              userBranchStr.isNotEmpty
                                                  ? userBranchStr[0]
                                                      .toUpperCase()
                                                  : 'U',
                                              style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  color: _primaryBlue),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Requested by $userBranchStr',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                    color: isDark
                                                        ? Colors.grey.shade300
                                                        : Colors.grey.shade800,
                                                  ),
                                                ),
                                                Text(
                                                  requestedAtStr,
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: isDark
                                                        ? Colors.grey.shade500
                                                        : Colors.grey.shade600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 16),

                                      // Action Buttons
                                      isProcessing
                                          ? const Center(
                                              child: SizedBox(
                                                height: 24,
                                                width: 24,
                                                child: CircularProgressIndicator(
                                                    strokeWidth: 2.5),
                                              ),
                                            )
                                          : Row(
                                              children: [
                                                Expanded(
                                                  child: OutlinedButton.icon(
                                                    onPressed: () => isEditing
                                                        ? _rejectEditing(
                                                            reqId, data)
                                                        : _rejectDeletion(
                                                            reqId, data),
                                                    icon: const Icon(
                                                        Icons.close_rounded,
                                                        size: 18,
                                                        color: Colors.red),
                                                    label: const Text('Reject',
                                                        style: TextStyle(
                                                            color: Colors.red)),
                                                    style: OutlinedButton
                                                        .styleFrom(
                                                      side: const BorderSide(
                                                          color: Colors.red),
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          vertical: 10),
                                                      shape:
                                                          RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(8),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: ElevatedButton.icon(
                                                    onPressed: () => isEditing
                                                        ? _approveEditing(
                                                            reqId, data)
                                                        : _approveDeletion(
                                                            reqId, data),
                                                    icon: const Icon(
                                                        Icons.check_rounded,
                                                        size: 18,
                                                        color: Colors.white),
                                                    label: const Text('Approve',
                                                        style: TextStyle(
                                                            color:
                                                                Colors.white)),
                                                    style: ElevatedButton
                                                        .styleFrom(
                                                      backgroundColor:
                                                          Colors.green,
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          vertical: 10),
                                                      shape:
                                                          RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(8),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildDiffRow(String label, dynamic oldVal, dynamic newVal, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 75,
            child: Text(
              '$label:',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
              ),
            ),
          ),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.grey.shade300 : Colors.black87,
                ),
                children: [
                  TextSpan(
                    text: '${oldVal ?? "-"} ',
                    style: const TextStyle(
                      decoration: TextDecoration.lineThrough,
                      color: Colors.red,
                    ),
                  ),
                  const TextSpan(text: ' ➔  '),
                  TextSpan(
                    text: '${newVal ?? "-"}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
