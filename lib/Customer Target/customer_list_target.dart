import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:call_log/call_log.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';

import '../Misc/theme_notifier.dart';

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
      final doc = await FirebaseFirestore.instance.collection('customer_target').doc(_docId).get();
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
      await FirebaseFirestore.instance
          .collection('customer_target')
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
        final textColor = isDark ? Colors.white : Colors.black87;

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

        return Scaffold(
          backgroundColor: bgColor,
          appBar: AppBar(
            title: Text('Customer List', style: TextStyle(color: Colors.white)),
            backgroundColor: isDark ? primaryBlue : primaryGreen,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: Container(
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))],
                  border: Border.all(color: isDark ? Colors.grey.shade800 : Colors.grey.shade300),
                ),
                child: DataTable(
                  headingRowColor: MaterialStateProperty.resolveWith<Color>(
                    (states) => isDark
                        ? primaryBlue.withOpacity(0.12)
                        : primaryGreen.withOpacity(0.18), // blue for light
                  ),
                  dataRowColor: MaterialStateProperty.resolveWith<Color>(
                    (states) => states.contains(MaterialState.selected)
                        ? (isDark
                            ? primaryGreen.withOpacity(0.18)
                            : primaryBlue.withOpacity(0.12)) // green for light
                        : (isDark ? const Color(0xFF181A20) : Colors.white),
                  ),
                  columns: [
                    DataColumn(label: Text('Sl. No', style: TextStyle(fontSize: 11, color: primaryGreen))),
                    DataColumn(label: Text('Customer Name', style: TextStyle(fontSize: 11, color: primaryBlue))),
                    DataColumn(label: Text('Contact No.', style: TextStyle(fontSize: 11, color: primaryGreen))),
                    DataColumn(label: Text('Called', style: TextStyle(fontSize: 11, color: primaryBlue))),
                    DataColumn(label: Text('Remarks', style: TextStyle(fontSize: 11, color: primaryGreen))),
                  ],
                  rows: List<DataRow>.generate(
                    _customers!.length,
                    (index) {
                      var customer = _customers![index];
                      bool callMade = customer['callMade'] == true;
                      final isEven = index % 2 == 0;
                      return DataRow(
                        color: MaterialStateProperty.resolveWith<Color>(
                          (states) => isDark
                              ? (isEven ? primaryBlue.withOpacity(0.06) : primaryGreen.withOpacity(0.06))
                              : (isEven ? primaryGreen.withOpacity(0.06) : primaryBlue.withOpacity(0.06)),
                        ),
                        cells: [
                          DataCell(Text(customer['slno'] ?? '', style: TextStyle(fontSize: 11, color: primaryGreen))),
                          DataCell(Text(customer['name'] ?? '', style: TextStyle(fontSize: 11, color: primaryBlue))),
                          DataCell(
                            InkWell(
                              child: Text(
                                customer['contact'] ?? '',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: primaryBlue,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                              onTap: () => _makeCall(customer['contact'] ?? '', index),
                            ),
                          ),
                          DataCell(
                            Icon(
                              callMade ? Icons.check_circle : Icons.cancel,
                              color: callMade ? primaryBlue : primaryGreen,
                              size: 16,
                            ),
                          ),
                          DataCell(
                            TextFormField(
                              initialValue: customer['remarks'] ?? '',
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                hintText: 'Enter remarks',
                              ),
                              style: TextStyle(fontSize: 11, color: primaryGreen),
                              onChanged: (val) {
                                setState(() {
                                  _customers![index]['remarks'] = val;
                                });
                                _updateFirestore();
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  border: TableBorder(
                    horizontalInside: BorderSide(color: isDark ? primaryBlue.withOpacity(0.18) : primaryGreen.withOpacity(0.18), width: 0.5),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}