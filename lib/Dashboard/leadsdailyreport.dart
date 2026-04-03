import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import '../Navigation/user_cache_service.dart';

Future<void> sendDailyLeadsReport(BuildContext context) async {
  try {
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));

    // Set window: from yesterday 12:00 PM to today 12:00 PM
    final start = DateTime(yesterday.year, yesterday.month, yesterday.day, 12); // yesterday 12:00 PM
    final end = DateTime(now.year, now.month, now.day, 12); // today 12:00 PM

    // Fetch users (from cache)
    final cachedUsers = await UserCacheService.instance.getAllUsers();
    final userMap = {for (var u in cachedUsers) u['uid'] as String: u};
    final branchUserStatus = <String, Map<String, Map<String, bool>>>{};

    // Prepare user status per branch
    for (var userId in userMap.keys) {
      final user = userMap[userId]!;
      final branch = user['branch'] ?? 'Unknown';
      branchUserStatus.putIfAbsent(branch, () => {});
      branchUserStatus[branch]![userId] = {
        'lead': false,
        'todo': false,
      };
    }

    // Batch fetch daily_report for all users in the window (instead of N+1 queries)
    final dailyReportSnap = await FirebaseFirestore.instance
        .collection('daily_report')
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('timestamp', isLessThan: Timestamp.fromDate(end))
        .get();

    for (final doc in dailyReportSnap.docs) {
      final data = doc.data();
      final userId = data['userId'] as String?;
      final type = data['type'] as String?;
      if (userId == null || type == null) continue;
      if (!userMap.containsKey(userId)) continue;
      final branch = userMap[userId]?['branch'] ?? 'Unknown';
      if (branchUserStatus.containsKey(branch) &&
          branchUserStatus[branch]!.containsKey(userId)) {
        if (type == 'leads') {
          branchUserStatus[branch]![userId]!['lead'] = true;
        } else if (type == 'todo') {
          branchUserStatus[branch]![userId]!['todo'] = true;
        }
      }
    }

    // Batch fetch todos for all users in the window (instead of N queries)
    final allTodosSnap = await FirebaseFirestore.instance
        .collection('todo')
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('timestamp', isLessThan: Timestamp.fromDate(end))
        .get();

    // Build email→userId lookup
    final emailToUserId = <String, String>{};
    for (var userId in userMap.keys) {
      final email = userMap[userId]?['email'];
      if (email != null) emailToUserId[email] = userId;
    }

    final todosByUser = <String, List<Map<String, dynamic>>>{};
    for (final doc in allTodosSnap.docs) {
      final data = doc.data();
      final email = data['email'] as String?;
      if (email == null) continue;
      final userId = emailToUserId[email];
      if (userId == null) continue;
      todosByUser.putIfAbsent(userId, () => []);
      todosByUser[userId]!.add(data);
    }

    // Generate Excel
    final workbook = xlsio.Workbook();
    bool firstSheet = true;
    branchUserStatus.forEach((branch, users) {
      final sheet = firstSheet
          ? workbook.worksheets[0]
          : workbook.worksheets.addWithName(branch);
      if (firstSheet) {
        sheet.name = branch;
        firstSheet = false;
      }
      int row = 1;

      // Summary table headers
      sheet.getRangeByName('A$row').setText('Username');
      sheet.getRangeByName('B$row').setText('Leads');
      sheet.getRangeByName('C$row').setText('Todo');
      row++;
      users.forEach((userId, status) {
        final user = userMap[userId]!;
        sheet.getRangeByName('A$row').setText(user['username'] ?? '');
        sheet.getRangeByName('B$row').setText(status['lead'] == true ? 'Yes' : 'No');
        sheet.getRangeByName('C$row').setText(status['todo'] == true ? 'Yes' : 'No');
        row++;
      });

      row++; // blank row for visual separation

      // Todos table headers
      sheet.getRangeByName('A$row').setText('Username');
      sheet.getRangeByName('B$row').setText('Title');
      sheet.getRangeByName('C$row').setText('Description');
      row++;
      users.forEach((userId, status) {
        final user = userMap[userId]!;
        final todos = todosByUser[userId] ?? [];
        for (var todo in todos) {
          sheet.getRangeByName('A$row').setText(user['username'] ?? '');
          sheet.getRangeByName('B$row').setText(todo['title'] ?? '');
          sheet.getRangeByName('C$row').setText(todo['description'] ?? '');
          row++;
        }
      });
    });

    final dir = await getTemporaryDirectory();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final filePath = '${dir.path}/leads_todos_${now.year}_${now.month}_${now.day}.xlsx';
    final List<int> fileBytes = workbook.saveAsStream();
    workbook.dispose();
    final file = File(filePath)..writeAsBytesSync(fileBytes);

    final smtpServer = gmail('crmmalabar@gmail.com', 'rhmo laoh qara qrnd');
    final message = Message()
      ..from = Address('crmmalabar@gmail.com', 'MTC Sync')
      ..recipients.addAll(['crmmalabar@gmail.com','performancemtc@gmail.com'])
      ..subject = 'Daily Leads & Todo Report for ${now.day}-${now.month}-${now.year}'
      ..text = 'Please find attached the daily leads and todo report for today.'
      ..attachments = [FileAttachment(file)];

    await send(message, smtpServer);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Daily report sent to crmmalabar@gmail.com')),
    );
  } catch (e, stack) {
    debugPrint('Daily report error: $e\n$stack');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Failed to send daily report: $e')),
    );
  }
}