import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../Navigation/user_cache_service.dart';

class PendingTodosModal extends StatefulWidget {
  final String role;
  final String branch;
  const PendingTodosModal(
      {super.key, required this.role, required this.branch});

  @override
  State<PendingTodosModal> createState() => _PendingTodosModalState();
}

class _PendingTodosModalState extends State<PendingTodosModal> {
  String? _selectedBranch;
  List<String> _branches = [];
  List<Map<String, dynamic>> _users = [];
  Map<String, int> _pendingCounts = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _fetchBranches();
    await _fetchUsersAndTodos();
    setState(() {
      _loading = false;
    });
  }

  Future<void> _fetchBranches() async {
    final branches = await UserCacheService.instance.getBranches();
    setState(() {
      _branches = branches;
      if (_branches.isNotEmpty && _selectedBranch == null) {
        _selectedBranch =
            (widget.role == 'manager' || widget.role == 'asst_manager') ? widget.branch : _branches.first;
      }
    });
  }

  Future<void> _fetchUsersAndTodos() async {
    Query usersQuery = FirebaseFirestore.instance.collection('users');
    if (widget.role == 'manager' || widget.role == 'asst_manager') {
      usersQuery = usersQuery.where('branch', isEqualTo: widget.branch);
    } else if (_selectedBranch != null && _selectedBranch!.isNotEmpty) {
      usersQuery = usersQuery.where('branch', isEqualTo: _selectedBranch);
    }
    final usersSnapshot = await usersQuery.get();
    final users = usersSnapshot.docs
        .map((doc) => {
              'uid': doc.id,
              'username': doc['username'] ?? '',
              'role': doc['role'] ?? '',
              'email': doc['email'] ?? '',
              'branch': doc['branch'] ?? '',
            })
        .where((u) => u['role'] != 'admin' && u['role'] != 'sync_head')
        .toList();

    final emails = users.map((u) => u['email'] as String).where((e) => e.isNotEmpty).toList();
    Query todosQuery = FirebaseFirestore.instance
        .collection('todo')
        .where('status', isEqualTo: 'pending')
        .where('email', whereIn: emails.isEmpty ? [''] : (emails.length > 30 ? emails.sublist(0, 30) : emails));

    final todosSnapshot = await todosQuery.get();
    final todos = todosSnapshot.docs
        .map((doc) => doc.data() as Map<String, dynamic>)
        .toList();

    final Map<String, int> pendingCounts = {};
    for (var user in users) {
      final email = user['email'];
      pendingCounts[email] = todos.where((t) => t['email'] == email).length;
    }

    setState(() {
      _users = users;
      _pendingCounts = pendingCounts;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1A1B22) : Colors.white;
    final cardColor =
        isDark ? const Color(0xFF23242B) : const Color(0xFFF5F7FA);
    final textColor = isDark ? Colors.white : const Color(0xFF1A1B22);

    return SafeArea(
      child: DraggableScrollableSheet(
        initialChildSize: 0.8,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: _loading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2.5))
              : ListView(
                  controller: scrollController,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white24 : Colors.black12,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: isDark ? 0.2 : 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.pending_actions_rounded,
                            color: isDark ? Colors.redAccent : Colors.red[700],
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Pending Todos",
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: textColor,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              Text(
                                "by team members",
                                style: TextStyle(
                                  fontSize: 13,
                                  color: textColor.withValues(alpha: 0.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (_branches.isNotEmpty && widget.role != 'manager' && widget.role != 'asst_manager')
                      Padding(
                        padding: const EdgeInsets.only(top: 16, bottom: 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 4),
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isDark
                                  ? Colors.white10
                                  : Colors.black.withValues(alpha: 0.06),
                            ),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedBranch,
                              items: _branches
                                  .map((b) => DropdownMenuItem(
                                      value: b, child: Text(b)))
                                  .toList(),
                              onChanged: (val) async {
                                setState(() {
                                  _selectedBranch = val;
                                  _loading = true;
                                });
                                await _fetchUsersAndTodos();
                                setState(() {
                                  _loading = false;
                                });
                              },
                              hint: Text(
                                "Select Branch",
                                style: TextStyle(
                                    color: textColor.withValues(alpha: 0.5)),
                              ),
                              isExpanded: true,
                              dropdownColor: bgColor,
                              style: TextStyle(
                                color: textColor,
                                fontSize: 14,
                              ),
                              icon: Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: textColor.withValues(alpha: 0.5),
                              ),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    if (_users.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 40),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(
                                Icons.person_off_rounded,
                                size: 48,
                                color: textColor.withValues(alpha: 0.15),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No sales users found',
                                style: TextStyle(
                                  color: textColor.withValues(alpha: 0.4),
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      ..._users.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final user = entry.value;
                        final count = _pendingCounts[user['email']] ?? 0;
                        final hasPending = count > 0;

                        return TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0.0, end: 1.0),
                          duration: Duration(milliseconds: 300 + (idx * 50)),
                          curve: Curves.easeOut,
                          builder: (context, value, child) {
                            return Opacity(
                              opacity: value,
                              child: Transform.translate(
                                offset: Offset(0, 20 * (1 - value)),
                                child: child,
                              ),
                            );
                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color: cardColor,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: hasPending
                                    ? Colors.red.withValues(alpha: 0.15)
                                    : Colors.green.withValues(alpha: 0.1),
                                width: 1,
                              ),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 6),
                              leading: Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: hasPending
                                        ? [
                                            Colors.red.withValues(alpha: 0.15),
                                            Colors.red.withValues(alpha: 0.05),
                                          ]
                                        : [
                                            Colors.green.withValues(alpha: 0.15),
                                            Colors.green.withValues(alpha: 0.05),
                                          ],
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Center(
                                  child: Text(
                                    (user['username'] as String).isNotEmpty
                                        ? (user['username'] as String)[0]
                                            .toUpperCase()
                                        : '?',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: hasPending
                                          ? Colors.red[700]
                                          : Colors.green[700],
                                    ),
                                  ),
                                ),
                              ),
                              title: Text(
                                user['username'],
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: textColor,
                                  fontSize: 14,
                                ),
                              ),
                              subtitle: Text(
                                user['branch'],
                                style: TextStyle(
                                  color: textColor.withValues(alpha: 0.45),
                                  fontSize: 12,
                                ),
                              ),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 6),
                                decoration: BoxDecoration(
                                  color: hasPending
                                      ? Colors.red
                                          .withValues(alpha: isDark ? 0.2 : 0.08)
                                      : Colors.green
                                          .withValues(alpha: isDark ? 0.2 : 0.08),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  '$count',
                                  style: TextStyle(
                                    color: hasPending
                                        ? (isDark
                                            ? Colors.redAccent
                                            : Colors.red[700])
                                        : (isDark
                                            ? Colors.greenAccent
                                            : Colors.green[700]),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                  ],
                ),
        ),
      ),
    );
  }
}
