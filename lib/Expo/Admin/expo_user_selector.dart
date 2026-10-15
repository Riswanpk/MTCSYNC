import 'package:flutter/material.dart';
import '../expo_service.dart';

const Color primaryBlue = Color(0xFF005BAC);
const Color primaryGreen = Color(0xFF8CC63F);

class ExpoUserSelectorPage extends StatefulWidget {
  final List<Map<String, dynamic>> initialSelectedUsers;

  const ExpoUserSelectorPage({
    super.key,
    required this.initialSelectedUsers,
  });

  @override
  State<ExpoUserSelectorPage> createState() => _ExpoUserSelectorPageState();
}

class _ExpoUserSelectorPageState extends State<ExpoUserSelectorPage> {
  final TextEditingController _searchController = TextEditingController();
  final Map<String, Map<String, dynamic>> _selectedUsers = {};

  Map<String, List<Map<String, dynamic>>> _branchUsersMap = {};
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    for (final u in widget.initialSelectedUsers) {
      final uid = u['uid']?.toString() ?? '';
      if (uid.isNotEmpty) {
        _selectedUsers[uid] = u;
      }
    }
    _loadUsers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    setState(() => _isLoading = true);
    try {
      final map = await ExpoService.instance.getUsersByBranch();
      if (mounted) {
        setState(() {
          _branchUsersMap = map;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load users: $e')),
        );
      }
    }
  }

  void _toggleUser(Map<String, dynamic> user) {
    final uid = user['uid']?.toString() ?? '';
    if (uid.isEmpty) return;

    setState(() {
      if (_selectedUsers.containsKey(uid)) {
        _selectedUsers.remove(uid);
      } else {
        _selectedUsers[uid] = user;
      }
    });
  }

  void _toggleBranch(String branch, List<Map<String, dynamic>> branchUsers) {
    final allSelected = branchUsers.every((u) {
      final uid = u['uid']?.toString() ?? '';
      return _selectedUsers.containsKey(uid);
    });

    setState(() {
      if (allSelected) {
        for (final u in branchUsers) {
          final uid = u['uid']?.toString() ?? '';
          _selectedUsers.remove(uid);
        }
      } else {
        for (final u in branchUsers) {
          final uid = u['uid']?.toString() ?? '';
          if (uid.isNotEmpty) {
            _selectedUsers[uid] = u;
          }
        }
      }
    });
  }

  void _toggleSelectAll() {
    final allFiltered = _getFilteredUsers();
    final allSelected = allFiltered.every((u) {
      final uid = u['uid']?.toString() ?? '';
      return _selectedUsers.containsKey(uid);
    });

    setState(() {
      if (allSelected) {
        for (final u in allFiltered) {
          final uid = u['uid']?.toString() ?? '';
          _selectedUsers.remove(uid);
        }
      } else {
        for (final u in allFiltered) {
          final uid = u['uid']?.toString() ?? '';
          if (uid.isNotEmpty) {
            _selectedUsers[uid] = u;
          }
        }
      }
    });
  }

  List<Map<String, dynamic>> _getFilteredUsers() {
    final List<Map<String, dynamic>> list = [];
    final q = _searchQuery.toLowerCase().trim();

    _branchUsersMap.forEach((branch, users) {
      for (final u in users) {
        final name = (u['username'] ?? '').toString().toLowerCase();
        final email = (u['email'] ?? '').toString().toLowerCase();
        final role = (u['role'] ?? '').toString().toLowerCase();
        final b = branch.toLowerCase();

        if (q.isEmpty ||
            name.contains(q) ||
            email.contains(q) ||
            role.contains(q) ||
            b.contains(q)) {
          list.add(u);
        }
      }
    });
    return list;
  }

