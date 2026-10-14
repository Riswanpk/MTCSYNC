import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import '../Navigation/user_cache_service.dart';

class MonthlyReportPage extends StatefulWidget {
  final String? branch;
  final List<Map<String, dynamic>> users;
  const MonthlyReportPage({super.key, this.branch, required this.users});

  @override
  State<MonthlyReportPage> createState() => _MonthlyReportPageState();
}

class _MonthlyReportPageState extends State<MonthlyReportPage> {
  Map<String, dynamic>? _selectedUser;
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;
  String? _selectedBranch;
  // ignore: unused_field
  String? _currentUserRole;
  List<String> _branches = [];
  List<Map<String, dynamic>> _usersForBranch = [];
  String? _userRole;
  bool _isInitialized = false;

  // Cache for report data
  List<Map<String, dynamic>>? _cachedReport;
  String? _cacheKey;

  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _initDropdowns();
  }

  Future<void> _initDropdowns({bool forceRefresh = false}) async {
    final cache = UserCacheService.instance;
    await cache.ensureLoaded();
    final userRole = cache.role;
    final userBranch = cache.branch;
    _currentUserRole = userRole;
    _userRole = userRole;

    // Fetch branches and users from cache (or force refresh if requested)
    final allBranches = await cache.getBranches(forceRefresh: forceRefresh);
    final branches = List<String>.from(allBranches)
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final isManager = (userRole == 'manager' || userRole == 'asst_manager');
    final isAdminLike = (userRole == 'admin' || userRole == 'Sync Head' || userRole == 'sync_head');

    if (isManager && userBranch != null && userBranch.isNotEmpty) {
      final users = await _getUsersForBranchFromCache(userBranch, forceRefresh: forceRefresh);
      if (!mounted) return;
      setState(() {
        _branches = [userBranch];
        _selectedBranch = userBranch; // For manager, branch is restricted to their own branch
        _usersForBranch = users;
        _selectedUser = null; // Do not auto-select salesman
        _isInitialized = true;
      });
      return;
    }

    if (!isAdminLike && widget.branch != null && widget.branch!.isNotEmpty) {
      final users = await _getUsersForBranchFromCache(widget.branch!, forceRefresh: forceRefresh);
      if (!mounted) return;
      setState(() {
        _branches = [widget.branch!];
        _selectedBranch = widget.branch;
        _usersForBranch = users;
        _selectedUser = null; // Do not auto-select salesman
        _isInitialized = true;
      });
      return;
    }

    // Admin / sync_head or unrestricted role: do not auto-select branch or salesman
    if (!mounted) return;
    setState(() {
      _branches = branches;
      _selectedBranch = null; // Do not auto-select branch
      _usersForBranch = [];
      _selectedUser = null; // Do not auto-select salesman
      _isInitialized = true;
    });
  }

  Future<List<Map<String, dynamic>>> _getUsersForBranchFromCache(String branch, {bool forceRefresh = false}) async {
    final allUsers = await UserCacheService.instance.getAllUsers(forceRefresh: forceRefresh);
    final filtered = allUsers
        .where((u) =>
            u['branch'] == branch &&
            u['role'] != 'admin')
        .toList()
      ..sort((a, b) => a['username'].toString().toLowerCase().compareTo(b['username'].toString().toLowerCase()));
    return filtered;
  }

  Future<void> _fetchUsersForBranch(String? branch, {bool forceRefresh = false}) async {
    if (branch == null || branch.isEmpty) {
      if (!mounted) return;
      setState(() {
        _usersForBranch = [];
        _selectedUser = null;
        _cachedReport = null;
      });
      return;
    }

    final users = await _getUsersForBranchFromCache(branch, forceRefresh: forceRefresh);

    if (!mounted) return;
    setState(() {
      _usersForBranch = users;
      // Keep selected user if still valid for this branch, otherwise null (do not auto-select)
      if (_selectedUser != null && !users.any((u) => u['uid'] == _selectedUser!['uid'])) {
        _selectedUser = null;
      }
      _cachedReport = null;
    });
  }

  Future<void> _onRefreshPressed() async {
    if (_isRefreshing) return;
    setState(() {
      _isRefreshing = true;
    });
    try {
      await UserCacheService.instance.refreshAllUsers();
      if (_selectedBranch != null) {
        await _fetchUsersForBranch(_selectedBranch, forceRefresh: true);
      } else {
        final allBranches = await UserCacheService.instance.getBranches();
        if (mounted) {
          setState(() {
            _branches = List<String>.from(allBranches)
              ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
          });
        }
      }
      if (_selectedUser != null) {
        // Invalidate cached report as well so it fetches fresh data
        setState(() {
          _cachedReport = null;
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Refreshed data from database'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to refresh: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  String _getCacheKey() {
    return '${_selectedUser?['uid']}_${_selectedMonth}_$_selectedYear';
  }

  Future<List<Map<String, dynamic>>> _generateUserMonthlyReport() async {
    final cacheKey = _getCacheKey();
    
    // Return cached data if available
    if (_cachedReport != null && _cacheKey == cacheKey) {
      return _cachedReport!;
    }

    final uid = _selectedUser!['uid'];
    final monthStart = DateTime(_selectedYear, _selectedMonth, 1);
    final nextMonth = _selectedMonth == 12 
        ? DateTime(_selectedYear + 1, 1, 1) 
        : DateTime(_selectedYear, _selectedMonth + 1, 1);
    final today = DateTime.now();
    final lastDay = (nextMonth.isAfter(today) 
        ? today 
        : nextMonth.subtract(const Duration(days: 1))).day;

    final userEmail = (_selectedUser?['email'] ?? '').toString().trim();

    // Fetch both follow_ups and todos in parallel for faster loading
    final results = await Future.wait([
      FirebaseFirestore.instance
          .collection('follow_ups')
          .where('created_by', isEqualTo: uid)
          .get(),
      FirebaseFirestore.instance
          .collection('todo')
          .where('created_by', isEqualTo: uid)
          .get(),
      if (userEmail.isNotEmpty)
        FirebaseFirestore.instance
            .collection('todo')
            .where('email', isEqualTo: userEmail)
            .get()
      else
        Future.value(null),
    ]);

    final leadSnap = results[0] as QuerySnapshot;
    final todoSnapUid = results[1] as QuerySnapshot;
    final todoSnapEmail = results[2] as QuerySnapshot?;

    final leadDates = <DateTime>{};
    for (final doc in leadSnap.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final ts = data['created_at'];
      if (ts is Timestamp) {
        leadDates.add(ts.toDate());
      } else {
        final dt = data['date'];
        if (dt is Timestamp) {
          leadDates.add(dt.toDate());
        } else if (dt is String) {
          final parsed = DateTime.tryParse(dt);
          if (parsed != null) leadDates.add(parsed);
        }
      }
    }

    final todoDates = <DateTime>{};
    for (final doc in todoSnapUid.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final ts = data['timestamp'];
      if (ts is Timestamp) {
        todoDates.add(ts.toDate());
      }
    }
    if (todoSnapEmail != null) {
      for (final doc in todoSnapEmail.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final ts = data['timestamp'];
        if (ts is Timestamp) {
          todoDates.add(ts.toDate());
        }
      }
    }

    List<Map<String, dynamic>> missedReport = [];

    for (int i = 0; i < lastDay; i++) {
      final date = monthStart.add(Duration(days: i));
      if (date.weekday == DateTime.sunday) continue;

      final dateStr = "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
      final dayStart = DateTime(date.year, date.month, date.day);

      DateTime windowStart;
      if (dayStart.weekday == DateTime.monday) {
        windowStart = dayStart.subtract(const Duration(days: 2)).add(const Duration(hours: 12));
      } else {
        windowStart = dayStart.subtract(const Duration(days: 1)).add(const Duration(hours: 12));
      }
      final windowEnd = dayStart.add(const Duration(hours: 12));

      final leadTick = leadDates.any((leadDate) =>
        leadDate.isAfter(windowStart) && leadDate.isBefore(windowEnd)
      );

      final todoTick = todoDates.any((todoDate) =>
        todoDate.isAfter(windowStart) && todoDate.isBefore(windowEnd)
      );

      missedReport.add({
        'date': dateStr,
        'todo': todoTick,
        'lead': leadTick,
      });
    }

    // Cache the result
    _cachedReport = missedReport;
    _cacheKey = cacheKey;

    return missedReport;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const Color primaryBlue = Color(0xFF005BAC);
    const Color primaryGreen = Color(0xFF8CC63F);

    if (!_isInitialized) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF181A20) : const Color(0xFFF8FAFC),
        body: const Center(
          child: CircularProgressIndicator(color: primaryBlue),
        ),
      );
    }

    return Scaffold(
        backgroundColor: isDark ? const Color(0xFF181A20) : const Color(0xFFF8FAFC),
        appBar: AppBar(
          elevation: 0,
          backgroundColor: primaryBlue,
          foregroundColor: Colors.white,
          title: const Text(
            'Monthly Report',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 18,
              letterSpacing: 0.2,
            ),
          ),
          centerTitle: false,
          actions: [
            IconButton(
              icon: _isRefreshing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.refresh_rounded),
              tooltip: 'Reload from database',
              onPressed: _isRefreshing ? null : _onRefreshPressed,
            ),
          ],
        ),
        body: Column(
          children: [
            // Filter Header Container
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF232730) : Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // 1. BRANCH DROPDOWN (if admin/sync_head)
                  if ((_userRole == 'admin' || _userRole == 'Sync Head' || _userRole == 'sync_head') && _branches.isNotEmpty) ...[
                    Flexible(
                      flex: 3,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF2D323F) : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isDark ? Colors.white12 : Colors.grey.shade300,
                            width: 0.8,
                          ),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            value: _selectedBranch,
                            hint: Text(
                              "Branch",
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                            ),
                            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Colors.grey),
                            dropdownColor: isDark ? const Color(0xFF232730) : Colors.white,
                            items: _branches.map((b) => DropdownMenuItem(
                                  value: b,
                                  child: Text(
                                    b,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: isDark ? Colors.white : const Color(0xFF1E293B),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                )).toList(),
                            onChanged: (val) async {
                              if (val == _selectedBranch) return;
                              setState(() {
                                _selectedBranch = val;
                              });
                              await _fetchUsersForBranch(val);
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],

                  // 2. USER DROPDOWN
                  Flexible(
                    flex: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF2D323F) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isDark ? Colors.white12 : Colors.grey.shade300,
                          width: 0.8,
                        ),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<Map<String, dynamic>>(
                          isExpanded: true,
                          value: _selectedUser,
                          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Colors.grey),
                          dropdownColor: isDark ? const Color(0xFF232730) : Colors.white,
                          items: _usersForBranch.map((u) => DropdownMenuItem(
                                  value: u,
                                  child: Text(
                                    u['username'] ?? '',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: isDark ? Colors.white : const Color(0xFF1E293B),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                )).toList(),
                          onChanged: (val) {
                            if (mounted) {
                              setState(() {
                                _selectedUser = val;
                                _cachedReport = null;
                              });
                            }
                          },
                          hint: Text(
                            "User",
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),

                  // 3. MONTH DROPDOWN
                  Flexible(
                    flex: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF2D323F) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isDark ? Colors.white12 : Colors.grey.shade300,
                          width: 0.8,
                        ),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          isExpanded: true,
                          value: _selectedMonth,
                          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Colors.grey),
                          dropdownColor: isDark ? const Color(0xFF232730) : Colors.white,
                          items: List.generate(12, (i) => i + 1).map((m) => DropdownMenuItem(
                                  value: m,
                                  child: Text(
                                    _getMonthShort(m),
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: isDark ? Colors.white : const Color(0xFF1E293B),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                )).toList(),
                          onChanged: (val) {
                            setState(() {
                              _selectedMonth = val!;
                              _cachedReport = null;
                            });
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),

                  // 4. YEAR DROPDOWN
                  Flexible(
                    flex: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF2D323F) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isDark ? Colors.white12 : Colors.grey.shade300,
                          width: 0.8,
                        ),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          isExpanded: true,
                          value: _selectedYear,
                          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Colors.grey),
                          dropdownColor: isDark ? const Color(0xFF232730) : Colors.white,
                          items: List.generate(5, (i) => DateTime.now().year - i).map((y) => DropdownMenuItem(
                                  value: y,
                                  child: Text(
                                    '$y',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: isDark ? Colors.white : const Color(0xFF1E293B),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                )).toList(),
                          onChanged: (val) {
                            setState(() {
                              _selectedYear = val!;
                              _cachedReport = null;
                            });
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // Report Table Section
            Expanded(
              child: _selectedUser != null
                  ? FutureBuilder<List<Map<String, dynamic>>>(
                      future: _generateUserMonthlyReport(),
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(color: primaryBlue),
                          );
                        }
                        if (snap.hasError) {
                          return Center(
                            child: Text(
                              'Error: ${snap.error}',
                              style: const TextStyle(color: Colors.red),
                            ),
                          );
                        }
                        final data = snap.data ?? [];
                        if (data.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.event_busy_rounded, size: 48, color: Colors.grey.shade400),
                                const SizedBox(height: 8),
                                Text(
                                  'No data recorded for this month.',
                                  style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                                ),
                              ],
                            ),
                          );
                        }

                        final int totalDays = data.length;
                        final int todoDays = data.where((d) => d['todo'] == true).length;
                        final int leadDays = data.where((d) => d['lead'] == true).length;

                        return ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          children: [
                            // Monthly Metrics Card
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF004987), primaryBlue],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(
                                    color: primaryBlue.withOpacity(0.18),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceAround,
                                children: [
                                  _buildMonthlyStat('Days Active', '$totalDays', Colors.white70, Colors.white),
                                  Container(width: 1, height: 26, color: Colors.white24),
                                  _buildMonthlyStat('Todo Done', '$todoDays', const Color(0xFF93C5FD), Colors.white),
                                  Container(width: 1, height: 26, color: Colors.white24),
                                  _buildMonthlyStat('Leads Logged', '$leadDays', const Color(0xFF86EFAC), Colors.white),
                                ],
                              ),
                            ),

                            // Data Table Card
                            Container(
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF232730) : Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isDark ? Colors.white12 : Colors.grey.shade200,
                                  width: 1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.02),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: DataTable(
                                  headingRowColor: WidgetStateProperty.all(
                                    isDark ? const Color(0xFF2D323F) : const Color(0xFFF1F5F9),
                                  ),
                                  headingTextStyle: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    color: isDark ? Colors.white : const Color(0xFF1E293B),
                                  ),
                                  dataTextStyle: TextStyle(
                                    fontSize: 13,
                                    color: isDark ? Colors.white70 : const Color(0xFF334155),
                                    fontWeight: FontWeight.w500,
                                  ),
                                  horizontalMargin: 18,
                                  columnSpacing: 24,
                                  columns: const [
                                    DataColumn(label: Text('Date')),
                                    DataColumn(label: Text('Todo')),
                                    DataColumn(label: Text('Lead')),
                                  ],
                                  rows: data.map((item) {
                                    final bool todo = item['todo'] == true;
                                    final bool lead = item['lead'] == true;
                                    return DataRow(
                                      cells: [
                                        DataCell(Text(item['date'] ?? '')),
                                        DataCell(
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                todo ? Icons.check_circle_rounded : Icons.schedule_rounded,
                                                color: todo ? const Color(0xFF059669) : const Color(0xFFDC2626),
                                                size: 18,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                todo ? 'Done' : 'Missed',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: todo ? const Color(0xFF059669) : const Color(0xFFDC2626),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        DataCell(
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                lead ? Icons.check_circle_rounded : Icons.cancel_outlined,
                                                color: lead ? primaryGreen : Colors.grey.shade400,
                                                size: 18,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                lead ? 'Logged' : 'None',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: lead ? const Color(0xFF4D7C0F) : Colors.grey.shade500,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    )
                  : Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.person_search_rounded, size: 52, color: Colors.grey.shade400),
                          const SizedBox(height: 10),
                          Text(
                            'Select a user to view their monthly report',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ));
  }

  Widget _buildMonthlyStat(String label, String value, Color labelColor, Color valColor) {
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

  String _getMonthShort(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[month - 1];
  }
}