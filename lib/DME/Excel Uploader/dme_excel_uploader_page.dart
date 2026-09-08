import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../dme_config.dart';
import 'excel_uploader_models.dart';
import 'excel_parsing_service.dart';
import 'excel_upload_service.dart';
import 'missing_phone_dialog.dart';
import 'phone_conflict_dialog.dart';
import 'customer_preview_section.dart';

export 'excel_uploader_models.dart';

class DmeExcelUploaderPage extends StatefulWidget {
  const DmeExcelUploaderPage({super.key});

  @override
  State<DmeExcelUploaderPage> createState() => _DmeExcelUploaderPageState();
}

class _DmeExcelUploaderPageState extends State<DmeExcelUploaderPage> with SingleTickerProviderStateMixin {
  String? _selectedFileName;
  Uint8List? _fileBytes;
  bool _isParsing = false;
  bool _isUploading = false;
  double _uploadProgress = 0.0;
  String _statusMessage = '';

  List<ParsedExcelRow> _parsedRows = [];
  List<GroupedSale> _groupedSales = [];
  List<ParsedCustomerItem> _customerList = [];
  List<CustomerConflict> _conflicts = [];
  List<MissingPhoneCustomer> _missingPhones = [];
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
      setState(() {
        _selectedFileName = file.name;
        _fileBytes = file.bytes;
        _parsedRows.clear();
        _groupedSales.clear();
        _customerList.clear();
        _conflicts.clear();
        _logs.clear();
        _statusMessage = 'File selected: ${file.name}';
      });

      if (_fileBytes != null) {
        await _parseExcel(_fileBytes!);
      } else if (file.path != null) {
        final bytes = await File(file.path!).readAsBytes();
        await _parseExcel(bytes);
      }
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

  /// Groups by phone number and queries Supabase + checks Excel within itself for repeated phones
  Future<void> _analyzeCustomerList() async {
    final client = _supabaseClient;

    setState(() {
      _isParsing = true;
      _statusMessage = 'Checking duplicate phone numbers & database records...';
    });

    try {
      final List<ParsedCustomerItem> customerItems = [];
      final List<CustomerConflict> detectedConflicts = [];
      final List<MissingPhoneCustomer> detectedMissingPhones = [];
      final Map<String, dynamic> dbCache = {};
      final Map<String, String> excelPhonePartyMap = {}; // phone -> first party seen in this excel

      for (var sale in _groupedSales) {
        bool isExisting = false;
        String? existingDbName;
        int? existingDbId;

        if (sale.phone.isEmpty) {
          if (!detectedMissingPhones.any((m) => m.partyName.toLowerCase() == sale.party.toLowerCase() && m.branchName == sale.branchName)) {
            detectedMissingPhones.add(MissingPhoneCustomer(
              partyName: sale.party,
              branchName: sale.branchName,
              voucherNo: sale.voucherNo,
              address: sale.address,
              salesman: sale.salesman,
              categoryName: sale.categoryName,
              typeName: sale.typeName,
              date: sale.date,
            ));
          }
        } else {
          // 1. Check if same phone is repeated within the same Excel with different party names
          if (excelPhonePartyMap.containsKey(sale.phone)) {
            final firstPartyInExcel = excelPhonePartyMap[sale.phone]!;
            if (firstPartyInExcel.toLowerCase() != sale.party.toLowerCase()) {
              if (!detectedConflicts.any((c) => c.originalPhone == sale.phone && c.newName == sale.party)) {
                detectedConflicts.add(CustomerConflict(
                  originalPhone: sale.phone,
                  existingName: '$firstPartyInExcel (in Excel)',
                  existingCustomerId: null,
                  isFromDatabase: false,
                  newName: sale.party,
                  newAddress: sale.address,
                  newSalesman: sale.salesman,
                ));
              }
            }
          } else {
            excelPhonePartyMap[sale.phone] = sale.party;
          }

          // 2. Check with Supabase database for existing record
          if (client != null && DmeConfig.isConfigured) {
            try {
              if (dbCache.containsKey(sale.phone)) {
                final res = dbCache[sale.phone];
                if (res != null) {
                  isExisting = true;
                  existingDbId = res['id'] as int?;
                  existingDbName = (res['name'] ?? '').toString().trim();
                }
              } else {
                final res = await client
                    .from('dme_customers')
                    .select('id, name, phone, address, salesman')
                    .eq('phone', sale.phone)
                    .maybeSingle();

                dbCache[sale.phone] = res;

                if (res != null) {
                  isExisting = true;
                  existingDbId = res['id'] as int?;
                  existingDbName = (res['name'] ?? '').toString().trim();

                  if (existingDbName.isNotEmpty &&
                      sale.party.isNotEmpty &&
                      existingDbName.toLowerCase() != sale.party.toLowerCase()) {
                    if (!detectedConflicts.any((c) => c.originalPhone == sale.phone)) {
                      detectedConflicts.add(CustomerConflict(
                        originalPhone: sale.phone,
                        existingName: existingDbName,
                        existingCustomerId: existingDbId,
                        isFromDatabase: true,
                        newName: sale.party,
                        newAddress: sale.address,
                        newSalesman: sale.salesman,
                      ));
                    }
                  }
                }
              }
            } catch (dbErr) {
              debugPrint('DB lookup failed for phone ${sale.phone}: $dbErr');
            }
          }
        }

        customerItems.add(ParsedCustomerItem(
          phone: sale.phone.isNotEmpty ? sale.phone : 'Missing Phone',
          partyName: sale.party.isNotEmpty ? sale.party : 'Unnamed Party',
          address: sale.address,
          branchName: sale.branchName,
          salesman: sale.salesman,
          categoryName: sale.categoryName,
          typeName: sale.typeName,
          totalSalesCount: 1,
          totalItemsCount: sale.products.length,
          isExisting: isExisting,
          existingDbName: existingDbName,
          existingDbId: existingDbId,
          resolution: detectedConflicts.any((c) => c.originalPhone == sale.phone)
              ? ConflictResolution.keepExisting
              : null,
        ));
      }

      setState(() {
        _customerList = customerItems;
        _conflicts = detectedConflicts;
        _missingPhones = detectedMissingPhones;
        _isParsing = false;
        if (_missingPhones.isNotEmpty) {
          _statusMessage = 'Found ${_missingPhones.length} customer(s) with missing phone number. Please enter phone numbers before uploading.';
        } else if (_conflicts.isNotEmpty) {
          _statusMessage = 'Found ${_conflicts.length} duplicate/conflict phone number(s). Review choices below.';
        } else {
          _statusMessage = 'Found ${_groupedSales.length} sale(s): ${_customerList.where((c) => !c.isExisting).length} New, ${_customerList.where((c) => c.isExisting).length} Existing.';
        }
      });

      if (_missingPhones.isNotEmpty && mounted) {
        await _showMissingPhoneDialog();
      } else if (_conflicts.isNotEmpty && mounted) {
        await _showConflictDialog();
      }
    } catch (e) {
      setState(() {
        _isParsing = false;
        _statusMessage = 'Could not verify database status: $e';
      });
    }
  }

