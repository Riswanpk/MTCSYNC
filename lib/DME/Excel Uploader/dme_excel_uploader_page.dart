import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:crypto/crypto.dart';

import '../Misc/dme_config.dart';
import '../Misc/dme_constants.dart';
import 'excel_uploader_models.dart';
import 'excel_parsing_service.dart';
import 'excel_upload_service.dart';
import 'customer_preview_section.dart';

export 'excel_uploader_models.dart';

class DmeExcelUploaderPage extends StatefulWidget {
  const DmeExcelUploaderPage({super.key});

  @override
  State<DmeExcelUploaderPage> createState() => _DmeExcelUploaderPageState();
}

class _DmeExcelUploaderPageState extends State<DmeExcelUploaderPage> with SingleTickerProviderStateMixin {
  String? _selectedFileName;
  String? _fileHash;
  bool _isParsing = false;
  bool _isUploading = false;
  double _uploadProgress = 0.0;
  String _statusMessage = '';

  List<ParsedExcelRow> _parsedRows = [];
  List<GroupedSale> _groupedSales = [];
  List<ParsedCustomerItem> _customerList = [];
  List<CustomerConflict> _conflicts = [];
  List<MissingPhoneCustomer> _missingPhones = [];
  List<MissingBranchSale> _missingBranches = [];
  List<ExcelConflictItem> _excelConflicts = [];
  final List<String> _logs = [];

  String _customerFilter = 'all'; // 'all', 'new', 'existing', 'conflict'
  String _customerSearch = '';

  SupabaseClient? get _supabaseClient {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _initSupabaseIfNeeded();
  }

  Future<void> _initSupabaseIfNeeded() async {
    if (!DmeConfig.isConfigured) return;
    try {
      Supabase.instance.client;
    } catch (_) {
      await Supabase.initialize(
        url: DmeConfig.supabaseUrl,
        anonKey: DmeConfig.supabaseAnonKey,
      );
    }
  }

  /// Pick and process the Excel file
  Future<void> _pickExcelFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      Uint8List? pickedBytes = file.bytes;
      if (pickedBytes == null && file.path != null) {
        pickedBytes = await File(file.path!).readAsBytes();
      }

      if (pickedBytes == null) {
        _showSnackBar('Could not read file data', isError: true);
        return;
      }

      // Calculate SHA-256 hash of file content to detect duplicate uploads
      final hash = sha256.convert(pickedBytes).toString();

