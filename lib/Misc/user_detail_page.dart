import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class UserDetailPage extends StatefulWidget {
  final String userId;
  final String currentUserRole;

  const UserDetailPage({
    super.key,
    required this.userId,
    required this.currentUserRole,
  });

  @override
  State<UserDetailPage> createState() => _UserDetailPageState();
}

class _UserDetailPageState extends State<UserDetailPage> {
  static const Color _primaryBlue = Color(0xFF005BAC);

  final List<String> _roles = ['sales', 'manager', 'admin', 'sync_head'];
  final List<String> _branches = [
    'BGR', 'CBE', 'CHN', 'CLT', 'EKM', 'JBL', 'KKM', 'KSD',
    'KTM', 'PKD', 'PKTR', 'PMNA', 'TRR', 'TSR', 'TLY', 'TVM',
    'UDP', 'VDK', 'WYND',
  ];

  Map<String, dynamic>? _userData;
  String? _appVersion;
  bool _isLoading = true;
  bool _isSaving = false;

  String? _selectedRole;
  String? _selectedBranch;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    setState(() => _isLoading = true);
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .get();

      final versionDoc = await FirebaseFirestore.instance
          .collection('user_version')
          .doc(widget.userId)
          .get();

      if (mounted) {
        setState(() {
          _userData = userDoc.data();
          _selectedRole = _userData?['role'] ?? 'sales';
          _selectedBranch = _userData?['branch'];
          _appVersion = versionDoc.data()?['appVersion'];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading user data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _saveChanges() async {
    if (_selectedRole == null) return;

    setState(() => _isSaving = true);
    try {
      final updates = <String, dynamic>{
        'role': _selectedRole,
      };
      if (_selectedBranch != null) {
        updates['branch'] = _selectedBranch;
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .update(updates);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('User updated successfully'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
        Navigator.of(context).pop(true); // Return true to signal refresh
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving changes: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  bool get _hasChanges {
    if (_userData == null) return false;
    return _selectedRole != (_userData!['role'] ?? 'sales') ||
        _selectedBranch != _userData!['branch'];
  }

  String _formatTimestamp(Timestamp? ts) {
    if (ts == null) return 'N/A';
    final dt = ts.toDate();
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('User Details'),
        backgroundColor: _primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      backgroundColor: isDark ? const Color(0xFF181A20) : const Color(0xFFF6F7FB),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _userData == null
              ? const Center(child: Text('User not found'))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      // Profile header
                      _buildProfileHeader(isDark),
                      const SizedBox(height: 24),
                      // Info card
                      _buildInfoCard(isDark),
                      const SizedBox(height: 24),
                      // Role & Branch editing card
                      _buildEditCard(isDark),
                      const SizedBox(height: 32),
                      // Save button
                      if (_hasChanges) _buildSaveButton(),
                    ],
                  ),
                ),
    );
  }

  Widget _buildProfileHeader(bool isDark) {
    final username = _userData?['username'] ?? 'Unknown';
    final email = _userData?['email'] ?? '';

    return Column(
      children: [
        CircleAvatar(
          radius: 44,
          backgroundColor: _primaryBlue,
          child: Text(
            username.isNotEmpty ? username[0].toUpperCase() : '?',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 32,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          username,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          email,
          style: TextStyle(
            fontSize: 14,
            color: isDark ? Colors.white60 : Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard(bool isDark) {
    final role = _userData?['role'] ?? 'sales';
    final branch = _userData?['branch'] ?? 'N/A';
    final createdAt = _userData?['createdAt'] as Timestamp?;

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: isDark ? const Color(0xFF23272F) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        child: Column(
          children: [
            _infoRow(Icons.badge_outlined, 'UID', widget.userId, isDark),
            const Divider(height: 20),
            _infoRow(
              Icons.security,
              'Current Role',
              role[0].toUpperCase() + role.substring(1),
              isDark,
              valueColor: role == 'admin'
                  ? Colors.deepPurple
                  : role == 'manager'
                      ? Colors.orange
                      : role == 'sync_head'
                          ? Colors.blue
                          : Colors.green,
            ),
            const Divider(height: 20),
            _infoRow(Icons.business, 'Branch', branch, isDark),
            const Divider(height: 20),
            _infoRow(Icons.phone_android, 'App Version', _appVersion ?? 'N/A', isDark),
            const Divider(height: 20),
            _infoRow(Icons.calendar_today, 'Registered', _formatTimestamp(createdAt), isDark),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value, bool isDark,
      {Color? valueColor}) {
    return Row(
      children: [
        Icon(icon, size: 20, color: _primaryBlue.withOpacity(0.7)),
        const SizedBox(width: 12),
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white60 : Colors.grey[600],
              fontSize: 13,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: valueColor ?? (isDark ? Colors.white : Colors.black87),
              fontSize: 14,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildEditCard(bool isDark) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: isDark ? const Color(0xFF23272F) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Edit User',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 16),
            // Role dropdown
            Text(
              'Role',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white60 : Colors.grey[700],
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: _selectedRole,
              decoration: InputDecoration(
                filled: true,
                fillColor: isDark ? const Color(0xFF181A20) : Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              borderRadius: BorderRadius.circular(12),
              dropdownColor: isDark ? const Color(0xFF23272F) : Colors.white,
              items: _roles
                  .map((r) => DropdownMenuItem(
                        value: r,
                        child: Row(
                          children: [
                            Icon(
                              r == 'admin'
                                  ? Icons.security
                                  : r == 'manager'
                                      ? Icons.supervisor_account
                                      : r == 'sync_head'
                                          ? Icons.hub
                                          : Icons.person,
                              color: r == 'admin'
                                  ? Colors.deepPurple
                                  : r == 'manager'
                                      ? Colors.orange
                                      : r == 'sync_head'
                                          ? Colors.blue
                                          : Colors.green,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Text(r[0].toUpperCase() + r.substring(1)),
                          ],
                        ),
                      ))
                  .toList(),
              onChanged: (value) {
                setState(() => _selectedRole = value);
              },
            ),
            const SizedBox(height: 20),
            // Branch dropdown
            Text(
              'Branch',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white60 : Colors.grey[700],
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: _branches.contains(_selectedBranch) ? _selectedBranch : null,
              decoration: InputDecoration(
                filled: true,
                fillColor: isDark ? const Color(0xFF181A20) : Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              borderRadius: BorderRadius.circular(12),
              dropdownColor: isDark ? const Color(0xFF23272F) : Colors.white,
              hint: const Text('Select branch'),
              items: _branches
                  .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                  .toList(),
              onChanged: (value) {
                setState(() => _selectedBranch = value);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton.icon(
        onPressed: _isSaving ? null : _saveChanges,
        icon: _isSaving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.save),
        label: Text(_isSaving ? 'Saving...' : 'Save Changes'),
        style: ElevatedButton.styleFrom(
          backgroundColor: _primaryBlue,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
