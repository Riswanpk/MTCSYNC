import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/dme_excel_parser.dart';
import '../services/dme_supabase_service.dart';
import '../models/dme_product.dart';

class DmeProductUploadPage extends StatefulWidget {
  const DmeProductUploadPage({super.key});

  @override
  State<DmeProductUploadPage> createState() => _DmeProductUploadPageState();
}

class _DmeProductUploadPageState extends State<DmeProductUploadPage> {
  final _svc = DmeSupabaseService.instance;
  final _searchCtrl = TextEditingController();

  List<DmeProduct>? _parsed;
  List<DmeProduct> _existing = [];
  bool _loading = true;
  bool _uploading = false;
  bool _picking = false;
  String? _error;
  int _totalCount = 0;

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    setState(() => _loading = true);
    _totalCount = await _svc.getProductCount();
    _existing = await _svc.getProducts(search: _searchCtrl.text.isEmpty ? null : _searchCtrl.text);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pickAndParse() async {
    setState(() { _picking = true; _error = null; });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
      );
      if (result == null || result.files.single.path == null) {
        setState(() => _picking = false);
        return;
      }
      final bytes = await File(result.files.single.path!).readAsBytes();
      final products = DmeExcelParser.parseProductExcel(bytes);
      if (products.isEmpty) throw Exception('No products found in the file');
      setState(() { _parsed = products; _picking = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _picking = false; });
    }
  }

  Future<void> _upload() async {
    if (_parsed == null) return;
    setState(() => _uploading = true);
    try {
      await _svc.upsertProducts(_parsed!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ ${_parsed!.length} products uploaded'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() => _parsed = null);
        _loadExisting();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
    if (mounted) setState(() => _uploading = false);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Product Master'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_file),
            tooltip: 'Upload Products Excel',
            onPressed: _picking ? null : _pickAndParse,
          ),
        ],
      ),
      body: _parsed != null ? _buildPreview() : _buildExistingList(),
    );
  }

  Widget _buildExistingList() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Search products...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  onSubmitted: (_) => _loadExisting(),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('$_totalCount products total',
                style: const TextStyle(color: Colors.grey, fontSize: 13)),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _existing.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.inventory_2, size: 64,
                              color: Colors.grey[300]),
                          const SizedBox(height: 12),
                          const Text('No products yet',
                              style: TextStyle(color: Colors.grey)),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _pickAndParse,
                            icon: const Icon(Icons.upload_file),
                            label: const Text('Upload Product Excel'),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _existing.length,
                      itemBuilder: (_, i) {
                        final p = _existing[i];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                const Color(0xFF607D8B).withOpacity(0.1),
                            child: const Icon(Icons.inventory_2,
                                color: Color(0xFF607D8B)),
                          ),
                          title: Text(p.name),
                          subtitle: Text(p.unit,
                              style: const TextStyle(fontSize: 12)),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildPreview() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: Colors.blue[50],
          child: Text('${_parsed!.length} products ready to upload',
              style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(_error!, style: const TextStyle(color: Colors.red)),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: _parsed!.length,
            itemBuilder: (_, i) {
              final p = _parsed![i];
              return ListTile(
                leading: CircleAvatar(child: Text('${i + 1}')),
                title: Text(p.name),
                subtitle: Text(p.unit),
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
                    onPressed: _uploading ? null : _upload,
                    icon: _uploading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.cloud_upload),
                    label: Text(
                        _uploading ? 'Uploading...' : 'Upload ${_parsed!.length} Products'),
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
