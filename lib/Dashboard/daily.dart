import 'package:flutter/material.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../Todo/todo_leads_full_month.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../Navigation/user_cache_service.dart';

const Color _primaryBlue = Color(0xFF005BAC);
const Color _primaryGreen = Color(0xFF8CC63F);

class DailyDashboardPage extends StatefulWidget {
  const DailyDashboardPage({super.key});

  @override
  State<DailyDashboardPage> createState() => _DailyDashboardPageState();
}

class _DailyDashboardPageState extends State<DailyDashboardPage> {
  DateTime _selectedDate = _getDefaultDashboardDateIST();
  static final _istLocation = _initIST();

  static tz.Location _initIST() {
    tz.initializeTimeZones();
    return tz.getLocation('Asia/Kolkata');
  }

  static DateTime _getDefaultDashboardDateIST() {
    final nowIST = tz.TZDateTime.now(_initIST());
    DateTime target = nowIST.hour >= 12
        ? nowIST.add(const Duration(days: 1))
        : nowIST;
    // Never allow Sunday - skip to Monday
    if (target.weekday == DateTime.sunday) {
      target = target.add(const Duration(days: 1));
    }
    return target;
  }

  String? _selectedBranch;
  List<String> _branches = [];
  String? _role;
  String? _userBranch;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final user = FirebaseAuth.instance.currentUser;
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(user!.uid).get();
    _role = userDoc['role'];
    _userBranch = userDoc['branch'];
    if (_role == 'admin' || _role == 'Sync Head' || _role == 'sync_head') {
      _branches = await UserCacheService.instance.getBranches();
      _selectedBranch = _branches.isNotEmpty ? _branches.first : null;
    } else {
      _selectedBranch = _userBranch;
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
    });
  }

  Future<void> _pickDate(BuildContext context) async {
    final nowIST = tz.TZDateTime.now(_istLocation);
    final defaultDate = _getDefaultDashboardDateIST();
    var maxDate = defaultDate.isAfter(nowIST) ? defaultDate : nowIST;
    if (maxDate.weekday == DateTime.sunday) {
      maxDate = maxDate.add(const Duration(days: 1));
    }
    final initial = _selectedDate.weekday == DateTime.sunday ? defaultDate : _selectedDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2023, 1, 1),
      lastDate: DateTime(maxDate.year, maxDate.month, maxDate.day),
      selectableDayPredicate: (DateTime date) => date.weekday != DateTime.sunday,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: _primaryBlue,
              onPrimary: Colors.white,
              onSurface: Color(0xFF1E293B),
            ),
          ),
          child: child!,
        );
      },
    );
    if (!mounted) return;
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<Map<String, List<Map<String, dynamic>>>> _fetchBranchDashboardData() async {
    if (_selectedBranch == null) {
      return {'sales': [], 'asst_manager': [], 'manager': [], 'other': []};
    }

    // 1. Fetch branch users from Firestore
    final usersSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('branch', isEqualTo: _selectedBranch)
        .get();

    final branchUsers = usersSnapshot.docs.map((doc) {
      final data = doc.data();
      return <String, dynamic>{
        'uid': doc.id,
        'username': (data['username'] ?? '').toString(),
        'email': (data['email'] ?? '').toString(),
        'role': (data['role'] ?? 'sales').toString().toLowerCase().trim(),
        'branch': (data['branch'] ?? _selectedBranch).toString(),
      };
    }).toList();

    // 2. Build email and username lookups across all users to match sendDailyTodoReport.js exactly
    final allCachedUsers = await UserCacheService.instance.getAllUsers();
    final userMap = <String, Map<String, dynamic>>{};
    final emailToUserId = <String, String>{};
    final usernameToUserId = <String, String>{};

    for (final u in allCachedUsers) {
      final uid = u['uid']?.toString() ?? '';
      if (uid.isNotEmpty) {
        userMap[uid] = u;
        final email = u['email']?.toString().trim().toLowerCase();
        if (email != null && email.isNotEmpty) {
          emailToUserId[email] = uid;
        }
        final username = u['username']?.toString().trim().toLowerCase();
        if (username != null && username.isNotEmpty) {
          usernameToUserId[username] = uid;
        }
      }
    }

    // Ensure branch users are registered in userMap and lookups
    for (final u in branchUsers) {
      final uid = u['uid']?.toString() ?? '';
      if (uid.isNotEmpty) {
        userMap.putIfAbsent(uid, () => u);
        final email = u['email']?.toString().trim().toLowerCase();
        if (email != null && email.isNotEmpty) {
          emailToUserId.putIfAbsent(email, () => uid);
        }
        final username = u['username']?.toString().trim().toLowerCase();
        if (username != null && username.isNotEmpty) {
          usernameToUserId.putIfAbsent(username, () => uid);
        }
      }
    }

    // 3. Time interval matching sendDailyTodoReport.js in IST
    final ist = _istLocation;
    final todayIST = tz.TZDateTime(ist, _selectedDate.year, _selectedDate.month, _selectedDate.day);
    DateTime windowStart;
    if (todayIST.weekday == DateTime.monday) {
      // Monday interval is Saturday 12 PM to Monday 12 PM
      final saturday = todayIST.subtract(const Duration(days: 2));
      windowStart = tz.TZDateTime(ist, saturday.year, saturday.month, saturday.day, 12);
    } else {
      // Previous day 12 PM to selected date 12 PM
      final yesterday = todayIST.subtract(const Duration(days: 1));
      windowStart = tz.TZDateTime(ist, yesterday.year, yesterday.month, yesterday.day, 12);
    }
    final windowEnd = tz.TZDateTime(ist, todayIST.year, todayIST.month, todayIST.day, 12);

    // 4. Fetch todos created in the window (leads checking completely removed)
    final todosSnap = await FirebaseFirestore.instance
        .collection('todo')
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(windowStart))
        .where('timestamp', isLessThan: Timestamp.fromDate(windowEnd))
        .get();

    // 5. Match todos to users using identical logic as sendDailyTodoReport.js
    final userIdsWithTodo = <String>{};

    for (final doc in todosSnap.docs) {
      final data = doc.data();
      String? userId = data['created_by']?.toString() ??
          data['userId']?.toString() ??
          data['user_id']?.toString();

      if ((userId == null || !userMap.containsKey(userId)) && data['email'] != null) {
        final email = data['email'].toString().trim().toLowerCase();
        if (emailToUserId.containsKey(email)) {
          userId = emailToUserId[email];
        }
      }

      if (userId == null || !userMap.containsKey(userId)) {
        final rawName = data['username'] ?? data['user_name'] ?? data['created_by_name'];
        if (rawName != null) {
          final name = rawName.toString().trim().toLowerCase();
          if (usernameToUserId.containsKey(name)) {
            userId = usernameToUserId[name];
          }
        }
      }

      if (userId == null || !userMap.containsKey(userId)) {
        final createdBy = data['created_by']?.toString().trim().toLowerCase();
        if (createdBy != null && usernameToUserId.containsKey(createdBy)) {
          userId = usernameToUserId[createdBy];
        }
      }

      if (userId != null && userMap.containsKey(userId)) {
        userIdsWithTodo.add(userId);
      }
    }

    // 6. Partition branch users by role and mark todo status
    final salesUsers = <Map<String, dynamic>>[];
    final asstUsers = <Map<String, dynamic>>[];
    final managerUsers = <Map<String, dynamic>>[];
    final otherUsers = <Map<String, dynamic>>[];

    for (final user in branchUsers) {
      final uid = user['uid']?.toString() ?? '';
      user['todo'] = userIdsWithTodo.contains(uid);

      final role = (user['role'] ?? '').toString();
      if (role == 'sales') {
        salesUsers.add(user);
      } else if (role == 'asst_manager' || role == 'asst manager' || role == 'assistant_manager') {
        asstUsers.add(user);
      } else if (role == 'manager') {
        managerUsers.add(user);
      } else {
        otherUsers.add(user);
      }
    }

    return {
      'sales': salesUsers,
      'asst_manager': asstUsers,
      'manager': managerUsers,
      'other': otherUsers,
    };
  }

  Widget _buildRoleHeader(String title, int count, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 4, top: 16, bottom: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _primaryBlue.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: _primaryBlue),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1E293B),
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserTile(Map<String, dynamic> user) {
    final username = (user['username'] ?? '').toString();
    final initial = username.isNotEmpty ? username.substring(0, 1).toUpperCase() : '?';
    final isDone = user['todo'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDone ? const Color(0xFF10B981).withOpacity(0.25) : Colors.grey.shade200,
          width: isDone ? 1.2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              // Avatar
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDone
                        ? [const Color(0xFF059669), const Color(0xFF10B981)]
                        : [_primaryBlue, const Color(0xFF1E40AF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // User Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      username,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E293B),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      (user['email'] ?? '').toString(),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Status Pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isDone
                      ? const Color(0xFFECFDF5)
                      : const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDone
                        ? const Color(0xFFA7F3D0)
                        : const Color(0xFFFECACA),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isDone ? Icons.check_circle_rounded : Icons.schedule_rounded,
                      size: 15,
                      color: isDone ? const Color(0xFF059669) : const Color(0xFFDC2626),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      isDone ? 'Completed' : 'Pending',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: isDone ? const Color(0xFF047857) : const Color(0xFFB91C1C),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard(Map<String, List<Map<String, dynamic>>> data, bool isAdmin, bool isManager) {
    int total = 0;
    int done = 0;

    final rolesToCheck = isAdmin
        ? ['sales', 'asst_manager', 'manager', 'other']
        : isManager
            ? ['sales', 'asst_manager']
            : ['sales', 'asst_manager', 'manager', 'other'];

    for (final role in rolesToCheck) {
      final list = data[role] ?? [];
      total += list.length;
      done += list.where((u) => u['todo'] == true).length;
    }

    final pending = total - done;
    final percent = total > 0 ? ((done / total) * 100).toInt() : 0;

    return Container(
      margin: const EdgeInsets.only(top: 12, bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF004987), Color(0xFF005BAC)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _primaryBlue.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Circular Progress Indicator
          SizedBox(
            width: 48,
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: total > 0 ? (done / total) : 0,
                  strokeWidth: 4.5,
                  backgroundColor: Colors.white.withOpacity(0.2),
                  valueColor: const AlwaysStoppedAnimation<Color>(_primaryGreen),
                ),
                Text(
                  '$percent%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // Metrics breakdown
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatPill('Total', '$total', Colors.white70, Colors.white),
                Container(width: 1, height: 26, color: Colors.white24),
                _buildStatPill('Done', '$done', const Color(0xFF86EFAC), const Color(0xFFBBF7D0)),
                Container(width: 1, height: 26, color: Colors.white24),
                _buildStatPill('Pending', '$pending', const Color(0xFFFCA5A5), const Color(0xFFFECACA)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatPill(String label, String value, Color labelColor, Color valColor) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: valColor,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: labelColor,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF8FAFC),
        body: Center(
          child: CircularProgressIndicator(color: _primaryBlue),
        ),
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Todo Daily Report',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            letterSpacing: 0.2,
          ),
        ),
        backgroundColor: _primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        actions: [
          if (_role == 'admin' || _role == 'Sync Head' || _role == 'sync_head')
            IconButton(
              icon: const Icon(Icons.file_download_outlined, size: 22),
              tooltip: 'Download Report',
              onPressed: () async {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const TodoLeadsFullMonthPage(),
                  ),
                );
              },
            ),
        ],
      ),
      body: Column(
        children: [
          // Top Control Card
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    // Date Selector
                    Expanded(
                      child: InkWell(
                        onTap: () => _pickDate(context),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade300, width: 0.8),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_today_rounded, size: 16, color: _primaryBlue),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  "${_selectedDate.day.toString().padLeft(2, '0')}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.year}",
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1E293B),
                                  ),
                                ),
                              ),
                              const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Colors.grey),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if ((_role == 'admin' || _role == 'Sync Head' || _role == 'sync_head') && _branches.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      // Branch Dropdown
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade300, width: 0.8),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedBranch,
                              isExpanded: true,
                              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Colors.grey),
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1E293B),
                              ),
                              items: _branches
                                  .map((b) => DropdownMenuItem(
                                        value: b,
                                        child: Text(
                                          b,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ))
                                  .toList(),
                              onChanged: (val) {
                                setState(() {
                                  _selectedBranch = val;
                                });
                              },
                              hint: const Text(
                                "Select Branch",
                                style: TextStyle(fontSize: 13, color: Colors.grey),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // Main User List Section
          Expanded(
            child: FutureBuilder<Map<String, List<Map<String, dynamic>>>>(
              future: _fetchBranchDashboardData(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: _primaryBlue),
                  );
                }
                if (!snapshot.hasData || snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inbox_outlined, size: 48, color: Colors.grey.shade400),
                        const SizedBox(height: 8),
                        Text(
                          'No users found.',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                        ),
                      ],
                    ),
                  );
                }
                final data = snapshot.data!;
                final salesUsers = data['sales'] ?? [];
                final asstUsers = data['asst_manager'] ?? [];
                final managerUsers = data['manager'] ?? [];
                final otherUsers = data['other'] ?? [];

                final isAdmin = _role == 'admin' || _role == 'Sync Head' || _role == 'sync_head';
                final isManager = _role == 'manager';

                if (isAdmin) {
                  if (salesUsers.isEmpty && asstUsers.isEmpty && managerUsers.isEmpty && otherUsers.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.people_outline, size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 8),
                          Text(
                            'No staff records for this branch.',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                          ),
                        ],
                      ),
                    );
                  }
                  return ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    children: [
                      _buildSummaryCard(data, isAdmin, isManager),
                      if (salesUsers.isNotEmpty) ...[
                        _buildRoleHeader('Sales Executive', salesUsers.length, Icons.point_of_sale_rounded),
                        ...salesUsers.map(_buildUserTile),
                      ],
                      if (asstUsers.isNotEmpty) ...[
                        _buildRoleHeader('Assistant Manager', asstUsers.length, Icons.supervisor_account_rounded),
                        ...asstUsers.map(_buildUserTile),
                      ],
                      if (managerUsers.isNotEmpty) ...[
                        _buildRoleHeader('Branch Manager', managerUsers.length, Icons.manage_accounts_rounded),
                        ...managerUsers.map(_buildUserTile),
                      ],
                      if (otherUsers.isNotEmpty) ...[
                        _buildRoleHeader('Other Team Members', otherUsers.length, Icons.groups_rounded),
                        ...otherUsers.map(_buildUserTile),
                      ],
                    ],
                  );
                } else if (isManager) {
                  if (salesUsers.isEmpty && asstUsers.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.people_outline, size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 8),
                          Text(
                            'No team members found.',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                          ),
                        ],
                      ),
                    );
                  }
                  return ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    children: [
                      _buildSummaryCard(data, isAdmin, isManager),
                      if (salesUsers.isNotEmpty) ...[
                        _buildRoleHeader('Sales Executive', salesUsers.length, Icons.point_of_sale_rounded),
                        ...salesUsers.map(_buildUserTile),
                      ],
                      if (asstUsers.isNotEmpty) ...[
                        _buildRoleHeader('Assistant Manager', asstUsers.length, Icons.supervisor_account_rounded),
                        ...asstUsers.map(_buildUserTile),
                      ],
                    ],
                  );
                } else {
                  final allBranchUsers = [...salesUsers, ...asstUsers, ...managerUsers, ...otherUsers];
                  if (allBranchUsers.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.people_outline, size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 8),
                          Text(
                            'No team members found.',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                          ),
                        ],
                      ),
                    );
                  }
                  return ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    children: [
                      _buildSummaryCard(data, isAdmin, isManager),
                      _buildRoleHeader('Team Members', allBranchUsers.length, Icons.groups_rounded),
                      ...allBranchUsers.map(_buildUserTile),
                    ],
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}