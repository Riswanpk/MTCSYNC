import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart';

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
  String? _error;
  String? _success;
  List<Map<String, dynamic>>? _customers; // Store imported customers

  @override
  void initState() {
    super.initState();
    _fetchUsersAndBranches();
  }

  Future<void> _fetchUsersAndBranches() async {
    // Fetch all users from Firestore
    final snapshot = await FirebaseFirestore.instance.collection('users').get();
    final users = snapshot.docs
        .map((doc) => {
              'email': doc['email'],
              'name': doc['username'],
              'branch': doc['branch'],
            })
        .toList();

    // Extract unique branches
    final branches = users.map((u) => u['branch'] as String).toSet().toList();

    setState(() {
      _allUsers = users;
      _branches = branches;
    });
  }

  void _filterUsersForBranch(String branch) {
    setState(() {
      _users = _allUsers.where((u) => u['branch'] == branch).toList();
      _selectedUserEmail = null;
    });
  }

  Future<void> _importExcel() async {
    setState(() {
      _loading = true;
      _error = null;
      _success = null;
      _customers = null;
    });
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx', 'xls']);
      if (result != null && result.files.single.path != null) {
        File file = File(result.files.single.path!);
        var bytes = await file.readAsBytes();
        var excel = Excel.decodeBytes(bytes);

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
        setState(() {
          _customers = customers;
          _success = "Excel imported. Ready to assign.";
        });
      }
    } catch (e) {
      setState(() {
        _error = "Failed: $e";
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _assignToFirestore() async {
    if (_customers == null || _selectedBranch == null || _selectedUserEmail == null) {
      setState(() {
        _error = "Please import Excel and select branch/user.";
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _success = null;
    });
    try {
      await FirebaseFirestore.instance
          .collection('customer_target')
          .doc(_selectedUserEmail)
          .set({
        'branch': _selectedBranch,
        'user': _selectedUserEmail,
        'customers': _customers,
        'updated': FieldValue.serverTimestamp(),
      });

      setState(() {
        _success = "Customer target assigned for $_selectedUserEmail";
      });
    } catch (e) {
      setState(() {
        _error = "Failed: $e";
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Widget _customerPreviewTable() {
    if (_customers == null) return const SizedBox();
    if (_customers!.isEmpty) return const Text('No customers in Excel.');
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Sl. No')),
          DataColumn(label: Text('Customer Name')),
          DataColumn(label: Text('Contact No.')),
        ],
        rows: _customers!
            .map((customer) => DataRow(
                  cells: [
                    DataCell(Text(customer['slno'] ?? '')),
                    DataCell(Text(customer['name'] ?? '')),
                    DataCell(Text(customer['contact'] ?? '')),
                  ],
                ))
            .toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Assign Customer Target')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Branch Dropdown
                  DropdownButtonFormField<String>(
                    value: _branches.contains(_selectedBranch) ? _selectedBranch : null,
                    hint: const Text('Select Branch'),
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
                      });
                      if (val != null) _filterUsersForBranch(val);
                    },
                  ),
                  const SizedBox(height: 16),
                  // User Dropdown
                  DropdownButtonFormField<String>(
                    value: _users.any((u) => u['email'] == _selectedUserEmail) ? _selectedUserEmail : null,
                    hint: const Text('Select User'),
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
                      });
                    },
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.upload_file),
                        label: const Text('Import Excel'),
                        onPressed: _importExcel,
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.assignment_turned_in),
                        label: const Text('Assign'),
                        onPressed: (_customers != null &&
                                _customers!.isNotEmpty &&
                                _selectedBranch != null &&
                                _selectedUserEmail != null)
                            ? _assignToFirestore
                            : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Customer Preview Table
                 
                  // Error and Success Messages
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],
                  if (_success != null) ...[
                    const SizedBox(height: 16),
                    Text(_success!, style: const TextStyle(color: Colors.green)),
                  ],
                ],
              ),
            ),
    );
  }
}