  Map<String, List<Map<String, dynamic>>> _getFilteredBranchMap() {
    final Map<String, List<Map<String, dynamic>>> filtered = {};
    final q = _searchQuery.toLowerCase().trim();

    _branchUsersMap.forEach((branch, users) {
      final matchedUsers = users.where((u) {
        if (q.isEmpty) return true;
        final name = (u['username'] ?? '').toString().toLowerCase();
        final email = (u['email'] ?? '').toString().toLowerCase();
        final role = (u['role'] ?? '').toString().toLowerCase();
        final b = branch.toLowerCase();
        return name.contains(q) ||
            email.contains(q) ||
            role.contains(q) ||
            b.contains(q);
      }).toList();

      if (matchedUsers.isNotEmpty) {
        filtered[branch] = matchedUsers;
      }
    });

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filteredMap = _getFilteredBranchMap();
    final sortedBranches = filteredMap.keys.toList()..sort();
    final totalSelected = _selectedUsers.length;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A1628) : const Color(0xFFF7F9FC),
      appBar: AppBar(
        title: const Text(
          'Select Users for Expo',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          TextButton.icon(
            onPressed: _branchUsersMap.isEmpty ? null : _toggleSelectAll,
            icon: const Icon(Icons.select_all_rounded, color: Colors.white, size: 20),
            label: Text(
              'Select All',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Search & Selection Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0D2137) : Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  onChanged: (val) => setState(() => _searchQuery = val),
                  decoration: InputDecoration(
                    hintText: 'Search by user, branch or role...',
                    prefixIcon: const Icon(Icons.search_rounded, color: primaryBlue),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 20),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : const Color(0xFFF1F5F9),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: primaryBlue.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '$totalSelected Selected',
                        style: const TextStyle(
                          color: primaryBlue,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    if (totalSelected > 0)
                      TextButton(
                        onPressed: () => setState(() => _selectedUsers.clear()),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(60, 30),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'Clear Selection',
                          style: TextStyle(
                            color: Colors.redAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // Users grouped by branch list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : sortedBranches.isEmpty
                    ? Center(
                        child: Text(
                          _searchQuery.isNotEmpty
                              ? 'No users match "$_searchQuery"'
                              : 'No users found',
                          style: TextStyle(
                            color: isDark ? Colors.white60 : Colors.black54,
                            fontSize: 15,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                        itemCount: sortedBranches.length,
                        itemBuilder: (context, bIndex) {
                          final branch = sortedBranches[bIndex];
                          final branchUsers = filteredMap[branch] ?? [];
                          final isBranchAllSelected = branchUsers.isNotEmpty &&
                              branchUsers.every((u) {
                                final uid = u['uid']?.toString() ?? '';
                                return _selectedUsers.containsKey(uid);
                              });
                          final someSelected = branchUsers.any((u) {
                            final uid = u['uid']?.toString() ?? '';
                            return _selectedUsers.containsKey(uid);
                          });

                          return Card(
                            margin: const EdgeInsets.only(bottom: 14),
                            elevation: 1,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(
                                color: isDark
                                    ? Colors.white12
                                    : Colors.black.withValues(alpha: 0.06),
                              ),
                            ),
                            color: isDark ? const Color(0xFF0F243E) : Colors.white,
                            clipBehavior: Clip.antiAlias,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Branch Header with select branch toggle
                                InkWell(
                                  onTap: () => _toggleBranch(branch, branchUsers),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? primaryBlue.withValues(alpha: 0.25)
                                          : primaryBlue.withValues(alpha: 0.08),
                                      border: Border(
                                        bottom: BorderSide(
                                          color: isDark
                                              ? Colors.white10
                                              : Colors.black.withValues(alpha: 0.05),
                                        ),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Checkbox(
                                          value: isBranchAllSelected
                                              ? true
                                              : (someSelected ? null : false),
                                          tristate: true,
                                          activeColor: primaryBlue,
                                          onChanged: (_) =>
                                              _toggleBranch(branch, branchUsers),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: primaryBlue,
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            branch,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Text(
                                          '${branchUsers.length} user${branchUsers.length > 1 ? "s" : ""}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                            color: isDark
                                                ? Colors.white70
                                                : Colors.black87,
                                          ),
                                        ),
                                        const Spacer(),
                                        Text(
                                          isBranchAllSelected
                                              ? 'Deselect Branch'
                                              : 'Select Branch',
                                          style: TextStyle(
                                            color: primaryBlue,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                                // Users under branch
                                ...branchUsers.map((user) {
                                  final uid = user['uid']?.toString() ?? '';
                                  final isChecked = _selectedUsers.containsKey(uid);
                                  final username = user['username'] ?? 'User';
                                  final role = (user['role'] ?? '').toString();
                                  final email = (user['email'] ?? '').toString();

                                  return InkWell(
                                    onTap: () => _toggleUser(user),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isChecked
                                            ? (isDark
                                                ? primaryGreen.withValues(alpha: 0.12)
                                                : primaryGreen.withValues(alpha: 0.08))
                                            : Colors.transparent,
                                        border: Border(
                                          bottom: BorderSide(
                                            color: isDark
                                                ? Colors.white.withValues(alpha: 0.04)
                                                : Colors.black.withValues(alpha: 0.03),
                                          ),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Checkbox(
                                            value: isChecked,
                                            activeColor: primaryGreen,
                                            onChanged: (_) => _toggleUser(user),
                                          ),
                                          CircleAvatar(
                                            radius: 18,
                                            backgroundColor: primaryBlue.withValues(alpha: 0.15),
                                            child: Text(
                                              username.isNotEmpty
                                                  ? username[0].toUpperCase()
                                                  : 'U',
                                              style: const TextStyle(
                                                color: primaryBlue,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  username,
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 14,
                                                    color: isDark
                                                        ? Colors.white
                                                        : Colors.black87,
                                                  ),
                                                ),
                                                if (email.isNotEmpty)
                                                  Text(
                                                    email,
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: isDark
                                                          ? Colors.white54
                                                          : Colors.black54,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                          if (role.isNotEmpty)
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 7,
                                                vertical: 3,
                                              ),
                                              decoration: BoxDecoration(
                                                color: isDark
                                                    ? Colors.white10
                                                    : Colors.black.withValues(alpha: 0.05),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                role.toUpperCase(),
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: isDark
                                                      ? Colors.white70
                                                      : Colors.black54,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  );
                                }),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
      bottomSheet: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0D2137) : Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: SafeArea(
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pop(_selectedUsers.values.toList());
              },
              icon: const Icon(Icons.check_circle_rounded, color: Colors.white),
              label: Text(
                'Confirm Selection ($totalSelected)',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryBlue,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
