import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:share_plus/share_plus.dart';

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

  @override
  void initState() {
    super.initState();
    _initDropdowns();
  }

  Future<void> _initDropdowns() async {
    // Get current user role and branch list
    final user = FirebaseAuth.instance.currentUser;
    String? userRole;
    String? userBranch;
    if (user != null) {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      userRole = userDoc['role'];
      userBranch = userDoc['branch'];
      _currentUserRole = userRole;
    }

    // If users and branch are provided (from dashboard/daily), use them
    if (widget.users.isNotEmpty && widget.branch != null) {
      setState(() {
        _selectedBranch = widget.branch;
        _usersForBranch = widget.users;
        _selectedUser = widget.users.isNotEmpty ? widget.users.first : null;
        _branches = [widget.branch!];
      });
      return;
    }

    // Fetch all branches from users collection (for admin)
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

    // For manager, auto-select their branch and users
    if (userRole == 'manager' && userBranch != null) {
      await _fetchUsersForBranch(userBranch);
      setState(() {
        _selectedBranch = userBranch;
      });
    } else {
      // For admin or others, use selected branch
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
        String? branch;
        if (snapshot.hasData && snapshot.data!.data() != null) {
          final data = snapshot.data!.data() as Map<String, dynamic>;
          role = data['role'] ?? 'sales';
          branch = data['branch'];
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Monthly Missed Report'),
            backgroundColor: const Color(0xFF005BAC),
            foregroundColor: Colors.white,
            elevation: 0,
            actions: [
              if (role == 'admin' || role == 'manager')
                PopupMenuButton<String>(
                  icon: const Icon(Icons.menu),
                  onSelected: (value) async {
                    if (value == 'download_pdf') {
                      await _downloadMonthlyReportPdf(context, role, branch);
                    } else if (value == 'leads_report') {
                      await _downloadLeadsSummaryPdf(context, role, branch);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'download_pdf',
                      child: ListTile(
                        leading: Icon(Icons.picture_as_pdf, color: Colors.red),
                        title: Text('Missed Report'),
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'leads_report',
                      child: ListTile(
                        leading: Icon(Icons.assignment, color: Colors.blue),
                        title: Text('Leads Report'),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          backgroundColor: isDark ? const Color(0xFF181A20) : const Color(0xFFF6F7FB),
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                children: [
                  // Only show branch dropdown for admin
                  
                  
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
                      future: _generateUserMonthlyReport(_selectedUser!['uid'], _selectedUser!['email'], _selectedMonth, _selectedYear),
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
                              DataCell(Icon(
                                m['todo'] ? Icons.check_circle : Icons.cancel,
                                color: m['todo'] ? Colors.green : Colors.red,
                              )),
                              DataCell(Icon(
                                m['lead'] ? Icons.check_circle : Icons.cancel,
                                color: m['lead'] ? Colors.green : Colors.red,
                              )),
                            ])).toList(),
                          ));
                        },
                    ),
                ],
              ),
            ),
          ),
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
      final doc = await FirebaseFirestore.instance.collection('daily_report').doc('$email-$dateStr').get();
      final data = doc.data();

      // --- LEAD LOGIC: tick if daily_report exists for this user, type 'leads', timestamp on this date ---
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

      // --- TODO LOGIC: tick if daily_report exists for this user, type 'todo', timestamp between yesterday 7pm and today 12pm ---
      final todoWindowStart = dayStart.subtract(const Duration(days: 1)).add(const Duration(hours: 19)); // yesterday 7pm
      final todoWindowEnd = dayStart.add(const Duration(hours: 12)); // today 12pm
      final todoQuery = await FirebaseFirestore.instance
          .collection('daily_report')
          .where('userId', isEqualTo: uid)
          .where('type', isEqualTo: 'todo')
          .where('timestamp', isGreaterThanOrEqualTo: todoWindowStart)
          .where('timestamp', isLessThanOrEqualTo: todoWindowEnd)
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

  Future<void> _downloadMonthlyReportPdf(BuildContext context, String role, String? branch) async {
    try {
      final pdf = pw.Document();

      // Use branch filtering from monthly.dart UI
      List<Map<String, dynamic>> usersToExport = _usersForBranch;
      if (role == 'admin' && _selectedBranch == null) {
        usersToExport = widget.users.where((u) => u['role'] != 'admin').toList();
      }

      for (final user in usersToExport) {
        final report = await _generateUserMonthlyReport(
          user['uid'],
          user['email'],
          _selectedMonth,
          _selectedYear,
        );
        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            build: (pw.Context context) {
              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Monthly Missed Report', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 8),
                  pw.Text('User: ${user['username']} (${user['email']})', style: pw.TextStyle(fontSize: 16)),
                  pw.SizedBox(height: 12),
                  pw.Table.fromTextArray(
                    headers: ['Date', 'Todo', 'Lead'],
                    data: report.map((m) => [
                      m['date'],
                      m['todo'] ? 'Yes' : 'No',
                      m['lead'] ? 'Yes' : 'No',
                    ]).toList(),
                    cellAlignment: pw.Alignment.center,
                    headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    cellStyle: const pw.TextStyle(fontSize: 12),
                  ),
                ],
              );
            },
          ),
        );
      }

      // Save PDF to a temporary file
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/monthly_report_${DateTime.now().millisecondsSinceEpoch}.pdf');
      await file.writeAsBytes(await pdf.save());

      // Share the PDF file
      await Share.shareXFiles([XFile(file.path)], text: 'Monthly Missed Report');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to share PDF: $e')),
      );
    }
  }

  Future<void> _downloadLeadsSummaryPdf(BuildContext context, String role, String? branch) async {
    try {
      final pdf = pw.Document();

      // Use branch filtering from monthly.dart UI
      List<Map<String, dynamic>> usersToExport = _usersForBranch;
      if (role == 'admin' && _selectedBranch == null) {
        usersToExport = widget.users.where((u) => u['role'] != 'admin').toList();
      }

      List<List<String>> tableData = [];
      for (final user in usersToExport) {
        final uid = user['uid'];
        final username = user['username'] ?? '';
        final userBranch = user['branch'] ?? '';

        final monthStart = DateTime(_selectedYear, _selectedMonth, 1);
        final nextMonth = _selectedMonth == 12
            ? DateTime(_selectedYear + 1, 1, 1)
            : DateTime(_selectedYear, _selectedMonth + 1, 1);

        final createdSnapshot = await FirebaseFirestore.instance
            .collection('follow_ups')
            .where('created_by', isEqualTo: uid)
            .where('created_at', isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
            .where('created_at', isLessThan: Timestamp.fromDate(nextMonth))
            .get();
        final createdCount = createdSnapshot.docs.length;

        final completedSnapshot = await FirebaseFirestore.instance
            .collection('follow_ups')
            .where('created_by', isEqualTo: uid)
            .where('status', isEqualTo: 'Completed')
            .where('created_at', isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
            .where('created_at', isLessThan: Timestamp.fromDate(nextMonth))
            .get();
        final completedCount = completedSnapshot.docs.length;

        tableData.add([
          username,
          createdCount.toString(),
          completedCount.toString(),
          userBranch,
        ]);
      }

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Leads Report', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 8),
                pw.Text(
                  'Month: ${_selectedMonth.toString().padLeft(2, '0')}-${_selectedYear}',
                  style: pw.TextStyle(fontSize: 16),
                ),
                pw.SizedBox(height: 12),
                pw.Table.fromTextArray(
                  headers: ['Username', 'Created', 'Completed', 'Branch'],
                  data: tableData,
                  cellAlignment: pw.Alignment.center,
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  cellStyle: const pw.TextStyle(fontSize: 12),
                ),
              ],
            );
          },
        ),
      );

      // Save PDF to a temporary file
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/leads_report_${DateTime.now().millisecondsSinceEpoch}.pdf');
      await file.writeAsBytes(await pdf.save());

      // Share the PDF file
      await Share.shareXFiles([XFile(file.path)], text: 'Leads Report');

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to generate leads report: $e')),
      );
    }
  }
}

