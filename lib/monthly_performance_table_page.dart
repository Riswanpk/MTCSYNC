import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class MonthlyPerformanceTablePage extends StatefulWidget {
  @override
  State<MonthlyPerformanceTablePage> createState() => _MonthlyPerformanceTablePageState();
}

class _MonthlyPerformanceTablePageState extends State<MonthlyPerformanceTablePage> {
  List<Map<String, dynamic>> dailyForms = [];
  bool isLoading = true;
  List<DateTime> monthDates = [];
  int selectedWeek = 0; // 0 = All, 1 = Week 1, etc.

  @override
  void initState() {
    super.initState();
    fetchMonthlyForms();
  }

  Future<void> fetchMonthlyForms() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final monthEnd = DateTime(now.year, now.month + 1, 1);

    final formsSnapshot = await FirebaseFirestore.instance
        .collection('dailyform')
        .where('userId', isEqualTo: user.uid)
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
        .where('timestamp', isLessThan: Timestamp.fromDate(monthEnd))
        .get();

    dailyForms = formsSnapshot.docs.map((doc) => doc.data() as Map<String, dynamic>).toList();

    // Get all dates in the month
    monthDates = List.generate(
      monthEnd.difference(monthStart).inDays,
      (i) => monthStart.add(Duration(days: i)),
    );

    setState(() {
      isLoading = false;
    });
  }

  // Helper to get form for a specific date
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
    // Week 1: days 1-7, Week 2: 8-14, etc.
    int start = (selectedWeek - 1) * 7;
    int end = start + 7;
    if (start >= monthDates.length) return [];
    if (end > monthDates.length) end = monthDates.length;
    return monthDates.sublist(start, end);
  }

  Widget buildTableSection(String title, List<String> categories, String sectionKey) {
    final filteredDates = getFilteredDates();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 10, // Reduce spacing between columns
            dataRowMinHeight: 28,
            dataRowMaxHeight: 32,
            headingRowHeight: 28,
            horizontalMargin: 6,
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
                      if (cat == 'Punching Time') value = form['attendance'] == 'present';
                      if (cat == 'Late time') value = form['attendance'] == 'late';
                      if (cat == 'Approved Leave') value = form['attendance'] == 'approvedLeave';
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
                      if (cat == 'Meeting') value = form['meeting']?['attended'] == true;
                    }
                    return DataCell(
                      value == null
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

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Calculate number of weeks in the month
    int numWeeks = (monthDates.length / 7).ceil();

    return Scaffold(
      appBar: AppBar(title: const Text('Monthly Performance Table')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Week filter dropdown
            Row(
              children: [
                const Text('Filter by week: ', style: TextStyle(fontWeight: FontWeight.bold)),
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
              ['Punching Time', 'Late time', 'Approved Leave'],
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
          ],
        ),
      ),
    );
  }
}