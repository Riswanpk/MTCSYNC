import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:call_log/call_log.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';

import '../Misc/theme_notifier.dart';
import 'sales_customer_tile_viewer.dart';
import 'add_customer.dart';

class CustomerListTarget extends StatefulWidget {
  const CustomerListTarget({super.key});

  @override
  State<CustomerListTarget> createState() => _CustomerListTargetState();
}

class _CustomerListTargetState extends State<CustomerListTarget> with WidgetsBindingObserver {
  List<Map<String, dynamic>>? _customers;
  String? _pendingCallNumber;
  int? _pendingCallIndex;
  bool _loading = true;
  String? _error;
  String? _docId;
  bool _sortCalledFirst = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchCustomerData();
  }

  Future<void> _fetchCustomerData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          _error = "Not logged in";
          _loading = false;
        });
        return;
      }
      _docId = user.email;
      // Get current month-year string, e.g., "Jan 2026"
      final now = DateTime.now();
      final monthYear = "${_monthName(now.month)} ${now.year}";

      final doc = await FirebaseFirestore.instance
          .collection('customer_target')
          .doc(monthYear)
          .collection('users')
          .doc(_docId)
          .get();
      if (doc.exists && doc.data()?['customers'] != null) {
        final List<dynamic> data = doc.data()!['customers'];
        setState(() {
          _customers = data.map((e) => Map<String, dynamic>.from(e)).toList();
          _loading = false;
        });
      } else {
        setState(() {
          _customers = null;
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = "Error: $e";
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _pendingCallNumber != null) {
      _checkIfCallWasMade();
    }
  }

  Future<void> _checkIfCallWasMade() async {
    if (_pendingCallNumber == null || _pendingCallIndex == null) return;

    try {
      final now = DateTime.now();
      final Iterable<CallLogEntry> entries = await CallLog.query(
        dateFrom: now.subtract(const Duration(minutes: 2)).millisecondsSinceEpoch,
        dateTo: now.millisecondsSinceEpoch,
      );

      bool callMade = entries.any((entry) {
        String logNumber = entry.number?.replaceAll(RegExp(r'\D'), '') ?? '';
        String pendingNumber = _pendingCallNumber!.replaceAll(RegExp(r'\D'), '');
        return logNumber.endsWith(pendingNumber) || pendingNumber.endsWith(logNumber);
      });

      if (callMade && _pendingCallIndex != null) {
        setState(() {
          _customers![_pendingCallIndex!]['callMade'] = true;
        });
        await _updateFirestore();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Call detected!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      debugPrint('Error checking call log: $e');
    } finally {
      _pendingCallNumber = null;
      _pendingCallIndex = null;
    }
  }

  Future<void> _makeCall(String contact, int index) async {
    var status = await Permission.phone.request();
    if (!status.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Phone permission denied')),
      );
      return;
    }

    _pendingCallNumber = contact;
    _pendingCallIndex = index;

    final uri = Uri(scheme: 'tel', path: contact);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not launch dialer')),
      );
      _pendingCallNumber = null;
      _pendingCallIndex = null;
    }
  }

  Future<void> _updateFirestore() async {
    if (_docId == null) return;
    try {
      // Get current month-year string, e.g., "Jan 2026"
      final now = DateTime.now();
      final monthYear = "${_monthName(now.month)} ${now.year}";

      await FirebaseFirestore.instance
          .collection('customer_target')
          .doc(monthYear)
          .collection('users')
          .doc(_docId)
          .update({'customers': _customers});
    } catch (e) {
      debugPrint('Failed to update Firestore: $e');
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
            : const Color(0xFFE3F2FD); // very light blue for page background
        final cardColor = isDark ? const Color(0xFF23262B) : Colors.white;
        final textColor = isDark ? Colors.white : Colors.black;

        if (_loading) {
          return Scaffold(
            backgroundColor: bgColor,
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        if (_error != null) {
          return Scaffold(
            backgroundColor: bgColor,
            appBar: AppBar(
              title: Text('Customer List', style: TextStyle(color: Colors.white)),
              backgroundColor: isDark ? primaryBlue : primaryGreen,
              iconTheme: const IconThemeData(color: Colors.white),
            ),
            body: Center(child: Text(_error!, style: TextStyle(color: textColor))),
          );
        }

        if (_customers == null) {
          return Scaffold(
            backgroundColor: bgColor,
            appBar: AppBar(
              title: Text('Customer List', style: TextStyle(color: Colors.white)),
              backgroundColor: isDark ? primaryBlue : primaryGreen,
              iconTheme: const IconThemeData(color: Colors.white),
            ),
            body: Center(child: Text('No data', style: TextStyle(color: textColor))),
          );
        }

        // Calculate called count
        int calledCount = _customers!.where((c) => c['callMade'] == true).length;
        int totalCount = _customers!.length;

        // Sort customers based on called status
        List<Map<String, dynamic>> sortedCustomers = List<Map<String, dynamic>>.from(_customers!);
        sortedCustomers.sort((a, b) {
          if (_sortCalledFirst) {
            return (b['callMade'] == true ? 1 : 0) - (a['callMade'] == true ? 1 : 0);
          } else {
            return (a['callMade'] == true ? 1 : 0) - (b['callMade'] == true ? 1 : 0);
          }
        });

        return Scaffold(
          backgroundColor: bgColor,
          appBar: AppBar(
            title: Text('Customer List', style: TextStyle(color: Colors.white)),
            backgroundColor: isDark ? primaryBlue : primaryGreen,
            iconTheme: const IconThemeData(color: Colors.white),
            actions: [
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'Add Customer',
                onPressed: () async {
                  final added = await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => AddCustomerPage()),
                  );
                  if (added == true) {
                    _fetchCustomerData();
                  }
                },
              ),
            ],
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8),
                child: Row(
                  children: [
                    Text(
                      'Called: $calledCount / $totalCount',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF8CC63F), // changed to green
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _sortCalledFirst = !_sortCalledFirst;
                        });
                      },
                      icon: Icon(
                        _sortCalledFirst ? Icons.arrow_downward : Icons.arrow_upward,
                        color: isDark ? Colors.white : Colors.black,
                        size: 20,
                      ),
                      label: const Text('Sort', style: TextStyle(fontWeight: FontWeight.bold)),
                      style: TextButton.styleFrom(
                        foregroundColor: isDark ? Colors.white : Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 0), // Remove horizontal padding
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.vertical,
                      child: Container(
                        // Remove margin and set width to fill parent
                        width: MediaQuery.of(context).size.width,
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))],
                          border: Border.all(color: isDark ? Colors.grey.shade800 : Colors.grey.shade300),
                        ),
                        child: DataTable(
                          showCheckboxColumn: false,
                          headingRowColor: MaterialStateProperty.resolveWith<Color>(
                            (states) => isDark
                                ? primaryBlue.withOpacity(0.12)
                                : primaryGreen.withOpacity(0.18),
                          ),
                          dataRowColor: MaterialStateProperty.resolveWith<Color>(
                            (states) => states.contains(MaterialState.selected)
                                ? (isDark
                                    ? primaryGreen.withOpacity(0.18)
                                    : primaryBlue.withOpacity(0.12))
                                : (isDark ? const Color(0xFF181A20) : Colors.white),
                          ),
                          columns: [
                            DataColumn(
                              label: Text(
                                'Customer Name',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: textColor,
                                  fontFamily: 'NotoSans',
                                ),
                              ),
                            ),
                            DataColumn(
                              label: Text(
                                'Called',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: textColor,
                                  fontFamily: 'NotoSans',
                                ),
                              ),
                            ),
                          ],
                          rows: List<DataRow>.generate(
                            sortedCustomers.length,
                            (index) {
                              var customer = sortedCustomers[index];
                              bool callMade = customer['callMade'] == true;
                              return DataRow(
                                color: MaterialStateProperty.resolveWith<Color>(
                                  (states) => isDark ? const Color(0xFF181A20) : Colors.white,
                                ),
                                onSelectChanged: (_) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => SalesCustomerTileViewer(
                                        customer: customer,
                                        onStatusChanged: (remarks) async {
                                          setState(() {
                                            customer['callMade'] = true;
                                            customer['remarks'] = remarks;
                                          });
                                          await _updateFirestore();
                                        },
                                      ),
                                    ),
                                  );
                                },
                                // Add onLongPress for row options
                                onLongPress: () async {
                                  final action = await showModalBottomSheet<String>(
                                    context: context,
                                    builder: (context) => SafeArea(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          ListTile(
                                            leading: const Icon(Icons.edit, color: Colors.blue),
                                            title: const Text('Edit'),
                                            onTap: () => Navigator.pop(context, 'edit'),
                                          ),
                                          ListTile(
                                            leading: const Icon(Icons.delete, color: Colors.red),
                                            title: const Text('Delete'),
                                            onTap: () => Navigator.pop(context, 'delete'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                  if (action == 'edit') {
                                    // Go to edit page (reuse SalesCustomerTileViewer and trigger edit dialog)
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => SalesCustomerTileViewer(
                                          customer: customer,
                                          onStatusChanged: (remarks) async {
                                            setState(() {
                                              customer['callMade'] = true;
                                              customer['remarks'] = remarks;
                                            });
                                            await _updateFirestore();
                                          },
                                        ),
                                      ),
                                    );
                                    // Optionally, refresh after edit
                                    await _fetchCustomerData();
                                  } else if (action == 'delete') {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text('Delete Customer'),
                                        content: const Text('Are you sure you want to delete this customer?'),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(context, false),
                                            child: const Text('Cancel'),
                                          ),
                                          TextButton(
                                            onPressed: () => Navigator.pop(context, true),
                                            child: const Text('Delete', style: TextStyle(color: Colors.red)),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirm == true) {
                                      setState(() {
                                        _customers!.removeWhere((c) =>
                                          c['name'] == customer['name'] &&
                                          c['contact'] == customer['contact']
                                        );
                                      });
                                      await _updateFirestore();
                                      await _fetchCustomerData();
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Customer deleted.'), backgroundColor: Colors.red),
                                      );
                                    }
                                  }
                                },
                                cells: [
                                  DataCell(
                                    Text(
                                      customer['name'] ?? '',
                                      style: TextStyle(
                                        fontSize: 15,
                                        color: textColor,
                                        fontFamily: 'NotoSans',
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Icon(
                                      callMade ? Icons.check_circle : Icons.cancel,
                                      color: callMade ? primaryBlue : primaryGreen,
                                      size: 16,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                          border: TableBorder(
                            horizontalInside: BorderSide(
                              color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                              width: 0.7,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}