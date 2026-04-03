import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mtcsync/Customer%20Target/customer_individual_export.dart';
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
  State<CustomerTargetExportPage> createState() => _CustomerTargetExportPageState();
}

class _CustomerTargetExportPageState extends State<CustomerTargetExportPage> {
  String? _selectedMonthYear;
  bool _loading = false;
  String? _error;
  bool _detailedReport = false;
  List<String> _branches = [];
  String? _selectedBranch = 'All Branches';

  final List<String> _monthYears = List.generate(
    12,
    (i) {
      final now = DateTime.now();
      final date = DateTime(now.year, now.month - i, 1);
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
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
    setState(() {
      _branches = ['All Branches', ...allBranches];
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

      // Fetch username map from cached users
      final allUsers = await UserCacheService.instance.getAllUsers();
      final Map<String, String> emailToUsername = {};
      for (final u in allUsers) {
        final email = (u['email'] as String? ?? '').toLowerCase();
        final username = u['username'] as String? ?? '';
        if (email.isNotEmpty) emailToUsername[email] = username;
      }

      final usersSnapshot = await FirebaseFirestore.instance
          .collection('customer_target')
          .doc(_selectedMonthYear)
          .collection('users')
          .get();

      // Group users by branch and then by user email, keeping customers per user
      final Map<String, Map<String, List<Map<String, dynamic>>>> branchUserMap = {};
      for (final doc in usersSnapshot.docs) {
        final data = doc.data();
        final branch = data['branch'] ?? 'Unknown';
        final userEmail = (data['user'] ?? doc.id).toString().toLowerCase();
        final customers = (data['customers'] as List<dynamic>? ?? [])
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        branchUserMap.putIfAbsent(branch, () => {});
        branchUserMap[branch]!.putIfAbsent(userEmail, () => []);
        branchUserMap[branch]![userEmail]!.addAll(customers);
      }

      // Filter branches if a single branch is selected
      Map<String, Map<String, List<Map<String, dynamic>>>> filteredBranchUserMap = branchUserMap;
      if (_selectedBranch != null && _selectedBranch != 'All Branches') {
        filteredBranchUserMap = {
          _selectedBranch!: branchUserMap[_selectedBranch!] ?? {}
        };
      }

      // For each branch, create a sheet
      int sheetIndex = 0;
      if (_detailedReport) {
        for (final branch in filteredBranchUserMap.keys) {
          final sheet = sheetIndex == 0
              ? workbook.worksheets[0]
              : workbook.worksheets.addWithName(branch);
          sheet.name = branch;
          int row = 1;
          for (final userEmail in filteredBranchUserMap[branch]!.keys) {
            final customers = List<Map<String, dynamic>>.from(filteredBranchUserMap[branch]![userEmail]!);
            // Sort: Called first, Not Called second
            customers.sort((a, b) =>
                (b['callMade'] == true ? 1 : 0) - (a['callMade'] == true ? 1 : 0));

            final username = emailToUsername[userEmail] ?? userEmail;
            final calledCount = customers.where((c) => c['callMade'] == true).length;
            final totalCount = customers.length;

            // --- Username header row ---
            final userRange = sheet.getRangeByName('A$row:C$row');
            userRange.merge();
            userRange.setText(username);
            userRange.cellStyle.bold = true;
            userRange.cellStyle.backColor = '#005BAC';
            userRange.cellStyle.fontColor = '#FFFFFF';
            userRange.cellStyle.fontSize = 12;
            userRange.cellStyle.borders.all.lineStyle = syncfusion.LineStyle.thin;
            userRange.cellStyle.borders.all.color = '#CCCCCC';
            row++;

            // --- Called progress row ---
            final progressRange = sheet.getRangeByName('A$row:C$row');
            progressRange.merge();
            progressRange.setText('Customers Called: $calledCount / $totalCount');
            progressRange.cellStyle.bold = true;
            progressRange.cellStyle.backColor = '#E8F5E9';
            progressRange.cellStyle.fontColor = '#1B5E20';
            progressRange.cellStyle.borders.all.lineStyle = syncfusion.LineStyle.thin;
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
            hB.setText('Remarks');
            hC.setText('Call Status');
            applyHeaderStyle(hA);
            applyHeaderStyle(hB);
            applyHeaderStyle(hC);
            row++;

            // --- Customer data rows ---
            for (final customer in customers) {
              final isCalled = customer['callMade'] == true;
              final cellA = sheet.getRangeByName('A$row');
              final cellB = sheet.getRangeByName('B$row');
              final cellC = sheet.getRangeByName('C$row');

              cellA.setText(customer['name'] ?? '');
              cellB.setText(customer['remarks'] ?? '');
              cellC.setText(isCalled ? 'Called' : 'Not Called');

              // Cell borders
              for (final cell in [cellA, cellB, cellC]) {
                cell.cellStyle.borders.all.lineStyle = syncfusion.LineStyle.thin;
                cell.cellStyle.borders.all.color = '#CCCCCC';
              }

              // Call Status colouring
              if (isCalled) {
                cellC.cellStyle.backColor = '#4CAF50';
                cellC.cellStyle.fontColor = '#FFFFFF';
                cellC.cellStyle.bold = true;
              } else {
                cellC.cellStyle.backColor = '#F44336';
                cellC.cellStyle.fontColor = '#FFFFFF';
                cellC.cellStyle.bold = true;
              }
              row++;
            }
            row++; // Empty row between users
          }
          // --- Autofit columns after filling data ---
          sheet.autoFitColumn(1);
          sheet.autoFitColumn(2);
          sheet.autoFitColumn(3);
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
      final file = File('${dir.path}/CustomerTarget_${_selectedMonthYear!.replaceAll(' ', '_')}.xlsx');
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles([XFile(file.path)], text: 'Customer Target $_selectedMonthYear');
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

  Future<void> triggerCustomerTargetExport(String monthYear, String fileMonth) async {
    final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable('exportCustomerTargetIndividualReport');
    final result = await callable.call({'monthYear': monthYear, 'fileMonth': fileMonth});
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
                prefixIcon: const Icon(Icons.calendar_today_rounded, color: _primaryBlue, size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: _primaryBlue.withValues(alpha: 0.4)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: _primaryBlue.withValues(alpha: 0.4)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _primaryBlue, width: 1.5),
                ),
                filled: true,
                fillColor: isDark ? const Color(0xFF162236) : const Color(0xFFF0F5FF),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
              dropdownColor: isDark ? const Color(0xFF162236) : Colors.white,
              style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14),
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
                prefixIcon: const Icon(Icons.location_city_rounded, color: _primaryBlue, size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: _primaryBlue.withValues(alpha: 0.4)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: _primaryBlue.withValues(alpha: 0.4)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _primaryBlue, width: 1.5),
                ),
                filled: true,
                fillColor: isDark ? const Color(0xFF162236) : const Color(0xFFF0F5FF),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
              dropdownColor: isDark ? const Color(0xFF162236) : Colors.white,
              style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14),
              items: _branches.map((b) => DropdownMenuItem(value: b, child: Text(b))).toList(),
              onChanged: (val) => setState(() => _selectedBranch = val),
            ),

            const SizedBox(height: 16),
            // Detailed Report checkbox styled
            Row(
              children: [
                Checkbox(
                  value: _detailedReport,
                  activeColor: _primaryBlue,
                  onChanged: (val) => setState(() => _detailedReport = val ?? false),
                ),
                const Text(
                  'Detailed Report',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
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
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.download_rounded),
              label: Text(_loading ? 'Exporting...' : 'Export as Excel'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
            style: TextStyle(fontSize: 13, color: isDark ? Colors.white60 : Colors.black54),
          ),
        ],
      ),
    );
  }
}