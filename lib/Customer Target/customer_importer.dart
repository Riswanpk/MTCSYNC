import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart';

class CustomerImporterPage extends StatefulWidget {
  final Function(List<Map<String, dynamic>>) onImport;
  const CustomerImporterPage({super.key, required this.onImport});

  @override
  State<CustomerImporterPage> createState() => _CustomerImporterPageState();
}

class _CustomerImporterPageState extends State<CustomerImporterPage> {
  String? _fileName;
  bool _loading = false;
  String? _error;

  Future<void> _importExcel() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx', 'xls']);
      if (result != null && result.files.single.path != null) {
        File file = File(result.files.single.path!);
        var bytes = await file.readAsBytes();
        var excel = Excel.decodeBytes(bytes);

        // Check if there are any sheets
        if (excel.tables.isEmpty) throw Exception("No sheet found in Excel file.");

        var sheet = excel.tables[excel.tables.keys.first];
        if (sheet == null) throw Exception("No sheet found");

        List<Map<String, dynamic>> customers = [];
        for (int i = 1; i < sheet.maxRows; i++) {
          var row = sheet.row(i);
          if (row.length >= 3) {
            customers.add({
              'slno': row[0]?.value?.toString() ?? '',
              'name': row[1]?.value?.toString() ?? '',
              'contact': row[2]?.value?.toString() ?? '',
              'remarks': '',
            });
          }
        }
        widget.onImport(customers);
      }
    } catch (e) {
      setState(() {
        _error = "Failed to import: $e";
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Import Customers from Excel')),
      body: Center(
        child: _loading
            ? const CircularProgressIndicator()
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Import Excel'),
                    onPressed: _importExcel,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ]
                ],
              ),
      ),
    );
  }
}