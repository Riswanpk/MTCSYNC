import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'tile_viewer/make_call.dart';
import 'tile_viewer/check_call_log_helper.dart';
import 'tile_viewer/fetch_last_remarks.dart';
import 'tile_viewer/update_remarks_in_firestore.dart';
import 'tile_viewer/edit_customer_dialog.dart';
import 'tile_viewer/customer_header_card.dart';
import 'tile_viewer/customer_status_indicator.dart';
import 'tile_viewer/customer_details_section.dart';
import 'tile_viewer/customer_last_remarks_section.dart';
import 'tile_viewer/customer_remarks_section.dart';
import 'tile_viewer/add_to_leads_button.dart';

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
  List<Map<String, String>> _pastRemarks = [];
  bool _loadingLastRemarks = false;
  bool _remarksSaved = false;
  bool _checkingCall = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    customer = Map<String, dynamic>.from(widget.customer);
    called = customer['callMade'] == true;
    remarksController.text = customer['remarks'] ?? '';
    remarksController.addListener(() {
      setState(() {
        _remarksSaved = false;
      });
    });
    _restorePendingCallState();
    _checkForAnyRecentCall();
    _fetchLastRemarksData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    remarksController.dispose();
    super.dispose();
  }

  Future<void> _restorePendingCallState() async {
    if (called) return;
    final prefs = await SharedPreferences.getInstance();
    final key = customerUniqueKey(customer);
    final savedNumber = prefs.getString('pending_call_number_$key');
    final savedTime = prefs.getInt('pending_call_time_$key');
    if (savedNumber != null && savedNumber.isNotEmpty && savedTime != null && savedTime > 0) {
      _pendingCallNumber = savedNumber;
      _callStartTime = DateTime.fromMillisecondsSinceEpoch(savedTime);
      _checkIfCallWasMade();
    }
  }

  Future<void> _checkIfCallWasMade() async {
    if (_pendingCallNumber == null || _callStartTime == null) return;
    if (_checkingCall) return;
    _checkingCall = true;
    try {
      await checkIfCallWasMade(
        customer: customer,
        pendingCallNumber: _pendingCallNumber,
        callStartTime: _callStartTime,
        context: context,
        mounted: mounted,
        onCallDetected: () {
          if (mounted) {
            setState(() {
              called = true;
            });
          } else {
            called = true;
          }
          _pendingCallNumber = null;
          _callStartTime = null;

          if (mounted) {
            Future.delayed(const Duration(milliseconds: 300), () {
              try {
                if (mounted) {
                  Scrollable.ensureVisible(
                    context,
                    alignment: 1.0,
                    duration: const Duration(milliseconds: 500),
                  );
                }
              } catch (_) {}
            });
          }
        },
      );
    } finally {
      _checkingCall = false;
    }
  }

  Future<void> _checkForAnyRecentCall() async {
    if (called) return;
    await checkForAnyRecentCall(
      customer: customer,
      context: context,
      mounted: mounted,
      onCallDetected: () {
        if (mounted) {
          setState(() {
            called = true;
          });
        } else {
          called = true;
        }
        _pendingCallNumber = null;
        _callStartTime = null;
      },
    );
  }

  Future<void> _reloadCallStatus() async {
    await reloadCallStatus(
      customer: customer,
      called: called,
      context: context,
      mounted: mounted,
      onCallDetected: () {
        if (mounted) {
          setState(() {
            called = true;
          });
        } else {
          called = true;
        }
        _pendingCallNumber = null;
        _callStartTime = null;
      },
    );
  }

  Future<void> _fetchLastRemarksData() async {
    if (!mounted) return;
    setState(() {
      _loadingLastRemarks = true;
    });
    final results = await fetchLastRemarks(customer: customer);
    if (mounted) {
      setState(() {
        _pastRemarks = results;
        _loadingLastRemarks = false;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_pendingCallNumber != null) {
        _checkIfCallWasMade().then((_) {
          if (!called && _pendingCallNumber != null && mounted) {
            Future.delayed(const Duration(seconds: 3), () {
              if (mounted && !called) _checkIfCallWasMade();
            });
          }
        });
      } else if (!called) {
        _checkForAnyRecentCall();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color blue = const Color(0xFF005BAC);
    final Color green = const Color.fromARGB(255, 108, 185, 13);
    final primaryColor = called ? green : blue;
    final swappedColor = called ? green : blue;

    String? contact1 = customer['contact1'] ?? customer['contact'];
    String? contact2 = customer['contact2'];
    String? customerName = customer['name'];
    String? address = customer['address'];
    List<MapEntry<String, dynamic>> fields = [];

    if (contact1 != null && contact1.isNotEmpty) {
      fields.add(MapEntry('contact_no_1', contact1));
    }
    if (contact2 != null && contact2.isNotEmpty) {
      fields.add(MapEntry('contact_no_2', contact2));
    }
    if (address != null && address.isNotEmpty) {
      fields.add(MapEntry('address', address));
    }

    customer.forEach((key, value) {
      if (key == 'slno' || key == 'remarks' || key == 'callMade' || key == 'callDate' || key == 'contact' || key == 'contact1' || key == 'contact2' || key == 'address' || key == 'lastCalledNumber' || key == 'lastRemarks' || key == 'pendingDeletion') return;
      if (key != 'name') {
        fields.add(MapEntry(key, value));
      }
    });

    bool remarksEntered = remarksController.text.trim().isNotEmpty;

    return PopScope(
      canPop: !(called && remarksController.text.trim().isEmpty),
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop && called && remarksController.text.trim().isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please enter remarks before leaving.'), backgroundColor: Colors.red),
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(
          elevation: 0,
          title: const Text('Customer Details', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          backgroundColor: primaryColor,
          iconTheme: const IconThemeData(color: Colors.white),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Reload Call Status',
              onPressed: _reloadCallStatus,
            ),
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: 'Edit Customer',
              onPressed: () {
                editCustomerDialog(
                  context: context,
                  customer: customer,
                  widgetCustomer: widget.customer,
                  onUpdated: (updatedFields) {
                    setState(() {
                      customer.addAll(updatedFields);
                    });
                  },
                );
              },
            ),
          ],
        ),
        body: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CustomerHeaderCard(
                customerName: customerName,
                contact1: contact1,
                contact2: contact2,
                called: called,
                primaryColor: primaryColor,
                onCallPressed: () {
                  makeCall(
                    context,
                    customer,
                    contact1 ?? '',
                    contact2,
                    (numberToCall, startTime) {
                      setState(() {
                        _pendingCallNumber = numberToCall;
                        _callStartTime = startTime;
                        customer['lastCalledNumber'] = numberToCall;
                      });
                    },
                  );
                },
              ),
              CustomerStatusIndicator(
                called: called,
                swappedColor: swappedColor,
              ),
              CustomerDetailsSection(
                fields: fields,
              ),
              CustomerLastRemarksSection(
                loadingLastRemarks: _loadingLastRemarks,
                pastRemarks: _pastRemarks,
              ),
              CustomerRemarksSection(
                remarksController: remarksController,
                called: called,
                remarksEntered: remarksEntered,
                primaryColor: primaryColor,
                onSavePressed: (called && remarksEntered)
                    ? () async {
                        final remarks = remarksController.text.trim();
                        if (customer.isNotEmpty) {
                          customer['remarks'] = remarks;
                          await updateRemarksInFirestore(
                            customer: customer,
                            remarks: remarks,
                            context: context,
                            mounted: mounted,
                          );
                          if (widget.onStatusChanged != null) {
                            await widget.onStatusChanged!(remarks);
                          }
                          if (mounted) {
                            setState(() {
                              _remarksSaved = true;
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Remarks saved.'), backgroundColor: Colors.green),
                            );
                          }
                        }
                      }
                    : null,
              ),
              AddToLeadsButton(
                customer: customer,
                called: called,
                remarksEntered: remarksEntered,
                remarksSaved: _remarksSaved,
                primaryColor: primaryColor,
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}