import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:call_log/call_log.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Customer List')),
        body: Center(child: Text(_error!)),
      );
    }

    if (_customers == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Customer List')),
        body: const Center(child: Text('No data')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer List'),
      ),
      body: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Sl. No')),
              DataColumn(label: Text('Customer Name')),
              DataColumn(label: Text('Contact No.')),
              DataColumn(label: Text('Called')),
              DataColumn(label: Text('Remarks')),
            ],
            rows: _customers!.asMap().entries.map((entry) {
              int idx = entry.key;
              var customer = entry.value;
              bool callMade = customer['callMade'] == true;

              return DataRow(
                cells: [
                  DataCell(Text(customer['slno'] ?? '')),
                  DataCell(Text(customer['name'] ?? '')),
                  DataCell(
                    InkWell(
                      child: Text(
                        customer['contact'] ?? '',
                        style: const TextStyle(
                          color: Colors.blue,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                      onTap: () => _makeCall(customer['contact'] ?? '', idx),
                    ),
                  ),
                  DataCell(
                    Icon(
                      callMade ? Icons.check_circle : Icons.cancel,
                      color: callMade ? Colors.green : Colors.red,
                    ),
                  ),
                  DataCell(
                    TextFormField(
                      initialValue: customer['remarks'] ?? '',
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: 'Enter remarks',
                      ),
                      onChanged: (val) {
                        setState(() {
                          _customers![idx]['remarks'] = val;
                        });
                        _updateFirestore();
                      },
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}