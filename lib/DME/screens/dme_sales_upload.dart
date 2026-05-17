import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async' show unawaited;
import '../dme_config.dart';
import '../services/dme_excel_parser.dart';
import '../services/dme_supabase_service.dart';
import '../models/dme_sale.dart';
import '../models/dme_customer.dart';

// ── Hardcoded lookup tables ───────────────────────────────────────
const Map<String, int> _categoryNameToId = {
  'EVENT': 1,
  'CATERING': 2,
  'RESTAURANT': 3,
  'PANTHAL': 4,
  'STAGE DECORATION': 5,
  'AUDITORIUM': 6,
  'TRUST': 7,
  'INSTITUTION': 8,
  'RENTAL': 9,
  'HIRING': 10,
  'VEHICLE SHOWROOM': 11,
  'RESORT': 12,
  'GENERAL & OTHERS': 13,
};

const Map<String, int> _customerTypeNameToId = {
  'PREMIUM': 1,
  'REGULAR': 2,
  'BARGAIN': 3,
  'INSTITUTIONS': 4,
  'DEALERS': 5,
  'GENERAL': 6,
};

// ── Preview item status ───────────────────────────────────────────
enum _RecordStatus { pending, checking, matchFound, newCustomer, conflict }

/// Per-row preview model enriched with DB-check results.
class _PreviewItem {
  final DmeSaleRecord record;
  _RecordStatus status;
  DmeCustomer? existingCustomer; // null = not found
  String? resolvedCustomerType;
  String? resolvedCategory;
  String? correctedPhone; // User-corrected phone (10 digits)

  // Category / type conflict (existing DB value ≠ Excel value)
  bool hasCategoryConflict = false;
  bool hasTypeConflict = false;
  bool updateCategoryToExcel = false; // default: keep existing DB value
  bool updateTypeToExcel = false; // default: keep existing DB value

  _PreviewItem({
    required this.record,
    this.status = _RecordStatus.pending,
    this.existingCustomer,
    this.resolvedCustomerType,
    this.resolvedCategory,
    this.correctedPhone,
  });

  // Conflict: phone matches but name differs → alternate name will be saved in purchased_for
  bool get hasConflict =>
      existingCustomer != null &&
      existingCustomer!.name.trim().toLowerCase() !=
          record.customerName.trim().toLowerCase();

  bool get _isNew => status == _RecordStatus.newCustomer;

  bool get needsCustomerType =>
      _isNew &&
      (resolvedCustomerType == null || resolvedCustomerType!.isEmpty) &&
      (record.customerType == null || record.customerType!.isEmpty);

  bool get needsCategory =>
      _isNew &&
      (resolvedCategory == null || resolvedCategory!.isEmpty) &&
      (record.category == null || record.category!.isEmpty);

  bool get needsDetails => needsCustomerType || needsCategory;
}

// ─────────────────────────────────────────────────────────────────
class DmeSalesUploadPage extends StatefulWidget {
  const DmeSalesUploadPage({super.key});

  @override
  State<DmeSalesUploadPage> createState() => _DmeSalesUploadPageState();
}

class _DmeSalesUploadPageState extends State<DmeSalesUploadPage> {
  List<_PreviewItem>? _items;
  bool _picking = false;
  bool _checking = false;
  bool _uploading = false;
  String? _error;
  String? _fileName;
  String? _selectedBranchName; // Track branch selected for all records
  final _svc = DmeSupabaseService.instance;

  static const _blue = Color(0xFF005BAC);
  static const _maxRetries = 3;
  static const _initialRetryDelayMs = 500;

  // ── Retry helper with exponential backoff ─────────────────────
  Future<T> _retryWithBackoff<T>({
    required Future<T> Function() operation,
    int maxRetries = _maxRetries,
    int initialDelayMs = _initialRetryDelayMs,
  }) async {
    int attempt = 0;
    while (true) {
      try {
        return await operation();
      } catch (e) {
        attempt++;
        if (attempt >= maxRetries) rethrow;
        final delayMs = initialDelayMs * (1 << (attempt - 1)); // exponential
        await Future.delayed(Duration(milliseconds: delayMs));
      }
    }
  }

