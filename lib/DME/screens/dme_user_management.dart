import 'package:flutter/material.dart';
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
        // Filter to show only dme_user entries
        _dmeUsers = (results[0] as List<DmeUser>)
            .where((u) => u.role == 'dme_user')
            .toList();
        _branches = results[1] as List<Map<String, dynamic>>;
        _loading = false;
      });
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('DME Users - Assign Branches'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _dmeUsers.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.people_outline, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'No DME users yet.',
                        style: TextStyle(
                          fontSize: 16,
                          color: isDark ? Colors.white54 : Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Assign users from Manage Users',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.white38 : Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _dmeUsers.length,
                  itemBuilder: (_, i) {
                    final u = _dmeUsers[i];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                      color: isDark ? const Color(0xFF23272F) : Colors.white,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFF005BAC).withOpacity(0.2),
                          child: Text(
                            u.username.isNotEmpty ? u.username[0].toUpperCase() : '?',
                            style: const TextStyle(
                              color: Color(0xFF005BAC),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          u.username,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          u.branchNames.isNotEmpty
                              ? u.branchNames.join(', ')
                              : 'No branches assigned',
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.edit, color: Color(0xFF005BAC)),
                          onPressed: () => _editBranches(u),
                          tooltip: 'Assign Branches',
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
