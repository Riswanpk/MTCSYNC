import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/dme_excel_parser.dart';
import '../services/dme_supabase_service.dart';
import '../models/dme_sale.dart';
import '../models/dme_customer.dart';

class DmeSalesUploadPage extends StatefulWidget {
  const DmeSalesUploadPage({super.key});

  @override
  State<DmeSalesUploadPage> createState() => _DmeSalesUploadPageState();
}

class _DmeSalesUploadPageState extends State<DmeSalesUploadPage> {
  List<DmeSaleRecord>? _parsed;
  bool _picking = false;
  bool _uploading = false;
  String? _error;
  String? _fileName;
  final _svc = DmeSupabaseService.instance;

  Future<void> _pickAndParse() async {
    setState(() { _picking = true; _error = null; _parsed = null; });
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
      setState(() { _parsed = records; _picking = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _picking = false; });
    }
  }

  Future<void> _upload() async {
    if (_parsed == null) return;
    setState(() { _uploading = true; _error = null; });

    final uid = FirebaseAuth.instance.currentUser?.uid;
    final dmeUser = uid != null ? await _svc.getCurrentUser(uid) : null;

    int success = 0;
    int failed = 0;
    final errors = <String>[];

    for (final record in _parsed!) {
      try {
        // 1. Find or create customer by phone
        DmeCustomer? existing;
        if (record.phone != null && record.phone!.isNotEmpty) {
          existing = await _svc.findCustomerByPhone(record.phone!);
        }

        int? customerId;
        if (existing != null) {
          customerId = existing.id;
          // Update last purchase date
          await _svc.updateLastPurchaseDate(customerId!, record.date);
        } else {
          // Insert new customer
          final phone = record.phone != null
              ? DmeCustomer.normalizePhone(record.phone!)
              : '';
          if (phone.isEmpty) {
            errors.add('${record.customerName}: No phone number');
            failed++;
            continue;
          }
          final newCust = await _svc.upsertCustomer(DmeCustomer(
            name: record.customerName,
            phone: phone,
            address: record.address,
            category: record.category,
            customerType: record.customerType,
            salesman: record.salesman,
            lastPurchaseDate: record.date,
          ));
          customerId = newCust.id;
        }

        // 2. Insert sale + items
        final sale = DmeSale(
          date: record.date,
          customerId: customerId,
          salesman: record.salesman,
          category: record.category,
          customerType: record.customerType,
          totalQuantity: record.headerQuantity,
          uploadedBy: dmeUser?.id,
          items: record.items,
        );
        await _svc.insertSale(sale);

        // 3. Upsert reminder (purchase date + 1 month)
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
            Text('✅ $success customers uploaded successfully'),
            if (failed > 0) ...[
              const SizedBox(height: 8),
              Text('❌ $failed failed', style: const TextStyle(color: Colors.red)),
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
              setState(() => _parsed = null);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Upload Daily Sales'),
        backgroundColor: const Color(0xFF005BAC),
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
          : _parsed != null
              ? _buildPreview()
              : _buildPicker(),
    );
  }

  Widget _buildPicker() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.upload_file, size: 80,
                color: Colors.grey[400]),
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
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.file_open),
              label: Text(_picking ? 'Reading...' : 'Choose Excel File'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF005BAC),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
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

  Widget _buildPreview() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: Colors.green[50],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('File: $_fileName',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('${_parsed!.length} customers found',
                  style: const TextStyle(color: Colors.green)),
              Text(
                '${_parsed!.fold<int>(0, (sum, r) => sum + r.items.length)} product items total',
                style: const TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _parsed!.length,
            itemBuilder: (_, i) {
              final r = _parsed![i];
              return ExpansionTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFF005BAC),
                  foregroundColor: Colors.white,
                  child: Text('${i + 1}'),
                ),
                title: Text(r.customerName,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(
                  [
                    if (r.phone != null) r.phone,
                    if (r.salesman != null) r.salesman,
                    r.date.toString().split(' ')[0],
                  ].join(' • '),
                  style: const TextStyle(fontSize: 12),
                ),
                children: r.items
                    .map((item) => ListTile(
                          dense: true,
                          leading: const Icon(Icons.inventory_2,
                              size: 18, color: Colors.grey),
                          title: Text(item.productName,
                              style: const TextStyle(fontStyle: FontStyle.italic)),
                          trailing: Text(
                            '${item.quantity} ${item.unit ?? ''}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ))
                    .toList(),
              );
            },
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() => _parsed = null),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _upload,
                    icon: const Icon(Icons.cloud_upload),
                    label: Text('Upload ${_parsed!.length} Sales'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF005BAC),
                      foregroundColor: Colors.white,
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
}