  // ── Async reminder update (non-blocking, fire-and-forget) ───────
  Future<void> _updateReminderAsync({
    required int customerId,
    required DmeSaleRecord record,
    required int branchId,
    required dynamic dmeUser,
    required String? effectiveCategory,
    required String? effectiveType,
  }) async {
    try {
      final branches = await _svc.getBranches();
      final branchName = branches.firstWhere(
        (b) => b['id'] == branchId,
        orElse: () => {'name': 'Unknown'},
      )['name'] as String?;

      await _retryWithBackoff(
        operation: () => _svc.upsertReminder(
          customerId: customerId,
          purchaseDate: record.date,
          purchaseForBranchId: branchId,
          purchaseForBranchName: branchName,
          assignedTo: dmeUser?.id,
          purchaseDetails: {
            'salesman': record.salesman,
            'category': effectiveCategory,
            'customer_type': effectiveType,
            'items_count': record.items.length,
          },
        ),
      );
    } catch (e) {
      // Log error but don't fail - reminder is non-critical
      debugPrint('Reminder update failed for customer $customerId: $e');
    }
  }

  // ── Phone validation dialog ────────────────────────────────────
  Future<bool> _validatePhoneNumbers() async {
    final itemsWithLongPhone = _items!.where((item) {
      final phone = item.record.phone;
      return phone != null && phone.replaceAll(RegExp(r'\D'), '').length > 10;
    }).toList();

    if (itemsWithLongPhone.isEmpty) return true;

    // Show dialog to correct phone numbers
    final Map<int, TextEditingController> controllers = {};
    for (int i = 0; i < itemsWithLongPhone.length; i++) {
      controllers[i] = TextEditingController(
        text: itemsWithLongPhone[i]
                .record
                .phone
                ?.replaceAll(RegExp(r'\D'), '')
                .substring(0, 10) ??
            '',
      );
    }

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (_, dialogSetState) => AlertDialog(
          title: const Text('Correct Phone Numbers'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'The following customers have phone numbers exceeding 10 digits.\n'
                'Please enter the correct 10-digit phone number:',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  itemCount: itemsWithLongPhone.length,
                  itemBuilder: (_, i) {
                    final item = itemsWithLongPhone[i];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.record.customerName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        TextField(
                          controller: controllers[i],
                          keyboardType: TextInputType.number,
                          maxLength: 10,
                          decoration: InputDecoration(
                            hintText: 'Enter 10-digit number',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                            counterText: '',
                          ),
                          onChanged: (v) => dialogSetState(() {}),
                        ),
                        if (i < itemsWithLongPhone.length - 1)
                          const SizedBox(height: 12),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: controllers.values.every((c) => c.text.length == 10)
                  ? () => Navigator.pop(context, true)
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _blue,
                foregroundColor: Colors.white,
              ),
              child: const Text('Confirm'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      // Save corrected phone numbers
      for (int i = 0; i < itemsWithLongPhone.length; i++) {
        itemsWithLongPhone[i].correctedPhone = controllers[i]!.text;
      }
      // Clean up controllers
      for (final controller in controllers.values) {
        controller.dispose();
      }
      return true;
    }
    // Clean up controllers
    for (final controller in controllers.values) {
      controller.dispose();
    }
    return false;
  }

  // ── Step 1: pick & parse ──────────────────────────────────────

  Future<void> _pickAndParse() async {
    setState(() {
      _picking = true;
      _error = null;
      _items = null;
      _selectedBranchName = null;
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
      );
      if (result == null || result.files.single.path == null) {
        setState(() => _picking = false);
        return;
      }
      _fileName = result.files.single.name;
      final bytes = await File(result.files.single.path!).readAsBytes();
      final records = DmeExcelParser.parseDailySalesExcel(bytes);
      if (records.isEmpty)
        throw Exception('No sales records found in the file');
      setState(() {
        _items = records.map((r) => _PreviewItem(record: r)).toList();
        _picking = false;
      });

      // Check if all records have null/empty branch
      final allBranchesEmpty = _items!.every((item) =>
          item.record.branch == null || item.record.branch!.trim().isEmpty);

      if (allBranchesEmpty) {
        // Ask user to select branch for all records
        final branchSelected = await _selectBranchForAllRecords();
        if (!branchSelected) {
          // User cancelled branch selection
          setState(() => _items = null);
          return;
        }
      }

      // Automatically trigger DB check after parse (and branch selection if needed)
      if (mounted && _items != null) {
        await _checkRecords();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _picking = false;
        });
      }
    }
  }

