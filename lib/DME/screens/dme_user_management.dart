import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/dme_supabase_service.dart';
import '../models/dme_user.dart';

class DmeUserManagementPage extends StatefulWidget {
  const DmeUserManagementPage({super.key});

  @override
  State<DmeUserManagementPage> createState() => _DmeUserManagementPageState();
}

class _DmeUserManagementPageState extends State<DmeUserManagementPage> {
  final _svc = DmeSupabaseService.instance;

  List<DmeUser> _dmeUsers = [];
  List<Map<String, dynamic>> _branches = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      _svc.getAllDmeUsers(),
      _svc.getBranches(),
    ]);
    if (mounted) {
      setState(() {
        _dmeUsers = results[0] as List<DmeUser>;
        _branches = results[1] as List<Map<String, dynamic>>;
        _loading = false;
      });
    }
  }

  Future<void> _addUser() async {
    // Fetch Firebase users to pick from
    final firebaseUsers = await FirebaseFirestore.instance
        .collection('users')
        .get();
    final existing = _dmeUsers.map((u) => u.firebaseUid).toSet();
    final available = firebaseUsers.docs
        .where((d) => !existing.contains(d.id))
        .toList();

    if (available.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All Firebase users already added')),
        );
      }
      return;
    }

    if (!mounted) return;
    final selected = await showDialog<QueryDocumentSnapshot>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Select User'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: ListView.builder(
            itemCount: available.length,
            itemBuilder: (_, i) {
              final d = available[i].data();
              return ListTile(
                title: Text(d['username']?.toString() ?? d['email']?.toString() ?? ''),
                subtitle: Text(d['email']?.toString() ?? ''),
                onTap: () => Navigator.pop(context, available[i]),
              );
            },
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
        ],
      ),
    );
    if (selected == null) return;

    // Pick role
    if (!mounted) return;
    final role = await showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Select Role'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'dme_admin'),
            child: const Text('DME Admin'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'dme_user'),
            child: const Text('DME User'),
          ),
        ],
      ),
    );
    if (role == null) return;

    // Pick branches
    if (!mounted) return;
    final selectedBranches = await _showBranchSelector([]);
    if (selectedBranches == null) return;

    try {
      final data = selected.data() as Map<String, dynamic>;
      await _svc.createDmeUser(
        firebaseUid: selected.id,
        email: data['email']?.toString() ?? '',
        username: data['username']?.toString() ?? '',
        role: role,
        branchIds: selectedBranches,
      );
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _editBranches(DmeUser user) async {
    final currentIds = await _svc.getUserBranchIds(user.id);
    final selected = await _showBranchSelector(currentIds);
    if (selected == null) return;
    try {
      await _svc.setUserBranches(user.id, selected);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _changeRole(DmeUser user) async {
    final newRole = user.role == 'dme_admin' ? 'dme_user' : 'dme_admin';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Change Role'),
        content: Text('Change ${user.username} to $newRole?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _svc.updateDmeUserRole(user.id, newRole);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteUser(DmeUser user) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove User'),
        content: Text('Remove ${user.username} from DME?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child:
                  const Text('Remove', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _svc.deleteDmeUser(user.id);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<List<int>?> _showBranchSelector(List<int> currentIds) async {
    final selected = Set<int>.from(currentIds);
    return showDialog<List<int>>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Select Branches'),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: ListView(
              children: _branches.map((b) {
                final id = b['id'] as int;
                final name = b['name'] as String;
                return CheckboxListTile(
                  title: Text(name),
                  value: selected.contains(id),
                  onChanged: (v) {
                    setDialogState(() {
                      if (v == true) {
                        selected.add(id);
                      } else {
                        selected.remove(id);
                      }
                    });
                  },
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () => Navigator.pop(context, selected.toList()),
                child: const Text('Save')),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('User Management'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addUser,
        backgroundColor: const Color(0xFF005BAC),
        child: const Icon(Icons.person_add, color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _dmeUsers.isEmpty
              ? const Center(child: Text('No DME users. Tap + to add one.'))
              : ListView.builder(
                  itemCount: _dmeUsers.length,
                  itemBuilder: (_, i) {
                    final u = _dmeUsers[i];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: u.isAdmin
                            ? const Color(0xFF005BAC).withOpacity(0.1)
                            : Colors.grey.withOpacity(0.1),
                        child: Icon(
                          u.isAdmin
                              ? Icons.admin_panel_settings
                              : Icons.person,
                          color: u.isAdmin
                              ? const Color(0xFF005BAC)
                              : Colors.grey,
                        ),
                      ),
                      title: Text(u.username,
                          style:
                              const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        [
                          u.role.toUpperCase(),
                          if (u.branchNames.isNotEmpty)
                            u.branchNames.join(', '),
                        ].join(' • '),
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (action) {
                          switch (action) {
                            case 'branches':
                              _editBranches(u);
                              break;
                            case 'role':
                              _changeRole(u);
                              break;
                            case 'delete':
                              _deleteUser(u);
                              break;
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                              value: 'branches',
                              child: Text('Edit Branches')),
                          const PopupMenuItem(
                              value: 'role', child: Text('Change Role')),
                          const PopupMenuItem(
                              value: 'delete',
                              child: Text('Remove',
                                  style: TextStyle(color: Colors.red))),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
