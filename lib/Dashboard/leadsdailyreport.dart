import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart' as ex;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:flutter/material.dart';

Future<void> sendDailyLeadsReport(BuildContext context) async {
  try {
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));

    // Set window: from yesterday 12:00 PM to today 12:00 PM
    final start = DateTime(yesterday.year, yesterday.month, yesterday.day, 12); // yesterday 12:00 PM
    final end = DateTime(now.year, now.month, now.day, 12); // today 12:00 PM

    // Fetch users
    final usersSnap = await FirebaseFirestore.instance.collection('users').get();
    final userMap = {for (var doc in usersSnap.docs) doc.id: doc.data()};
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

    // For each user, check leads and todos in the noon-to-noon window
    for (var branch in branchUserStatus.keys) {
      for (var userId in branchUserStatus[branch]!.keys) {
        // Check leads
        final leadSnap = await FirebaseFirestore.instance
            .collection('daily_report')
            .where('userId', isEqualTo: userId)
            .where('type', isEqualTo: 'leads')
            .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
            .where('timestamp', isLessThan: Timestamp.fromDate(end))
            .limit(1)
            .get();
        branchUserStatus[branch]![userId]!['lead'] = leadSnap.docs.isNotEmpty;

        // Check todos
        final todoSnap = await FirebaseFirestore.instance
            .collection('daily_report')
            .where('userId', isEqualTo: userId)
            .where('type', isEqualTo: 'todo')
            .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
            .where('timestamp', isLessThan: Timestamp.fromDate(end))
            .limit(1)
            .get();
        branchUserStatus[branch]![userId]!['todo'] = todoSnap.docs.isNotEmpty;
      }
    }

    // --- Fetch todos created by each user in the noon-to-noon window ---
    final todosByUser = <String, List<Map<String, dynamic>>>{};
    for (var userId in userMap.keys) {
      final userEmail = userMap[userId]?['email'];
      if (userEmail == null) continue;
      final todosSnap = await FirebaseFirestore.instance
          .collection('todo')
          .where('email', isEqualTo: userEmail)
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('timestamp', isLessThan: Timestamp.fromDate(end))
          .get();
      todosByUser[userId] = todosSnap.docs.map((d) => d.data()).toList();
    }

    // Generate Excel
    final excel = ex.Excel.createExcel();
    branchUserStatus.forEach((branch, users) {
      final sheet = excel[branch];
      // Summary table
      sheet.appendRow([
        ex.TextCellValue('Username'),
        ex.TextCellValue('Leads'),
        ex.TextCellValue('Todo'),
      ]);
      users.forEach((userId, status) {
        final user = userMap[userId]!;
        sheet.appendRow([
          ex.TextCellValue(user['username'] ?? ''),
          ex.TextCellValue(status['lead'] == true ? 'Yes' : 'No'),
          ex.TextCellValue(status['todo'] == true ? 'Yes' : 'No'),
        ]);
      });

      // Add a blank row for visual separation
      sheet.appendRow([ex.TextCellValue(''), ex.TextCellValue(''), ex.TextCellValue('')]);

      // Todos Table: Username, Title, Description
      sheet.appendRow([
        ex.TextCellValue('Username'),
        ex.TextCellValue('Title'),
        ex.TextCellValue('Description'),
      ]);
      users.forEach((userId, status) {
        final user = userMap[userId]!;
        final todos = todosByUser[userId] ?? [];
        for (var todo in todos) {
          sheet.appendRow([
            ex.TextCellValue(user['username'] ?? ''),
            ex.TextCellValue(todo['title'] ?? ''),
            ex.TextCellValue(todo['description'] ?? ''),
          ]);
        }
      });
    });

    final dir = await getTemporaryDirectory();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final filePath = '${dir.path}/leads_todos_${now.year}_${now.month}_${now.day}.xlsx';
    final fileBytes = await excel.encode();
    final file = File(filePath)..writeAsBytesSync(fileBytes!);

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
    print('Daily report error: $e\n$stack');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Failed to send daily report: $e')),
    );
  }
}