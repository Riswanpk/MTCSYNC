import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_auth/firebase_auth.dart';

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

  @override
  void initState() {
    super.initState();
    // Filter out admin users from the dropdown
    final nonAdminUsers = widget.users.where((u) => u['role'] != 'admin').toList();
    if (nonAdminUsers.isNotEmpty) {
      _selectedUser = nonAdminUsers.first;
    }
    _showTodoWarningIfNeeded();
  }

  void _showTodoWarningIfNeeded() async {
    final now = DateTime.now();
    if (now.hour < 11) return; // Only show after 11 AM

    final nonAdminUsers = widget.users.where((u) =>
        u['role'] == 'sales' || u['role'] == 'manager').toList();

    final todayStart = DateTime(now.year, now.month, now.day);
    final elevenAM = DateTime(now.year, now.month, now.day, 11, 0, 0);

    // Fetch todos created before 11 AM today
    final todosSnapshot = await FirebaseFirestore.instance
        .collection('todo')
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart))
        .where('timestamp', isLessThan: Timestamp.fromDate(elevenAM))
        .get();

    final Set<String> emailsWithTodo = todosSnapshot.docs
        .map((doc) => (doc.data() as Map<String, dynamic>)['email'] as String?)
        .whereType<String>()
        .toSet();

    final usersMissingTodo = nonAdminUsers
        .where((u) => !emailsWithTodo.contains(u['email']))
        .toList();

    if (usersMissingTodo.isNotEmpty && mounted) {
      final names = usersMissingTodo.map((u) => u['username']).join(', ');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Warning: The following users have not added a todo by 11 AM: $names',
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.orange[800],
            duration: const Duration(seconds: 6),
          ),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final nonAdminUsers = widget.users.where((u) => u['role'] != 'admin').toList();

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
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'download_pdf',
                      child: ListTile(
                        leading: Icon(Icons.picture_as_pdf, color: Colors.red),
                        title: Text('Download PDF'),
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
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: DropdownButton<Map<String, dynamic>>(
                      value: _selectedUser,
                      items: nonAdminUsers
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
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
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
                      const SizedBox(width: 16),
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
                          ),
                        );
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

  Future<List<Map<String, dynamic>>> _generateUserMonthlyReport(String uid, String email, int month, int year) async {
    final monthStart = DateTime(year, month, 1);
    final nextMonth = month == 12 ? DateTime(year + 1, 1, 1) : DateTime(year, month + 1, 1);
    final today = DateTime.now();
    final lastDay = (nextMonth.isAfter(today) ? today : nextMonth.subtract(const Duration(days: 1))).day;

    Map<String, Map<String, bool>> missed = {};

    for (int i = 0; i < lastDay; i++) {
      final date = monthStart.add(Duration(days: i));
      final dateStr = "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
      missed[dateStr] = {'todo': false, 'lead': false};

      final windowStart = date.subtract(const Duration(days: 1)).add(const Duration(hours: 19)); // 7pm previous day
      final windowEnd = DateTime(date.year, date.month, date.day, 12, 0, 0); // 12pm current day

      // Query todos for this user in the window
      final todosSnapshot = await FirebaseFirestore.instance
          .collection('todo')
          .where('email', isEqualTo: email)
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(windowStart))
          .where('timestamp', isLessThan: Timestamp.fromDate(windowEnd))
          .get();

      if (todosSnapshot.docs.isNotEmpty) {
        missed[dateStr]!['todo'] = true;
      }
    }

    final leadsSnapshot = await FirebaseFirestore.instance
        .collection('follow_ups')
        .where('created_by', isEqualTo: uid)
        .where('created_at', isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
        .where('created_at', isLessThan: Timestamp.fromDate(nextMonth))
        .get();

    for (var doc in leadsSnapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final timestamp = (data['created_at'] as Timestamp?)?.toDate();
      if (timestamp != null) {
        final dateStr = "${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')}";
        if (missed[dateStr] != null) {
          missed[dateStr]!['lead'] = true;
        }
      }
    }

    final List<Map<String, dynamic>> missedReport = [];
    missed.forEach((dateStr, entry) {
      missedReport.add({
        'date': dateStr,
        'todo': entry['todo'] ?? false,
        'lead': entry['lead'] ?? false,
      });
    });
    return missedReport;
  }

  Future<void> _downloadMonthlyReportPdf(BuildContext context, String role, String? branch) async {
    try {
      // Request storage permission if needed
      if (Platform.isAndroid) {
        var status = await Permission.manageExternalStorage.request();
        if (!status.isGranted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Storage permission denied')),
          );
          return;
        }
      }

      final pdf = pw.Document();
      // Filter users for admin/manager
      List<Map<String, dynamic>> usersToExport = widget.users.where((u) => u['role'] != 'admin').toList();
      if (role == 'manager') {
        usersToExport = usersToExport.where((u) => u['branch'] == branch).toList();
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

      final bytes = await pdf.save();
      Directory? downloadsDir;
      if (Platform.isAndroid) {
        downloadsDir = Directory('/storage/emulated/0/Download');
      } else {
        downloadsDir = await getApplicationDocumentsDirectory();
      }
      final file = File('${downloadsDir.path}/monthly_report_${DateTime.now().millisecondsSinceEpoch}.pdf');
      await file.writeAsBytes(bytes);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF downloaded to ${file.path}')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to download PDF: $e')),
      );
    }
  }
}

