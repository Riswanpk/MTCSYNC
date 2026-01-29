import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'customer_target_admin.dart';
import 'customer_target_export_page.dart'; // <-- Import the export page
import 'package:provider/provider.dart';
import '../Misc/theme_notifier.dart';

class CustomerAdminViewerPage extends StatefulWidget {
  final String? forceBranch;
  final bool hideBranchDropdown;
  const CustomerAdminViewerPage({super.key, this.forceBranch, this.hideBranchDropdown = false});

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
  bool _sortCalledFirst = true;
  bool _dropdownsVisible = true;

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
    _selectedMonthYear = _monthYears.first;
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
      branches.sort(); // Sort branches in ascending order
      String? autoBranch = widget.forceBranch;
      List<Map<String, dynamic>> filteredUsers = users;
      if (autoBranch != null) {
        filteredUsers = users.where((u) => u['branch'] == autoBranch).toList();
      }
      setState(() {
        _allUsers = users;
        _branches = branches;
        if (autoBranch != null) {
          _selectedBranch = autoBranch;
          _users = filteredUsers;
        }
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
            title: Text('Customer List', style: TextStyle(color: Colors.white)),
            backgroundColor: isDark ? primaryGreen : primaryBlue,
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
              IconButton(
                icon: const Icon(Icons.download),
                tooltip: 'Export Customer Target',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CustomerTargetExportPage()),
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // --- Collapsible Dropdowns ---
                      AnimatedSize(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOut,
                        child: _dropdownsVisible
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
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
                                  if (!widget.hideBranchDropdown)
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
                                  if (!widget.hideBranchDropdown) const SizedBox(height: 16),
                                  // --- User Dropdown ---
                                  DropdownButtonFormField<String>(
                                    value: _users.any((u) => u['email'] == _selectedUserEmail) ? _selectedUserEmail : null,
                                    hint: Text('Select User', style: TextStyle(color: primaryBlue)),
                                    items: _users.isNotEmpty
                                        ? _users
                                            .map((u) => DropdownMenuItem<String>(
                                                  value: u['email'] as String,
                                                  child: Text(u['name'] ?? '', style: TextStyle(color: primaryBlue)),
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
                                ],
                              )
                            : const SizedBox.shrink(),
                      ),
                      // --- Toggle arrow button ---
                      Center(
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _dropdownsVisible = !_dropdownsVisible;
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: AnimatedRotation(
                              turns: _dropdownsVisible ? 0 : 0.5,
                              duration: const Duration(milliseconds: 250),
                              child: Icon(
                                Icons.keyboard_arrow_up,
                                color: primaryGreen,
                                size: 28,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_error != null) ...[
                        Text(_error!, style: const TextStyle(color: Colors.red)),
                        const SizedBox(height: 16),
                      ],
                      if (_customers != null)
                        Expanded(
                          child: Container(
                            // height: MediaQuery.of(context).size.height * 0.6, // Remove fixed height
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

    // Sort customers by call status if needed
    List<Map<String, dynamic>> sortedCustomers = List<Map<String, dynamic>>.from(_customers!);
    sortedCustomers.sort((a, b) {
      if (_sortCalledFirst) {
        return (b['callMade'] == true ? 1 : 0) - (a['callMade'] == true ? 1 : 0);
      } else {
        return (a['callMade'] == true ? 1 : 0) - (b['callMade'] == true ? 1 : 0);
      }
    });

    return ListView(
      padding: const EdgeInsets.all(0),
      children: [
        Row(
          children: [
            Text(
              'Progress: ${_customers!.where((c) => c['callMade'] == true).length} / ${_customers!.length} called',
              style: TextStyle(fontWeight: FontWeight.bold, color: primaryBlue),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(_sortCalledFirst ? Icons.arrow_downward : Icons.arrow_upward, color: primaryGreen, size: 20),
              tooltip: 'Sort by call status',
              onPressed: () {
                setState(() {
                  _sortCalledFirst = !_sortCalledFirst;
                });
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: SizedBox(
            width: 500, //adjust as needed
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
                DataColumn(
                  label: Builder(
                    builder: (context) {
                      final isDark = Theme.of(context).brightness == Brightness.dark;
                      return SizedBox(
                        width: 120,
                        child: Text(
                          'Customer Name',
                          style: tableTextStyle.copyWith(
                            color: isDark ? primaryBlue : primaryGreen,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    },
                  ),
                ),
                DataColumn(
                  label: SizedBox(
                    width: 10,
                    child: Icon(Icons.phone, color: primaryGreen, size: 16),
                  ),
                ),
                DataColumn(
                  label: SizedBox(
                    width: 180,
                    child: Text('Remarks', style: tableTextStyle.copyWith(color: primaryBlue)),
                  ),
                ),
              ],
              rows: List<DataRow>.generate(
                sortedCustomers.length,
                (index) {
                  final customer = sortedCustomers[index];
                  final isEven = index % 2 == 0;
                  return DataRow(
                    color: MaterialStateProperty.resolveWith<Color>(
                      (states) => isDark
                          ? (isEven ? primaryGreen.withOpacity(0.06) : primaryBlue.withOpacity(0.06))
                          : (isEven ? primaryBlue.withOpacity(0.06) : primaryGreen.withOpacity(0.06)),
                    ),
                    cells: [
                      DataCell(
                        Builder(
                          builder: (context) {
                            final isDark = Theme.of(context).brightness == Brightness.dark;
                            return SizedBox(
                              width: 170,
                              child: Text(
                                customer['name'] ?? '',
                                style: tableTextStyle.copyWith(
                                  color: isDark ? primaryBlue : primaryGreen,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          },
                        ),
                      ),
                      DataCell(
                        Icon(
                          customer['callMade'] == true ? Icons.check_circle : Icons.cancel,
                          color: customer['callMade'] == true ? primaryBlue : primaryGreen,
                          size: 16,
                        ),
                      ),
                      DataCell(
                        Builder(
                          builder: (context) {
                            final isDark = Theme.of(context).brightness == Brightness.dark;
                            return SizedBox(
                              width: 180,
                              child: Text(
                                customer['remarks'] ?? '',
                                style: tableTextStyle.copyWith(
                                  color: isDark ? primaryBlue : primaryGreen,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          },
                        ),
                      ),
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
      ],
    );
  }
}