  /// Dialog requiring the user to enter a phone number for customers without one
  Future<void> _showMissingPhoneDialog() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => MissingPhoneDialog(
        missingPhones: _missingPhones,
        groupedSales: _groupedSales,
        parsedRows: _parsedRows,
        customerList: _customerList,
        onCompleted: () {
          setState(() {});
          if (_conflicts.isNotEmpty && mounted) {
            _showConflictDialog();
          }
        },
      ),
    );
  }

  /// Dialog allowing the user to choose which customer to keep or change phone number
  Future<void> _showConflictDialog() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PhoneConflictDialog(
        conflicts: _conflicts,
        onApplied: () {
          setState(() {});
        },
      ),
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

    // STRICT CHECK: Ensure no customer has a missing phone number before uploading
    final missingPhoneSales = _groupedSales.where((s) => s.phone.trim().isEmpty).toList();
    if (missingPhoneSales.isNotEmpty || _missingPhones.isNotEmpty) {
      if (_missingPhones.isEmpty) {
        for (var s in missingPhoneSales) {
          if (!_missingPhones.any((m) => m.partyName.toLowerCase() == s.party.toLowerCase() && m.branchName == s.branchName)) {
            _missingPhones.add(MissingPhoneCustomer(
              partyName: s.party,
              branchName: s.branchName,
              voucherNo: s.voucherNo,
              address: s.address,
              salesman: s.salesman,
              categoryName: s.categoryName,
              typeName: s.typeName,
              date: s.date,
            ));
          }
        }
      }
      _showSnackBar('Please fill in missing phone numbers before uploading.', isError: true);
      await _showMissingPhoneDialog();
      return;
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
          if (_conflicts.isNotEmpty)
            IconButton(
              icon: Badge(
                label: Text('${_conflicts.length}'),
                child: const Icon(Icons.warning_amber_rounded),
              ),
              tooltip: 'Review Duplicates',
              onPressed: _showConflictDialog,
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
                          if (_conflicts.isNotEmpty)
                            _buildStatItem(
                              'Conflicts',
                              '${_conflicts.length}',
                              Icons.warning_amber,
                              color: Colors.orange,
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: (_isUploading || _isParsing) ? null : _startUpload,
                          icon: const Icon(Icons.cloud_upload),
                          label: Text('Upload ${_groupedSales.length} Sales to Supabase'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF8CC63F),
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
                onResolveConflictsPressed: _showConflictDialog,
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
