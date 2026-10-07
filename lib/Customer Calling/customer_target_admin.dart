import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../Navigation/user_cache_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' hide Border;

/// Details of a customer occurrence inside the uploaded Excel
class ExcelRowCustomerInfo {
  final int rowNumber;
  final String customerName;
  final String rawPhone;

  ExcelRowCustomerInfo({
    required this.rowNumber,
    required this.customerName,
    required this.rawPhone,
  });
}

/// A duplicate phone number group occurring multiple times within the uploaded Excel sheet
class InternalExcelDuplicate {
  final String phone;
  final List<ExcelRowCustomerInfo> occurrences;

  InternalExcelDuplicate({
    required this.phone,
    required this.occurrences,
  });
}

/// An entry in an existing user's calling list in Firestore
class ExistingPhoneRecord {
  final String userEmail;
  final String username;
  final String branch;
  final String customerName;
  final bool isSelf;
  final bool isSameBranch;

  ExistingPhoneRecord({
    required this.userEmail,
    required this.username,
    required this.branch,
    required this.customerName,
    required this.isSelf,
    required this.isSameBranch,
  });
}

/// A customer in the uploaded Excel whose phone number already exists in Firestore
class ExternalCallingDuplicate {
  final String phone;
  final String excelCustomerName;
  final int excelRowNumber;
  final String existingCustomerName;
  final String assignedUsername;
  final String assignedUserEmail;
  final String assignedBranch;
  final bool isSameBranch;
  final bool isSelf;

  ExternalCallingDuplicate({
    required this.phone,
    required this.excelCustomerName,
    required this.excelRowNumber,
    required this.existingCustomerName,
    required this.assignedUsername,
    required this.assignedUserEmail,
    required this.assignedBranch,
    required this.isSameBranch,
    required this.isSelf,
  });
}

class CustomerTargetAdminPage extends StatefulWidget {
  const CustomerTargetAdminPage({super.key});

  @override
  State<CustomerTargetAdminPage> createState() => _CustomerTargetAdminPageState();
}

class _CustomerTargetAdminPageState extends State<CustomerTargetAdminPage> {
  String? _selectedBranch;
  String? _selectedUserEmail;
  List<String> _branches = [];
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _allUsers = [];
  bool _loading = false;
  String _loadingMessage = '';
  String? _error;
  String? _success;
  List<Map<String, dynamic>>? _customers; // Store imported customers when valid
  String? _selectedMonthYear;

  List<InternalExcelDuplicate> _internalDuplicates = [];
  List<ExternalCallingDuplicate> _externalDuplicates = [];

