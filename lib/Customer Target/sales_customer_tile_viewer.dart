import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:call_log/call_log.dart';
import '../Todo & Leads/leadsform.dart';

class SalesCustomerTileViewer extends StatefulWidget {
  final Map<String, dynamic> customer;
  final Future<void> Function(String remarks)? onStatusChanged;
  const SalesCustomerTileViewer({Key? key, required this.customer, this.onStatusChanged}) : super(key: key);

  @override
  State<SalesCustomerTileViewer> createState() => _SalesCustomerTileViewerState();
}

class _SalesCustomerTileViewerState extends State<SalesCustomerTileViewer> with WidgetsBindingObserver {
  late Map<String, dynamic> customer;
  bool called = false;
  TextEditingController remarksController = TextEditingController();
  String? _pendingCallNumber;
  DateTime? _callStartTime;
  String? _lastRemarks;
  bool _loadingLastRemarks = false;
  bool _remarksSaved = false; // Add this flag

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    customer = Map<String, dynamic>.from(widget.customer);
    called = customer['callMade'] == true;
    remarksController.text = customer['remarks'] ?? '';
    remarksController.addListener(() {
      setState(() {
        _remarksSaved = false; // Reset flag when remarks change
      });
    });
    _fetchLastRemarks();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    remarksController.dispose();
    super.dispose();
  }

  Future<void> _makeCall(BuildContext context, String contact1, [String? contact2]) async {
    String? numberToCall = contact1;
    if (contact2 != null && contact2.isNotEmpty) {
      // Ask user which number to call
      numberToCall = await showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Select Number to Call'),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, contact1),
              child: Text(contact1),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, contact2),
              child: Text(contact2),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Cancel', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );
      if (numberToCall == null) return;
    }
    var status = await Permission.phone.request();
    if (!status.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Phone permission denied')),
      );
      return;
    }
    final uri = Uri(scheme: 'tel', path: numberToCall);
    if (await canLaunchUrl(uri)) {
      _pendingCallNumber = numberToCall;
      _callStartTime = DateTime.now();
      // Store the called number for leads
      setState(() {
        customer['lastCalledNumber'] = numberToCall;
      });
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not launch dialer')),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _pendingCallNumber != null) {
      _checkIfCallWasMade();
    }
  }

  Future<void> _checkIfCallWasMade() async {
    if (_pendingCallNumber == null || _callStartTime == null) return;
    try {
      final now = DateTime.now();
      final Iterable<CallLogEntry> entries = await CallLog.query(
        dateFrom: _callStartTime!.millisecondsSinceEpoch,
        dateTo: now.millisecondsSinceEpoch,
      );
      // Accept call to either contact1 or contact2
      String? c1 = customer['contact1'] ?? customer['contact'];
      String? c2 = customer['contact2'];
      bool callMade = entries.any((entry) {
        String logNumber = entry.number?.replaceAll(RegExp(r'\\D'), '') ?? '';
        bool wasConnected = (entry.duration ?? 0) > 0;
        bool matches1 = c1 != null && logNumber.endsWith(c1.replaceAll(RegExp(r'\\D'), ''));
        bool matches2 = c2 != null && c2.isNotEmpty && logNumber.endsWith(c2.replaceAll(RegExp(r'\\D'), ''));
        return (matches1 || matches2) && wasConnected;
      });
      if (callMade) {
        setState(() {
          called = true;
          customer['callMade'] = true;
        });
        // Update Firestore to persist callMade status
        await _updateCallStatusInFirestore();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Call detected! Please add remarks.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
        Future.delayed(const Duration(milliseconds: 300), () {
          Scrollable.ensureVisible(
            context,
            alignment: 1.0,
            duration: const Duration(milliseconds: 500),
          );
        });
      }
    } catch (e) {
      debugPrint('Error checking call log: $e');
    } finally {
      _pendingCallNumber = null;
      _callStartTime = null;
    }
  }

  Future<void> _updateCallStatusInFirestore() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final now = DateTime.now();
      final months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      final monthYear = "${months[now.month - 1]} ${now.year}";
      final docRef = FirebaseFirestore.instance
          .collection('customer_target')
          .doc(monthYear)
          .collection('users')
          .doc(user.email);
      final doc = await docRef.get();
      if (doc.exists && doc.data()?['customers'] != null) {
        List customers = List.from(doc.data()!['customers']);
        // Find the customer by contact1/contact
        String? c1 = customer['contact1'] ?? customer['contact'];
        String? c2 = customer['contact2'];
        int idx = customers.indexWhere((c) =>
          (c['contact'] == c1) || (c2 != null && c2.isNotEmpty && c['contact'] == c2)
        );
        if (idx != -1) {
          customers[idx]['callMade'] = true;
          await docRef.update({'customers': customers});
        }
      }
    } catch (e) {
      debugPrint('Failed to update callMade in Firestore: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update call status in Firestore: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<bool> _onWillPop() async {
    if (called && remarksController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter remarks before leaving.'), backgroundColor: Colors.red),
      );
      return false;
    }
    return true;
  }

  String _formatFieldName(String key) {
    return key.split('_').map((word) => word[0].toUpperCase() + word.substring(1)).join(' ');
  }

  Future<void> _editCustomerDialog() async {
    final nameController = TextEditingController(text: customer['name'] ?? '');
    final addressController = TextEditingController(text: customer['address'] ?? '');
    final contact1Controller = TextEditingController(text: customer['contact1'] ?? customer['contact'] ?? '');
    final contact2Controller = TextEditingController(text: customer['contact2'] ?? '');
    final formKey = GlobalKey<FormState>();
    bool loading = false;
    String? error;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('Edit Customer'),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(error!, style: const TextStyle(color: Colors.red)),
                    ),
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Customer Name'),
                    validator: (v) => v == null || v.trim().isEmpty ? 'Enter name' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: addressController,
                    decoration: const InputDecoration(labelText: 'Address'),
                    validator: (v) => v == null || v.trim().isEmpty ? 'Enter address' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: contact1Controller,
                    decoration: const InputDecoration(labelText: 'Contact Number 1'),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Enter contact';
                      if (v.length != 10) return 'Enter exactly 10 digits';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: contact2Controller,
                    decoration: const InputDecoration(labelText: 'Contact Number 2 (optional)'),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    validator: (v) {
                      if (v != null && v.isNotEmpty && v.length != 10) return 'Enter exactly 10 digits';
                      return null;
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: loading ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: loading
                    ? null
                    : () async {
                        if (!formKey.currentState!.validate()) return;
                        setState(() => loading = true);
                        try {
                          // Update local state
                          this.setState(() {
                            customer['name'] = nameController.text.trim();
                            customer['address'] = addressController.text.trim();
                            customer['contact1'] = contact1Controller.text.trim();
                            customer['contact2'] = contact2Controller.text.trim();
                            customer['contact'] = contact1Controller.text.trim();
                          });
                          // Update Firestore
                          final user = FirebaseAuth.instance.currentUser;
                          if (user != null) {
                            final docId = user.email;
                            final now = DateTime.now();
                            final months = [
                              'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                              'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
                            ];
                            final monthYear = "${months[now.month - 1]} ${now.year}";
                            final docRef = FirebaseFirestore.instance
                                .collection('customer_target')
                                .doc(monthYear)
                                .collection('users')
                                .doc(docId);
                            final doc = await docRef.get();
                            if (doc.exists && doc.data()?['customers'] != null) {
                              List customers = List.from(doc.data()!['customers']);
                              int idx = customers.indexWhere((c) =>
                                  (c['name'] == widget.customer['name'] &&
                                   (c['contact1'] ?? c['contact']) == (widget.customer['contact1'] ?? widget.customer['contact'])));
                              if (idx != -1) {
                                customers[idx]['name'] = nameController.text.trim();
                                customers[idx]['address'] = addressController.text.trim();
                                customers[idx]['contact1'] = contact1Controller.text.trim();
                                customers[idx]['contact2'] = contact2Controller.text.trim();
                                customers[idx]['contact'] = contact1Controller.text.trim();
                                await docRef.update({'customers': customers});
                              }
                            }
                          }
                          Navigator.pop(context);
                        } catch (e) {
                          setState(() => error = 'Failed to update: $e');
                        } finally {
                          setState(() => loading = false);
                        }
                      },
                child: loading
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Save'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _fetchLastRemarks() async {
    setState(() {
      _loadingLastRemarks = true;
    });
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      // Support both contact1/contact2 and contact
      final contact1 = customer['contact1'] ?? customer['contact'];
      final contact2 = customer['contact2'];
      if ((contact1 == null || contact1.isEmpty) && (contact2 == null || contact2.isEmpty)) return;

      // Get previous month and year
      final now = DateTime.now();
      final months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      final prev = DateTime(now.year, now.month - 1, 1);
      final monthYear = "${months[prev.month - 1]} ${prev.year}";
      final doc = await FirebaseFirestore.instance
          .collection('customer_target')
          .doc(monthYear)
          .collection('users')
          .doc(user.email)
          .get();
      if (doc.exists && doc.data()?['customers'] != null) {
        final List customers = doc.data()!['customers'];
        // Try to find by contact1, then contact2
        dynamic prevCustomer;
        if (contact1 != null && contact1.isNotEmpty) {
          prevCustomer = customers.firstWhere(
            (c) => c['contact'] == contact1,
            orElse: () => null,
          );
        }
        if ((prevCustomer == null || prevCustomer['remarks'] == null || prevCustomer['remarks'].toString().trim().isEmpty) &&
            contact2 != null && contact2.isNotEmpty) {
          prevCustomer = customers.firstWhere(
            (c) => c['contact'] == contact2,
            orElse: () => null,
          );
        }
        if (prevCustomer != null && prevCustomer['remarks'] != null && prevCustomer['remarks'].toString().trim().isNotEmpty) {
          setState(() {
            _lastRemarks = prevCustomer['remarks'];
            _loadingLastRemarks = false;
          });
          return;
        }
      }
      setState(() {
        _lastRemarks = null;
        _loadingLastRemarks = false;
      });
    } catch (e) {
      setState(() {
        _lastRemarks = null;
        _loadingLastRemarks = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final Color blue = const Color(0xFF005BAC);
    final Color green = const Color.fromARGB(255, 108, 185, 13);
    final primaryColor = called ? green : blue;
    final swappedColor = called ? green : blue;

    String? contact1 = customer['contact1'] ?? customer['contact'];
    String? contact2 = customer['contact2'];
    String? customerName = customer['name'];
    String? address = customer['address'];
    List<MapEntry<String, dynamic>> fields = [];

    // Add contact numbers as the first fields in details
    if (contact1 != null && contact1.isNotEmpty) {
      fields.add(MapEntry('contact_no_1', contact1));
    }
    if (contact2 != null && contact2.isNotEmpty) {
      fields.add(MapEntry('contact_no_2', contact2));
    }

    // Add address as a field just after contact numbers
    if (address != null && address.isNotEmpty) {
      fields.add(MapEntry('address', address));
    }

    customer.forEach((key, value) {
      if (key == 'slno' || key == 'remarks' || key == 'callMade' || key == 'contact' || key == 'contact1' || key == 'contact2' || key == 'address' || key == 'lastCalledNumber') return;
      if (key == 'name') {
        // handled separately
      } else {
        fields.add(MapEntry(key, value));
      }
    });

    bool remarksEntered = remarksController.text.trim().isNotEmpty;

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          elevation: 0,
          title: const Text('Customer Details', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          backgroundColor: primaryColor,
          iconTheme: const IconThemeData(color: Colors.white),
          actions: [
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: 'Edit Customer',
              onPressed: _editCustomerDialog,
            ),
          ],
        ),
        body: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Card with Contact Info
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [primaryColor, primaryColor.withOpacity(0.8)],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          called ? Icons.check_circle : Icons.person,
                          size: 50,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (customerName != null) ...[
                        Text(
                          customerName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        if (contact1 != null && contact1.isNotEmpty)
                          called
                              // Call Completed: white background, swapped color text
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(25),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                    ),
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: null,
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.phone, color: primaryColor),
                                              const SizedBox(width: 8),
                                              Text(
                                                'Call Completed',
                                                style: TextStyle(
                                                  color: primaryColor,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                              // Make Call: gradient button
                              : ClipRRect(
                                  borderRadius: BorderRadius.circular(25),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          primaryColor,
                                          primaryColor.withOpacity(0.8),
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                    ),
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: () => _makeCall(context, contact1, contact2),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.phone, color: Colors.white),
                                              const SizedBox(width: 8),
                                              const Text(
                                                'Make Call',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                      ],
                    ],
                  ),
                ),
              ),

              // Status Indicator
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: called
                      ? swappedColor.withOpacity(0.1)
                      : Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: called ? swappedColor : Colors.orange,
                    width: 2,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      called ? Icons.check_circle : Icons.pending,
                      color: called ? swappedColor : Colors.orange,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            called ? 'Call Completed' : 'Call Pending',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: called ? swappedColor : Colors.orange[700],
                            ),
                          ),
                          Text(
                            called ? 'Please add remarks below' : 'Tap the button above to call',
                            style: TextStyle(
                              fontSize: 14,
                              color: called ? swappedColor : Colors.orange[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Customer Details Section
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Customer Details',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Details Cards (now includes contact numbers at the top)
              ...fields.map((entry) => Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[850] : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _formatFieldName(entry.key),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      entry.value?.toString() ?? '-',
                      style: TextStyle(
                        fontSize: 16,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ],
                ),
              )).toList(),

              // --- Last Remarks Section ---
              if (_loadingLastRemarks)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: LinearProgressIndicator(),
                ),
              if (!_loadingLastRemarks && _lastRemarks != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Last Remarks',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _lastRemarks!,
                          style: const TextStyle(fontSize: 15, color: Colors.black87),
                        ),
                      ),
                    ],
                  ),
                ),

              // --- Remarks Section ---
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Remarks',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[850] : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: TextFormField(
                  controller: remarksController,
                  enabled: called,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: called ? 'Enter call remarks here...' : 'Complete the call first to add remarks',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: primaryColor, width: 2),
                    ),
                    disabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey[200]!),
                    ),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                    fontSize: 16,
                  ),
                ),
              ),
              // Save Button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: remarksEntered
                          ? LinearGradient(
                              colors: [
                                primaryColor,
                                primaryColor.withOpacity(0.8),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : null,
                      color: remarksEntered ? null : Colors.grey[400],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: called && remarksEntered
                            ? () async {
                                customer['remarks'] = remarksController.text.trim();
                                if (widget.onStatusChanged != null) {
                                  await widget.onStatusChanged!(customer['remarks']);
                                }
                                setState(() {
                                  _remarksSaved = true; // Set flag after save
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Remarks saved.'), backgroundColor: Colors.green),
                                );
                              }
                            : null,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.save, color: remarksEntered ? Colors.white : Colors.white70),
                              const SizedBox(width: 8),
                              Text(
                                'Save',
                                style: TextStyle(
                                  color: remarksEntered ? Colors.white : Colors.white70,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Add To Leads Button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: (_remarksSaved && remarksEntered)
                          ? LinearGradient(
                              colors: [
                                primaryColor,
                                primaryColor.withOpacity(0.8),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : null,
                      color: (_remarksSaved && remarksEntered) ? null : Colors.grey[400],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: (called && remarksEntered && _remarksSaved)
                            ? () async {
                                // Always use lastCalledNumber for leads
                                String? phone = customer['lastCalledNumber'] ?? customer['contact1'] ?? customer['contact'] ?? customer['phone'];
                                String? name = customer['name'];
                                String? address = customer['address'];
                                Map<String, dynamic>? customerData;

                                if (phone != null && phone.isNotEmpty) {
                                  final snap = await FirebaseFirestore.instance
                                      .collection('customer')
                                      .where('phone', isEqualTo: phone)
                                      .limit(1)
                                      .get();
                                  if (snap.docs.isNotEmpty) {
                                    customerData = snap.docs.first.data();
                                  }
                                }

                                final prefillName = customerData?['name'] ?? name ?? '';
                                final prefillPhone = customerData?['phone'] ?? phone ?? '';
                                final prefillAddress = customerData?['address'] ?? address ?? '';

                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) => FollowUpForm(
                                      key: UniqueKey(),
                                      initialName: prefillName,
                                      initialPhone: prefillPhone,
                                      initialAddress: prefillAddress,
                                    ),
                                  ),
                                );
                              }
                            : null,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add, color: (_remarksSaved && remarksEntered) ? Colors.white : Colors.white70),
                              const SizedBox(width: 8),
                              Text(
                                'Add To Leads',
                                style: TextStyle(
                                  color: (_remarksSaved && remarksEntered) ? Colors.white : Colors.white70,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}