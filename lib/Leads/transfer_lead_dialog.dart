import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

/// Dialog to transfer a lead to another user and/or branch
class TransferLeadDialog extends StatefulWidget {
  final String leadDocId;
  final String currentBranch;
  final String currentCreatedBy;
  final Map<String, dynamic> leadData;

  const TransferLeadDialog({
    super.key,
    required this.leadDocId,
    required this.currentBranch,
    required this.currentCreatedBy,
    required this.leadData,
  });

  @override
  State<TransferLeadDialog> createState() => _TransferLeadDialogState();
}

class _TransferLeadDialogState extends State<TransferLeadDialog> {
  String? _selectedBranch;
  String? _selectedUserId;
  String? _selectedUserName;
  List<String> _branches = [];
  List<Map<String, dynamic>> _users = [];
  bool _isLoading = true;
  bool _isTransferring = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initializeBranchesAndUsers();
  }

  Future<void> _initializeBranchesAndUsers() async {
    try {
      // Fetch all branches
      final branchesSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .get();

      final branchesSet = <String>{};
      for (final doc in branchesSnapshot.docs) {
        final branch = doc.data()['branch'] as String?;
        if (branch != null && branch.isNotEmpty) {
          branchesSet.add(branch);
        }
      }

      setState(() {
        _branches = branchesSet.toList()..sort();
        _selectedBranch = widget.currentBranch;
        _isLoading = false;
      });

      // Load users for current branch
      if (mounted) {
        await _loadUsersForBranch(widget.currentBranch);
      }
    } catch (e) {
      setState(() {
        _error = 'Error loading branches: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadUsersForBranch(String branch) async {
    try {
      final usersSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('branch', isEqualTo: branch)
          .where('role', whereIn: ['manager', 'asst_manager', 'sales'])
          .get();

      final users = <Map<String, dynamic>>[];
      for (final doc in usersSnapshot.docs) {
        final data = doc.data();
        users.add({
          'uid': data['uid'] ?? doc.id,
          'username': data['username'] ?? data['email'] ?? 'Unknown',
          'role': data['role'] ?? 'sales',
        });
      }

      // Sort by username
      users.sort((a, b) =>
          (a['username'] as String).compareTo(b['username'] as String));

      if (mounted) {
        setState(() {
          _users = users;
          _selectedUserId = null;
          _selectedUserName = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error loading users: $e';
        });
      }
    }
  }

  Future<void> _transferLead() async {
    if (_selectedBranch == null || _selectedUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select both branch and user')),
      );
      return;
    }

    setState(() => _isTransferring = true);

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('User not logged in');
      }

      // Prepare update data
      final updateData = <String, dynamic>{
        'created_by': _selectedUserId,
        'assigned_to': _selectedUserId,
        'assigned_to_name': _selectedUserName,
        'branch': _selectedBranch,
        'transferred_at': FieldValue.serverTimestamp(),
        'transferred_by': currentUser.uid,
        'notification_seen': false, // Mark notification as unseen on transfer
      };

      // Add original values if they don't already exist (first transfer)
      final currentData = widget.leadData;
      if (!currentData.containsKey('original_created_user') ||
          currentData['original_created_user'] == null) {
        updateData['original_created_user'] = widget.currentCreatedBy;
      }
      if (!currentData.containsKey('original_branch') ||
          currentData['original_branch'] == null) {
        updateData['original_branch'] = widget.currentBranch;
      }

      // Perform the transfer
      await FirebaseFirestore.instance
          .collection('follow_ups')
          .doc(widget.leadDocId)
          .update(updateData);

      // Cancel the local reminder notification on this device so it doesn't
      // fire for the original owner after the lead has been transferred away.
      final notifId = int.tryParse(
              widget.leadDocId.hashCode.abs().toString().substring(0, 7)) ??
          0;
      await AwesomeNotifications().cancelSchedule(notifId);

      if (mounted) {
        Navigator.of(context).pop(true); // Return true to indicate success
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isTransferring = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Transfer failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_isLoading) {
      return AlertDialog(
        title: const Text('Transfer Lead'),
        content: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return AlertDialog(
      title: const Text('Transfer Lead'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Display lead info
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF23272F)
                    : const Color(0xFFF0F2F5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.leadData['name'] ?? 'Unknown',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Phone: ${widget.leadData['phone'] ?? 'N/A'}',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Branch Selection
            Text(
              'Select Branch',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(
                  color: isDark ? Colors.white24 : Colors.black12,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButton<String>(
                isExpanded: true,
                value: _selectedBranch,
                underline: const SizedBox(),
                dropdownColor: isDark ? const Color(0xFF23272F) : Colors.white,
                items: _branches.map((branch) {
                  return DropdownMenuItem(
                    value: branch,
                    child: Text(branch),
                  );
                }).toList(),
                onChanged: (newBranch) async {
                  setState(() => _selectedBranch = newBranch);
                  if (newBranch != null) {
                    await _loadUsersForBranch(newBranch);
                  }
                },
              ),
            ),
            const SizedBox(height: 20),

            // User Selection
            Text(
              'Select User (${_selectedBranch ?? 'N/A'})',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 8),
            if (_users.isEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF23272F)
                      : const Color(0xFFF0F2F5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'No users available for selected branch',
                  style: TextStyle(fontSize: 13),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: isDark ? Colors.white24 : Colors.black12,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: _selectedUserId,
                  underline: const SizedBox(),
                  hint: const Text('Select user...'),
                  dropdownColor:
                      isDark ? const Color(0xFF23272F) : Colors.white,
                  items: _users.map((user) {
                    return DropdownMenuItem(
                      value: user['uid'] as String,
                      child: Text(
                        '${user['username']} (${user['role']})',
                      ),
                    );
                  }).toList(),
                  onChanged: (newUserId) {
                    setState(() {
                      _selectedUserId = newUserId;
                      if (newUserId != null) {
                        _selectedUserName = _users
                            .firstWhere((u) => u['uid'] == newUserId)['username'];
                      }
                    });
                  },
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: Colors.red,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isTransferring ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isTransferring ? null : _transferLead,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF005BAC),
            foregroundColor: Colors.white,
          ),
          child: _isTransferring
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Text('Transfer'),
        ),
      ],
    );
  }
}
