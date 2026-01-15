import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'customer_target_admin.dart';
import 'package:provider/provider.dart';
import '../Misc/theme_notifier.dart';

class CustomerAdminViewerPage extends StatefulWidget {
  const CustomerAdminViewerPage({super.key});

  @override
  State<CustomerAdminViewerPage> createState() => _CustomerAdminViewerPageState();
}

class _CustomerAdminViewerPageState extends State<CustomerAdminViewerPage> {
  String? _selectedBranch;
  String? _selectedUserEmail;
  String? _selectedMonthYear; // <-- Add this
  List<String> _branches = [];
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _allUsers = [];
  List<Map<String, dynamic>>? _customers;
  bool _loading = false;
  String? _error;

  final List<String> _monthYears = List.generate(
    12,
    (i) {
      final now = DateTime.now();
      final date = DateTime(now.year, now.month - i, 1);
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return "${months[date.month - 1]} ${date.year}";
    },
  );

  @override
  void initState() {
    super.initState();
    _selectedMonthYear = _monthYears.first; // Default to current month
    _fetchUsersAndBranches();
  }

  Future<void> _fetchUsersAndBranches() async {
    setState(() { _loading = true; });
    try {
      final snapshot = await FirebaseFirestore.instance.collection('users').get();
      final users = snapshot.docs
          .map((doc) => {
                'email': doc['email'],
                'name': doc['username'],
                'branch': doc['branch'],
              })
          .toList();
      final branches = users.map((u) => u['branch'] as String).toSet().toList();
      setState(() {
        _allUsers = users;
        _branches = branches;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = "Failed to fetch users/branches: $e";
        _loading = false;
      });
    }
  }

  void _filterUsersForBranch(String branch) {
    setState(() {
      _users = _allUsers.where((u) => u['branch'] == branch).toList();
      _selectedUserEmail = null;
      _customers = null;
    });
  }

