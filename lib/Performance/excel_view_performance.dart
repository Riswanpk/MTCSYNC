import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../Misc/theme_notifier.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'monthly_performance_table_page.dart';

class ExcelViewPerformancePage extends StatefulWidget {
  @override
  State<ExcelViewPerformancePage> createState() => _ExcelViewPerformancePageState();
}

class _ExcelViewPerformancePageState extends State<ExcelViewPerformancePage> {
  String? selectedBranch;
  String? selectedUserId;
  Map<String, String> userIdToName = {};
  List<String> branches = [];
  List<String> usersInBranch = [];
  bool isLoadingBranches = true;
  bool isLoadingUsers = false;

  @override
  void initState() {
    super.initState();
    fetchBranches();
  }

  Future<void> fetchBranches() async {
    setState(() { isLoadingBranches = true; });
    final snap = await FirebaseFirestore.instance.collection('users').get();
    final branchSet = <String>{};
    for (var doc in snap.docs) {
      final branch = doc.data()['branch'];
      if (branch != null) branchSet.add(branch);
    }
    setState(() {
      branches = branchSet.toList()..sort();
      isLoadingBranches = false;
    });
  }

  Future<void> fetchUsersForBranch(String branch) async {
    setState(() { isLoadingUsers = true; });
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .where('branch', isEqualTo: branch)
        .get();
    userIdToName.clear();
    usersInBranch = [];
    for (var doc in snap.docs) {
      userIdToName[doc.id] = doc.data()['username'] ?? doc.data()['email'] ?? doc.id;
      usersInBranch.add(doc.id);
    }
    setState(() {
      isLoadingUsers = false;
      selectedUserId = usersInBranch.isNotEmpty ? usersInBranch.first : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Monthly Report'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Branch Dropdown
            isLoadingBranches
                ? const Center(child: CircularProgressIndicator())
                : DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'Select Branch'),
                    value: selectedBranch,
                    items: branches
                        .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                        .toList(),
                    onChanged: (val) {
                      setState(() {
                        selectedBranch = val;
                        selectedUserId = null;
                        usersInBranch = [];
                      });
                      if (val != null) fetchUsersForBranch(val);
                    },
                  ),
            const SizedBox(height: 16),
            // User Dropdown
            if (selectedBranch != null)
              isLoadingUsers
                  ? const Center(child: CircularProgressIndicator())
                  : DropdownButtonFormField<String>(
                      decoration: const InputDecoration(labelText: 'Select User'),
                      value: selectedUserId,
                      items: usersInBranch
                          .map((uid) => DropdownMenuItem(
                                value: uid,
                                child: Text(userIdToName[uid] ?? uid),
                              ))
                          .toList(),
                      onChanged: (val) {
                        setState(() {
                          selectedUserId = val;
                        });
                      },
                    ),
            const SizedBox(height: 24),
            // Show performance table for selected user
            if (selectedBranch != null && selectedUserId != null)
              Expanded(
                // Use a UniqueKey based on selectedUserId to force rebuild/fetch
                child: _PerformanceTableView(
                  key: ValueKey(selectedUserId),
                  userId: selectedUserId!,
                ),
              ),
          ],
        ),
      ),
      backgroundColor: isDark ? const Color(0xFF181A20) : Colors.white,
    );
  }
}

// Widget to show performance table for selected user
class _PerformanceTableView extends StatefulWidget {
  final String userId;
  const _PerformanceTableView({Key? key, required this.userId}) : super(key: key);

  @override
  State<_PerformanceTableView> createState() => _PerformanceTableViewState();
}

class _PerformanceTableViewState extends State<_PerformanceTableView> {
  List<Map<String, dynamic>> dailyForms = [];
  bool isLoading = true;
  List<DateTime> monthDates = [];
  int selectedWeek = 0;
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    fetchMonthlyForms();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> fetchMonthlyForms() async {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final monthEnd = DateTime(now.year, now.month + 1, 1);

    final formsSnapshot = await FirebaseFirestore.instance
        .collection('dailyform')
        .where('userId', isEqualTo: widget.userId)
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
        .where('timestamp', isLessThan: Timestamp.fromDate(monthEnd))
        .get();

    dailyForms = formsSnapshot.docs.map((doc) => doc.data() as Map<String, dynamic>).toList();
    monthDates = List.generate(
      monthEnd.difference(monthStart).inDays,
      (i) => monthStart.add(Duration(days: i)),
    );
    setState(() { isLoading = false; });
  }

