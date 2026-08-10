import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../Navigation/user_cache_service.dart';

const Color _primaryBlue = Color(0xFF005BAC);
const Color _primaryGreen = Color(0xFF8CC63F);

class SmeDeletionApprovalPage extends StatefulWidget {
  const SmeDeletionApprovalPage({super.key});

  @override
  State<SmeDeletionApprovalPage> createState() =>
      _SmeDeletionApprovalPageState();
}

class _SmeDeletionApprovalPageState extends State<SmeDeletionApprovalPage> {
  final Map<String, bool> _processingIds = {};
  List<Map<String, dynamic>> _allUsers = [];

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
    final userDocId = (data['requestedBy'] as String?)?.trim().toLowerCase() ?? '';

    if (_allUsers.isNotEmpty && (name.isEmpty || name.contains('@') || branch.isEmpty)) {
      final matched = _allUsers.firstWhere(
        (u) =>
            (u['email'] as String? ?? '').toLowerCase() == email ||
            (u['uid'] as String? ?? '').toLowerCase() == userDocId ||
            (u['email'] as String? ?? '').toLowerCase() == userDocId,
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

  Future<void> _approveDeletion(
      String reqId, Map<String, dynamic> data) async {
    setState(() => _processingIds[reqId] = true);
    try {
      final leadId = data['leadId'] as String?;

      if (leadId == null || leadId.isEmpty) {
        throw Exception('Invalid lead ID format');
      }

      final leadRef = FirebaseFirestore.instance
          .collection('follow_ups')
          .doc(leadId);

      final reqRef = FirebaseFirestore.instance
          .collection('sme_deletion_requests')
          .doc(reqId);

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        transaction.delete(leadRef);
        transaction.update(reqRef, {
          'status': 'approved',
          'approvedAt': FieldValue.serverTimestamp(),
        });
      });

      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text('SME Lead deletion approved & permanently removed.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text('Error approving deletion: $e'),
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

  Future<void> _rejectDeletion(
      String reqId, Map<String, dynamic> data) async {
    setState(() => _processingIds[reqId] = true);
    try {
      final leadId = data['leadId'] as String?;

      if (leadId != null && leadId.isNotEmpty) {
        final leadRef = FirebaseFirestore.instance
            .collection('follow_ups')
            .doc(leadId);

        final reqRef = FirebaseFirestore.instance
            .collection('sme_deletion_requests')
            .doc(reqId);

        await FirebaseFirestore.instance.runTransaction((transaction) async {
          final snapshot = await transaction.get(leadRef);
          if (snapshot.exists) {
            transaction.update(leadRef, {'pendingDeletion': false});
          }
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: const Text(
          'SME Lead Deletion Approvals',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black87,
        elevation: 1,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('sme_deletion_requests')
            .where('status', isEqualTo: 'pending')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Error loading deletion requests: ${snapshot.error}',
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];
          docs.sort((a, b) {
            final aData = a.data() as Map<String, dynamic>;
            final bData = b.data() as Map<String, dynamic>;
            final aTime = (aData['requestedAt'] as Timestamp?)?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bTime = (bData['requestedAt'] as Timestamp?)?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);
            return bTime.compareTo(aTime);
          });

          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 72,
                    color: Colors.green.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No pending deletion approvals',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.all(16),
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
                      child: const Icon(Icons.pending_actions, color: Colors.orange, size: 28),
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
                              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                            ),
                          ),
                          Text(
                            '${docs.length} ${docs.length == 1 ? 'Request' : 'Requests'}',
                            style: TextStyle(
                              fontSize: 20,
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
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final reqId = doc.id;
                    final data = doc.data() as Map<String, dynamic>;
                    final leadData = (data['leadData'] as Map<String, dynamic>?) ?? {};
                    final userBranchStr = _resolveUserBranch(data);
                    final requestedAtTS = data['requestedAt'] as Timestamp?;
                    final requestedAtStr = requestedAtTS != null
                        ? DateFormat('MMM dd, yyyy • hh:mm a').format(requestedAtTS.toDate())
                        : 'Recently';

                    final isProcessing = _processingIds[reqId] == true;

                    final leadName = (leadData['name'] ?? 'Unknown').toString().toUpperCase();
                    final leadPhone = (leadData['phone'] ?? '-').toString();
                    final leadBranch = (leadData['branch'] ?? '').toString();
                    final reason = (data['reason'] ?? '').toString();

                    return Card(
                      margin: const EdgeInsets.only(bottom: 14),
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      color: isDark ? const Color(0xFF1E222A) : Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    leadName,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: _primaryGreen,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (leadBranch.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: _primaryBlue.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      leadBranch,
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
                            Row(
                              children: [
                                const Icon(Icons.phone, size: 15, color: Colors.grey),
                                const SizedBox(width: 6),
                                Text(
                                  leadPhone,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isDark ? Colors.grey.shade300 : Colors.grey.shade800,
                                  ),
                                ),
                              ],
                            ),
                            if (reason.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.red.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.red.withValues(alpha: 0.3),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(Icons.warning_amber_rounded, size: 16, color: Colors.red),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text.rich(
                                        TextSpan(
                                          children: [
                                            const TextSpan(
                                              text: 'Reason: ',
                                              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
                                            ),
                                            TextSpan(
                                              text: reason,
                                              style: TextStyle(
                                                color: isDark ? Colors.grey.shade300 : Colors.black87,
                                              ),
                                            ),
                                          ],
                                        ),
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const Divider(height: 24),
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 12,
                                  backgroundColor: Colors.blue.shade100,
                                  child: Text(
                                    userBranchStr.isNotEmpty ? userBranchStr[0].toUpperCase() : 'U',
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _primaryBlue),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Requested by $userBranchStr',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: isDark ? Colors.grey.shade300 : Colors.grey.shade800,
                                        ),
                                      ),
                                      Text(
                                        requestedAtStr,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            isProcessing
                                ? const Center(
                                    child: SizedBox(
                                      height: 24,
                                      width: 24,
                                      child: CircularProgressIndicator(strokeWidth: 2.5),
                                    ),
                                  )
                                : Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: () => _rejectDeletion(reqId, data),
                                          icon: const Icon(Icons.close_rounded, size: 18, color: Colors.red),
                                          label: const Text('Reject', style: TextStyle(color: Colors.red)),
                                          style: OutlinedButton.styleFrom(
                                            side: const BorderSide(color: Colors.red),
                                            padding: const EdgeInsets.symmetric(vertical: 10),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          onPressed: () => _approveDeletion(reqId, data),
                                          icon: const Icon(Icons.check_rounded, size: 18, color: Colors.white),
                                          label: const Text('Approve', style: TextStyle(color: Colors.white)),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.green,
                                            padding: const EdgeInsets.symmetric(vertical: 10),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(8),
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
      ),
    );
  }
}