  Future<void> _fetchCustomerTarget() async {
    if (_selectedUserEmail == null || _selectedMonthYear == null) return;
    setState(() { _loading = true; _error = null; });
    try {
      final doc = await FirebaseFirestore.instance
          .collection('customer_target')
          .doc(_selectedMonthYear)
          .collection('users')
          .doc(_selectedUserEmail)
          .get();
      if (doc.exists && doc.data()?['customers'] != null) {
        final List<dynamic> data = doc.data()!['customers'];
        setState(() {
          _customers = data.map((e) => Map<String, dynamic>.from(e)).toList();
          _loading = false;
        });
      } else {
        setState(() {
          _customers = [];
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = "Failed to fetch customer target: $e";
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        // Use your home.dart colors
        const Color primaryBlue = Color(0xFF8CC63F); // blue swapped to green
        const Color primaryGreen = Color(0xFF005BAC); // green swapped to blue
        final theme = Theme.of(context);
        final isDark = themeProvider.themeMode == ThemeMode.dark ||
            (themeProvider.themeMode == ThemeMode.system && theme.brightness == Brightness.dark);

        // Light mode: use more saturated backgrounds
        final bgColor = isDark
            ? const Color(0xFF181A20)
            : const Color(0xFFE8F5E9); // very light green for page background
        final cardColor = isDark
            ? const Color(0xFF23262B)
            : Colors.white;
        final textColor = isDark ? Colors.white : Colors.black87;

        return Scaffold(
          backgroundColor: bgColor,
          appBar: AppBar(
            title: Text('Customer Target Progress Viewer', style: TextStyle(color: Colors.white)),
            backgroundColor: isDark ? primaryGreen : primaryBlue, // green for dark, blue for light
            iconTheme: const IconThemeData(color: Colors.white),
            actions: [
              IconButton(
                icon: const Icon(Icons.assignment_turned_in),
                tooltip: 'Assign Customer Target',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CustomerTargetAdminPage()),
                  );
                },
              ),
            ],
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // --- Month-Year Dropdown ---
                      DropdownButtonFormField<String>(
                        value: _selectedMonthYear,
                        hint: Text('Select Month', style: TextStyle(color: primaryBlue)),
                        items: _monthYears
                            .map((m) => DropdownMenuItem(value: m, child: Text(m, style: TextStyle(color: primaryBlue))))
                            .toList(),
                        onChanged: (val) {
                          setState(() {
                            _selectedMonthYear = val;
                            _customers = null;
                          });
                          if (val != null && _selectedUserEmail != null) _fetchCustomerTarget();
                        },
                        dropdownColor: cardColor,
                      ),
                      const SizedBox(height: 16),
                      // --- Branch Dropdown ---
                      DropdownButtonFormField<String>(
                        value: _branches.contains(_selectedBranch) ? _selectedBranch : null,
                        hint: Text('Select Branch', style: TextStyle(color: primaryGreen)),
                        items: _branches.isNotEmpty
                            ? _branches
                                .map((b) => DropdownMenuItem(value: b, child: Text(b, style: TextStyle(color: primaryGreen))))
                                .toList()
                            : [
                                DropdownMenuItem(
                                  value: null,
                                  child: Text('No branches found', style: TextStyle(color: primaryGreen)),
                                ),
                              ],
                        onChanged: (val) {
                          setState(() {
                            _selectedBranch = val;
                            _selectedUserEmail = null;
                            _users = [];
                            _customers = null;
                          });
                          if (val != null) _filterUsersForBranch(val);
                        },
                        dropdownColor: cardColor,
                      ),
                      const SizedBox(height: 16),
                      // --- User Dropdown ---
                      DropdownButtonFormField<String>(
                        value: _users.any((u) => u['email'] == _selectedUserEmail) ? _selectedUserEmail : null,
                        hint: Text('Select User', style: TextStyle(color: primaryBlue)),
                        items: _users.isNotEmpty
                            ? _users
                                .map((u) => DropdownMenuItem<String>(
                                      value: u['email'] as String,
                                      child: Text('${u['name']} (${u['email']})', style: TextStyle(color: primaryBlue)),
                                    ))
                                .toList()
                            : [
                                DropdownMenuItem(
                                  value: null,
                                  child: Text('No users found', style: TextStyle(color: primaryBlue)),
                                ),
                              ],
                        onChanged: (val) {
                          setState(() {
                            _selectedUserEmail = val;
                            _customers = null;
                          });
                          if (val != null && _selectedMonthYear != null) _fetchCustomerTarget();
                        },
                        dropdownColor: cardColor,
                      ),
                      const SizedBox(height: 24),
                      if (_error != null) ...[
                        Text(_error!, style: const TextStyle(color: Colors.red)),
                      ],
                      if (_customers != null)
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: cardColor,
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))],
                              border: Border.all(color: isDark ? Colors.grey.shade800 : Colors.grey.shade300),
                            ),
                            child: _customerProgressTable(isDark, textColor, primaryBlue, primaryGreen),
                          ),
                        ),
                    ],
                  ),
                ),
        );
      },
    );
  }

  Widget _customerProgressTable(bool isDark, Color textColor, Color primaryBlue, Color primaryGreen) {
    if (_customers == null) return const SizedBox();
    if (_customers!.isEmpty) return Text('No customer target assigned.', style: TextStyle(color: textColor));
    const tableTextStyle = TextStyle(fontSize: 11);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Progress: ${_customers!.where((c) => c['callMade'] == true).length} / ${_customers!.length} called',
            style: TextStyle(fontWeight: FontWeight.bold, color: primaryBlue)),
        const SizedBox(height: 8),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: DataTable(
                headingRowColor: MaterialStateProperty.resolveWith<Color>(
                  (states) => isDark
                      ? primaryGreen.withOpacity(0.12)
                      : primaryBlue.withOpacity(0.18), // blue for light
                ),
                dataRowColor: MaterialStateProperty.resolveWith<Color>(
                  (states) => states.contains(MaterialState.selected)
                      ? (isDark
                          ? primaryBlue.withOpacity(0.18)
                          : primaryGreen.withOpacity(0.12)) // green for light
                      : (isDark ? const Color(0xFF181A20) : Colors.white),
                ),
                columns: [
                  // DataColumn(label: Text('Sl. No', style: tableTextStyle.copyWith(color: primaryGreen))), // removed
                  DataColumn(label: Text('Customer Name', style: tableTextStyle.copyWith(color: primaryBlue))),
                  DataColumn(label: Text('Called', style: tableTextStyle.copyWith(color: primaryGreen))),
                  DataColumn(label: Text('Remarks', style: tableTextStyle.copyWith(color: primaryBlue))),
                ],
                rows: List<DataRow>.generate(
                  _customers!.length,
                  (index) {
                    final customer = _customers![index];
                    final isEven = index % 2 == 0;
                    return DataRow(
                      color: MaterialStateProperty.resolveWith<Color>(
                        (states) => isDark
                            ? (isEven ? primaryGreen.withOpacity(0.06) : primaryBlue.withOpacity(0.06))
                            : (isEven ? primaryBlue.withOpacity(0.06) : primaryGreen.withOpacity(0.06)),
                      ),
                      cells: [
                        // DataCell(Text(customer['slno'] ?? '', style: tableTextStyle.copyWith(color: primaryGreen))), // removed
                        DataCell(Text(customer['name'] ?? '', style: tableTextStyle.copyWith(color: primaryBlue))),
                        DataCell(
                          Icon(
                            customer['callMade'] == true ? Icons.check_circle : Icons.cancel,
                            color: customer['callMade'] == true ? primaryBlue : primaryGreen,
                            size: 16,
                          ),
                        ),
                        DataCell(Text(customer['remarks'] ?? '', style: tableTextStyle.copyWith(color: primaryBlue))),
                      ],
                    );
                  },
                ),
                border: TableBorder(
                  horizontalInside: BorderSide(color: isDark ? primaryGreen.withOpacity(0.18) : primaryBlue.withOpacity(0.18), width: 0.5),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
