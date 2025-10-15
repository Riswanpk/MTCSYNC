import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:excel/excel.dart' hide TextSpan;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:share_plus/share_plus.dart';
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
  bool _isLoading = false;
  double _progress = 0.0; // Add this line

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
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      userRole = userDoc['role'];
      userBranch = userDoc['branch'];
      _currentUserRole = userRole;
    }

    if (widget.users.isNotEmpty && widget.branch != null) {
      setState(() {
        _selectedBranch = widget.branch;
        _usersForBranch = widget.users;
        _selectedUser = widget.users.isNotEmpty ? widget.users.first : null;
        _branches = [widget.branch!];
      });
      return;
    }

    final usersSnapshot = await FirebaseFirestore.instance.collection('users').get();
    final branches = usersSnapshot.docs
        .map((doc) => doc['branch'] ?? '')
        .where((b) => b != null && b.toString().isNotEmpty)
        .toSet()
        .cast<String>()
        .toList();

    setState(() {
      _branches = branches;
      if (_branches.isNotEmpty && _selectedBranch == null) {
        _selectedBranch = _branches.first;
      }
    });

    if (userRole == 'manager' && userBranch != null) {
      await _fetchUsersForBranch(userBranch);
      setState(() {
        _selectedBranch = userBranch;
      });
    } else {
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
        .toList();

    setState(() {
      _usersForBranch = users;
      _selectedUser = users.isNotEmpty ? users.first : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(FirebaseAuth.instance.currentUser!.uid).get(),
      builder: (context, snapshot) {
        String role = 'sales';
        if (snapshot.connectionState == ConnectionState.waiting) {
          // Center the loading indicator both vertically and horizontally
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }
        if (snapshot.hasData && snapshot.data!.data() != null) {
          final data = snapshot.data!.data() as Map<String, dynamic>;
          role = data['role'] ?? 'sales';
        }

        return Stack(
          children: [
            Scaffold(
              appBar: AppBar(
                title: const Text('Monthly Missed Report'),
                backgroundColor: const Color(0xFF005BAC),
                foregroundColor: Colors.white,
                elevation: 0,
                actions: [
                  IconButton(
                    icon: const Icon(Icons.download),
                    tooltip: 'Export Excel',
                    onPressed: _isLoading ? null : () async {
                      setState(() => _isLoading = true);
                      await _generateAndShareExcel(role);
                      setState(() => _isLoading = false);
                    },
                  ),
                ],
              ),
              backgroundColor: isDark ? const Color(0xFF181A20) : const Color(0xFFF6F7FB),
              body: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (role == 'admin' && _branches.isNotEmpty)
                            DropdownButton<String>(
                              value: _selectedBranch,
                              items: _branches
                                  .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                                  .toList(),
                              onChanged: (val) async {
                                setState(() {
                                  _selectedBranch = val;
                                });
                                await _fetchUsersForBranch(val);
                              },
                              hint: const Text("Select Branch"),
                            ),
                          DropdownButton<Map<String, dynamic>>(
                            value: _selectedUser,
                            items: _usersForBranch
                                .map((u) => DropdownMenuItem(
                                      value: u,
                                      child: Text(u['username']),
                                    ))
                                .toList(),
                            onChanged: (val) {
                              setState(() {
                                _selectedUser = val;
                              });
                            },
                            hint: const Text("Select User"),
                          ),
                          DropdownButton<int>(
                            value: _selectedMonth,
                            items: List.generate(12, (i) => i + 1)
                                .map((m) => DropdownMenuItem(
                                      value: m,
                                      child: Text(
                                        [
                                          'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                                          'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
                                        ][m - 1],
                                      ),
                                    ))
                                .toList(),
                            onChanged: (val) {
                              setState(() {
                                _selectedMonth = val!;
                              });
                            },
                          ),
                          DropdownButton<int>(
                            value: _selectedYear,
                            items: List.generate(5, (i) => DateTime.now().year - i)
                                .map((y) => DropdownMenuItem(value: y, child: Text('$y')))
                                .toList(),
                            onChanged: (val) {
                              setState(() {
                                _selectedYear = val!;
                              });
                            },
                          ),
                        ],
                      ),
                      if (_selectedUser != null)
                        FutureBuilder<List<Map<String, dynamic>>>(
                          future: _generateUserMonthlyReport(
                            _selectedUser!['uid'],
                            _selectedUser!['email'],
                            _selectedMonth,
                            _selectedYear,
                          ),
                          builder: (context, snap) {
                            if (snap.connectionState == ConnectionState.waiting) {
                              return const Center(child: CircularProgressIndicator());
                            }
                            if (snap.hasError) {
                              return Center(child: Text('Error: ${snap.error}'));
                            }
                            if (!snap.hasData || snap.data!.isEmpty) {
                              return const Center(child: Text('No missed entries this month.'));
                            }
                            final missed = snap.data!;
                            return SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: DataTable(
                                columns: const [
                                  DataColumn(label: Text('Date')),
                                  DataColumn(label: Text('Todo')),
                                  DataColumn(label: Text('Lead')),
                                ],
                                rows: missed.map((m) => DataRow(cells: [
                                  DataCell(Text(m['date'])),
                                  DataCell(
                                    Text(
                                      m['todo'] ? '✓' : '⭕',
                                      style: TextStyle(
                                        color: m['todo'] ? Colors.green : Colors.red,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      m['lead'] ? '✓' : '⭕',
                                      style: TextStyle(
                                        color: m['lead'] ? Colors.green : Colors.red,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                ])).toList(),
                              )
                            );
                            },
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (_isLoading)
              Container(
                color: Colors.black.withOpacity(0.3),
                child: Center(
                  child: SizedBox(
                    width: 260,
                    child: Card(
                      color: Colors.white,
                      elevation: 12,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(28.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              "Generating Excel...",
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                            ),
                            const SizedBox(height: 28),
                            Stack(
                              alignment: Alignment.center,
                              children: [
                                // Glossy background
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    height: 22,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.blue.shade200.withOpacity(0.5),
                                          Colors.blue.shade50.withOpacity(0.2),
                                          Colors.white.withOpacity(0.6),
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                    ),
                                    child: const SizedBox(width: double.infinity, height: 22),
                                  ),
                                ),
                                // Progress bar
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: TweenAnimationBuilder<double>(
                                    tween: Tween<double>(begin: 0, end: _progress),
                                    duration: const Duration(milliseconds: 400),
                                    curve: Curves.easeInOutCubic,
                                    builder: (context, value, child) {
                                      return LinearProgressIndicator(
                                        value: value,
                                        minHeight: 22,
                                        backgroundColor: Colors.transparent,
                                        valueColor: AlwaysStoppedAnimation<Color>(
                                          Colors.blueAccent.shade700,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                // Glossy highlight overlay
                                Positioned.fill(
                                  child: IgnorePointer(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(12),
                                        gradient: LinearGradient(
                                          colors: [
                                            Colors.white.withOpacity(0.25),
                                            Colors.transparent,
                                          ],
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            TweenAnimationBuilder<double>(
                              tween: Tween<double>(begin: 0, end: _progress),
                              duration: const Duration(milliseconds: 400),
                              curve: Curves.easeInOutCubic,
                              builder: (context, value, child) {
                                return Text(
                                  "${(value * 100).toInt()} %",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: Colors.blueAccent,
                                    letterSpacing: 1.2,
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _generateUserMonthlyReport(
    String uid, String email, int month, int year) async {
    final monthStart = DateTime(year, month, 1);
    final nextMonth = month == 12 ? DateTime(year + 1, 1, 1) : DateTime(year, month + 1, 1);
    final today = DateTime.now();
    final lastDay = (nextMonth.isAfter(today) ? today : nextMonth.subtract(const Duration(days: 1))).day;

    List<Map<String, dynamic>> missedReport = [];

    for (int i = 0; i < lastDay; i++) {
      final date = monthStart.add(Duration(days: i));
      final dateStr = "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
      final dayStart = DateTime(date.year, date.month, date.day);
      final dayEnd = dayStart.add(const Duration(days: 1));
      final leadQuery = await FirebaseFirestore.instance
          .collection('daily_report')
          .where('userId', isEqualTo: uid)
          .where('type', isEqualTo: 'leads')
          .where('timestamp', isGreaterThanOrEqualTo: dayStart)
          .where('timestamp', isLessThan: dayEnd)
          .get();
      final leadTick = leadQuery.docs.isNotEmpty;

      final todoWindowStart = dayStart.subtract(const Duration(days: 1)).add(const Duration(hours: 12)); // Previous day 12 PM
      final todoWindowEnd = dayStart.add(const Duration(hours: 12)); // Current day 11:59:59 AM
      final todoQuery = await FirebaseFirestore.instance
          .collection('daily_report')
          .where('userId', isEqualTo: uid)
          .where('type', isEqualTo: 'todo')
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(todoWindowStart))
          .where('timestamp', isLessThan: Timestamp.fromDate(todoWindowEnd))
          .get();
      final todoTick = todoQuery.docs.isNotEmpty;

      missedReport.add({
        'date': dateStr,
        'todo': todoTick,
        'lead': leadTick,
      });
    }
    return missedReport;
  }

  Future<void> _generateAndShareExcel(String role) async {
    try {
      setState(() {
        _isLoading = true;
        _progress = 0.0;
      });

      // Determine branch to use
      String branchToUse = '';
      if (role == 'admin') {
        branchToUse = _selectedBranch ?? '';
      } else if (role == 'manager') {
        branchToUse = _selectedBranch ?? '';
      } else {
        final user = FirebaseAuth.instance.currentUser;
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(user!.uid).get();
        branchToUse = userDoc['branch'] ?? '';
      }

      // Fetch all users of the branch
      final usersSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('branch', isEqualTo: branchToUse)
          .where('role', isNotEqualTo: 'admin')
          .get();

      final users = usersSnapshot.docs
          .map((doc) => {
                'uid': doc.id,
                'username': doc['username'] ?? '',
                'email': doc['email'] ?? '',
              })
          .toList();

      // Table 1: Username, Leads Created, Leads Completed
      final excel = Excel.createExcel();
      final sheet1 = excel['Leads Summary'];
      sheet1.appendRow([
        TextCellValue('Username'),
        TextCellValue('Leads Created'),
        TextCellValue('Leads Completed'),
      ]);

      final monthStart = DateTime(_selectedYear, _selectedMonth, 1);
      final nextMonth = _selectedMonth == 12
          ? DateTime(_selectedYear + 1, 1, 1)
          : DateTime(_selectedYear, _selectedMonth + 1, 1);

      for (int i = 0; i < users.length; i++) {
        final user = users[i];
        // Leads Created
        final createdSnapshot = await FirebaseFirestore.instance
            .collection('follow_ups')
            .where('created_by', isEqualTo: user['uid'])
            .where('created_at', isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
            .where('created_at', isLessThan: Timestamp.fromDate(nextMonth))
            .get();
        final createdCount = createdSnapshot.docs.length;

        // Leads Completed
        final completedSnapshot = await FirebaseFirestore.instance
            .collection('follow_ups')
            .where('created_by', isEqualTo: user['uid'])
            .where('status', isEqualTo: 'Completed')
            .where('created_at', isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
            .where('created_at', isLessThan: Timestamp.fromDate(nextMonth))
            .get();
        final completedCount = completedSnapshot.docs.length;

        sheet1.appendRow([
          TextCellValue(user['username']),
          TextCellValue(createdCount.toString()),
          TextCellValue(completedCount.toString()),
        ]);
        setState(() {
          _progress = (i + 1) / (users.length * 2); // First half for table 1
        });
      }

      // Table 2: Username, Date, Todo, Lead (with space after each user, colored Yes/No)
      final sheet2 = excel['Missed Report'];
      sheet2.appendRow([
        TextCellValue('Username'),
        TextCellValue('Date'),
        TextCellValue('Todo'),
        TextCellValue('Lead'),
      ]);

      for (int i = 0; i < users.length; i++) {
        final user = users[i];
        final missed = await _generateUserMonthlyReport(
          user['uid'],
          user['email'],
          _selectedMonth,
          _selectedYear,
        );
        for (final m in missed) {
          final todoCell = TextCellValue(m['todo'] ? 'Yes' : 'No');
          final leadCell = TextCellValue(m['lead'] ? 'Yes' : 'No');
          final rowIdx = sheet2.maxRows;
          sheet2.appendRow([
            TextCellValue(user['username']),
            TextCellValue(m['date']),
            todoCell,
            leadCell,
          ]);
          // Color the "Yes" as green and "No" as red
          final todoExcelCell = sheet2.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIdx));
          final leadExcelCell = sheet2.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIdx));
          if (m['todo']) {
            todoExcelCell.cellStyle = CellStyle(fontColorHex: ExcelColor.fromHexString('#008000')); // green
          } else {
            todoExcelCell.cellStyle = CellStyle(fontColorHex: ExcelColor.fromHexString('#FF0000')); // red
          }
          if (m['lead']) {
            leadExcelCell.cellStyle = CellStyle(fontColorHex: ExcelColor.fromHexString('#008000')); // green
          } else {
            leadExcelCell.cellStyle = CellStyle(fontColorHex: ExcelColor.fromHexString('#FF0000')); // red
          }
        }
        // Add an empty row after each user for spacing
        sheet2.appendRow([
          TextCellValue(''),
          TextCellValue(''),
          TextCellValue(''),
          TextCellValue(''),
        ]);
        setState(() {
          _progress = 0.5 + ((i + 1) / (users.length * 2)); // Second half for table 2
        });
      }

      // Save and share
      final tempDir = await getTemporaryDirectory();
      final branchName = (branchToUse.isNotEmpty ? branchToUse : "AllBranches").replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final monthName = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ][_selectedMonth - 1];
      final file = File('${tempDir.path}/Monthly Report $branchName $monthName.xlsx');
      final fileBytes = await excel.encode();
      await file.writeAsBytes(fileBytes!);

      await Share.shareXFiles([XFile(file.path)], text: 'Monthly Report Excel');

      setState(() {
        _progress = 1.0;
      });

      // Optionally, wait a moment to show 100%
      await Future.delayed(const Duration(milliseconds: 400));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to generate Excel: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
        _progress = 0.0;
      });
    }
  }
}