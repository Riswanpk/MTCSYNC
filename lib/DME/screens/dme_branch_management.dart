import 'package:flutter/material.dart';
import '../services/dme_supabase_service.dart';

class DmeBranchManagementPage extends StatefulWidget {
  const DmeBranchManagementPage({super.key});

  @override
  State<DmeBranchManagementPage> createState() => _DmeBranchManagementPageState();
}

class _DmeBranchManagementPageState extends State<DmeBranchManagementPage> {
  final _svc = DmeSupabaseService.instance;
  List<Map<String, dynamic>> _branches = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  Future<void> _loadBranches() async {
    setState(() => _loading = true);
    _branches = await _svc.getBranches();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _addBranch() async {
    final name = await _showNameDialog(title: 'Add Branch');
    if (name == null || name.isEmpty) return;
    try {
      await _svc.addBranch(name);
      _loadBranches();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _renameBranch(int id, String currentName) async {
    final name = await _showNameDialog(
        title: 'Rename Branch', initialValue: currentName);
    if (name == null || name.isEmpty || name == currentName) return;
    try {
      await _svc.updateBranch(id, name);
      _loadBranches();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteBranch(int id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Branch'),
        content: Text('Delete "$name"? This will unlink all users and customers from this branch.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _svc.deleteBranch(id);
      _loadBranches();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<String?> _showNameDialog({
    required String title,
    String? initialValue,
  }) async {
    final ctrl = TextEditingController(text: initialValue);
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Branch name',
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.characters,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Branch Management'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addBranch,
        backgroundColor: const Color(0xFF005BAC),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _branches.isEmpty
              ? const Center(child: Text('No branches. Tap + to add one.'))
              : ListView.builder(
                  itemCount: _branches.length,
                  itemBuilder: (_, i) {
                    final b = _branches[i];
                    final id = b['id'] as int;
                    final name = b['name'] as String;
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            const Color(0xFF005BAC).withOpacity(0.1),
                        child: const Icon(Icons.business,
                            color: Color(0xFF005BAC)),
                      ),
                      title: Text(name,
                          style:
                              const TextStyle(fontWeight: FontWeight.w600)),
                      trailing: PopupMenuButton<String>(
                        onSelected: (action) {
                          if (action == 'rename') _renameBranch(id, name);
                          if (action == 'delete') _deleteBranch(id, name);
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                              value: 'rename', child: Text('Rename')),
                          const PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete',
                                  style: TextStyle(color: Colors.red))),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
