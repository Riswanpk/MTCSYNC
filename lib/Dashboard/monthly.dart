import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';

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
  String? _currentUserRole;
  List<String> _branches = [];
  List<Map<String, dynamic>> _usersForBranch = [];
  String? _userRole;
  bool _isInitialized = false;

  // Cache for report data
  List<Map<String, dynamic>>? _cachedReport;
  String? _cacheKey;

  @override
  void initState() {
    super.initState();
    _initDropdowns();
  }

  Future<void> _initDropdowns() async {
    final user = FirebaseAuth.instance.currentUser;
    String? userRole;
    String? userBranch;
    
    if (user != null) {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      userRole = userDoc['role'];
      userBranch = userDoc['branch'];
      _currentUserRole = userRole;
      _userRole = userRole;
    }

    if (widget.users.isNotEmpty && widget.branch != null) {
      setState(() {
        _selectedBranch = widget.branch;
        _usersForBranch = List<Map<String, dynamic>>.from(widget.users)
          ..sort((a, b) => a['username'].toString().toLowerCase().compareTo(b['username'].toString().toLowerCase()));
        _selectedUser = _usersForBranch.isNotEmpty ? _usersForBranch.first : null;
        _branches = [widget.branch!];
        _isInitialized = true;
      });
      return;
    }

    final usersSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .get();
    
    final branches = usersSnapshot.docs
        .map((doc) => doc['branch'] ?? '')
        .where((b) => b != null && b.toString().isNotEmpty)
        .toSet()
        .cast<String>()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())); // Sort branches alphabetically

    if (userRole == 'manager' && userBranch != null) {
      await _fetchUsersForBranch(userBranch);
      setState(() {
        _selectedBranch = userBranch;
        _branches = [userBranch ?? ''];
        _isInitialized = true;
      });
    } else {
      setState(() {
        _branches = branches;
        if (_branches.isNotEmpty && _selectedBranch == null) {
          _selectedBranch = _branches.first;
        }
        _isInitialized = true;
      });
      await _fetchUsersForBranch(_selectedBranch);
    }
  }

  Future<void> _fetchUsersForBranch(String? branch) async {
    if (branch == null) {
      setState(() {
        _usersForBranch = [];
        _selectedUser = null;
      });
      return;
    }
    
    final usersSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('branch', isEqualTo: branch)
        .where('role', isNotEqualTo: 'admin')
        .get();

    final users = usersSnapshot.docs
        .map((doc) => {
              'uid': doc.id,
              'username': doc['username'] ?? '',
              'role': doc['role'] ?? '',
              'email': doc['email'] ?? '',
              'branch': doc['branch'] ?? '',
            })
        .toList()
      ..sort((a, b) => a['username'].toString().toLowerCase().compareTo(b['username'].toString().toLowerCase())); // Sort usernames alphabetically

    setState(() {
      _usersForBranch = users;
      _selectedUser = users.isNotEmpty ? users.first : null;
      _cachedReport = null; // Clear cache when user changes
    });
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

    // Fetch both snapshots in parallel for faster loading
    final results = await Future.wait([
      FirebaseFirestore.instance
          .collection('daily_report')
          .where('userId', isEqualTo: uid)
          .where('type', isEqualTo: 'leads')
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
          .where('timestamp', isLessThan: Timestamp.fromDate(nextMonth))
          .get(),
      FirebaseFirestore.instance
          .collection('daily_report')
          .where('userId', isEqualTo: uid)
          .where('type', isEqualTo: 'todo')
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart.subtract(const Duration(days: 2))))
          .where('timestamp', isLessThan: Timestamp.fromDate(nextMonth.add(const Duration(hours: 12))))
          .get(),
    ]);

    final leadDates = results[0].docs
        .map((doc) => (doc['timestamp'] as Timestamp).toDate())
        .toSet();
    final todoDates = results[1].docs
        .map((doc) => (doc['timestamp'] as Timestamp).toDate())
        .toSet();

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

    // Define your colors here for consistency
    const Color selectedGreen = Color.fromARGB(255, 97, 175, 34);
    const Color listBlue = Colors.blue;

    if (!_isInitialized) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF181A20) : const Color(0xFFF6F7FB),
        body: Center(
          child: CircularProgressIndicator(
            color: isDark ? Colors.white : const Color(0xFF6C5CE7),
          ),
        ),
      );
    }

    return Scaffold(
        backgroundColor: isDark ? const Color(0xFF181A20) : const Color(0xFFF6F7FB),
        appBar: AppBar(
          elevation: 0,
          backgroundColor: const Color.fromARGB(255, 6, 91, 160),
          title: Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            decoration: BoxDecoration(
              color: const Color.fromARGB(255, 6, 91, 160),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Monthly Report',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 22,
              ),
            ),
          ),
          centerTitle: true,
        ),
        body: Column(
          children: [
            // Compact Filter Section
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // -------------------------
                  // 1. BRANCH DROPDOWN
                  // -------------------------
                  if (_userRole == 'admin' && _branches.isNotEmpty)
                    Flexible(
                      flex: 2,
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: _selectedBranch,
                          icon: const Icon(Icons.keyboard_arrow_down, size: 18, color: Colors.black),
                          dropdownColor: Colors.white,
                          
                          // 1. ITEMS (The Open Menu -> BLUE)
                          items: _branches.map((b) => DropdownMenuItem(
                                value: b,
                                child: Text(
                                  b,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: listBlue, // Blue inside list
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              )).toList(),
                          
                          // 2. SELECTED (The Closed Button -> GREEN)
                          selectedItemBuilder: (BuildContext context) {
                            return _branches.map((String value) {
                              return Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  value,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: selectedGreen, // Green when selected
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              );
                            }).toList();
                          },

                          onChanged: (val) async {
                            await _fetchUsersForBranch(val);
                            setState(() {
                              _selectedBranch = val;
                            });
                          },
                        ),
                      ),
                    ),
                  
                  if (!(_userRole == 'admin' && _branches.isNotEmpty)) const SizedBox.shrink(),
                  const SizedBox(width: 6),

                  // -------------------------
                  // 2. USER DROPDOWN
                  // -------------------------
                  Flexible(
                    flex: 3,
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<Map<String, dynamic>>(
                        isExpanded: true,
                        value: _selectedUser,
                        icon: const Icon(Icons.keyboard_arrow_down, size: 18, color: Colors.black),
                        dropdownColor: Colors.white,
                        
                        // 1. ITEMS (The Open Menu -> BLUE)
                        items: _usersForBranch.map((u) => DropdownMenuItem(
                                value: u,
                                child: Text(
                                  u['username'],
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: listBlue, // Blue inside list
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              )).toList(),

                        // 2. SELECTED (The Closed Button -> GREEN)
                        selectedItemBuilder: (BuildContext context) {
                          return _usersForBranch.map((Map<String, dynamic> value) {
                            return Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                value['username'],
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: selectedGreen, // Green when selected
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            );
                          }).toList();
                        },

                        onChanged: (val) {
                          setState(() {
                            _selectedUser = val;
                            _cachedReport = null;
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),

                  // -------------------------
                  // 3. MONTH DROPDOWN
                  // -------------------------
                  Flexible(
                    flex: 2,
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        isExpanded: true,
                        value: _selectedMonth,
                        icon: const Icon(Icons.keyboard_arrow_down, size: 18, color: Colors.black),
                        dropdownColor: Colors.white,

                        // 1. ITEMS (The Open Menu -> BLUE)
                        items: List.generate(12, (i) => i + 1).map((m) => DropdownMenuItem(
                                value: m,
                                child: Text(
                                  _getMonthShort(m),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: listBlue, // Blue inside list
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              )).toList(),

                        // 2. SELECTED (The Closed Button -> GREEN)
                        selectedItemBuilder: (BuildContext context) {
                          return List.generate(12, (i) => i + 1).map((int value) {
                            return Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                _getMonthShort(value),
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: selectedGreen, // Green when selected
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            );
                          }).toList();
                        },

                        onChanged: (val) {
                          setState(() {
                            _selectedMonth = val!;
                            _cachedReport = null;
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),

                  // -------------------------
                  // 4. YEAR DROPDOWN
                  // -------------------------
                  Flexible(
                    flex: 2,
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        isExpanded: true,
                        value: _selectedYear,
                        icon: const Icon(Icons.keyboard_arrow_down, size: 18, color: Colors.black),
                        dropdownColor: Colors.white,

                        // 1. ITEMS (The Open Menu -> BLUE)
                        items: List.generate(5, (i) => DateTime.now().year - i).map((y) => DropdownMenuItem(
                                value: y,
                                child: Text(
                                  '$y',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: listBlue, // Blue inside list
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              )).toList(),

                        // 2. SELECTED (The Closed Button -> GREEN)
                        selectedItemBuilder: (BuildContext context) {
                          return List.generate(5, (i) => DateTime.now().year - i).map((int value) {
                            return Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '$value',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: selectedGreen, // Green when selected
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            );
                          }).toList();
                        },

                        onChanged: (val) {
                          setState(() {
                            _selectedYear = val!;
                            _cachedReport = null;
                          });
                        },
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
                          return Center(
                            child: CircularProgressIndicator(
                              color: isDark ? Colors.white : const Color(0xFF6C5CE7),
                            ),
                          );
                        }
                        if (snap.hasError) {
                          return Center(child: Text('Error: ${snap.error}'));
                        }
                        final data = snap.data ?? [];
                        if (data.isEmpty) {
                          return const Center(child: Text('No data for this month.'));
                        }
                        return Scrollbar(
                          thumbVisibility: true,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.vertical,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: SizedBox(
                                width: MediaQuery.of(context).size.width,
                                child: DataTable(
                                  columnSpacing: MediaQuery.of(context).size.width / 8,
                                  columns: const [
                                    DataColumn(label: Text('Date', style: TextStyle(color: selectedGreen, fontWeight: FontWeight.bold))),
                                    DataColumn(label: Text('Todo', style: TextStyle(color: selectedGreen, fontWeight: FontWeight.bold))),
                                    DataColumn(label: Text('Lead', style: TextStyle(color: selectedGreen, fontWeight: FontWeight.bold))),
                                  ],
                                  rows: data.map((item) {
                                    return DataRow(cells: [
                                      DataCell(Text(item['date'])),
                                      DataCell(Icon(
                                        item['todo'] ? Icons.check_circle : Icons.cancel,
                                        color: item['todo'] ? Colors.blue : Colors.red,
                                        size: 20,
                                      )),
                                      DataCell(Icon(
                                        item['lead'] ? Icons.check_circle : Icons.cancel,
                                        color: item['lead'] ? Colors.green : Colors.red,
                                        size: 20,
                                      )),
                                    ]);
                                  }).toList(),
                                ),
                              ),
                            ),
                          )
                          );
                        },
                      )
                  : const Center(child: Text('Select a user to view report')),
            ),
          ],
        ));
  }

  String _getMonthShort(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[month - 1];
  }
}