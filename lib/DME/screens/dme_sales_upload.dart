import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../dme_config.dart';
import '../services/dme_excel_parser.dart';
import '../services/dme_supabase_service.dart';
import '../models/dme_sale.dart';
import '../models/dme_customer.dart';

// ── Preview item status ───────────────────────────────────────────
enum _RecordStatus { pending, checking, matchFound, newCustomer, conflict }

// ── Conflict resolution choice ────────────────────────────────────
enum _ConflictChoice { useExisting, addSeparate }

/// Per-row preview model enriched with DB-check results.
class _PreviewItem {
  final DmeSaleRecord record;
  _RecordStatus status;
  DmeCustomer? existingCustomer; // null = not found
  _ConflictChoice conflictChoice;
  String? resolvedCustomerType;
  String? resolvedCategory;

  _PreviewItem({
    required this.record,
    this.status = _RecordStatus.pending,
    this.existingCustomer,
    this.conflictChoice = _ConflictChoice.useExisting,
    this.resolvedCustomerType,
    this.resolvedCategory,
  });

  bool get hasConflict =>
      existingCustomer != null &&
      existingCustomer!.name.trim().toLowerCase() !=
          record.customerName.trim().toLowerCase();

  bool get _isNewEntry =>
      status == _RecordStatus.newCustomer ||
      (hasConflict && conflictChoice == _ConflictChoice.addSeparate);

  bool get needsCustomerType =>
      _isNewEntry &&
      (resolvedCustomerType == null || resolvedCustomerType!.isEmpty) &&
      (record.customerType == null || record.customerType!.isEmpty);

  bool get needsCategory =>
      _isNewEntry &&
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
  final _svc = DmeSupabaseService.instance;

  static const _blue = Color(0xFF005BAC);

  // ── Step 1: pick & parse ──────────────────────────────────────