      // Check if this exact file was already uploaded to Supabase
      final client = _supabaseClient;
      if (client != null && DmeConfig.isConfigured) {
        final existingUpload = await ExcelUploadService.checkDuplicateFile(
          client: client,
          fileHash: hash,
        );

        if (existingUpload != null) {
          if (!mounted) return;
          final uploadedAtStr = existingUpload['uploaded_at']?.toString();
          String formattedDate = uploadedAtStr ?? 'a previous session';
          if (uploadedAtStr != null) {
            final parsedDt = DateTime.tryParse(uploadedAtStr);
            if (parsedDt != null) {
              formattedDate = DateFormat('dd MMM yyyy, hh:mm a').format(parsedDt);
            }
          }
          final uploader = existingUpload['uploaded_by'] ?? 'another user';
          final originalName = existingUpload['file_name'] ?? file.name;

          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text('Duplicate File Detected'),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'This exact Excel file has already been uploaded and processed into the database.',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('• File Name: $originalName', style: const TextStyle(fontSize: 13)),
                        const SizedBox(height: 4),
                        Text('• Uploaded At: $formattedDate', style: const TextStyle(fontSize: 13)),
                        const SizedBox(height: 4),
                        Text('• Uploaded By: $uploader', style: const TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'To prevent duplicate sales and inaccurate reminder schedules, re-uploading the same file is blocked.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
              actions: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade700,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
          return;
        }
      }

      setState(() {
        _selectedFileName = file.name;
        _fileHash = hash;
        _parsedRows.clear();
        _groupedSales.clear();
        _customerList.clear();
        _conflicts.clear();
        _missingPhones.clear();
        _missingBranches.clear();
        _excelConflicts.clear();
        _logs.clear();
        _statusMessage = 'File selected: ${file.name}';
      });

      await _parseExcel(pickedBytes);
    } catch (e) {
      _showSnackBar('Error picking file: $e', isError: true);
    }
  }

  /// Parses the Excel file and groups continuous items into sales
  Future<void> _parseExcel(Uint8List bytes) async {
    setState(() {
      _isParsing = true;
      _statusMessage = 'Reading and parsing Excel data...';
    });

    try {
      final result = ExcelParsingService.parseExcelBytes(bytes);
      final List<ParsedExcelRow> parsed = result['parsedRows'] as List<ParsedExcelRow>;
      final List<GroupedSale> groupedList = result['groupedSales'] as List<GroupedSale>;

      setState(() {
        _parsedRows = parsed;
        _groupedSales = groupedList;
      });

      // Analyze and Build Customer List and detect duplicates & database conflicts
      await _analyzeCustomerList();
    } catch (e) {
      setState(() {
        _isParsing = false;
        _statusMessage = 'Error parsing file: $e';
      });
      _showSnackBar('Parsing error: $e', isError: true);
    }
  }

  /// Groups by phone number, checks missing phones & branches, queries database for existing records & applies the PREMIUM rule
  Future<void> _analyzeCustomerList() async {
    final client = _supabaseClient;

    setState(() {
      _isParsing = true;
      _statusMessage = 'Checking phone numbers, branches & customer records...';
    });

    try {
      final List<ParsedCustomerItem> customerItems = [];
      final List<ExcelConflictItem> detectedConflicts = [];
      final Map<String, dynamic> dbCache = {};
      final Set<String> premiumPhones = {};

      // 1. First pass: Collect unique valid phones and Excel PREMIUM customer types
      for (var sale in _groupedSales) {
        if (ExcelParsingService.isIgnoredParty(sale.party)) continue;

        final cleanPh = ExcelParsingService.cleanPhoneNumber(sale.phone);
        final isExcelPremium = sale.typeId == 1 || sale.typeName.trim().toUpperCase() == 'PREMIUM';
        if (isExcelPremium && cleanPh.length == 10) {
          premiumPhones.add(cleanPh);
        }
      }

      // 2. Query Supabase for existing customers (chunked) to check DB PREMIUM status and customer names
      final uniquePhones = _groupedSales
          .where((s) => !ExcelParsingService.isIgnoredParty(s.party))
          .map((s) => ExcelParsingService.cleanPhoneNumber(s.phone))
          .where((p) => p.length == 10)
          .toSet()
          .toList();

      final Map<String, int> phoneToDbCustomerId = {};

      if (client != null && DmeConfig.isConfigured && uniquePhones.isNotEmpty) {
        for (int i = 0; i < uniquePhones.length; i += 500) {
          final chunk = uniquePhones.sublist(
            i,
            (i + 500 > uniquePhones.length) ? uniquePhones.length : i + 500,
          );
          try {
            final res = await client
                .from('dme_customers')
                .select('id, name, phone, address, salesman')
                .inFilter('phone', chunk);

            for (var row in (res as List)) {
              final ph = row['phone']?.toString();
              final id = row['id'] as int?;
              if (ph != null) {
                dbCache[ph] = row;
                if (id != null) phoneToDbCustomerId[ph] = id;
              }
            }
          } catch (dbErr) {
            debugPrint('DB lookup failed for customer chunk: $dbErr');
          }
        }

        // Check if any existing customer has customer_type_id = 1 (PREMIUM) in dme_customer_branches or dme_sales
        final existingCustIds = phoneToDbCustomerId.values.toSet().toList();
        if (existingCustIds.isNotEmpty) {
          for (int i = 0; i < existingCustIds.length; i += 500) {
            final chunk = existingCustIds.sublist(
              i,
              (i + 500 > existingCustIds.length) ? existingCustIds.length : i + 500,
            );
            try {
              final brRes = await client
                  .from('dme_customer_branches')
                  .select('customer_id')
                  .inFilter('customer_id', chunk)
                  .eq('customer_type_id', 1);

              for (var row in (brRes as List)) {
                final id = row['customer_id'] as int?;
                if (id != null) {
                  final ph = phoneToDbCustomerId.entries.firstWhere((e) => e.value == id, orElse: () => const MapEntry('', 0)).key;
                  if (ph.isNotEmpty) premiumPhones.add(ph);
                }
              }
            } catch (e) {
              debugPrint('Check premium in dme_customer_branches failed: $e');
            }

            try {
              final slRes = await client
                  .from('dme_sales')
                  .select('customer_id')
                  .inFilter('customer_id', chunk)
                  .eq('customer_type_id', 1);

              for (var row in (slRes as List)) {
                final id = row['customer_id'] as int?;
                if (id != null) {
                  final ph = phoneToDbCustomerId.entries.firstWhere((e) => e.value == id, orElse: () => const MapEntry('', 0)).key;
                  if (ph.isNotEmpty) premiumPhones.add(ph);
                }
              }
            } catch (e) {
              debugPrint('Check premium in dme_sales failed: $e');
            }
          }
        }
      }

      // 3. Enforce PREMIUM customer rule across all grouped sales and parsed rows:
      // "premium customers will always be premium, when uploading just check that if it has premium and if it has then change to premium from whatever customer type it has in excel."
      if (premiumPhones.isNotEmpty) {
        for (var sale in _groupedSales) {
          if (premiumPhones.contains(sale.phone)) {
            sale.typeId = 1;
            sale.typeName = 'PREMIUM';
          }
        }
        for (var row in _parsedRows) {
          if (premiumPhones.contains(row.phone)) {
            row.typeId = 1;
            row.typeName = 'PREMIUM';
          }
        }
      }

      // 4. Comprehensive conflict detection & build preview customer list:
      // Rule: "if a party name is missing and that customer is an existing one then dont just take the database name, show conflict and tell user to reupload with name"
      for (var sale in _groupedSales) {
        if (ExcelParsingService.isIgnoredParty(sale.party)) continue;

        final List<String> issues = [];

        // Phone number check: missing, less than 10 digits, or more than 10 digits
        final cleanPh = ExcelParsingService.cleanPhoneNumber(sale.phone);
        if (cleanPh.isEmpty) {
          issues.add('Missing phone number');
        } else if (cleanPh.length < 10) {
          issues.add('Phone has less than 10 digits (${cleanPh.length} digits: $cleanPh)');
        } else if (cleanPh.length > 10) {
          issues.add('Phone has more than 10 digits (${cleanPh.length} digits: $cleanPh)');
        }

        // Existing customer lookup
        bool isExisting = false;
        String? existingDbName;
        int? existingDbId;

        if (cleanPh.isNotEmpty && dbCache.containsKey(cleanPh)) {
          final res = dbCache[cleanPh];
          if (res != null) {
            isExisting = true;
            existingDbId = res['id'] as int?;
            existingDbName = (res['name'] ?? '').toString().trim();
          }
        }

        // Party Name check
        final isPartyMissing = sale.party.trim().isEmpty ||
            sale.party.trim().toLowerCase() == 'unnamed party' ||
            sale.party.trim().toLowerCase() == 'null';

        if (isPartyMissing) {
          if (isExisting && existingDbName != null && existingDbName.isNotEmpty) {
            issues.add('Missing party name in Excel (Existing DB customer: "$existingDbName"). Please reupload with name.');
          } else {
            issues.add('Missing party name in Excel');
          }
        }

        // Category check
        if (sale.categoryName.trim().isEmpty || sale.categoryId == null || sale.categoryName.trim().toLowerCase() == 'null') {
          issues.add('Missing category');
        }

        // Customer Type check
        if (sale.typeName.trim().isEmpty || sale.typeId == null || sale.typeName.trim().toLowerCase() == 'null') {
          issues.add('Missing customer type');
        }

        // Salesman check
        if (sale.salesman.trim().isEmpty || sale.salesman.trim().toLowerCase() == 'null') {
          issues.add('Missing salesman');
        }

        // Branch check
        final isBranchValid = sale.branchName.trim().isNotEmpty &&
            sale.branchId != null &&
            DmeConstants.getBranchIdByName(sale.branchName) != null;
        if (!isBranchValid) {
          issues.add('Missing or invalid branch ("${sale.branchName}")');
        }

        if (issues.isNotEmpty) {
          detectedConflicts.add(ExcelConflictItem(
            partyName: sale.party.isNotEmpty
                ? sale.party
                : (isExisting && existingDbName != null && existingDbName.isNotEmpty
                    ? '[Missing in Excel] (DB: $existingDbName)'
                    : '[Missing Party Name]'),
            voucherNo: sale.voucherNo,
            branchName: sale.branchName.isNotEmpty ? sale.branchName : 'Unknown Branch',
            phone: cleanPh,
            issues: issues,
          ));
        }

        final isPremium = premiumPhones.contains(sale.phone);
        final effectiveTypeName = isPremium ? 'PREMIUM' : sale.typeName;

        customerItems.add(ParsedCustomerItem(
          phone: sale.phone.isNotEmpty ? sale.phone : 'Missing Phone',
          partyName: sale.party.isNotEmpty
              ? sale.party
              : (isExisting && existingDbName != null && existingDbName.isNotEmpty
                  ? '[Missing in Excel] (DB: $existingDbName)'
                  : 'Unnamed Party'),
          address: sale.address,
          branchName: sale.branchName.isNotEmpty ? sale.branchName : 'Unknown Branch',
          salesman: sale.salesman,
          categoryName: sale.categoryName,
          typeName: effectiveTypeName,
          totalSalesCount: 1,
          totalItemsCount: sale.products.length,
          isExisting: isExisting,
          existingDbName: existingDbName,
          existingDbId: existingDbId,
        ));
      }

      setState(() {
        _customerList = customerItems;
        _conflicts = []; // Name differences are automatically taken from Excel without asking user
        _excelConflicts = detectedConflicts;
        _missingPhones = [];
        _missingBranches = [];
        _isParsing = false;
        if (_excelConflicts.isNotEmpty) {
          _statusMessage = 'Found ${_excelConflicts.length} conflict(s). Please message branch to update excel and reupload.';
        } else {
          _statusMessage = 'Found ${_groupedSales.length} sale(s): ${_customerList.where((c) => !c.isExisting).length} New, ${_customerList.where((c) => c.isExisting).length} Existing.';
        }
      });

      // Show conflict popup if any conflicts detected
      if (_excelConflicts.isNotEmpty && mounted) {
        await _showConflictsDialog();
      }
    } catch (e) {
      setState(() {
        _isParsing = false;
        _statusMessage = 'Could not verify database status: $e';
      });
    }
  }

  /// Dialog displaying all detected conflicts with strict instruction to edit Excel and reupload
  Future<void> _showConflictsDialog() async {
    if (!mounted || _excelConflicts.isEmpty) return;

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 24),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Excel Conflicts Detected',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Please message branch to update excel and reupload',
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Found ${_excelConflicts.length} conflict(s). Manual entry is disabled. All missing or invalid fields must be corrected in the Excel file by the branch before uploading.',
                        style: TextStyle(fontSize: 12, color: Colors.grey[800]),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Conflicts List (${_excelConflicts.length}):',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _excelConflicts.length,
                    separatorBuilder: (_, __) => const Divider(height: 16),
                    itemBuilder: (context, idx) {
                      final c = _excelConflicts[idx];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  c.partyName,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ),
                              if (c.voucherNo.isNotEmpty) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    c.voucherNo,
                                    style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
                                  ),
                                ),
                                const SizedBox(width: 4),
                              ],
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF005BAC).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  c.branchName,
                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF005BAC)),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: c.issues.map((issue) {
                              final isPhone = issue.toLowerCase().contains('phone');
                              return Container(
                                constraints: const BoxConstraints(maxWidth: 480),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: isPhone
                                      ? Colors.red.withValues(alpha: 0.12)
                                      : Colors.orange.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: isPhone ? Colors.red.shade300 : Colors.orange.shade300,
                                    width: 0.8,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Icon(
                                        Icons.close_rounded,
                                        size: 12,
                                        color: isPhone ? Colors.red[800] : Colors.orange[900],
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        issue,
                                        softWrap: true,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: isPhone ? Colors.red[800] : Colors.orange[900],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  /// Uploads all processed data to Supabase in fast batch operations
  Future<void> _startUpload() async {
    final client = _supabaseClient;
    if (client == null || !DmeConfig.isConfigured) {
      _showConfigDialog();
      return;
    }

    if (_groupedSales.isEmpty) {
      _showSnackBar('No sales to upload', isError: true);
      return;
    }

    // STRICT CHECK: Ensure zero conflicts exist before uploading
    if (_excelConflicts.isNotEmpty) {
      _showSnackBar('Please message branch to update excel and reupload', isError: true);
      await _showConflictsDialog();
      return;
    }

    // Check duplicate file right before upload begins
    if (_fileHash != null) {
      final existingUpload = await ExcelUploadService.checkDuplicateFile(
        client: client,
        fileHash: _fileHash!,
      );
      if (existingUpload != null) {
        final uploadedAtStr = existingUpload['uploaded_at']?.toString();
        String formattedDate = uploadedAtStr ?? 'a previous session';
        if (uploadedAtStr != null) {
          final parsedDt = DateTime.tryParse(uploadedAtStr);
          if (parsedDt != null) {
            formattedDate = DateFormat('dd MMM yyyy, hh:mm a').format(parsedDt);
          }
        }
        final uploader = existingUpload['uploaded_by'] ?? 'another user';
        final originalName = existingUpload['file_name'] ?? _selectedFileName ?? 'this file';

        if (mounted) {
          _showSnackBar('Duplicate file: already uploaded on $formattedDate', isError: true);
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text('Duplicate File Detected'),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'This exact Excel file has already been uploaded and processed into the database.',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('• File Name: $originalName', style: const TextStyle(fontSize: 13)),
                        const SizedBox(height: 4),
                        Text('• Uploaded At: $formattedDate', style: const TextStyle(fontSize: 13)),
                        const SizedBox(height: 4),
                        Text('• Uploaded By: $uploader', style: const TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'To prevent duplicate sales and inaccurate reminder schedules, re-uploading the same file is blocked.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
              actions: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade700,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
        return;
      }
    }

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.1;
      _logs.clear();
      _statusMessage = 'Preparing batch upload...';
    });

    try {
      final insertedCount = await ExcelUploadService.uploadSales(
        client: client,
        groupedSales: _groupedSales,
        conflicts: _conflicts,
        fileName: _selectedFileName,
        fileHash: _fileHash,
        rowsCount: _parsedRows.length,
        onProgress: (progress, status) {
          if (mounted) {
            setState(() {
              _uploadProgress = progress;
              _statusMessage = status;
            });
          }
        },
        onLog: (log) {
          if (mounted) _addLog(log);
        },
      );

      if (!mounted) return;
      setState(() {
        _uploadProgress = 1.0;
        _isUploading = false;
        _statusMessage = 'Upload completed: $insertedCount sales uploaded successfully!';
      });

      _showSummaryDialog(insertedCount, 0);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isUploading = false;
        _statusMessage = 'Batch upload failed: $e';
      });
      _addLog('✗ Batch upload error: $e');
      _showSnackBar('Upload error: $e', isError: true);
    }
  }

  void _addLog(String msg) {
    if (!mounted) return;
    setState(() {
      _logs.add('[${DateFormat('HH:mm:ss').format(DateTime.now())}] $msg');
    });
  }

  void _showSnackBar(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red[700] : Colors.green[700],
      ),
    );
  }

  void _showConfigDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supabase Not Configured'),
        content: const Text(
          'Please set your Supabase URL and Anon Key in `lib/DME/dme_config.dart` before uploading.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showSummaryDialog(int success, int errors) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              errors == 0 ? Icons.check_circle : Icons.info,
              color: errors == 0 ? Colors.green : Colors.orange,
            ),
            const SizedBox(width: 8),
            const Text('Upload Summary'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Successfully synced: $success sales'),
            if (errors > 0) Text('Failed to sync: $errors sales', style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            Text(
              'All matched branch IDs, categories, customer types, and item details have been saved to Supabase.',
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('DME Excel Sales Uploader'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
        actions: [
          if (_excelConflicts.isNotEmpty)
            IconButton(
              icon: Badge(
                label: Text('${_excelConflicts.length}'),
                child: const Icon(Icons.warning_amber_rounded),
              ),
              tooltip: 'Excel Conflicts',
              onPressed: _showConflictsDialog,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Pick File Card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    ElevatedButton.icon(
                      onPressed: (_isParsing || _isUploading) ? null : _pickExcelFile,
                      icon: const Icon(Icons.file_upload),
                      label: Text(_selectedFileName == null ? 'Select Excel File' : 'Change Excel File'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF005BAC),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    if (_selectedFileName != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        'File: $_selectedFileName',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                    if (_isParsing) ...[
                      const SizedBox(height: 16),
                      const LinearProgressIndicator(),
                      const SizedBox(height: 8),
                      Text(_statusMessage, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Parsed Statistics Card
            if (_parsedRows.isNotEmpty) ...[
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Upload Overview',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildStatItem('Total Rows', '${_parsedRows.length}', Icons.list_alt),
                          _buildStatItem('Sales', '${_groupedSales.length}', Icons.receipt_long),
                          _buildStatItem(
                            'New',
                            '${_customerList.where((c) => !c.isExisting).length}',
                            Icons.person_add,
                            color: Colors.green,
                          ),
                          _buildStatItem(
                            'Existing',
                            '${_customerList.where((c) => c.isExisting).length}',
                            Icons.how_to_reg,
                            color: Colors.blue,
                          ),
                          if (_excelConflicts.isNotEmpty)
                            _buildStatItem(
                              'Conflicts',
                              '${_excelConflicts.length}',
                              Icons.error_outline_rounded,
                              color: Colors.red,
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (_excelConflicts.isNotEmpty) ...[
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.red.shade300, width: 1.2),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.error_outline_rounded, color: Colors.red, size: 22),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Please message branch to update excel and reupload',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: Colors.red,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Found ${_excelConflicts.length} conflict(s) across transactions (e.g. missing or invalid phone number, missing category, type, salesman, branch, or party name). Manual entry is disabled.',
                                style: TextStyle(fontSize: 12, color: Colors.grey[800]),
                              ),
                              const SizedBox(height: 10),
                              ElevatedButton.icon(
                                onPressed: _showConflictsDialog,
                                icon: const Icon(Icons.visibility_rounded, size: 16),
                                label: Text('View ${_excelConflicts.length} Conflict(s)'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red.shade700,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: (_isUploading || _isParsing || _excelConflicts.isNotEmpty) ? null : _startUpload,
                          icon: const Icon(Icons.cloud_upload),
                          label: Text(_excelConflicts.isNotEmpty
                              ? 'Upload Blocked (${_excelConflicts.length} Conflicts)'
                              : 'Upload ${_groupedSales.length} Sales to Supabase'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _excelConflicts.isNotEmpty ? Colors.grey : const Color(0xFF8CC63F),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Customer Preview Section
              CustomerPreviewSection(
                customerList: _customerList,
                conflicts: _conflicts,
                customerFilter: _customerFilter,
                customerSearch: _customerSearch,
                onFilterChanged: (filter) => setState(() => _customerFilter = filter),
                onSearchChanged: (val) => setState(() => _customerSearch = val),
                onResolveConflictsPressed: () {},
              ),
              const SizedBox(height: 16),
            ],

            // Upload Progress & Logs
            if (_isUploading || _logs.isNotEmpty) ...[
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Upload Progress', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                          Text('${(_uploadProgress * 100).toStringAsFixed(0)}%'),
                        ],
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: _uploadProgress,
                        backgroundColor: Colors.grey[200],
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF8CC63F)),
                      ),
                      const SizedBox(height: 8),
                      Text(_statusMessage, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                      const Divider(height: 24),
                      Text('Activity Logs', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Container(
                        height: 200,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.grey[900] : Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                        ),
                        child: ListView.builder(
                          reverse: true,
                          itemCount: _logs.length,
                          itemBuilder: (context, idx) {
                            final log = _logs[_logs.length - 1 - idx];
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2.0),
                              child: Text(
                                log,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                  color: log.contains('✗')
                                      ? Colors.red
                                      : log.contains('✓')
                                          ? Colors.green
                                          : (isDark ? Colors.white70 : Colors.black87),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, {Color? color}) {
    return Column(
      children: [
        Icon(icon, color: color ?? const Color(0xFF005BAC), size: 26),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color ?? const Color(0xFF005BAC),
          ),
        ),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }
}
