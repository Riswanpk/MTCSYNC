import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

/// Roles considered for the monthly report (non-admin).
const List<String> _targetRoles = ['sales', 'manager', 'asst_manager'];

/// Generates an Excel monthly performance report for a given [year] and [month].
///
/// If [isSummary] is false (Detailed mode):
///  A. Users who created NO supersale orders for campaigns whose deliveryEnd
///     falls within the selected month (per campaign breakdown).
///  B. Orders (pending) whose delivery deadline falls within the month but
///     have NOT been delivered.
///
/// If [isSummary] is true (Summary mode):
///  A. Per user: Username, Role, Total Campaigns applicable, Completed Campaigns count.
///  B. Per user: Username, Role, Overdue Orders count.
Future<void> generateMonthlyReport({
  required int year,
  required int month,
  bool isSummary = false,
}) async {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  // Month boundaries
  final DateTime monthStart = DateTime(year, month, 1);
  final DateTime monthEnd = DateTime(year, month + 1, 0, 23, 59, 59);

  // 1. Load all non-admin users
  final usersSnap = await firestore.collection('users').get();

  final Map<String, Map<String, dynamic>> allUsersById = {};
  final Map<String, List<Map<String, dynamic>>> usersByBranch = {};

  for (final doc in usersSnap.docs) {
    final data = doc.data();
    final String role = (data['role'] ?? '').toString().toLowerCase().trim();
    if (!_targetRoles.contains(role)) continue;

    final String branch = (data['branch'] ?? '').toString().trim();
    if (branch.isEmpty || branch.toLowerCase() == 'admin') continue;

    final userInfo = {
      'uid': doc.id,
      'username': data['username'] ?? data['email'] ?? 'Unknown',
      'email': data['email'] ?? '',
      'role': role,
      'branch': branch,
    };
    allUsersById[doc.id] = userInfo;
    usersByBranch.putIfAbsent(branch, () => []).add(userInfo);
  }

  // 2. Load supersale campaigns whose deliveryEnd falls in the month
  final supersalesSnap = await firestore.collection('supersales').get();

  final List<Map<String, dynamic>> relevantCampaigns = [];
  for (final doc in supersalesSnap.docs) {
    final data = doc.data();
    final dynamic dEnd = data['deliveryEnd'];
    if (dEnd == null) continue;
    final DateTime deliveryEnd = dEnd is Timestamp
        ? dEnd.toDate()
        : DateTime.tryParse(dEnd.toString()) ?? DateTime(2000);

    if (!deliveryEnd.isBefore(monthStart) && !deliveryEnd.isAfter(monthEnd)) {
      final List<dynamic> rawBranches = data['branches'] ?? [];
      relevantCampaigns.add({
        'id': doc.id,
        'item': data['item'] as String? ?? 'Unnamed',
        'branches': rawBranches,
        'deliveryEnd': deliveryEnd,
      });
    }
  }

  // 3. Fetch entries for each campaign per branch
  final List<String> fallbackBranches = [
    'BGR', 'CBE', 'CHN', 'CLT', 'EKM', 'JBL', 'KKM', 'KSD',
    'KTM', 'PKD', 'PKT', 'PMN', 'TRR', 'TSR', 'TLY', 'TVM',
    'UDP', 'VDK', 'WND', 'PKTR', 'PLA', 'PMNA',
  ];

  // campaignId -> branch -> list of entry maps
  final Map<String, Map<String, List<Map<String, dynamic>>>> campaignEntries = {};

  for (final campaign in relevantCampaigns) {
    final String campaignId = campaign['id'];
    final String itemName = campaign['item'];
    final List<dynamic> campaignBranches = campaign['branches'];

    List<String> targetBranches;
    if (campaignBranches.isEmpty || campaignBranches.contains('all')) {
      targetBranches = fallbackBranches;
    } else {
      targetBranches = campaignBranches.map((b) => b.toString()).toList();
    }

    campaignEntries[campaignId] = {};

    await Future.wait(targetBranches.map((branch) async {
      final snap = await firestore
          .collection('supersale_user_entries')
          .doc(branch)
          .collection(itemName)
          .where('adminPostingId', isEqualTo: campaignId)
          .get();
      campaignEntries[campaignId]![branch] =
          snap.docs.map((d) => {'docId': d.id, ...d.data()}).toList();
    }));
  }

  // 4. Build Excel
  final xlsio.Workbook workbook = xlsio.Workbook();
  bool isFirstSheet = true;

  final String monthLabel = DateFormat('MMMM yyyy').format(DateTime(year, month));
  final DateFormat dateFmt = DateFormat('dd/MM/yyyy');
  const List<String> roleOrder = ['manager', 'asst_manager', 'sales'];

  void styleHeader(xlsio.Worksheet sheet, int row, List<String> headers, String backColor) {
    for (int c = 0; c < headers.length; c++) {
      final cell = sheet.getRangeByIndex(row, c + 1);
      cell.setText(headers[c]);
      cell.cellStyle.bold = true;
      cell.cellStyle.backColor = backColor;
      cell.cellStyle.hAlign = xlsio.HAlignType.center;
      cell.cellStyle.wrapText = true;
    }
  }

  void writeSectionTitle(xlsio.Worksheet sheet, int row, String title, int colSpan, String fontColor) {
    final cell = sheet.getRangeByIndex(row, 1);
    cell.setText(title);
    cell.cellStyle.bold = true;
    cell.cellStyle.fontSize = 12;
    cell.cellStyle.fontColor = fontColor;
    if (colSpan > 1) {
      sheet.getRangeByIndex(row, 1, row, colSpan).merge();
    }
  }

  final List<String> allBranches = usersByBranch.keys.toList()..sort();

  for (final branch in allBranches) {
    final List<Map<String, dynamic>> branchUsers = usersByBranch[branch] ?? [];
    if (branchUsers.isEmpty) continue;

    final Map<String, Map<String, dynamic>> branchUsersById = {
      for (final u in branchUsers) u['uid'] as String: u,
    };

    if (isSummary) {
      // ================= SUMMARY REPORT MODE =================

      // Section A: For each user in branch, count applicable campaigns and completed campaigns
      // A user "completed" a campaign if they have at least one delivered order in it.
      // Total = count of relevant campaigns that apply to this branch.
      final List<Map<String, dynamic>> branchCampaigns = relevantCampaigns.where((campaign) {
        final List<dynamic> cb = campaign['branches'] ?? [];
        return cb.isEmpty || cb.contains('all') || cb.contains(branch);
      }).toList();

      final int totalCampaignsCount = branchCampaigns.length;

      final List<Map<String, dynamic>> userCampaignSummary = [];

      for (final user in branchUsers) {
        final String uid = user['uid'] as String;
        int completedCount = 0;

        for (final campaign in branchCampaigns) {
          final String campaignId = campaign['id'] as String;
          final List<Map<String, dynamic>> entries = campaignEntries[campaignId]?[branch] ?? [];

          final bool hasCompleted = entries.any((entry) {
            final String entryUid = (entry['userId'] ?? '').toString();
            final String status = (entry['status'] ?? '').toString().toLowerCase();
            return entryUid == uid && status == 'delivered';
          });

          if (hasCompleted) {
            completedCount++;
          }
        }

        userCampaignSummary.add({
          'username': user['username'] as String,
          'role': user['role'] as String,
          'total': totalCampaignsCount,
          'completed': completedCount,
        });
      }

      // Section B: For each user, count overdue orders in this branch
      final Map<String, int> overdueCountByUser = {};
      for (final campaign in branchCampaigns) {
        final String campaignId = campaign['id'] as String;
        final List<Map<String, dynamic>> entries = campaignEntries[campaignId]?[branch] ?? [];

        for (final entry in entries) {
          final String status = (entry['status'] ?? '').toString().toLowerCase();
          if (status == 'delivered' || status == 'cancelled') continue;

          DateTime? deadline;
          final dynamic drRaw = entry['deliveryReminder'];
          final dynamic deRaw = entry['deliveryEnd'];

          if (drRaw is Timestamp) {
            deadline = drRaw.toDate();
          } else if (deRaw is Timestamp) {
            deadline = deRaw.toDate();
          } else if (deRaw is String) {
            deadline = DateTime.tryParse(deRaw);
          }

          if (deadline == null) continue;
          if (deadline.isAfter(monthEnd)) continue;

          final String uid = (entry['userId'] ?? '').toString();
          if (uid.isNotEmpty) {
            overdueCountByUser[uid] = (overdueCountByUser[uid] ?? 0) + 1;
          }
        }
      }

      final List<Map<String, dynamic>> userOverdueSummary = [];
      for (final user in branchUsers) {
        final String uid = user['uid'] as String;
        final int count = overdueCountByUser[uid] ?? 0;
        if (count > 0) {
          userOverdueSummary.add({
            'username': user['username'] as String,
            'role': user['role'] as String,
            'overdueCount': count,
          });
        }
      }

      // Check if there is anything to show
      if (branchCampaigns.isEmpty && userOverdueSummary.isEmpty) continue;

      xlsio.Worksheet sheet;
      if (isFirstSheet) {
        sheet = workbook.worksheets[0];
        sheet.name = branch;
        isFirstSheet = false;
      } else {
        sheet = workbook.worksheets.addWithName(branch);
      }

      int row = 1;
      final titleCell = sheet.getRangeByIndex(row, 1);
      titleCell.setText('MONTHLY PERFORMANCE SUMMARY — $branch — $monthLabel');
      titleCell.cellStyle.bold = true;
      titleCell.cellStyle.fontSize = 14;
      sheet.getRangeByIndex(row, 1, row, 6).merge();
      row += 2;

      // --- SECTION A: Campaign Completion Summary ---
      writeSectionTitle(
        sheet,
        row,
        'SECTION A — Campaign Completion Summary (Delivery ending in $monthLabel)',
        6,
        '#005BAC',
      );
      row++;

      styleHeader(
        sheet,
        row,
        ['Sl.No', 'Username', 'Role', 'Total Campaigns', 'Completed', 'Completion %'],
        '#D9E1F2',
      );
      row++;

      // Sort by role then username
      userCampaignSummary.sort((a, b) {
        final ra = roleOrder.indexOf(a['role'] as String);
        final rb = roleOrder.indexOf(b['role'] as String);
        final roleComp = (ra == -1 ? 99 : ra).compareTo(rb == -1 ? 99 : rb);
        if (roleComp != 0) return roleComp;
        return (a['username'] as String).compareTo(b['username'] as String);
      });

      int slA = 1;
      for (final rec in userCampaignSummary) {
        final int total = rec['total'] as int;
        final int completed = rec['completed'] as int;
        final double pct = total > 0 ? (completed / total) * 100 : 0.0;

        sheet.getRangeByIndex(row, 1).setNumber(slA.toDouble());
        sheet.getRangeByIndex(row, 2).setText(rec['username'] as String);
        sheet.getRangeByIndex(row, 3).setText(_formatRole(rec['role'] as String));
        sheet.getRangeByIndex(row, 4).setNumber(total.toDouble());
        sheet.getRangeByIndex(row, 5).setNumber(completed.toDouble());
        sheet.getRangeByIndex(row, 6).setText('${pct.toStringAsFixed(0)}%');

        final String r = rec['role'] as String;
        String rowColor = '';
        if (r == 'manager') rowColor = '#FFF2CC';
        if (r == 'asst_manager') rowColor = '#EAF1FB';
        if (rowColor.isNotEmpty) {
          for (int c = 1; c <= 6; c++) {
            sheet.getRangeByIndex(row, c).cellStyle.backColor = rowColor;
          }
        }
        slA++;
        row++;
      }

      row += 2;

      // --- SECTION B: Overdue Orders Summary ---
      writeSectionTitle(
        sheet,
        row,
        'SECTION B — Overdue Orders Count (as of $monthLabel)',
        6,
        '#7030A0',
      );
      row++;

      if (userOverdueSummary.isEmpty) {
        sheet.getRangeByIndex(row, 1).setText('No overdue orders for this branch in $monthLabel.');
        sheet.getRangeByIndex(row, 1, row, 6).merge();
        sheet.getRangeByIndex(row, 1).cellStyle.fontColor = '#375623';
        row++;
      } else {
        styleHeader(
          sheet,
          row,
          ['Sl.No', 'Username', 'Role', 'No. of Overdue Orders'],
          '#FCE4D6',
        );
        row++;

        // Sort descending by overdue count, then username
        userOverdueSummary.sort((a, b) {
          final countComp = (b['overdueCount'] as int).compareTo(a['overdueCount'] as int);
          if (countComp != 0) return countComp;
          return (a['username'] as String).compareTo(b['username'] as String);
        });

        int slB = 1;
        for (final rec in userOverdueSummary) {
          final int count = rec['overdueCount'] as int;
          sheet.getRangeByIndex(row, 1).setNumber(slB.toDouble());
          sheet.getRangeByIndex(row, 2).setText(rec['username'] as String);
          sheet.getRangeByIndex(row, 3).setText(_formatRole(rec['role'] as String));
          sheet.getRangeByIndex(row, 4).setNumber(count.toDouble());

          final String rowColor = count >= 5 ? '#FFCCCC' : (count >= 2 ? '#FFE5CC' : '#FFFACD');
          for (int c = 1; c <= 4; c++) {
            sheet.getRangeByIndex(row, c).cellStyle.backColor = rowColor;
          }
          slB++;
          row++;
        }
      }

      for (int c = 1; c <= 6; c++) {
        sheet.autoFitColumn(c);
      }
    } else {
      // ================= DETAILED REPORT MODE (Original) =================

      // --- Section A: Non-participants ---
      final List<Map<String, dynamic>> nonParticipants = [];

      for (final campaign in relevantCampaigns) {
        final String campaignId = campaign['id'];
        final String itemName = campaign['item'];
        final List<dynamic> campaignBranches = campaign['branches'];
        final DateTime deliveryEnd = campaign['deliveryEnd'] as DateTime;

        final bool appliesToBranch = campaignBranches.isEmpty ||
            campaignBranches.contains('all') ||
            campaignBranches.contains(branch);
        if (!appliesToBranch) continue;

        final List<Map<String, dynamic>> entries =
            campaignEntries[campaignId]?[branch] ?? [];

        final Set<String> participatingUids = {};
        for (final entry in entries) {
          final String status = (entry['status'] ?? '').toString().toLowerCase();
          if (status != 'cancelled') {
            final String uid = (entry['userId'] ?? '').toString();
            if (uid.isNotEmpty) participatingUids.add(uid);
          }
        }

        for (final user in branchUsers) {
          final String uid = user['uid'] as String;
          if (!participatingUids.contains(uid)) {
            nonParticipants.add({
              'username': user['username'],
              'role': user['role'],
              'campaign': itemName,
              'deliveryEnd': dateFmt.format(deliveryEnd),
            });
          }
        }
      }

      // --- Section B: Overdue orders ---
      final List<Map<String, dynamic>> overdueOrders = [];

      for (final campaign in relevantCampaigns) {
        final String campaignId = campaign['id'];
        final String itemName = campaign['item'];
        final List<dynamic> campaignBranches = campaign['branches'];

        final bool appliesToBranch = campaignBranches.isEmpty ||
            campaignBranches.contains('all') ||
            campaignBranches.contains(branch);
        if (!appliesToBranch) continue;

        final List<Map<String, dynamic>> entries =
            campaignEntries[campaignId]?[branch] ?? [];

        for (final entry in entries) {
          final String status = (entry['status'] ?? '').toString().toLowerCase();
          if (status == 'delivered' || status == 'cancelled') continue;

          DateTime? deadline;
          final dynamic drRaw = entry['deliveryReminder'];
          final dynamic deRaw = entry['deliveryEnd'];

          if (drRaw is Timestamp) {
            deadline = drRaw.toDate();
          } else if (deRaw is Timestamp) {
            deadline = deRaw.toDate();
          } else if (deRaw is String) {
            deadline = DateTime.tryParse(deRaw);
          }

          if (deadline == null) continue;
          if (deadline.isAfter(monthEnd)) continue;

          final String uid = (entry['userId'] ?? '').toString();
          final Map<String, dynamic>? userInfo =
              branchUsersById[uid] ?? allUsersById[uid];

          final String username =
              userInfo?['username'] ?? entry['username']?.toString() ?? 'Unknown';
          final String role =
              userInfo?['role'] ?? entry['role']?.toString() ?? '-';

          final String customerName = entry['customerName']?.toString() ?? '-';
          final dynamic createdRaw = entry['created_at'];
          final String bookedDate = createdRaw is Timestamp
              ? dateFmt.format(createdRaw.toDate())
              : '-';

          overdueOrders.add({
            'username': username,
            'role': role,
            'campaign': itemName,
            'customerName': customerName,
            'bookedDate': bookedDate,
            'deadline': dateFmt.format(deadline),
            'daysOverdue': DateTime.now().difference(deadline).inDays,
          });
        }
      }

      if (nonParticipants.isEmpty && overdueOrders.isEmpty) continue;

      xlsio.Worksheet sheet;
      if (isFirstSheet) {
        sheet = workbook.worksheets[0];
        sheet.name = branch;
        isFirstSheet = false;
      } else {
        sheet = workbook.worksheets.addWithName(branch);
      }

      int row = 1;

      final titleCell = sheet.getRangeByIndex(row, 1);
      titleCell.setText('MONTHLY PERFORMANCE REPORT (DETAILED) — $branch — $monthLabel');
      titleCell.cellStyle.bold = true;
      titleCell.cellStyle.fontSize = 14;
      sheet.getRangeByIndex(row, 1, row, 8).merge();
      row += 2;

      // SECTION A
      writeSectionTitle(sheet, row, 'SECTION A — Users With NO Supersale Orders (Delivery ending in $monthLabel)', 8, '#C00000');
      row++;

      if (nonParticipants.isEmpty) {
        sheet.getRangeByIndex(row, 1).setText('All eligible users participated in all campaigns this month.');
        sheet.getRangeByIndex(row, 1, row, 8).merge();
        sheet.getRangeByIndex(row, 1).cellStyle.fontColor = '#375623';
        row++;
      } else {
        styleHeader(sheet, row, ['Sl.No', 'Username', 'Role', 'Campaign / Item', 'Delivery End Date'], '#FCE4D6');
        row++;

        nonParticipants.sort((a, b) {
          final ra = roleOrder.indexOf(a['role'] as String);
          final rb = roleOrder.indexOf(b['role'] as String);
          final roleComp = (ra == -1 ? 99 : ra).compareTo(rb == -1 ? 99 : rb);
          if (roleComp != 0) return roleComp;
          return (a['username'] as String).compareTo(b['username'] as String);
        });

        int sl = 1;
        for (final rec in nonParticipants) {
          sheet.getRangeByIndex(row, 1).setNumber(sl.toDouble());
          sheet.getRangeByIndex(row, 2).setText(rec['username'] as String);
          sheet.getRangeByIndex(row, 3).setText(_formatRole(rec['role'] as String));
          sheet.getRangeByIndex(row, 4).setText(rec['campaign'] as String);
          sheet.getRangeByIndex(row, 5).setText(rec['deliveryEnd'] as String);

          final String r = rec['role'] as String;
          String rowColor = '';
          if (r == 'manager') rowColor = '#FFF2CC';
          if (r == 'asst_manager') rowColor = '#EAF1FB';
          if (rowColor.isNotEmpty) {
            for (int c = 1; c <= 5; c++) {
              sheet.getRangeByIndex(row, c).cellStyle.backColor = rowColor;
            }
          }
          sl++;
          row++;
        }
      }

      row += 2;

      // SECTION B
      writeSectionTitle(sheet, row, 'SECTION B — Orders Not Completed Within Delivery Date (as of $monthLabel)', 8, '#7030A0');
      row++;

      if (overdueOrders.isEmpty) {
        sheet.getRangeByIndex(row, 1).setText('No overdue orders for this branch in $monthLabel.');
        sheet.getRangeByIndex(row, 1, row, 8).merge();
        sheet.getRangeByIndex(row, 1).cellStyle.fontColor = '#375623';
        row++;
      } else {
        styleHeader(
          sheet,
          row,
          ['Sl.No', 'Username', 'Role', 'Campaign / Item', 'Customer Name', 'Booked Date', 'Delivery Deadline', 'Days Overdue'],
          '#E2EFDA',
        );
        row++;

        overdueOrders.sort((a, b) => (b['daysOverdue'] as int).compareTo(a['daysOverdue'] as int));

        int sl = 1;
        for (final rec in overdueOrders) {
          final int daysOverdue = rec['daysOverdue'] as int;
          sheet.getRangeByIndex(row, 1).setNumber(sl.toDouble());
          sheet.getRangeByIndex(row, 2).setText(rec['username'] as String);
          sheet.getRangeByIndex(row, 3).setText(_formatRole(rec['role'] as String));
          sheet.getRangeByIndex(row, 4).setText(rec['campaign'] as String);
          sheet.getRangeByIndex(row, 5).setText(rec['customerName'] as String);
          sheet.getRangeByIndex(row, 6).setText(rec['bookedDate'] as String);
          sheet.getRangeByIndex(row, 7).setText(rec['deadline'] as String);
          sheet.getRangeByIndex(row, 8).setNumber(daysOverdue.toDouble());

          final String rowColor = daysOverdue > 14 ? '#FFCCCC' : (daysOverdue > 7 ? '#FFE5CC' : '#FFFACD');
          for (int c = 1; c <= 8; c++) {
            sheet.getRangeByIndex(row, c).cellStyle.backColor = rowColor;
          }
          sl++;
          row++;
        }
      }

      for (int c = 1; c <= 8; c++) {
        sheet.autoFitColumn(c);
      }
    }
  }

  if (isFirstSheet) {
    final sheet = workbook.worksheets[0];
    sheet.name = 'Monthly Report';
    sheet.getRangeByIndex(1, 1).setText(
        'No data found for $monthLabel. No campaigns with delivery ending this month, or no matching users.');
  }

  final List<int> bytes = workbook.saveAsStream();
  workbook.dispose();

  final Directory directory = await getTemporaryDirectory();
  final String modeSuffix = isSummary ? 'Summary' : 'Detailed';
  final String fileName =
      'Supersale_Monthly_${modeSuffix}_Report_${DateFormat('MMMM_yyyy').format(DateTime(year, month))}_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';
  final File file = File('${directory.path}/$fileName');
  await file.writeAsBytes(bytes, flush: true);

  await Share.shareXFiles(
    [XFile(file.path)],
    text: 'Supersale Monthly $modeSuffix Report — $monthLabel',
  );
}

String _formatRole(String role) {
  switch (role.toLowerCase()) {
    case 'manager':
      return 'Manager';
    case 'asst_manager':
      return 'Asst. Manager';
    case 'sales':
      return 'Sales';
    default:
      return role;
  }
}
