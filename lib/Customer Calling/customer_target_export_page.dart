import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mtcsync/Customer%20Calling/customer_individual_export.dart';
import '../Navigation/user_cache_service.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as syncfusion;
import 'package:cloud_functions/cloud_functions.dart';

const Color _primaryBlue = Color(0xFF005BAC);
const Color _primaryGreen = Color(0xFF8CC63F);

class CustomerTargetExportPage extends StatefulWidget {
  const CustomerTargetExportPage({super.key});

  @override
  State<CustomerTargetExportPage> createState() =>
      _CustomerTargetExportPageState();
}

class _CustomerTargetExportPageState extends State<CustomerTargetExportPage> {
  String? _selectedMonthYear;
  bool _loading = false;
  String? _error;
  bool _detailedReport = false;
  bool _datewiseReport = false;
  bool _threeMonthReport = false;
  List<String> _branches = [];
  String? _selectedBranch = 'All Branches';

  final List<String> _monthYears = List.generate(
    12,
    (i) {
      final now = DateTime.now();
      final date = DateTime(now.year, now.month - i, 1);
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec'
      ];
      return "${months[date.month - 1]} ${date.year}";
    },
  );

  @override
  void initState() {
    super.initState();
    _selectedMonthYear = _monthYears.first;
    _fetchBranches();
  }

  Future<void> _fetchBranches() async {
    final allBranches = await UserCacheService.instance.getBranches();
    final nonAdminBranches = allBranches
        .where((b) => b.trim().toLowerCase() != 'admin')
        .toList();
    setState(() {
      _branches = ['All Branches', ...nonAdminBranches];
      _selectedBranch = 'All Branches';
    });
  }

  Future<void> _exportExcel() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final workbook = syncfusion.Workbook();

      // Fetch username map from cached users (force refresh to ensure deleted users are excluded)
      final allUsers =
          await UserCacheService.instance.getAllUsers(forceRefresh: true);
      final Map<String, String> emailToUsername = {};
      for (final u in allUsers) {
        final email = (u['email'] as String? ?? '').toLowerCase().trim();
        final username = u['username'] as String? ?? '';
        if (email.isNotEmpty) emailToUsername[email] = username;
      }

      final usersSnapshot = await FirebaseFirestore.instance
          .collection('customer_target')
          .doc(_selectedMonthYear)
          .collection('users')
          .get();

      // Group users by branch and then by user email, keeping customers per user
      final Map<String, Map<String, List<Map<String, dynamic>>>> branchUserMap =
          {};
      for (final doc in usersSnapshot.docs) {
        final data = doc.data();
        final branch = data['branch'] ?? 'Unknown';
        if (branch.toString().trim().toLowerCase() == 'admin') continue;

        final userEmail =
            (data['user'] ?? doc.id).toString().toLowerCase().trim();

        // Skip users deleted from the app (not in active users list)
        if (!emailToUsername.containsKey(userEmail)) continue;

        final customers = (data['customers'] as List<dynamic>? ?? [])
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        branchUserMap.putIfAbsent(branch, () => {});
        branchUserMap[branch]!.putIfAbsent(userEmail, () => []);
        branchUserMap[branch]![userEmail]!.addAll(customers);
      }

      // Filter branches if a single branch is selected
      Map<String, Map<String, List<Map<String, dynamic>>>>
          filteredBranchUserMap = branchUserMap;
      if (_selectedBranch != null && _selectedBranch != 'All Branches') {
        filteredBranchUserMap = {
          _selectedBranch!: branchUserMap[_selectedBranch!] ?? {}
        };
      }

      // For each branch, create a sheet
      int sheetIndex = 0;
      if (_detailedReport || _threeMonthReport) {
        // If 3-month report is selected, prepare previous 2 months' data
        String? prev1MonthYear;
        String? prev2MonthYear;
        // email -> contact/normalized -> remark
        final Map<String, Map<String, String>> prev1RemarksByUser = {};
        final Map<String, Map<String, String>> prev2RemarksByUser = {};

        if (_threeMonthReport && _selectedMonthYear != null) {
          final parts = _selectedMonthYear!.split(' ');
          final monthStr = parts[0];
          final year = int.parse(parts[1]);
          const months = [
            'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
            'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
          ];
          final monthIdx = months.indexOf(monthStr); // 0 to 11
          final selectedDate = DateTime(year, monthIdx + 1, 1);

          final prev1Date = DateTime(selectedDate.year, selectedDate.month - 1, 1);
          final prev2Date = DateTime(selectedDate.year, selectedDate.month - 2, 1);

          prev1MonthYear = "${months[prev1Date.month - 1]} ${prev1Date.year}";
          prev2MonthYear = "${months[prev2Date.month - 1]} ${prev2Date.year}";

          // Fetch previous 2 months concurrently
          final futures = await Future.wait([
            FirebaseFirestore.instance
                .collection('customer_target')
                .doc(prev1MonthYear)
                .collection('users')
                .get(),
            FirebaseFirestore.instance
                .collection('customer_target')
                .doc(prev2MonthYear)
                .collection('users')
                .get(),
          ]);

          void extractRemarks(
              QuerySnapshot snapshot, Map<String, Map<String, String>> targetMap) {
            for (final doc in snapshot.docs) {
              final data = doc.data() as Map<String, dynamic>? ?? {};
              final userEmail =
                  (data['user'] ?? doc.id).toString().toLowerCase().trim();
              final customers = (data['customers'] as List<dynamic>? ?? [])
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList();
              final userRemarks = targetMap.putIfAbsent(userEmail, () => {});
              for (final c in customers) {
                final remarks = (c['remarks'] ?? '').toString().trim();
                if (remarks.isEmpty) continue;
                final c1 = (c['contact1'] ?? c['contact'] ?? '').toString().trim();
                final c2 = (c['contact2'] ?? '').toString().trim();
                final cName = (c['name'] ?? '').toString().trim().toLowerCase();
                if (c1.isNotEmpty) userRemarks[c1] = remarks;
                if (c2.isNotEmpty) userRemarks[c2] = remarks;
                if (cName.isNotEmpty) userRemarks['name:$cName'] = remarks;
              }
            }
          }

          extractRemarks(futures[0], prev1RemarksByUser);
          extractRemarks(futures[1], prev2RemarksByUser);
        }

        for (final branch in filteredBranchUserMap.keys) {
          final sheet = sheetIndex == 0
              ? workbook.worksheets[0]
              : workbook.worksheets.addWithName(branch);
          sheet.name = branch;
          int row = 1;
          for (final userEmail in filteredBranchUserMap[branch]!.keys) {
            final customers = List<Map<String, dynamic>>.from(
                filteredBranchUserMap[branch]![userEmail]!);
            // Sort: Called first, Not Called second
            customers.sort((a, b) =>
                (b['callMade'] == true ? 1 : 0) -
                (a['callMade'] == true ? 1 : 0));

            final username = emailToUsername[userEmail] ?? userEmail;
            final calledCount =
                customers.where((c) => c['callMade'] == true).length;
            final totalCount = customers.length;

            final maxColLetter = _threeMonthReport ? 'E' : 'C';

            // --- Username header row ---
            final userRange = sheet.getRangeByName('A$row:$maxColLetter$row');
            userRange.merge();
            userRange.setText(username);
            userRange.cellStyle.bold = true;
            userRange.cellStyle.backColor = '#005BAC';
            userRange.cellStyle.fontColor = '#FFFFFF';
            userRange.cellStyle.fontSize = 12;
            userRange.cellStyle.borders.all.lineStyle =
                syncfusion.LineStyle.thin;
            userRange.cellStyle.borders.all.color = '#CCCCCC';
            row++;

            // --- Called progress row ---
            final progressRange = sheet.getRangeByName('A$row:$maxColLetter$row');
            progressRange.merge();
            progressRange
                .setText('Customers Called: $calledCount / $totalCount');
            progressRange.cellStyle.bold = true;
            progressRange.cellStyle.backColor = '#E8F5E9';
            progressRange.cellStyle.fontColor = '#1B5E20';
            progressRange.cellStyle.borders.all.lineStyle =
                syncfusion.LineStyle.thin;
            progressRange.cellStyle.borders.all.color = '#CCCCCC';
            row++;

            // --- Table column headers ---
            void applyHeaderStyle(syncfusion.Range r) {
              r.cellStyle.bold = true;
              r.cellStyle.backColor = '#37474F';
              r.cellStyle.fontColor = '#FFFFFF';
              r.cellStyle.borders.all.lineStyle = syncfusion.LineStyle.thin;
              r.cellStyle.borders.all.color = '#CCCCCC';
            }

            final hA = sheet.getRangeByName('A$row');
            final hB = sheet.getRangeByName('B$row');
            final hC = sheet.getRangeByName('C$row');
            hA.setText('Customer Name');
            hB.setText('Call Status');
            hC.setText('Remarks');
            applyHeaderStyle(hA);
            applyHeaderStyle(hB);
            applyHeaderStyle(hC);

            if (_threeMonthReport) {
              final hD = sheet.getRangeByName('D$row');
              final hE = sheet.getRangeByName('E$row');
              hD.setText(prev1MonthYear != null
                  ? '$prev1MonthYear Remarks'
                  : 'Previous Month Remarks');
              hE.setText(prev2MonthYear != null
                  ? '$prev2MonthYear Remarks'
                  : 'Prev to Prev Month Remarks');
              applyHeaderStyle(hD);
              applyHeaderStyle(hE);
            }
            row++;

            final userPrev1 = prev1RemarksByUser[userEmail] ?? {};
            final userPrev2 = prev2RemarksByUser[userEmail] ?? {};

            // --- Customer data rows ---
            for (final customer in customers) {
              final isCalled = customer['callMade'] == true;
              final cellA = sheet.getRangeByName('A$row');
              final cellB = sheet.getRangeByName('B$row');
              final cellC = sheet.getRangeByName('C$row');

              cellA.setText(customer['name'] ?? '');
              cellB.setText(isCalled ? 'Called' : 'Not Called');
              cellC.setText(customer['remarks'] ?? '');

              final cellsToBorder = [cellA, cellB, cellC];

              if (_threeMonthReport) {
                final cellD = sheet.getRangeByName('D$row');
                final cellE = sheet.getRangeByName('E$row');

                final c1 = (customer['contact1'] ?? customer['contact'] ?? '')
                    .toString()
                    .trim();
                final c2 = (customer['contact2'] ?? '').toString().trim();
                final cName = (customer['name'] ?? '').toString().trim().toLowerCase();

                String prev1Remark = '';
                if (c1.isNotEmpty && userPrev1.containsKey(c1)) {
                  prev1Remark = userPrev1[c1]!;
                } else if (c2.isNotEmpty && userPrev1.containsKey(c2)) {
                  prev1Remark = userPrev1[c2]!;
                } else if (cName.isNotEmpty && userPrev1.containsKey('name:$cName')) {
                  prev1Remark = userPrev1['name:$cName']!;
                }

                String prev2Remark = '';
                if (c1.isNotEmpty && userPrev2.containsKey(c1)) {
                  prev2Remark = userPrev2[c1]!;
                } else if (c2.isNotEmpty && userPrev2.containsKey(c2)) {
                  prev2Remark = userPrev2[c2]!;
                } else if (cName.isNotEmpty && userPrev2.containsKey('name:$cName')) {
                  prev2Remark = userPrev2['name:$cName']!;
                }

                cellD.setText(prev1Remark);
                cellE.setText(prev2Remark);

                cellsToBorder.addAll([cellD, cellE]);
              }

              // Cell borders
              for (final cell in cellsToBorder) {
                cell.cellStyle.borders.all.lineStyle =
                    syncfusion.LineStyle.thin;
                cell.cellStyle.borders.all.color = '#CCCCCC';
              }

              // Call Status colouring (Column B)
              if (isCalled) {
                cellB.cellStyle.backColor = '#4CAF50';
                cellB.cellStyle.fontColor = '#FFFFFF';
                cellB.cellStyle.bold = true;
              } else {
                cellB.cellStyle.backColor = '#F44336';
                cellB.cellStyle.fontColor = '#FFFFFF';
                cellB.cellStyle.bold = true;
              }
              row++;
            }
            row++; // Empty row between users
          }
          // --- Autofit columns after filling data ---
          sheet.autoFitColumn(1);
          sheet.autoFitColumn(2);
          sheet.autoFitColumn(3);
          if (_threeMonthReport) {
            sheet.autoFitColumn(4);
            sheet.autoFitColumn(5);
          }
          sheetIndex++;
        }
      } else if (_datewiseReport) {
        // ── Datewise report ─────────────────────────────────────────────
        for (final branch in filteredBranchUserMap.keys) {
          final sheet = sheetIndex == 0
              ? workbook.worksheets[0]
              : workbook.worksheets.addWithName(branch);
          sheet.name = branch;

          // Parse month and year
          final parts = _selectedMonthYear!.split(' ');
          final monthStr = parts[0];
          final year = int.parse(parts[1]);
          const months = [
            'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
            'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
          ];
          final month = months.indexOf(monthStr) + 1;
          final daysInMonth = DateTime(year, month + 1, 0).day;

          // Title row
          final titleRange = sheet.getRangeByIndex(1, 1, 1, 1 + daysInMonth + 1);
          titleRange.merge();
          titleRange.setText('Customer Target Datewise Report — $branch ($_selectedMonthYear)');
          titleRange.cellStyle.bold = true;
          titleRange.cellStyle.fontSize = 13;
          titleRange.cellStyle.backColor = '#005BAC';
          titleRange.cellStyle.fontColor = '#FFFFFF';
          titleRange.cellStyle.hAlign = syncfusion.HAlignType.center;
          titleRange.cellStyle.vAlign = syncfusion.VAlignType.center;
          sheet.getRangeByIndex(1, 1).rowHeight = 28;

          // Headers: A2 is "Username", B2 to ... are dates (1, 2, ..., daysInMonth), last is "Total Calls"
          void applyHeaderStyle(syncfusion.Range r) {
            r.cellStyle.bold = true;
            r.cellStyle.backColor = '#8CC63F';
            r.cellStyle.fontColor = '#FFFFFF';
            r.cellStyle.borders.all.lineStyle = syncfusion.LineStyle.thin;
            r.cellStyle.borders.all.color = '#CCCCCC';
            r.cellStyle.hAlign = syncfusion.HAlignType.center;
            r.cellStyle.vAlign = syncfusion.VAlignType.center;
          }

          final hUsername = sheet.getRangeByIndex(2, 1);
          hUsername.setText('Username');
          applyHeaderStyle(hUsername);

          for (int day = 1; day <= daysInMonth; day++) {
            final hDay = sheet.getRangeByIndex(2, 1 + day);
            hDay.setNumber(day.toDouble());
            applyHeaderStyle(hDay);
          }

          final hTotal = sheet.getRangeByIndex(2, 1 + daysInMonth + 1);
          hTotal.setText('Total Calls');
          applyHeaderStyle(hTotal);

          int dataRow = 3;
          int rowIdx = 0;
          for (final userEmail in filteredBranchUserMap[branch]!.keys) {
            final customers = filteredBranchUserMap[branch]![userEmail]!;
            final username = emailToUsername[userEmail] ?? userEmail;

            // Count calls for each day
            final Map<int, int> dayCallCounts = {};
            for (int day = 1; day <= daysInMonth; day++) {
              dayCallCounts[day] = 0;
            }
            int totalCallsForUser = 0;

            for (final customer in customers) {
              if (customer['callMade'] == true) {
                final rawDate = customer['callDate'];
                DateTime? callDate;
                if (rawDate != null) {
                  if (rawDate is String) {
                    callDate = DateTime.tryParse(rawDate);
                  } else if (rawDate is Timestamp) {
                    callDate = rawDate.toDate();
                  } else if (rawDate is DateTime) {
                    callDate = rawDate;
                  }
                }
                if (callDate != null) {
                  final day = callDate.day;
                  if (day >= 1 && day <= daysInMonth) {
                    dayCallCounts[day] = (dayCallCounts[day] ?? 0) + 1;
                  }
                }
                totalCallsForUser++;
              }
            }

            final bgColor = rowIdx % 2 == 1 ? '#F0F5FF' : '#FFFFFF';

            // Username cell
            final cellUsername = sheet.getRangeByIndex(dataRow, 1);
            cellUsername.setText(username);
            cellUsername.cellStyle.borders.all.lineStyle = syncfusion.LineStyle.thin;
            cellUsername.cellStyle.borders.all.color = '#CCCCCC';
            cellUsername.cellStyle.backColor = bgColor;
            cellUsername.cellStyle.hAlign = syncfusion.HAlignType.left;
            cellUsername.cellStyle.vAlign = syncfusion.VAlignType.center;

            // Day count cells
            for (int day = 1; day <= daysInMonth; day++) {
              final cellDay = sheet.getRangeByIndex(dataRow, 1 + day);
              final count = dayCallCounts[day] ?? 0;
              cellDay.setNumber(count.toDouble());
              cellDay.cellStyle.borders.all.lineStyle = syncfusion.LineStyle.thin;
              cellDay.cellStyle.borders.all.color = '#CCCCCC';
              cellDay.cellStyle.backColor = bgColor;
              cellDay.cellStyle.hAlign = syncfusion.HAlignType.center;
              cellDay.cellStyle.vAlign = syncfusion.VAlignType.center;
            }

            // Total Calls cell
            final cellTotal = sheet.getRangeByIndex(dataRow, 1 + daysInMonth + 1);
            cellTotal.setNumber(totalCallsForUser.toDouble());
            cellTotal.cellStyle.borders.all.lineStyle = syncfusion.LineStyle.thin;
            cellTotal.cellStyle.borders.all.color = '#CCCCCC';
            cellTotal.cellStyle.backColor = bgColor;
            cellTotal.cellStyle.hAlign = syncfusion.HAlignType.center;
            cellTotal.cellStyle.vAlign = syncfusion.VAlignType.center;
            cellTotal.cellStyle.bold = true;

            dataRow++;
            rowIdx++;
          }

          sheet.autoFitColumn(1);
          // Set column width for dates to be compact
          for (int day = 1; day <= daysInMonth; day++) {
            sheet.getRangeByIndex(1, 1 + day).columnWidth = 4.5;
          }
          sheet.getRangeByIndex(1, 1 + daysInMonth + 1).columnWidth = 12;

          sheetIndex++;
        }
      } else {
        // ── Summary report ──────────────────────────────────────────────
        for (final branch in filteredBranchUserMap.keys) {
          final sheet = sheetIndex == 0
              ? workbook.worksheets[0]
              : workbook.worksheets.addWithName(branch);
          sheet.name = branch;

          // Title row
          final titleRange = sheet.getRangeByName('A1:C1');
          titleRange.merge();
          titleRange.setText('Customer Target — $branch ($_selectedMonthYear)');
          titleRange.cellStyle.bold = true;
          titleRange.cellStyle.fontSize = 13;
          titleRange.cellStyle.backColor = '#005BAC';
          titleRange.cellStyle.fontColor = '#FFFFFF';
          titleRange.cellStyle.hAlign = syncfusion.HAlignType.center;
          sheet.getRangeByIndex(1, 1).rowHeight = 28;

          // Column headers
          void applyHeaderStyle(syncfusion.Range r) {
            r.cellStyle.bold = true;
            r.cellStyle.backColor = '#8CC63F';
            r.cellStyle.fontColor = '#FFFFFF';
            r.cellStyle.borders.all.lineStyle = syncfusion.LineStyle.thin;
            r.cellStyle.borders.all.color = '#CCCCCC';
            r.cellStyle.hAlign = syncfusion.HAlignType.center;
          }

          final hA = sheet.getRangeByName('A2');
          final hB = sheet.getRangeByName('B2');
          final hC = sheet.getRangeByName('C2');
          hA.setText('Username');
          hB.setText('Total No. Of Customers');
          hC.setText('Total Called');
          applyHeaderStyle(hA);
          applyHeaderStyle(hB);
          applyHeaderStyle(hC);

          int dataRow = 3;
          int rowIdx = 0;
          for (final userEmail in filteredBranchUserMap[branch]!.keys) {
            final customers = filteredBranchUserMap[branch]![userEmail]!;
            final username = emailToUsername[userEmail] ?? userEmail;
            final totalCount = customers.length;
            final calledCount =
                customers.where((c) => c['callMade'] == true).length;

            final bgColor = rowIdx % 2 == 1 ? '#F0F5FF' : '#FFFFFF';
            final cellA = sheet.getRangeByName('A$dataRow');
            final cellB = sheet.getRangeByName('B$dataRow');
            final cellC = sheet.getRangeByName('C$dataRow');

            cellA.setText(username);
            cellB.setNumber(totalCount.toDouble());
            cellC.setNumber(calledCount.toDouble());

            for (final cell in [cellA, cellB, cellC]) {
              cell.cellStyle.borders.all.lineStyle = syncfusion.LineStyle.thin;
              cell.cellStyle.borders.all.color = '#CCCCCC';
              cell.cellStyle.backColor = bgColor;
            }
            cellA.cellStyle.hAlign = syncfusion.HAlignType.left;
            cellB.cellStyle.hAlign = syncfusion.HAlignType.center;
            cellC.cellStyle.hAlign = syncfusion.HAlignType.center;

            dataRow++;
            rowIdx++;
          }

          sheet.autoFitColumn(1);
          sheet.getRangeByIndex(1, 2).columnWidth = 24;
          sheet.getRangeByIndex(1, 3).columnWidth = 16;
          sheetIndex++;
        }
      }

      final List<int> bytes = workbook.saveAsStream();
      workbook.dispose();

      final dir = await getTemporaryDirectory();
      String fileName;
      String shareText;

      final branchPrefix = (_selectedBranch != null && _selectedBranch != 'All Branches')
          ? _selectedBranch!
          : 'All Branches';
      final monthName = _selectedMonthYear?.split(' ').first.toLowerCase() ?? '';

      if (_threeMonthReport) {
        fileName = '$branchPrefix 3-month $monthName report.xlsx';
        shareText = '$branchPrefix 3-month $monthName report';
      } else if (_detailedReport) {
        fileName = '${branchPrefix}_Detailed_${_selectedMonthYear!.replaceAll(' ', '_')}.xlsx';
        shareText = '$branchPrefix Customer Target Detailed $_selectedMonthYear';
      } else if (_datewiseReport) {
        fileName = '${branchPrefix}_Datewise_${_selectedMonthYear!.replaceAll(' ', '_')}.xlsx';
        shareText = '$branchPrefix Customer Target Datewise $_selectedMonthYear';
      } else {
        fileName = 'CustomerTarget_${_selectedMonthYear!.replaceAll(' ', '_')}.xlsx';
        shareText = 'Customer Target $_selectedMonthYear';
      }

      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles([XFile(file.path)],
          text: shareText);
    } catch (e) {
      setState(() {
        _error = 'Export failed: $e';
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> triggerCustomerTargetExport(
      String monthYear, String fileMonth) async {
    final HttpsCallable callable = FirebaseFunctions.instance
        .httpsCallable('exportCustomerTargetIndividualReport');
    final result =
        await callable.call({'monthYear': monthYear, 'fileMonth': fileMonth});
    // Handle result (e.g., show a dialog with the download link)
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0A1628) : const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Export Customer Target'),
        backgroundColor: _primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_search_rounded),
            tooltip: 'Export Individual Customer List',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const CustomerIndividualExportPage(),
                ),
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Month dropdown styled
            DropdownButtonFormField<String>(
              value: _selectedMonthYear,
              decoration: InputDecoration(
                labelText: 'Month',
                labelStyle: const TextStyle(color: _primaryBlue),
                prefixIcon: const Icon(Icons.calendar_today_rounded,
                    color: _primaryBlue, size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      BorderSide(color: _primaryBlue.withValues(alpha: 0.4)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      BorderSide(color: _primaryBlue.withValues(alpha: 0.4)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _primaryBlue, width: 1.5),
                ),
                filled: true,
                fillColor:
                    isDark ? const Color(0xFF162236) : const Color(0xFFF0F5FF),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
              dropdownColor: isDark ? const Color(0xFF162236) : Colors.white,
              style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87, fontSize: 14),
              items: _monthYears
                  .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                  .toList(),
              onChanged: (val) => setState(() => _selectedMonthYear = val),
            ),
            const SizedBox(height: 16),

            // Branch dropdown styled
            DropdownButtonFormField<String>(
              value: _selectedBranch,
              decoration: InputDecoration(
                labelText: 'Branch',
                labelStyle: const TextStyle(color: _primaryBlue),
                prefixIcon: const Icon(Icons.location_city_rounded,
                    color: _primaryBlue, size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      BorderSide(color: _primaryBlue.withValues(alpha: 0.4)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      BorderSide(color: _primaryBlue.withValues(alpha: 0.4)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _primaryBlue, width: 1.5),
                ),
                filled: true,
                fillColor:
                    isDark ? const Color(0xFF162236) : const Color(0xFFF0F5FF),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
              dropdownColor: isDark ? const Color(0xFF162236) : Colors.white,
              style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87, fontSize: 14),
              items: _branches
                  .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                  .toList(),
              onChanged: (val) => setState(() => _selectedBranch = val),
            ),

            // Report checkboxes styled
            Wrap(
              spacing: 16,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkbox(
                      value: _detailedReport,
                      activeColor: _primaryBlue,
                      onChanged: (val) => setState(() {
                        _detailedReport = val ?? false;
                        if (_detailedReport) {
                          _datewiseReport = false;
                          _threeMonthReport = false;
                        }
                      }),
                    ),
                    const Text(
                      'Detailed Report',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkbox(
                      value: _datewiseReport,
                      activeColor: _primaryBlue,
                      onChanged: (val) => setState(() {
                        _datewiseReport = val ?? false;
                        if (_datewiseReport) {
                          _detailedReport = false;
                          _threeMonthReport = false;
                        }
                      }),
                    ),
                    const Text(
                      'Datewise Report',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkbox(
                      value: _threeMonthReport,
                      activeColor: _primaryBlue,
                      onChanged: (val) => setState(() {
                        _threeMonthReport = val ?? false;
                        if (_threeMonthReport) {
                          _detailedReport = false;
                          _datewiseReport = false;
                        }
                      }),
                    ),
                    const Text(
                      '3-month report',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Export button styled
            ElevatedButton.icon(
              onPressed: _loading ? null : _exportExcel,
              icon: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.download_rounded),
              label: Text(_loading ? 'Exporting...' : 'Export as Excel'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),

            const SizedBox(height: 24),

            // Info card (optional, for help or status)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0D2137) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _primaryBlue.withValues(alpha: 0.15)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoLine(IconData icon, String text, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 16, color: isDark ? Colors.white38 : Colors.black38),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
                fontSize: 13, color: isDark ? Colors.white60 : Colors.black54),
          ),
        ],
      ),
    );
  }
}