  Map<String, dynamic>? getFormForDate(DateTime date) {
    return dailyForms.firstWhere(
      (form) {
        final ts = form['timestamp'];
        final formDate = ts is Timestamp ? ts.toDate() : DateTime.parse(ts.toString());
        return formDate.year == date.year && formDate.month == date.month && formDate.day == date.day;
      },
      orElse: () => {},
    );
  }

  List<DateTime> getFilteredDates() {
    if (selectedWeek == 0) return monthDates;
    int start = (selectedWeek - 1) * 7;
    int end = start + 7;
    if (start >= monthDates.length) return [];
    if (end > monthDates.length) end = monthDates.length;
    return monthDates.sublist(start, end);
  }

  Widget buildTableSection(String title, List<String> categories, String sectionKey) {
    final filteredDates = getFilteredDates();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isDark ? Colors.white : Colors.black)),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          controller: _scrollController,
          child: DataTable(
            columnSpacing: 10,
            dataRowMinHeight: 28,
            dataRowMaxHeight: 32,
            headingRowHeight: 28,
            horizontalMargin: 6,
            headingRowColor: MaterialStateProperty.resolveWith<Color?>(
              (states) => isDark ? Colors.grey[900] : Colors.grey[200],
            ),
            columns: [
              const DataColumn(
                label: Text('Category', style: TextStyle(fontSize: 11)),
              ),
              ...filteredDates.map((d) => DataColumn(
                label: Text(
                  '${d.day}-${d.month < 10 ? '0' : ''}${d.month}',
                  style: const TextStyle(fontSize: 11),
                ),
              )),
            ],
            rows: categories.map((cat) {
              return DataRow(
                cells: [
                  DataCell(Text(cat, style: const TextStyle(fontSize: 11))),
                  ...filteredDates.map((date) {
                    final form = getFormForDate(date);
                    bool? value;
                    if (form == null || form.isEmpty) return const DataCell(Text('-', style: TextStyle(fontSize: 11)));
                    if (sectionKey == 'attendance') {
                      String att = form['attendance'] ?? '';
                      if (cat == 'Punching Time') {
                        value = att == 'punching' ? true : null;
                      } else if (cat == 'Late time') {
                        value = att == 'late' ? true : null;
                      } else if (cat == 'Approved Leave') {
                        value = att == 'approved' ? true : null;
                      } else if (cat == 'Unapproved Leave') {
                        value = att == 'notApproved' ? true : null;
                      }
                    } else if (sectionKey == 'dressCode') {
                      if (cat == 'Wear clean uniform') value = form['dressCode']?['cleanUniform'] != false;
                      if (cat == 'Keep inside') value = form['dressCode']?['keepInside'] != false;
                      if (cat == 'Keep your hair neat') value = form['dressCode']?['neatHair'] != false;
                    } else if (sectionKey == 'attitude') {
                      if (cat == 'Greet with a warm smile') value = form['attitude']?['greetSmile'] != false;
                      if (cat == 'Ask about their needs') value = form['attitude']?['askNeeds'] != false;
                      if (cat == 'Help find the right product') value = form['attitude']?['helpFindProduct'] != false;
                      if (cat == 'Confirm the purchase') value = form['attitude']?['confirmPurchase'] != false;
                      if (cat == 'Offer carry or delivery help') value = form['attitude']?['offerHelp'] != false;
                    } else if (sectionKey == 'meeting') {
                      if (cat == 'Meeting') {
                        if (form['meeting']?['noMeeting'] == true) {
                          // Show a special icon for "No meeting conducted"
                          value = null;
                        } else {
                          value = form['meeting']?['attended'] == true;
                        }
                      }
                    }
                    return DataCell(
                      sectionKey == 'meeting' && form['meeting']?['noMeeting'] == true
                          ? Row(
                              children: const [
                                Icon(Icons.info_outline, color: Colors.blue, size: 16),
                                SizedBox(width: 2),
                                Text('No meeting', style: TextStyle(fontSize: 10, color: Colors.blue)),
                              ],
                            )
                          : value == null
                              ? const Text('-', style: TextStyle(fontSize: 11))
                              : value
                                  ? const Icon(Icons.check, color: Colors.green, size: 16)
                                  : const Icon(Icons.close, color: Colors.red, size: 16),
                    );
                  }).toList(),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget buildNewQuestionTableSection(String title, String fieldKey, {bool isBool = false, String? trueText, String? falseText}) {
    final filteredDates = getFilteredDates();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isDark ? Colors.white : Colors.black)),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          controller: _scrollController,
          child: DataTable(
            columnSpacing: 10,
            dataRowMinHeight: 28,
            dataRowMaxHeight: 32,
            headingRowHeight: 28,
            horizontalMargin: 6,
            headingRowColor: MaterialStateProperty.resolveWith<Color?>(
              (states) => isDark ? Colors.grey[900] : Colors.grey[200],
            ),
            columns: [
              const DataColumn(
                label: Text('Category', style: TextStyle(fontSize: 11)),
              ),
              ...filteredDates.map((d) => DataColumn(
                label: Text(
                  '${d.day}-${d.month < 10 ? '0' : ''}${d.month}',
                  style: const TextStyle(fontSize: 11),
                ),
              )),
            ],
            rows: [
              DataRow(
                cells: [
                  DataCell(Text(title, style: const TextStyle(fontSize: 11))),
                  ...filteredDates.map((date) {
                    final form = getFormForDate(date);
                    if (form == null || form.isEmpty) {
                      return const DataCell(Text('-', style: TextStyle(fontSize: 11)));
                    }
                    final value = form[fieldKey];
                    if (isBool) {
                      if (value == true) {
                        return const DataCell(Icon(Icons.check, color: Colors.green, size: 16));
                      } else if (value == false) {
                        return const DataCell(Icon(Icons.close, color: Colors.red, size: 16));
                      } else {
                        return const DataCell(Text('-', style: TextStyle(fontSize: 11)));
                      }
                    } else {
                      String display = (value ?? '').toString();
                      if (display.isEmpty || display == 'null') display = '-';
                      return DataCell(Text(display, style: const TextStyle(fontSize: 11)));
                    }
                  }).toList(),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    int numWeeks = (monthDates.length / 7).ceil();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Week filter dropdown
          Row(
            children: [
              Text('Filter by week: ', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
              DropdownButton<int>(
                value: selectedWeek,
                items: [
                  const DropdownMenuItem(value: 0, child: Text('All')),
                  ...List.generate(numWeeks, (i) => DropdownMenuItem(
                    value: i + 1,
                    child: Text('Week ${i + 1}'),
                  )),
                ],
                onChanged: (val) {
                  setState(() {
                    selectedWeek = val ?? 0;
                  });
                },
              ),
            ],
          ),
          buildTableSection(
            'ATTENDANCE (OUT OF 20)',
            ['Punching Time', 'Late time', 'Approved Leave', 'Unapproved Leave'],
            'attendance',
          ),
          buildTableSection(
            'DRESS CODE (OUT OF 20)',
            ['Wear clean uniform', 'Keep inside', 'Keep your hair neat'],
            'dressCode',
          ),
          buildTableSection(
            'ATTITUDE (OUT OF 20)',
            [
              'Greet with a warm smile',
              'Ask about their needs',
              'Help find the right product',
              'Confirm the purchase',
              'Offer carry or delivery help'
            ],
            'attitude',
          ),
          buildTableSection(
            'MEETING (OUT OF 10)',
            ['Meeting'],
            'meeting',
          ),
              // New questions
              buildNewQuestionTableSection('Time Taken for Other Tasks (min)', 'timeTakenOtherTasks'),
              buildNewQuestionTableSection('Old Stock Offer Given?', 'oldStockOfferGiven', isBool: true, trueText: 'Yes', falseText: 'No'),
              buildNewQuestionTableSection('Cross-selling & Upselling?', 'crossSellingUpselling', isBool: true, trueText: 'Yes', falseText: 'No'),
              buildNewQuestionTableSection('Product Complaints?', 'productComplaints', isBool: true, trueText: 'Yes', falseText: 'No'),
              buildNewQuestionTableSection('Achieved Daily Target?', 'achievedDailyTarget', isBool: true, trueText: 'Yes', falseText: 'No'),
        ],
      ),
    );
  }
}