  Future<void> _pickAndParse() async {
    setState(() { _picking = true; _error = null; _items = null; });
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
      if (records.isEmpty) throw Exception('No sales records found in the file');
      setState(() {
        _items = records.map((r) => _PreviewItem(record: r)).toList();
        _picking = false;
      });
      // Automatically trigger DB check after parse
      await _checkRecords();
    } catch (e) {
      setState(() { _error = e.toString(); _picking = false; });
    }
  }

  // ── Step 2: DB check ──────────────────────────────────────────

  Future<void> _checkRecords() async {
    if (_items == null) return;
    setState(() => _checking = true);

    for (final item in _items!) {
      setState(() => item.status = _RecordStatus.checking);
      try {
        final phone = item.record.phone;
        if (phone == null || phone.trim().isEmpty) {
          setState(() => item.status = _RecordStatus.newCustomer);
          continue;
        }
        // In daily sales the "customerName" column holds the company / party name.
        // Pass it so the service can try an exact (phone + company) match first.
        final existing = await _svc.findCustomerByPhone(
            phone, company: item.record.customerName);
        if (existing != null) {
          final nameMatch = existing.name.trim().toLowerCase() ==
              item.record.customerName.trim().toLowerCase();
          setState(() {
            item.existingCustomer = existing;
            item.status =
                nameMatch ? _RecordStatus.matchFound : _RecordStatus.conflict;
          });
        } else {
          setState(() => item.status = _RecordStatus.newCustomer);
        }
      } catch (_) {
        setState(() => item.status = _RecordStatus.newCustomer);
      }
    }
    setState(() => _checking = false);
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

  Future<void> _upload() async {
    if (_items == null) return;
    setState(() { _uploading = true; _error = null; });

    final uid = FirebaseAuth.instance.currentUser?.uid;
    final dmeUser = uid != null ? await _svc.getCurrentUser(uid) : null;

    int success = 0;
    int failed = 0;
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

        if (item.status == _RecordStatus.matchFound) {
          // Existing customer with same name — just update purchase date
          customerId = item.existingCustomer!.id;
          await _svc.updateLastPurchaseDate(customerId!, record.date);
        } else if (item.status == _RecordStatus.conflict &&
            item.conflictChoice == _ConflictChoice.useExisting) {
          // Conflict but user chose to keep existing name
          customerId = item.existingCustomer!.id;
          await _svc.updateLastPurchaseDate(customerId!, record.date);
        } else {
          // New customer OR conflict resolved as separate
          final phone = record.phone != null
              ? DmeCustomer.normalizePhone(record.phone!)
              : '';
          if (phone.isEmpty) {
            errors.add('${record.customerName}: No phone number');
            failed++;
            continue;
          }
          if (item.status == _RecordStatus.conflict &&
              item.conflictChoice == _ConflictChoice.addSeparate) {
            // insertCustomer allows duplicate phone
            final newCust = await _svc.insertCustomer(DmeCustomer(
              name: record.customerName,
              phone: phone,
              address: record.address,
              category: effectiveCategory,
              customerType: effectiveType,
              salesman: record.salesman,
              lastPurchaseDate: record.date,
            ));
            customerId = newCust.id;
          } else {
            final newCust = await _svc.upsertCustomer(DmeCustomer(
              name: record.customerName,
              phone: phone,
              address: record.address,
              category: effectiveCategory,
              customerType: effectiveType,
              salesman: record.salesman,
              lastPurchaseDate: record.date,
            ));
            customerId = newCust.id;
          }
        }

        // Insert sale + items
        final sale = DmeSale(
          date: record.date,
          customerId: customerId,
          salesman: record.salesman,
          category: effectiveCategory,
          customerType: effectiveType,
          totalQuantity: record.headerQuantity,
          uploadedBy: dmeUser?.id,
          items: record.items,
        );
        await _svc.insertSale(sale);

        // Upsert reminder
        if (customerId != null) {
          await _svc.upsertReminder(
            customerId: customerId,
            purchaseDate: record.date,
            assignedTo: dmeUser?.id,
          );
        }

        success++;
      } catch (e) {
        errors.add('${record.customerName}: $e');
        failed++;
      }
    }

    if (mounted) {
      setState(() => _uploading = false);
      _showResult(success, failed, errors);
    }
  }

  void _showResult(int success, int failed, List<String> errors) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Upload Complete'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('✅ $success records uploaded successfully'),
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
                padding: const EdgeInsets.symmetric(
                    horizontal: 28, vertical: 14),
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
    final newCount = items
        .where((i) =>
            i.status == _RecordStatus.newCustomer ||
            (i.status == _RecordStatus.conflict &&
                i.conflictChoice == _ConflictChoice.addSeparate))
        .length;
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
              if (_checking) ...[
                const SizedBox(height: 6),
                const Row(children: [
                  SizedBox(
                      width: 14,
                      height: 14,
                      child:
                          CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 8),
                  Text('Checking database…',
                      style: TextStyle(fontSize: 13)),
                ]),
              ] else ...[
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  children: [
                    _chip('${items.length} total', Colors.grey),
                    if (matchCount > 0)
                      _chip('$matchCount match',
                          Colors.green),
                    if (newCount > 0)
                      _chip('$newCount new', _blue),
                    if (conflictCount > 0)
                      _chip('$conflictCount conflict',
                          Colors.orange),
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
                    onPressed: () => setState(() => _items = null),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _canUpload ? _upload : null,
                    icon: const Icon(Icons.cloud_upload),
                    label: Text(
                        _checking ? 'Checking…' : 'Upload ${items.length} Sales'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _blue,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey[400],
                      disabledForegroundColor: Colors.white,
                      padding:
                          const EdgeInsets.symmetric(vertical: 14),
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
        bgColor = Colors.green.withOpacity(0.04);
        statusIcon = Icons.check_circle_outline;
        statusLabel = 'Existing customer';
        break;
      case _RecordStatus.conflict:
        borderColor = Colors.orange;
        bgColor = Colors.orange.withOpacity(0.04);
        statusIcon = Icons.warning_amber_rounded;
        statusLabel = 'Name conflict';
        break;
      case _RecordStatus.newCustomer:
        borderColor = _blue;
        bgColor = _blue.withOpacity(0.04);
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
              color: Colors.black.withOpacity(0.04),
              blurRadius: 3,
              offset: const Offset(0, 1)),
        ],
      ),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: borderColor.withOpacity(0.15),
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
          // ── Conflict resolution ──────────────────────────────
          if (item.status == _RecordStatus.conflict) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: Colors.orange.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('⚠ Same phone number found with a different name:',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: Colors.orange)),
                  const SizedBox(height: 6),
                  Text(
                    'DB name:    ${item.existingCustomer!.name}\n'
                    'File name:  ${r.customerName}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  const Text('Choose action:',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                  RadioListTile<_ConflictChoice>(
                    dense: true,
                    value: _ConflictChoice.useExisting,
                    groupValue: item.conflictChoice,
                    title: Text(
                        'Use existing name  (${item.existingCustomer!.name})',
                        style: const TextStyle(fontSize: 13)),
                    onChanged: (v) =>
                        setState(() => item.conflictChoice = v!),
                  ),
                  RadioListTile<_ConflictChoice>(
                    dense: true,
                    value: _ConflictChoice.addSeparate,
                    groupValue: item.conflictChoice,
                    title: Text('Create as new company  (${r.customerName})',
                        style: const TextStyle(fontSize: 13)),
                    onChanged: (v) =>
                        setState(() => item.conflictChoice = v!),
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
                color: _blue.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _blue.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('New customer — fill in missing details:',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 8),
                  if (item.needsCustomerType) ...[
                    const Text('Customer Type', style: TextStyle(fontSize: 12, color: Colors.grey)),
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
                          .map((t) =>
                              DropdownMenuItem(value: t, child: Text(t)))
                          .toList(),
                      onChanged: (v) =>
                          setState(() => item.resolvedCustomerType = v),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (item.needsCategory) ...[
                    const Text('Category', style: TextStyle(fontSize: 12, color: Colors.grey)),
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
                          .map((c) =>
                              DropdownMenuItem(value: c, child: Text(c)))
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
                    '${item.quantity} ${item.unit ?? ''}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                )),
        ],
      ),
    );
  }
}