  // ── Branch selection (if all records have null branch) ────────

  Future<bool> _selectBranchForAllRecords() async {
    try {
      final branches = await _svc.getBranches();
      if (branches.isEmpty) {
        if (mounted) {
          setState(() => _error = 'No branches available');
        }
        return false;
      }

      String? selectedBranch;
      final result = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => StatefulBuilder(
          builder: (_, dialogSetState) => AlertDialog(
            title: const Text('Select Branch for All Records'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'No branch information found in the Excel file.\n'
                  'Please select a branch to apply to all records:',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedBranch,
                  hint: const Text('Select a branch'),
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  items: branches
                      .map((b) => DropdownMenuItem(
                          value: b['name'] as String?,
                          child: Text(b['name'] as String? ?? 'Unknown')))
                      .toList(),
                  onChanged: (v) => dialogSetState(() => selectedBranch = v),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: selectedBranch != null
                    ? () => Navigator.pop(context, selectedBranch)
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _blue,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Apply'),
              ),
            ],
          ),
        ),
      );

      if (result != null && mounted) {
        setState(() {
          _selectedBranchName = result;
        });
        return true;
      }
      return false;
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Error loading branches: $e');
      }
      return false;
    }
  }

  // ── Category / Type conflict resolution dialog ─────────────

  Future<bool> _validateCategoryTypeConflicts() async {
    final conflictItems = _items!
        .where((item) =>
            (item.status == _RecordStatus.matchFound ||
                item.status == _RecordStatus.conflict) &&
            (item.hasCategoryConflict || item.hasTypeConflict))
        .toList();

    if (conflictItems.isEmpty) return true;

    // Default all choices to "keep existing"
    for (final item in conflictItems) {
      item.updateCategoryToExcel = false;
      item.updateTypeToExcel = false;
    }

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (_, dialogSetState) => AlertDialog(
          title: const Text('Category / Type Mismatch'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'These customers exist in the database with a different '
                  'category or type than the Excel file.\n'
                  'Choose which value to keep for each:',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: conflictItems.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 20),
                    itemBuilder: (_, i) {
                      final item = conflictItems[i];
                      final r = item.record;
                      final existing = item.existingCustomer!;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            r.customerName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 6),
                          if (item.hasCategoryConflict) ...
                            [
                              const Text(
                                'Category',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey),
                              ),
                              RadioListTile<bool>(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  'Keep existing: ${existing.category ?? "—"}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                value: false,
                                groupValue: item.updateCategoryToExcel,
                                onChanged: (v) => dialogSetState(
                                    () => item.updateCategoryToExcel = v!),
                              ),
                              RadioListTile<bool>(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  'Update to: ${r.category ?? "—"}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                value: true,
                                groupValue: item.updateCategoryToExcel,
                                onChanged: (v) => dialogSetState(
                                    () => item.updateCategoryToExcel = v!),
                              ),
                            ],
                          if (item.hasTypeConflict) ...
                            [
                              const Text(
                                'Customer Type',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey),
                              ),
                              RadioListTile<bool>(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  'Keep existing: ${existing.customerType ?? "—"}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                value: false,
                                groupValue: item.updateTypeToExcel,
                                onChanged: (v) => dialogSetState(
                                    () => item.updateTypeToExcel = v!),
                              ),
                              RadioListTile<bool>(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  'Update to: ${r.customerType ?? "—"}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                value: true,
                                groupValue: item.updateTypeToExcel,
                                onChanged: (v) => dialogSetState(
                                    () => item.updateTypeToExcel = v!),
                              ),
                            ],
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: _blue,
                foregroundColor: Colors.white,
              ),
              child: const Text('Confirm'),
            ),
          ],
        ),
      ),
    );

    return result == true;
  }

  // ── Step 2: DB check ──────────────────────────────────────────

  Future<void> _checkRecords() async {
    if (_items == null) return;
    if (mounted) {
      setState(() => _checking = true);
    }

    for (final item in _items!) {
      if (mounted && _items != null) {
        setState(() => item.status = _RecordStatus.checking);
      }
      try {
        final phone = item.record.phone;
        if (phone == null || phone.trim().isEmpty) {
          if (mounted && _items != null) {
            setState(() => item.status = _RecordStatus.newCustomer);
          }
          continue;
        }
        final existing = await _svc.findCustomerByPhone(phone);
        if (mounted && _items != null) {
          if (existing != null) {
            final nameMatch = existing.name.trim().toLowerCase() ==
                item.record.customerName.trim().toLowerCase();

            // Detect category / type mismatches
            final excelCat = item.record.category?.trim().toUpperCase();
            final dbCat = existing.category?.trim().toUpperCase();
            final catConflict = excelCat != null &&
                excelCat.isNotEmpty &&
                dbCat != null &&
                dbCat.isNotEmpty &&
                excelCat != dbCat;

            final excelType = item.record.customerType?.trim().toUpperCase();
            final dbType = existing.customerType?.trim().toUpperCase();
            final typeConflict = excelType != null &&
                excelType.isNotEmpty &&
                dbType != null &&
                dbType.isNotEmpty &&
                excelType != dbType;

            setState(() {
              item.existingCustomer = existing;
              item.status =
                  nameMatch ? _RecordStatus.matchFound : _RecordStatus.conflict;
              item.hasCategoryConflict = catConflict;
              item.hasTypeConflict = typeConflict;
            });
          } else {
            setState(() => item.status = _RecordStatus.newCustomer);
          }
        }
      } catch (_) {
        if (mounted && _items != null) {
          setState(() => item.status = _RecordStatus.newCustomer);
        }
      }
    }
    if (mounted) {
      setState(() => _checking = false);
    }
  }

  // ── Step 3: upload ────────────────────────────────────────────

  bool get _canUpload {
    if (_items == null || _checking) return false;
    for (final item in _items!) {
      if (item.status == _RecordStatus.pending ||
          item.status == _RecordStatus.checking) return false;
      if (item.needsDetails) return false;
    }
    return true;
  }

  /// Updates category / type on an existing customer record if the user
  /// chose to overwrite the DB value with the Excel value.
  /// Also updates the branch if provided.
  Future<void> _applyExistingCustomerCategoryTypeUpdate({
    required _PreviewItem item,
    required int customerId,
    required String? effectiveCategory,
    required String? effectiveType,
    required int? branchId,
  }) async {
    final updateCat = item.hasCategoryConflict && item.updateCategoryToExcel;
    final updateType = item.hasTypeConflict && item.updateTypeToExcel;
    
    // Update if there's a category/type conflict OR if branch needs updating
    if (!updateCat && !updateType && branchId == null) return;

    final existing = item.existingCustomer!;
    final newCategory = updateCat ? effectiveCategory : existing.category;
    final newType = updateType ? effectiveType : existing.customerType;
    final newCategoryId = newCategory != null
        ? _categoryNameToId[newCategory.toUpperCase()]
        : existing.categoryId;
    final newTypeId = newType != null
        ? _customerTypeNameToId[newType.toUpperCase()]
        : existing.customerTypeId;

    await _retryWithBackoff(
      operation: () => _svc.updateCustomer(
        customerId: customerId,
        name: existing.name,
        phone: existing.phone,
        address: existing.address,
        category: newCategory,
        customerType: newType,
        categoryId: newCategoryId,
        customerTypeId: newTypeId,
        salesman: existing.salesman,
        branchId: branchId,
      ),
    );
  }

  Future<void> _upload() async {
    if (_items == null) return;

    // Validate phone numbers before proceeding
    final phoneValid = await _validatePhoneNumbers();
    if (!phoneValid) return;

    // Resolve category / type conflicts for existing customers
    final categoryTypeValid = await _validateCategoryTypeConflicts();
    if (!categoryTypeValid) return;

    if (mounted) {
      setState(() {
        _uploading = true;
        _error = null;
      });
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    final dmeUser = uid != null ? await _svc.getCurrentUser(uid) : null;

    // Pre-resolve branch IDs from branch names in records
    final branchCache = <String, int?>{};
    final allBranches = await _svc.getBranches();
    for (final b in allBranches) {
      branchCache[(b['name'] as String).toUpperCase()] = b['id'] as int;
    }

    int success = 0;
    int failed = 0;
    int ignored = 0;
    int alternateNamesRecorded = 0;
    final errors = <String>[];

    for (final item in _items!) {
      final record = item.record;
      try {
        int? customerId;
        final effectiveType = (record.customerType?.isNotEmpty == true)
            ? record.customerType
            : item.resolvedCustomerType;
        final effectiveCategory = (record.category?.isNotEmpty == true)
            ? record.category
            : item.resolvedCategory;

        // Use record.branch if it exists and is not empty, otherwise use selected branch
        final effectiveBranch = (record.branch?.trim().isNotEmpty == true)
            ? record.branch
            : _selectedBranchName;
        final branchId = effectiveBranch != null
            ? branchCache[effectiveBranch.toUpperCase()]
            : null;

        if (item.status == _RecordStatus.matchFound) {
          // Exact match — update last_purchase_date only
          customerId = item.existingCustomer!.id;
          await _retryWithBackoff(
            operation: () =>
                _svc.updateLastPurchaseDate(customerId!, record.date),
          );
          // Update category / type and branch if needed
          await _applyExistingCustomerCategoryTypeUpdate(
            item: item,
            customerId: customerId!,
            effectiveCategory: effectiveCategory,
            effectiveType: effectiveType,
            branchId: branchId,
          );
        } else if (item.status == _RecordStatus.conflict) {
          // Phone matches, name differs → keep existing, record alternate name
          customerId = item.existingCustomer!.id;
          await _retryWithBackoff(
            operation: () =>
                _svc.updateLastPurchaseDate(customerId!, record.date),
          );
          await _retryWithBackoff(
            operation: () =>
                _svc.appendPurchasedFor(customerId!, record.customerName),
          );
          alternateNamesRecorded++;
          // Update category / type and branch if needed
          await _applyExistingCustomerCategoryTypeUpdate(
            item: item,
            customerId: customerId!,
            effectiveCategory: effectiveCategory,
            effectiveType: effectiveType,
            branchId: branchId,
          );
        } else {
          // New customer
          final phone =
              (item.correctedPhone != null && item.correctedPhone!.isNotEmpty)
                  ? item.correctedPhone!
                  : (record.phone != null
                      ? DmeCustomer.normalizePhone(record.phone!)
                      : '');
          if (phone.isEmpty) {
            errors.add('${record.customerName}: No phone number');
            failed++;
            continue;
          }

          // Look up category and type IDs for new customer
          int? categoryId;
          int? typeId;
          if (effectiveCategory != null && effectiveCategory.isNotEmpty) {
            categoryId = _categoryNameToId[effectiveCategory.toUpperCase()];
            if (categoryId == null) {
              errors.add(
                  '${record.customerName}: Category "$effectiveCategory" not found in lookup table');
              failed++;
              continue;
            }
          }
          if (effectiveType != null && effectiveType.isNotEmpty) {
            typeId = _customerTypeNameToId[effectiveType.toUpperCase()];
            if (typeId == null) {
              errors.add(
                  '${record.customerName}: Type "$effectiveType" not found in lookup table');
              failed++;
              continue;
            }
          }

          final newCust = await _retryWithBackoff(
            operation: () => _svc.upsertCustomer(DmeCustomer(
              name: record.customerName,
              phone: phone,
              address: record.address,
              branchId: branchId,
              category: effectiveCategory,
              customerType: effectiveType,
              categoryId: categoryId,
              customerTypeId: typeId,
              salesman: record.salesman,
              lastPurchaseDate: record.date,
            )),
          );
          customerId = newCust.id;
        }

        // Insert sale + items
        // Look up category and type IDs - validate they exist in lookup tables
        int? categoryId;
        int? typeId;
        if (effectiveCategory != null && effectiveCategory.isNotEmpty) {
          categoryId = _categoryNameToId[effectiveCategory.toUpperCase()];
          if (categoryId == null) {
            errors.add(
                'Sale for ${record.customerName}: Category "$effectiveCategory" not found');
            failed++;
            continue;
          }
        }
        if (effectiveType != null && effectiveType.isNotEmpty) {
          typeId = _customerTypeNameToId[effectiveType.toUpperCase()];
          if (typeId == null) {
            errors.add(
                'Sale for ${record.customerName}: Type "$effectiveType" not found');
            failed++;
            continue;
          }
        }

        final sale = DmeSale(
          date: record.date,
          customerId: customerId,
          salesman: record.salesman,
          category: effectiveCategory,
          customerType: effectiveType,
          categoryId: categoryId,
          customerTypeId: typeId,
          uploadedBy: dmeUser?.id,
          items: record.items,
        );
        await _retryWithBackoff(
          operation: () => _svc.insertSale(sale),
        );

        // Upsert reminder with purchase branch tracking (non-blocking)
        // Details are saved to dme_customers and purchases tables
        // Reminder update failure does not fail the sale record
        // Use branchId if available, otherwise use a fallback from available branches
        final reminderBranchId = branchId ?? 
            (allBranches.isNotEmpty ? allBranches.first['id'] as int : 1);
        if (customerId != null) {
          unawaited(_updateReminderAsync(
            customerId: customerId,
            record: record,
            branchId: reminderBranchId,
            dmeUser: dmeUser,
            effectiveCategory: effectiveCategory,
            effectiveType: effectiveType,
          ));
        }
        success++;
      } catch (e) {
        errors.add('${record.customerName}: $e');
        failed++;
      }
    }

    if (mounted) {
      setState(() => _uploading = false);
      _showResult(success, failed, alternateNamesRecorded, ignored, errors);
    }
  }

  void _showResult(int success, int failed, int alternates, int ignored,
      List<String> errors) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Upload Complete'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('✅ $success records uploaded successfully'),
            if (ignored > 0) ...[
              const SizedBox(height: 6),
              Text('⏭️ $ignored records already uploaded (ignored)',
                  style: const TextStyle(color: Colors.orange, fontSize: 13)),
            ],
            if (alternates > 0) ...[
              const SizedBox(height: 6),
              Text('📋 $alternates alternate name(s) recorded in Purchased For',
                  style: const TextStyle(color: Colors.blue, fontSize: 13)),
            ],
            if (failed > 0) ...[
              const SizedBox(height: 8),
              Text('❌ $failed failed',
                  style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 4),
              ...errors.take(10).map((e) => Text('• $e',
                  style: const TextStyle(fontSize: 12, color: Colors.red))),
              if (errors.length > 10)
                Text('... and ${errors.length - 10} more',
                    style: const TextStyle(fontSize: 12)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _items = null);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Upload Daily Sales'),
        backgroundColor: _blue,
        foregroundColor: Colors.white,
      ),
      body: _uploading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Uploading sales data...'),
                ],
              ),
            )
          : _items != null
              ? _buildPreview()
              : _buildPicker(),
    );
  }

  // ── Picker screen ─────────────────────────────────────────────

  Widget _buildPicker() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.upload_file, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text(
              'Select a daily sales Excel file (.xlsx)\nwith customer and product data',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _picking ? null : _pickAndParse,
              icon: _picking
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.file_open),
              label: Text(_picking ? 'Reading...' : 'Choose Excel File'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _blue,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
    );
  }

  // ── Preview screen ────────────────────────────────────────────

  Widget _buildPreview() {
    final items = _items!;
    final newCount =
        items.where((i) => i.status == _RecordStatus.newCustomer).length;
    final matchCount =
        items.where((i) => i.status == _RecordStatus.matchFound).length;
    final conflictCount =
        items.where((i) => i.status == _RecordStatus.conflict).length;

    return Column(
      children: [
        // Summary header
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          color: Colors.blue[50],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('File: $_fileName',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              if (_selectedBranchName != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.location_on, size: 14, color: Colors.blue),
                    const SizedBox(width: 6),
                    Text('Branch: $_selectedBranchName',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ),
              ],
              if (_checking) ...[
                const SizedBox(height: 6),
                const Row(children: [
                  SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 8),
                  Text('Checking database…', style: TextStyle(fontSize: 13)),
                ]),
              ] else ...[
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  children: [
                    _chip('${items.length} total', Colors.grey),
                    if (matchCount > 0)
                      _chip('$matchCount match', Colors.green),
                    if (newCount > 0) _chip('$newCount new', _blue),
                    if (conflictCount > 0)
                      _chip('$conflictCount conflict', Colors.orange),
                  ],
                ),
              ],
            ],
          ),
        ),

        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: items.length,
            itemBuilder: (_, i) => _buildItemCard(items[i], i),
          ),
        ),

        // Bottom action bar
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() {
                      _items = null;
                      _selectedBranchName = null;
                    }),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _canUpload ? _upload : null,
                    icon: const Icon(Icons.cloud_upload),
                    label: Text(_checking
                        ? 'Checking…'
                        : 'Upload ${items.length} Sales'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _blue,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey[400],
                      disabledForegroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _chip(String label, Color color) {
    return Chip(
      label: Text(label,
          style: const TextStyle(fontSize: 11, color: Colors.white)),
      backgroundColor: color,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildItemCard(_PreviewItem item, int index) {
    final r = item.record;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color borderColor;
    Color? bgColor;
    IconData statusIcon;
    String statusLabel;

    switch (item.status) {
      case _RecordStatus.matchFound:
        borderColor = Colors.green;
        bgColor = Colors.green.withValues(alpha: 0.04);
        statusIcon = Icons.check_circle_outline;
        statusLabel = 'Existing customer';
        break;
      case _RecordStatus.conflict:
        borderColor = Colors.orange;
        bgColor = Colors.orange.withValues(alpha: 0.04);
        statusIcon = Icons.warning_amber_rounded;
        statusLabel = 'Name conflict';
        break;
      case _RecordStatus.newCustomer:
        borderColor = _blue;
        bgColor = _blue.withValues(alpha: 0.04);
        statusIcon = Icons.person_add_alt_1;
        statusLabel = 'New customer';
        break;
      case _RecordStatus.checking:
        borderColor = Colors.grey;
        bgColor = null;
        statusIcon = Icons.hourglass_empty;
        statusLabel = 'Checking…';
        break;
      default:
        borderColor = Colors.grey[300]!;
        bgColor = null;
        statusIcon = Icons.pending_outlined;
        statusLabel = 'Pending';
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bgColor ?? (isDark ? Colors.grey[850] : Colors.white),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 3,
              offset: const Offset(0, 1)),
        ],
      ),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: borderColor.withValues(alpha: 0.15),
          child: Icon(statusIcon, color: borderColor, size: 18),
        ),
        title: Text(r.customerName,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(statusLabel,
                style: TextStyle(
                    fontSize: 12,
                    color: borderColor,
                    fontWeight: FontWeight.w600)),
            Text(
              [
                if (r.phone != null) r.phone,
                if (r.salesman != null) r.salesman,
                r.date.toString().split(' ')[0],
              ].join(' • '),
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
        childrenPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        children: [
          // ── Name conflict info (auto-resolved) ────────────────────
          if (item.status == _RecordStatus.conflict) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('⚠ Same phone — different name:',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: Colors.orange)),
                  const SizedBox(height: 6),
                  Text(
                    'Existing:  ${item.existingCustomer!.name}\n'
                    'In file:   ${r.customerName}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '📋 The name from the file will be saved in '
                    '"Purchased For" of the existing customer.',
                    style: TextStyle(fontSize: 12, color: Colors.blueGrey),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],

          // ── Category / type conflict info ──────────────────────
          if ((item.status == _RecordStatus.matchFound ||
                  item.status == _RecordStatus.conflict) &&
              (item.hasCategoryConflict || item.hasTypeConflict)) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.purple.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.purple.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '⚠ Category / type differs from database:',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: Colors.purple),
                  ),
                  const SizedBox(height: 6),
                  if (item.hasCategoryConflict)
                    Text(
                      'Category — DB: ${item.existingCustomer!.category}  |  Excel: ${item.record.category}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  if (item.hasTypeConflict) ...[
                    if (item.hasCategoryConflict) const SizedBox(height: 4),
                    Text(
                      'Type — DB: ${item.existingCustomer!.customerType}  |  Excel: ${item.record.customerType}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 8),
                  const Text(
                    '📋 You will be asked which value to keep before uploading.',
                    style: TextStyle(fontSize: 12, color: Colors.blueGrey),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],

          // ── Customer details (type + category) when missing for new record ──
          if (item.needsCustomerType || item.needsCategory) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _blue.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _blue.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('New customer — fill in missing details:',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 8),
                  if (item.needsCustomerType) ...[
                    const Text('Customer Type',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 4),
                    DropdownButtonFormField<String>(
                      value: item.resolvedCustomerType,
                      hint: const Text('Select customer type'),
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      items: dmeCustomerTypes
                          .map(
                              (t) => DropdownMenuItem(value: t, child: Text(t)))
                          .toList(),
                      onChanged: (v) =>
                          setState(() => item.resolvedCustomerType = v),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (item.needsCategory) ...[
                    const Text('Category',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 4),
                    DropdownButtonFormField<String>(
                      value: item.resolvedCategory,
                      hint: const Text('Select category'),
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      items: dmeCategories
                          .map(
                              (c) => DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: (v) =>
                          setState(() => item.resolvedCategory = v),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],

          // ── Product items ──────────────────────────────────────
          if (r.items.isEmpty)
            const Text('No product items',
                style: TextStyle(fontSize: 12, color: Colors.grey))
          else
            ...r.items.map((item) => ListTile(
                  dense: true,
                  leading: const Icon(Icons.inventory_2,
                      size: 16, color: Colors.grey),
                  title: Text(item.productName,
                      style: const TextStyle(
                          fontStyle: FontStyle.italic, fontSize: 13)),
                  trailing: Text(
                    '${item.quantity}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                )),
        ],
      ),
    );
  }
}
