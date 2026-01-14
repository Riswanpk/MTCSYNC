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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    customer = Map<String, dynamic>.from(widget.customer);
    called = customer['callMade'] == true;
    remarksController.text = customer['remarks'] ?? '';
    remarksController.addListener(() {
      setState(() {}); // Rebuild to update save button state
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    remarksController.dispose();
    super.dispose();
  }

  Future<void> _makeCall(BuildContext context, String contact) async {
    var status = await Permission.phone.request();
    if (!status.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Phone permission denied')),
      );
      return;
    }
    final uri = Uri(scheme: 'tel', path: contact);
    if (await canLaunchUrl(uri)) {
      _pendingCallNumber = contact;
      _callStartTime = DateTime.now();
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
      bool callMade = entries.any((entry) {
        String logNumber = entry.number?.replaceAll(RegExp(r'\D'), '') ?? '';
        String pendingNumber = _pendingCallNumber!.replaceAll(RegExp(r'\D'), '');
        // Check if call was connected (duration > 0)
        bool numberMatches = logNumber.endsWith(pendingNumber) || pendingNumber.endsWith(logNumber);
        bool wasConnected = (entry.duration ?? 0) > 0;
        return numberMatches && wasConnected;
      });
      if (callMade) {
        setState(() {
          called = true;
          customer['callMade'] = true;
        });
        _pendingCallNumber = null;
        _callStartTime = null;
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Call detected! Please add remarks.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
        
        // Auto-scroll to remarks field
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
    final contactController = TextEditingController(text: customer['contact'] ?? '');
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
                    controller: contactController,
                    decoration: const InputDecoration(labelText: 'Contact Number'),
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
                            customer['contact'] = contactController.text.trim();
                          });
                          // Update Firestore
                          final user = FirebaseAuth.instance.currentUser;
                          if (user != null) {
                            final docId = user.email;
                            final docRef = FirebaseFirestore.instance.collection('customer_target').doc(docId);
                            final doc = await docRef.get();
                            if (doc.exists && doc.data()?['customers'] != null) {
                              List customers = List.from(doc.data()!['customers']);
                              int idx = customers.indexWhere((c) =>
                                  (c['name'] == widget.customer['name'] && c['contact'] == widget.customer['contact']));
                              if (idx != -1) {
                                customers[idx]['name'] = nameController.text.trim();
                                customers[idx]['contact'] = contactController.text.trim();
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Swap blue and green if called
    final Color blue = const Color(0xFF005BAC);
    final Color green = const Color.fromARGB(255, 108, 185, 13);
    final primaryColor = called
        ? (isDark ? blue : green)
        : (isDark ? green : blue);

    final swappedColor = called
        ? (isDark ? green : blue)
        : (isDark ? blue : green);

    String? contactNumber;
    String? customerName;
    List<MapEntry<String, dynamic>> fields = [];
    
    customer.forEach((key, value) {
      if (key == 'slno' || key == 'remarks' || key == 'callMade') return;
      if (key == 'contact') {
        contactNumber = value?.toString();
        fields.add(MapEntry(key, value)); // Add contact to details
      } else if (key == 'name') {
        customerName = value?.toString();
        // Do NOT add name to fields (removes name box from details)
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
                          customerName!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        if (contactNumber != null)
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
                                        onTap: () => _makeCall(context, contactNumber!),
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

              // Details Cards (name field removed)
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

              // Remarks Section
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
                                // Fetch customer details from Firestore if exists
                                String? phone = customer['contact'] ?? customer['phone'];
                                String? name = customer['name'];
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

                                // Use Firestore data if exists, else fallback to current
                                final prefillName = customerData?['name'] ?? name ?? '';
                                final prefillPhone = customerData?['phone'] ?? phone ?? '';
                                final prefillAddress = customerData?['address'] ?? '';

                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) => FollowUpForm(
                                      // Pass initial values using a constructor or static method
                                      // You may need to add these parameters to FollowUpForm
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
                              Icon(Icons.add, color: remarksEntered ? Colors.white : Colors.white70),
                              const SizedBox(width: 8),
                              Text(
                                'Add To Leads',
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
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}