  final List<String> _monthYears = List.generate(
    6,
    (i) {
      final now = DateTime.now();
      // i=0 -> next month, i=1 -> current month, i=2 -> prev month, etc.
      final date = DateTime(now.year, now.month - i + 1, 1);
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
    _selectedMonthYear = _monthYears[1]; // default to current month
    _fetchUsersAndBranches();
  }

  Future<void> _fetchUsersAndBranches() async {
    // Fetch all users from cache
    final cachedUsers = await UserCacheService.instance.getAllUsers();
    final users = cachedUsers
        .map((u) => {
              'email': u['email'],
              'name': u['username'],
              'branch': u['branch'],
            })
        .toList();

    // Extract unique branches
    final branches = users.map((u) => u['branch'] as String).toSet().toList();
    branches.sort(); // Sort branches in ascending order

    if (mounted) {
      setState(() {
        _allUsers = users;
        _branches = branches;
      });
    }
  }

  void _filterUsersForBranch(String branch) {
    setState(() {
      _users = _allUsers.where((u) => u['branch'] == branch).toList();
      _selectedUserEmail = null;
      _resetImportState();
    });
  }

  void _resetImportState() {
    _customers = null;
    _internalDuplicates = [];
    _externalDuplicates = [];
    _error = null;
    _success = null;
  }

  String _normalizePhone(String? phone) {
    if (phone == null) return '';
    final digits =
        RegExp(r'\d').allMatches(phone).map((m) => m.group(0)).join();
    if (digits.length >= 10) {
      return digits.substring(digits.length - 10);
    }
    return digits;
  }

  void _copyDuplicateReport() {
    final buffer = StringBuffer();
    buffer.writeln("=== CUSTOMER CALLING DUPLICATE REPORT ===");
    buffer.writeln("Month: ${_selectedMonthYear ?? 'N/A'}");
    buffer.writeln("Branch: ${_selectedBranch ?? 'N/A'}");
    buffer.writeln("Target User: ${_selectedUserEmail ?? 'N/A'}");
    buffer.writeln("Generated: ${DateTime.now().toLocal()}");
    buffer.writeln("");

    if (_internalDuplicates.isNotEmpty) {
      buffer.writeln("--- DUPLICATES WITHIN UPLOADED EXCEL (${_internalDuplicates.length}) ---");
      for (final dup in _internalDuplicates) {
        buffer.writeln("Phone: ${dup.phone}");
        for (final occ in dup.occurrences) {
          buffer.writeln("  - Row ${occ.rowNumber}: ${occ.customerName} (${occ.rawPhone})");
        }
      }
      buffer.writeln("");
    }

    if (_externalDuplicates.isNotEmpty) {
      buffer.writeln("--- ALREADY ASSIGNED TO OTHER USERS (${_externalDuplicates.length}) ---");
      for (final dup in _externalDuplicates) {
        buffer.writeln("Phone: ${dup.phone}");
        buffer.writeln("  Excel Customer: Row ${dup.excelRowNumber}: ${dup.excelCustomerName}");
        if (dup.isSelf) {
          buffer.writeln("  Assigned To: Already in this user's list (${dup.existingCustomerName})");
        } else {
          buffer.writeln("  Assigned To: ${dup.assignedUsername} (${dup.assignedBranch})");
          buffer.writeln("  Existing Customer Name: ${dup.existingCustomerName}");
        }
      }
      buffer.writeln("");
    }

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Duplicate report copied to clipboard'),
        backgroundColor: Colors.black87,
      ),
    );
  }

  void _showDuplicateAlertDialog(int internalCount, int externalCount) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 48),
        title: const Text(
          'Duplicates Detected - Upload Blocked',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The uploaded Excel cannot be uploaded or assigned until the following duplicate phone numbers are resolved:',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            if (internalCount > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '• $internalCount duplicate phone number(s) within the Excel file.',
                  style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.red),
                ),
              ),
            if (externalCount > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '• $externalCount customer(s) already assigned to other users in branch / month.',
                  style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.deepOrange),
                ),
              ),
            const SizedBox(height: 12),
            const Text(
              'Please review the detailed conflict list below, resolve the duplicate numbers in your Excel file, and re-import.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy Report'),
            onPressed: () {
              Navigator.pop(ctx);
              _copyDuplicateReport();
            },
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            child: const Text('View Conflicts'),
          ),
        ],
      ),
    );
  }

  Future<void> _importExcel() async {
    if (_selectedMonthYear == null || _selectedBranch == null || _selectedUserEmail == null) {
      setState(() {
        _error = "Please select Month, Branch, and User before importing Excel.";
      });
      return;
    }

    setState(() {
      _loading = true;
      _loadingMessage = "Selecting Excel file...";
      _error = null;
      _success = null;
      _customers = null;
      _internalDuplicates = [];
      _externalDuplicates = [];
    });

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
      );

      if (result == null || result.files.single.path == null) {
        setState(() {
          _loading = false;
        });
        return;
      }

      setState(() {
        _loadingMessage = "Reading Excel sheet...";
      });

      File file = File(result.files.single.path!);
      var bytes = await file.readAsBytes();
      var excel = Excel.decodeBytes(bytes);

      if (excel.tables.isEmpty) {
        throw Exception("No sheets found in Excel file");
      }

      final sheet = excel.tables.values.first;
      if (sheet.maxRows < 2) {
        throw Exception("Sheet is empty");
      }

      // ---- READ HEADER ROW ----
      final headerRow = sheet.row(0);

      int? nameCol;
      int? contactCol;
      int? contact2Col;
      int? addressCol;

      for (int i = 0; i < headerRow.length; i++) {
        final header = headerRow[i]?.value?.toString().toLowerCase().trim();

        if (header == null) continue;

        if (header.contains('name') || header.contains('customer') || header.contains('client')) {
          nameCol ??= i;
        }

        if (header.contains('phone 2') ||
            header.contains('mobile 2') ||
            header.contains('contact 2') ||
            header.contains('alternate') ||
            header.contains('second contact') ||
            header.contains('second phone')) {
          contact2Col ??= i;
        } else if (header.contains('phone') ||
            header.contains('mobile') ||
            header.contains('contact')) {
          contactCol ??= i;
        }

        if (header.contains('address')) {
          addressCol ??= i;
        }
      }

      if (nameCol == null || contactCol == null || addressCol == null) {
        throw Exception("Required columns not found (Name / Address / Contact)");
      }

      // ---- READ DATA ROWS ----
      List<Map<String, dynamic>> parsedRows = [];

      for (int i = 1; i < sheet.maxRows; i++) {
        final row = sheet.row(i);
        final excelRowNum = i + 1; // 1-indexed row number in Excel

        String name = row.length > nameCol && row[nameCol]?.value != null
            ? row[nameCol]!.value.toString().trim()
            : '';

        String address = row.length > addressCol && row[addressCol]?.value != null
            ? row[addressCol]!.value.toString().trim()
            : '';

        String contactRaw = row.length > contactCol && row[contactCol]?.value != null
            ? row[contactCol]!.value.toString().trim()
            : '';

        // Split by comma, slash, or pipe
        List<String> contacts = contactRaw
            .split(RegExp(r'[,/|]'))
            .map((c) => c.trim())
            .where((c) => c.isNotEmpty)
            .toList();

        String contact1 = contacts.isNotEmpty ? contacts[0] : '';
        String contact2 = contacts.length > 1 ? contacts[1] : '';

        if (contact2.isEmpty &&
            contact2Col != null &&
            row.length > contact2Col &&
            row[contact2Col]?.value != null) {
          contact2 = row[contact2Col]!.value.toString().trim();
        }

        if (name.isNotEmpty && (contact1.isNotEmpty || contact2.isNotEmpty)) {
          parsedRows.add({
            'name': name,
            'address': address,
            'contact1': contact1,
            'contact2': contact2,
            'row': excelRowNum,
          });
        }
      }

      if (parsedRows.isEmpty) {
        throw Exception("No valid customer data found in Excel.");
      }

      // =========================================================================
      // CHECK 1: INTERNAL DUPLICATES WITHIN THE UPLOADED EXCEL SHEET
      // =========================================================================
      setState(() {
        _loadingMessage = "Checking for duplicates within Excel list...";
      });

      final Map<String, List<ExcelRowCustomerInfo>> internalPhoneMap = {};

      for (final row in parsedRows) {
        final rowName = row['name'] as String;
        final rowNum = row['row'] as int;
        final c1 = row['contact1'] as String;
        final c2 = row['contact2'] as String;

        final norm1 = _normalizePhone(c1);
        final norm2 = _normalizePhone(c2);

        if (norm1.length >= 7) {
          internalPhoneMap.putIfAbsent(norm1, () => []).add(
            ExcelRowCustomerInfo(rowNumber: rowNum, customerName: rowName, rawPhone: c1),
          );
        }

        if (norm2.length >= 7) {
          if (norm2 == norm1) {
            // Same contact repeated in contact1 and contact2
            internalPhoneMap.putIfAbsent(norm2, () => []).add(
              ExcelRowCustomerInfo(rowNumber: rowNum, customerName: '$rowName (Contact 2)', rawPhone: c2),
            );
          } else {
            internalPhoneMap.putIfAbsent(norm2, () => []).add(
              ExcelRowCustomerInfo(rowNumber: rowNum, customerName: rowName, rawPhone: c2),
            );
          }
        }
      }

      final List<InternalExcelDuplicate> internalDuplicates = [];
      internalPhoneMap.forEach((phone, occurrences) {
        if (occurrences.length > 1) {
          internalDuplicates.add(
            InternalExcelDuplicate(phone: phone, occurrences: occurrences),
          );
        }
      });

      // =========================================================================
      // CHECK 2: EXTERNAL DUPLICATES IN HIS BRANCH & OTHER USERS' LISTS
      // =========================================================================
      setState(() {
        _loadingMessage = "Checking for duplicates across calling lists in branch...";
      });

      final usersSnapshot = await FirebaseFirestore.instance
          .collection('customer_target')
          .doc(_selectedMonthYear!)
          .collection('users')
          .get();

      // Build active user lookup from _allUsers
      final Map<String, Map<String, String>> userInfoMap = {};
      for (final u in _allUsers) {
        final email = (u['email'] as String? ?? '').toLowerCase().trim();
        if (email.isNotEmpty) {
          userInfoMap[email] = {
            'name': (u['name'] as String? ?? email).trim(),
            'branch': (u['branch'] as String? ?? '').trim(),
          };
        }
      }

      final Map<String, List<ExistingPhoneRecord>> existingPhoneMap = {};

      for (final doc in usersSnapshot.docs) {
        final data = doc.data();
        final docEmail = (data['user'] ?? doc.id).toString().toLowerCase().trim();
        final docBranch = (data['branch'] ?? userInfoMap[docEmail]?['branch'] ?? 'Unknown').toString().trim();
        final docUsername = userInfoMap[docEmail]?['name'] ?? (data['user'] ?? docEmail).toString();
        final isSelf = docEmail == _selectedUserEmail!.toLowerCase().trim();
        final isSameBranch = docBranch.toLowerCase() == _selectedBranch!.toLowerCase().trim();

        final customersList = data['customers'] as List<dynamic>? ?? [];
        for (final c in customersList) {
          if (c is! Map) continue;
          final cName = (c['name'] ?? 'Unnamed').toString().trim();
          final p1 = _normalizePhone(c['contact1'] ?? c['contact']);
          final p2 = _normalizePhone(c['contact2']);

          if (p1.length >= 7) {
            existingPhoneMap.putIfAbsent(p1, () => []).add(
              ExistingPhoneRecord(
                userEmail: docEmail,
                username: docUsername,
                branch: docBranch,
                customerName: cName,
                isSelf: isSelf,
                isSameBranch: isSameBranch,
              ),
            );
          }
          if (p2.length >= 7 && p2 != p1) {
            existingPhoneMap.putIfAbsent(p2, () => []).add(
              ExistingPhoneRecord(
                userEmail: docEmail,
                username: docUsername,
                branch: docBranch,
                customerName: cName,
                isSelf: isSelf,
                isSameBranch: isSameBranch,
              ),
            );
          }
        }
      }

      final List<ExternalCallingDuplicate> externalDuplicates = [];

      for (final row in parsedRows) {
        final rowName = row['name'] as String;
        final rowNum = row['row'] as int;
        final c1 = row['contact1'] as String;
        final c2 = row['contact2'] as String;
        final norm1 = _normalizePhone(c1);
        final norm2 = _normalizePhone(c2);

        final Set<String> checkedNormsInRow = {};
        for (final norm in [norm1, norm2]) {
          if (norm.length >= 7 && !checkedNormsInRow.contains(norm)) {
            checkedNormsInRow.add(norm);
            final matches = existingPhoneMap[norm];
            if (matches != null && matches.isNotEmpty) {
              for (final m in matches) {
                externalDuplicates.add(
                  ExternalCallingDuplicate(
                    phone: norm,
                    excelCustomerName: rowName,
                    excelRowNumber: rowNum,
                    existingCustomerName: m.customerName,
                    assignedUsername: m.username,
                    assignedUserEmail: m.userEmail,
                    assignedBranch: m.branch,
                    isSameBranch: m.isSameBranch,
                    isSelf: m.isSelf,
                  ),
                );
              }
            }
          }
        }
      }

      // =========================================================================
      // OUTCOME & VALIDATION
      // =========================================================================
      if (internalDuplicates.isNotEmpty || externalDuplicates.isNotEmpty) {
        // STRICTLY PREVENT UPLOADING
        setState(() {
          _customers = null;
          _internalDuplicates = internalDuplicates;
          _externalDuplicates = externalDuplicates;
          _error = "Upload blocked: Duplicates detected. You cannot assign until duplicates are resolved.";
          _success = null;
        });

        if (mounted) {
          _showDuplicateAlertDialog(internalDuplicates.length, externalDuplicates.length);
        }
      } else {
        // All clean - ready to assign!
        final cleanCustomers = parsedRows.map((r) => {
          'name': r['name'],
          'address': r['address'],
          'contact1': r['contact1'],
          'contact2': r['contact2'],
          'remarks': '',
        }).toList();

        setState(() {
          _customers = cleanCustomers;
          _internalDuplicates = [];
          _externalDuplicates = [];
          _error = null;
          _success = "Excel verified! ${cleanCustomers.length} customer(s) ready to assign.";
        });
      }
    } catch (e) {
      setState(() {
        _error = "Failed to import: $e";
        _customers = null;
        _internalDuplicates = [];
        _externalDuplicates = [];
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _assignToFirestore() async {
    if (_customers == null ||
        _customers!.isEmpty ||
        _internalDuplicates.isNotEmpty ||
        _externalDuplicates.isNotEmpty ||
        _selectedBranch == null ||
        _selectedUserEmail == null ||
        _selectedMonthYear == null) {
      setState(() {
        _error = "Upload blocked: Please resolve all duplicates and import a valid Excel file.";
      });
      return;
    }

    setState(() {
      _loading = true;
      _loadingMessage = "Assigning customers to Firestore...";
      _error = null;
      _success = null;
    });

    try {
      final monthYear = _selectedMonthYear!;
      final docRef = FirebaseFirestore.instance
          .collection('customer_target')
          .doc(monthYear)
          .collection('users')
          .doc(_selectedUserEmail!.toLowerCase());

      final importedCustomers = List<Map<String, dynamic>>.from(_customers!);
      int newCount = 0;

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final docSnap = await transaction.get(docRef);

        List<Map<String, dynamic>> existingCustomers = [];
        if (docSnap.exists && docSnap.data()?['customers'] != null) {
          existingCustomers = List<Map<String, dynamic>>.from(
            (docSnap.data()!['customers'] as List)
                .map((e) => Map<String, dynamic>.from(e as Map)),
          );
        }

        // Normalize phone set from existing customers
        final existingPhoneSet = <String>{};
        for (final c in existingCustomers) {
          final p1 = _normalizePhone(c['contact1'] ?? c['contact']);
          final p2 = _normalizePhone(c['contact2']);
          if (p1.length >= 7) existingPhoneSet.add(p1);
          if (p2.length >= 7) existingPhoneSet.add(p2);
        }

        // Only add customers whose phone numbers don't conflict with existing entries
        final newCustomers = <Map<String, dynamic>>[];
        for (final c in importedCustomers) {
          final p1 = _normalizePhone(c['contact1']);
          final p2 = _normalizePhone(c['contact2']);
          final p1Exists = p1.length >= 7 && existingPhoneSet.contains(p1);
          final p2Exists = p2.length >= 7 && existingPhoneSet.contains(p2);

          if (!p1Exists && !p2Exists) {
            newCustomers.add({...c, 'callMade': false});
            if (p1.length >= 7) existingPhoneSet.add(p1);
            if (p2.length >= 7) existingPhoneSet.add(p2);
          }
        }

        newCount = newCustomers.length;
        final updatedCustomers = [...existingCustomers, ...newCustomers];

        transaction.set(docRef, {
          'branch': _selectedBranch,
          'user': _selectedUserEmail!.toLowerCase(),
          'customers': updatedCustomers,
          'updated': FieldValue.serverTimestamp(),
        });
      });

      if (mounted) {
        setState(() {
          _customers = null; // Clear imported list after assigning
          _internalDuplicates = [];
          _externalDuplicates = [];
          _success = "Customer target assigned successfully! $newCount new customer(s) added.";
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = "Failed: $e";
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Widget _buildDuplicateConflictsView() {
    final bool hasInternal = _internalDuplicates.isNotEmpty;
    final bool hasExternal = _externalDuplicates.isNotEmpty;

    if (!hasInternal && !hasExternal) return const SizedBox();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(top: 20),
      decoration: BoxDecoration(
        color: isDark ? Colors.red.shade900.withValues(alpha: 0.15) : Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade300, width: 1.5),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner Header
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.block, color: Colors.red, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Upload Blocked - Duplicates Found',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'You cannot upload or assign this list until duplicate numbers are resolved in your Excel file.',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.grey.shade300 : Colors.red.shade900,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy, color: Colors.red),
                tooltip: 'Copy Report',
                onPressed: _copyDuplicateReport,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // INTERNAL DUPLICATES SECTION
          if (hasInternal) ...[
            Container(
              decoration: BoxDecoration(
                color: isDark ? Colors.grey.shade900 : Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.repeat, color: Colors.red, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Duplicates Within Uploaded Excel (${_internalDuplicates.length})',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'These phone numbers appear more than once in the uploaded Excel sheet:',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const Divider(height: 16),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _internalDuplicates.length,
                    separatorBuilder: (_, __) => const Divider(height: 16),
                    itemBuilder: (context, idx) {
                      final dup = _internalDuplicates[idx];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade100,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '📞 ${dup.phone}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: Colors.red,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${dup.occurrences.length} rows affected',
                                style: const TextStyle(fontSize: 11, color: Colors.grey),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ...dup.occurrences.map(
                            (occ) => Padding(
                              padding: const EdgeInsets.only(left: 12, top: 2),
                              child: Row(
                                children: [
                                  Text(
                                    '• Row ${occ.rowNumber}: ',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      '${occ.customerName} (${occ.rawPhone})',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // EXTERNAL DUPLICATES SECTION
          if (hasExternal) ...[
            Container(
              decoration: BoxDecoration(
                color: isDark ? Colors.grey.shade900 : Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade300),
              ),
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.person_off, color: Colors.deepOrange, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Already Assigned In Calling Lists (${_externalDuplicates.length})',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.deepOrange,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'These phone numbers already exist in calling lists for $_selectedMonthYear:',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const Divider(height: 16),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _externalDuplicates.length,
                    separatorBuilder: (_, __) => const Divider(height: 16),
                    itemBuilder: (context, idx) {
                      final dup = _externalDuplicates[idx];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.orange.shade100,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '📞 ${dup.phone}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: Colors.deepOrange,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: dup.isSameBranch
                                      ? Colors.blue.shade100
                                      : Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  dup.isSelf
                                      ? 'In this user list'
                                      : (dup.isSameBranch ? 'Same Branch: ${dup.assignedBranch}' : 'Branch: ${dup.assignedBranch}'),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: dup.isSameBranch ? Colors.blue.shade900 : Colors.grey.shade800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Text('• Excel File: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                    Expanded(
                                      child: Text(
                                        'Row ${dup.excelRowNumber}: ${dup.excelCustomerName}',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    const Text('• Assigned User: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                    Expanded(
                                      child: Text(
                                        '${dup.assignedUsername} (${dup.assignedUserEmail})',
                                        style: const TextStyle(fontSize: 12, color: Colors.blueAccent),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    const Text('• Existing Customer: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                    Expanded(
                                      child: Text(
                                        dup.existingCustomerName,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _customerPreviewTable() {
    if (_customers == null) return const SizedBox();
    if (_customers!.isEmpty) return const Text('No customers in Excel.');
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Customer Name')),
          DataColumn(label: Text('Address')),
          DataColumn(label: Text('Contact No. 1')),
          DataColumn(label: Text('Contact No. 2')),
        ],
        rows: _customers!
            .map((customer) => DataRow(
                  cells: [
                    DataCell(Text(customer['name'] ?? '')),
                    DataCell(Text(customer['address'] ?? '')),
                    DataCell(Text(customer['contact1'] ?? '')),
                    DataCell(Text(customer['contact2'] ?? '')),
                  ],
                ))
            .toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool canAssign = _customers != null &&
        _customers!.isNotEmpty &&
        _internalDuplicates.isEmpty &&
        _externalDuplicates.isEmpty &&
        _selectedBranch != null &&
        _selectedUserEmail != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Assign Customer Target'),
        actions: [
          if (_internalDuplicates.isNotEmpty || _externalDuplicates.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.copy),
              tooltip: 'Copy Conflict Report',
              onPressed: _copyDuplicateReport,
            ),
        ],
      ),
      body: _loading
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    _loadingMessage.isNotEmpty ? _loadingMessage : 'Processing...',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Month Dropdown
                  DropdownButtonFormField<String>(
                    initialValue: _selectedMonthYear,
                    decoration: const InputDecoration(
                      labelText: 'Target Month',
                      border: OutlineInputBorder(),
                    ),
                    items: _monthYears
                        .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                        .toList(),
                    onChanged: (val) {
                      setState(() {
                        _selectedMonthYear = val;
                        _resetImportState();
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  // Branch Dropdown
                  DropdownButtonFormField<String>(
                    initialValue: _branches.contains(_selectedBranch) ? _selectedBranch : null,
                    decoration: const InputDecoration(
                      labelText: 'Branch',
                      border: OutlineInputBorder(),
                    ),
                    items: _branches.isNotEmpty
                        ? _branches
                            .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                            .toList()
                        : [
                            const DropdownMenuItem(
                              value: null,
                              child: Text('No branches found'),
                            ),
                          ],
                    onChanged: (val) {
                      setState(() {
                        _selectedBranch = val;
                        _selectedUserEmail = null;
                        _users = [];
                        _resetImportState();
                      });
                      if (val != null) _filterUsersForBranch(val);
                    },
                  ),
                  const SizedBox(height: 16),
                  // User Dropdown
                  DropdownButtonFormField<String>(
                    initialValue: _users.any((u) => u['email'] == _selectedUserEmail) ? _selectedUserEmail : null,
                    decoration: const InputDecoration(
                      labelText: 'User',
                      border: OutlineInputBorder(),
                    ),
                    items: _users.isNotEmpty
                        ? _users
                            .map((u) => DropdownMenuItem<String>(
                                  value: u['email'] as String,
                                  child: Text('${u['name']} (${u['email']})'),
                                ))
                            .toList()
                        : [
                            const DropdownMenuItem(
                              value: null,
                              child: Text('No users found'),
                            ),
                          ],
                    onChanged: (val) {
                      setState(() {
                        _selectedUserEmail = val;
                        _resetImportState();
                      });
                    },
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.upload_file),
                          label: const Text('Import Excel'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: _importExcel,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.assignment_turned_in),
                          label: const Text('Assign'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            backgroundColor: canAssign ? Colors.green.shade700 : null,
                            foregroundColor: canAssign ? Colors.white : null,
                          ),
                          onPressed: canAssign ? _assignToFirestore : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Error and Success Messages
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (_success != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_outline, color: Colors.green),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _success!,
                              style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _customerPreviewTable(),
                  ],

                  // Duplicates conflict widget
                  _buildDuplicateConflictsView(),
                ],
              ),
            ),
    );
  }
}