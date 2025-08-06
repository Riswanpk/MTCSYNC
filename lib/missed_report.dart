import 'package:cloud_firestore/cloud_firestore.dart';

Future<List<Map<String, dynamic>>> getMissedReport(String email, int month, int year) async {
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
    missedReport.add({
      'date': dateStr,
      'todo': data?['todo'] ?? false,
      'lead': data?['lead'] ?? false,
    });
  }
  return missedReport;
}