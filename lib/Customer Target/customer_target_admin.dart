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
      branches.sort(); // Sort branches in ascending order

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
      _customers = null;
    });

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
      );

      if (result == null || result.files.single.path == null) return;

      File file = File(result.files.single.path!);
      var bytes = await file.readAsBytes();
      var excel = Excel.decodeBytes(bytes);

      if (excel.tables.isEmpty) {
        throw Exception("No sheets found in Excel file");
      }

      final sheet = excel.tables.values.first;
      if (sheet == null || sheet.maxRows < 2) {
        throw Exception("Sheet is empty");
      }

      // ---- READ HEADER ROW ----
      final headerRow = sheet.row(0);

      int? nameCol;
      int? contactCol;
      int? addressCol;

      for (int i = 0; i < headerRow.length; i++) {
        final header = headerRow[i]?.value?.toString().toLowerCase().trim();

        if (header == null) continue;

        if (header.contains('name') || header.contains('customer') || header.contains('client')) {
          nameCol ??= i;
        }

        if (header.contains('phone') ||
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
      List<Map<String, dynamic>> customers = [];

      for (int i = 1; i < sheet.maxRows; i++) {
        final row = sheet.row(i);

        String name = row.length > nameCol && row[nameCol]?.value != null
            ? row[nameCol]!.value.toString().trim()
            : '';

        String address = row.length > addressCol && row[addressCol]?.value != null
            ? row[addressCol]!.value.toString().trim()
            : '';

        String contactRaw = row.length > contactCol && row[contactCol]?.value != null
            ? row[contactCol]!.value.toString().trim()
            : '';

        // Split by comma, trim, and filter empty
        List<String> contacts = contactRaw
            .split(',')
            .map((c) => c.trim())
            .where((c) => c.isNotEmpty)
            .toList();

        String contact1 = contacts.isNotEmpty ? contacts[0] : '';
        String contact2 = contacts.length > 1 ? contacts[1] : '';

        if (name.isNotEmpty && contact1.isNotEmpty) {
          customers.add({
            'name': name,
            'address': address,
            'contact1': contact1,
            'contact2': contact2,
            'remarks': '',
          });
        }
      }

      if (customers.isEmpty) {
        throw Exception("No valid customer data found");
      }

      setState(() {
        _customers = customers;
        _success = "Excel imported. Ready to assign.";
      });
    } catch (e) {
      setState(() {
        _error = "Failed to import: $e";
        _customers = null;
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
      final now = DateTime.now();
      final monthYear = "${_monthName(now.month)} ${now.year}";
      final docRef = FirebaseFirestore.instance
          .collection('customer_target')
          .doc(monthYear)
          .collection('users')
          .doc(_selectedUserEmail);

      // Fetch existing customers
      final docSnap = await docRef.get();
      List<Map<String, dynamic>> existingCustomers = [];
      if (docSnap.exists && docSnap.data()?['customers'] != null) {
        existingCustomers = List<Map<String, dynamic>>.from(docSnap.data()!['customers']);
      }

      // Use a Set for fast lookup (by name + contact1)
      final existingSet = existingCustomers
          .map((c) => "${c['name']}_${c['contact1']}")
          .toSet();

      // Filter only new customers
      final newCustomers = _customers!.where((c) =>
          !existingSet.contains("${c['name']}_${c['contact1']}")).toList();

      // Combine existing + new
      final updatedCustomers = [...existingCustomers, ...newCustomers];

      await docRef.set({
        'branch': _selectedBranch,
        'user': _selectedUserEmail,
        'customers': updatedCustomers,
        'updated': FieldValue.serverTimestamp(),
      });

      setState(() {
        _success = "Customer target assigned. ${newCustomers.length} new customers added.";
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

  // Helper to get month name
  String _monthName(int month) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return months[month - 1];
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