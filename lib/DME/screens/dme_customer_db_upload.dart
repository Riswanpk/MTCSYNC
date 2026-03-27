import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/dme_excel_parser.dart';
import '../services/dme_supabase_service.dart';
import '../models/dme_customer.dart';

class DmeCustomerDbUploadPage extends StatefulWidget {
  const DmeCustomerDbUploadPage({super.key});

  @override
  State<DmeCustomerDbUploadPage> createState() => _DmeCustomerDbUploadPageState();
}

class _DmeCustomerDbUploadPageState extends State<DmeCustomerDbUploadPage> {
  final _svc = DmeSupabaseService.instance;

  List<DmeCustomer>? _parsed;
  List<Map<String, dynamic>> _branches = [];
  int? _selectedBranchId;
  bool _loading = false;
  bool _uploading = false;
  bool _picking = false;
  String? _error;
  String? _fileName;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  Future<void> _loadBranches() async {
    _branches = await _svc.getBranches();
    if (mounted) setState(() {});
  }

  Future<void> _pickAndParse() async {
    if (_selectedBranchId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a branch first')),
      );
      return;
    }
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
      final customers = DmeExcelParser.parseCustomerDatabaseExcel(bytes);
      if (customers.isEmpty) throw Exception('No customers found in the file');
      setState(() { _parsed = customers; _picking = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _picking = false; });
    }
  }

  Future<void> _upload() async {
    if (_parsed == null || _selectedBranchId == null) return;
    setState(() { _uploading = true; _progress = 0; });

    try {
      final rows = _parsed!.map((c) {
        final map = c.toInsertMap();
        map['branch_id'] = _selectedBranchId;
        map['updated_at'] = DateTime.now().toUtc().toIso8601String();
        return map;
      }).toList();

      await _svc.upsertCustomersBatch(
        rows,
        onProgress: (done, total) {
          if (mounted) setState(() => _progress = done / total);
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ ${_parsed!.length} customers uploaded'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() { _parsed = null; _uploading = false; });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
        setState(() => _uploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer Database Upload'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
      ),
      body: _uploading
          ? _buildProgress()
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
            Icon(Icons.cloud_upload, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text(
              'Select a branch, then upload the\ncustomer database Excel file',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            // Branch selector
            DropdownButton<int>(
              hint: const Text('Select Branch'),
              value: _selectedBranchId,
              isExpanded: true,
              items: _branches
                  .map((b) => DropdownMenuItem<int>(
                        value: b['id'] as int,
                        child: Text(b['name'] as String),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _selectedBranchId = v),
            ),
            const SizedBox(height: 20),
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
                backgroundColor: const Color(0xFF005BAC),
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
              Text('${_parsed!.length} customers ready to upload',
                  style: const TextStyle(color: Colors.green)),
              Text(
                'Branch: ${_branches.firstWhere((b) => b['id'] == _selectedBranchId)['name']}',
                style: const TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _parsed!.length > 100 ? 100 : _parsed!.length,
            itemBuilder: (_, i) {
              final c = _parsed![i];
              return ListTile(
                leading: CircleAvatar(child: Text('${i + 1}')),
                title: Text(c.name),
                subtitle: Text(
                  [c.phone, if (c.category != null) c.category].join(' • '),
                  style: const TextStyle(fontSize: 12),
                ),
              );
            },
          ),
        ),
        if (_parsed!.length > 100)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              'Showing first 100 of ${_parsed!.length} records',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
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
                    label: Text('Upload ${_parsed!.length} Customers'),
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

  Widget _buildProgress() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(value: _progress > 0 ? _progress : null),
            const SizedBox(height: 20),
            Text(
              _progress > 0
                  ? 'Uploading... ${(_progress * 100).toInt()}%'
                  : 'Uploading...',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 8),
            if (_parsed != null)
              Text('${(_progress * _parsed!.length).toInt()} / ${_parsed!.length} records',
                  style: const TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
