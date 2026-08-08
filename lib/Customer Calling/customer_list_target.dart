import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';

import '../Misc/theme_notifier.dart';
import 'customer_target_customer_tile_viewer.dart';
import 'customer_calling_remarks_pending.dart';
import 'customer_list_target_service.dart';
import 'customer_list_tile_item.dart';
import 'call_scanner_service.dart';
import 'call_detected_remarks_dialog.dart';
import 'add_customer.dart';

class CustomerListTarget extends StatefulWidget {
  const CustomerListTarget({super.key});

  @override
  State<CustomerListTarget> createState() => _CustomerListTargetState();
}

class _CustomerListTargetState extends State<CustomerListTarget> with WidgetsBindingObserver {
  List<Map<String, dynamic>>? _customers;
  bool _loading = true;
  String? _error;
  String? _docId;
  /// True only after the current month's doc was confirmed from Firestore.
  bool _firestoreConfirmed = false;
  /// True while the tile viewer is open.
  bool _isTileViewerOpen = false;
  bool _sortCalledFirst = true;
  String _searchText = '';
  bool _showSearchBar = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchCustomerData().then((_) => _autoScanCallLog());
  }

  Future<void> _fetchCustomerData() async {
    if (!mounted) return;
    setState(() {
      _error = null;
    });
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (!mounted) return;
        setState(() {
          _error = "Not logged in";
          _loading = false;
        });
        return;
      }
      _docId = user.email!.toLowerCase();

      // Load from local cache for instant display on first load
      if (_customers == null) {
        final cached = await _loadFromLocalCache();
        if (!mounted) return;
        if (cached != null) {
          setState(() {
            _customers = cached;
            _loading = false;
          });
        } else {
          setState(() {
            _loading = true;
          });
        }
      }

      // Fetch latest from Firestore
      final now = DateTime.now();
      final monthYear = "${CustomerListTargetService.monthName(now.month)} ${now.year}";

      final usersRef = FirebaseFirestore.instance
          .collection('customer_target')
          .doc(monthYear)
          .collection('users');

      var doc = await usersRef.doc(_docId).get();

      // If not found with lowercase email, search case-insensitively
      if (!doc.exists || doc.data()?['customers'] == null) {
        final querySnap = await usersRef.get();
        for (final d in querySnap.docs) {
          if (d.id.toLowerCase() == _docId!.toLowerCase() && d.id != _docId) {
            final oldData = d.data();
            await usersRef.doc(_docId).set(oldData);
            await usersRef.doc(d.id).delete();
            doc = await usersRef.doc(_docId).get();
            break;
          }
        }
      }

      if (!mounted) return;
      if (doc.exists && doc.data()?['customers'] != null) {
        final List<dynamic> data = doc.data()!['customers'];
        final customers = data.map((e) => Map<String, dynamic>.from(e)).toList();
        setState(() {
          _customers = customers;
          _loading = false;
        });
        _firestoreConfirmed = true;
        await _saveToLocalCache();
      } else {
        // Document missing for this month – try to copy from previous month
        final previousMonthData = await _tryGetPreviousMonthData();
        if (previousMonthData != null) {
          final newData = previousMonthData.map((e) {
            final copy = Map<String, dynamic>.from(e);
            copy['callMade'] = false;
            copy['remarks'] = '';
            return copy;
          }).toList();

          await usersRef.doc(_docId).set({'customers': newData});

          setState(() {
            _customers = newData;
            _loading = false;
          });
          _firestoreConfirmed = true;
          await _saveToLocalCache();

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Customer list initialized from previous month'),
                backgroundColor: Colors.blue,
                duration: Duration(seconds: 2),
              ),
            );
          }
        } else {
          _firestoreConfirmed = false;
          setState(() {
            _loading = false;
          });
        }
      }
    } catch (e) {
      if (!mounted) return;
      if (_customers != null) {
        setState(() {
          _loading = false;
        });
      } else {
        setState(() {
          _error = "Error: $e";
          _loading = false;
        });
      }
    }
  }

  Future<List<Map<String, dynamic>>?> _tryGetPreviousMonthData() async {
    if (_docId == null) return null;

    try {
      final now = DateTime.now();
      final prevDate = DateTime(now.year, now.month - 1);
      final prevMonthYear =
          "${CustomerListTargetService.monthName(prevDate.month)} ${prevDate.year}";

      final prevUsersRef = FirebaseFirestore.instance
          .collection('customer_target')
          .doc(prevMonthYear)
          .collection('users');

      var prevDoc = await prevUsersRef.doc(_docId).get();

      if (!prevDoc.exists || prevDoc.data()?['customers'] == null) {
        final querySnap = await prevUsersRef.get();
        for (final d in querySnap.docs) {
          if (d.id.toLowerCase() == _docId!.toLowerCase()) {
            prevDoc = d;
            break;
          }
        }
      }

      if (prevDoc.exists && prevDoc.data()?['customers'] != null) {
        final List<dynamic> data = prevDoc.data()!['customers'];
        return data.map((e) => Map<String, dynamic>.from(e)).toList();
      }

      return null;
    } catch (e) {
      debugPrint('Error fetching previous month data: $e');
      return null;
    }
  }

  String _cacheKey() {
    final now = DateTime.now();
    final monthYear =
        "${CustomerListTargetService.monthName(now.month)} ${now.year}";
    return 'customer_list_${_docId}_$monthYear';
  }

  Future<void> _saveToLocalCache() async {
    if (_customers == null || _docId == null) return;
    final prefs = await SharedPreferences.getInstance();
    final customersJson = jsonEncode(_customers, toEncodable: (nonEncodable) {
      if (nonEncodable is Timestamp) {
        return nonEncodable.toDate().toIso8601String();
      }
      return nonEncodable.toString();
    });
    await prefs.setString(_cacheKey(), customersJson);
  }

  Future<List<Map<String, dynamic>>?> _loadFromLocalCache() async {
    if (_docId == null) return null;
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_cacheKey());
    if (cached != null) {
      final List<dynamic> data = jsonDecode(cached);
      final list = data.map((e) => Map<String, dynamic>.from(e)).toList();
      for (final customer in list) {
        final rawDate = customer['callDate'];
        if (rawDate != null && rawDate is String) {
          final date = DateTime.tryParse(rawDate);
          if (date != null) {
            customer['callDate'] = Timestamp.fromDate(date);
          }
        }
      }
      return list;
    }
    return null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_isTileViewerOpen) return;
      _fetchCustomerData().then((_) => _autoScanCallLog());
    }
  }

  /// Silently scans today's call log and auto-marks customers as called
  Future<void> _autoScanCallLog() async {
    if (_customers == null || _customers!.isEmpty) return;

    final newlyCalled = await CallScannerService.scanTodayCallLog(_customers!);
    if (newlyCalled.isNotEmpty) {
      for (var c in newlyCalled) {
        c['callMade'] = true;
        c['callDate'] = Timestamp.now();
      }
      if (mounted) {
        setState(() {});
        await _updateFirestore();
        _showRemarksPromptDialog(newlyCalled);
      }
    }
  }

  void _showRemarksPromptDialog(List<Map<String, dynamic>> customers) {
    showDialog(
      context: context,
      builder: (ctx) => CallDetectedRemarksDialog(
        customers: customers,
        titleText: 'Call Detected! Add Remarks',
        onCustomerSelected: () {
          _isTileViewerOpen = true;
        },
        onStatusChanged: (c, remarks) async {
          setState(() {
            c['remarks'] = remarks;
          });
          await _updateFirestore();
          _isTileViewerOpen = false;
          await _fetchCustomerData();
        },
      ),
    );
  }

  Future<void> _updateFirestore() async {
    if (_docId == null) return;
    if (!_firestoreConfirmed) {
      debugPrint('Skipping Firestore write – data not confirmed from server');
      return;
    }
    try {
      final now = DateTime.now();
      final monthYear =
          "${CustomerListTargetService.monthName(now.month)} ${now.year}";

      await FirebaseFirestore.instance
          .collection('customer_target')
          .doc(monthYear)
          .collection('users')
          .doc(_docId)
          .update({'customers': _customers});
    } catch (e) {
      debugPrint('Failed to update Firestore: $e');
    }
    await _saveToLocalCache();
  }

  Future<void> _scanCallLogAndShowMatches() async {
    if (_customers == null || _customers!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No customers to check.'), backgroundColor: Colors.orange),
      );
      return;
    }

    var status = await Permission.phone.request();
    if (!status.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Phone permission denied')),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      List<Map<String, dynamic>> matchedCustomers =
          await CallScannerService.scanTodayCallLog(_customers!);

      if (!mounted) return;
      Navigator.of(context).pop();

      if (matchedCustomers.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No new calls detected for today.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      if (mounted) {
        await showDialog(
          context: context,
          builder: (ctx) => CallDetectedRemarksDialog(
            customers: matchedCustomers,
            titleText: 'Calls Detected',
            onCustomerSelected: () {
              _isTileViewerOpen = true;
            },
            onStatusChanged: (c, remarks) async {
              setState(() {
                c['callMade'] = true;
                if (c['callDate'] == null) {
                  c['callDate'] = Timestamp.now();
                }
                c['remarks'] = remarks;
              });
              await _updateFirestore();
              _isTileViewerOpen = false;
              await _fetchCustomerData();
            },
          ),
        );
      }
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      debugPrint('Error scanning call log: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error scanning call log: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        const Color primaryBlue = Color(0xFF8CC63F);
        const Color primaryGreen = Color(0xFF005BAC);
        final theme = Theme.of(context);
        final isDark = themeProvider.themeMode == ThemeMode.dark ||
            (themeProvider.themeMode == ThemeMode.system && theme.brightness == Brightness.dark);

        final bgColor = isDark
            ? const Color(0xFF181A20)
            : const Color(0xFFE3F2FD);
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
              title: const Text('Customer List', style: TextStyle(color: Colors.white)),
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
              title: const Text('Customer List', style: TextStyle(color: Colors.white)),
              backgroundColor: isDark ? primaryBlue : primaryGreen,
              iconTheme: const IconThemeData(color: Colors.white),
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Scan Call Log',
                  onPressed: _scanCallLogAndShowMatches,
                ),
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
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('No data', style: TextStyle(color: textColor)),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Add Customer'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryBlue,
                      foregroundColor: Colors.white,
                    ),
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
            ),
          );
        }

        List<Map<String, dynamic>> filteredCustomers = _customers!;
        if (_searchText.isNotEmpty) {
          filteredCustomers = filteredCustomers
              .where((c) =>
                  (c['name'] ?? '').toString().toLowerCase().contains(_searchText.toLowerCase()) ||
                  (c['contact1'] ?? c['contact'] ?? '').toString().toLowerCase().contains(_searchText.toLowerCase()))
              .toList();
        }

        int totalCount = filteredCustomers.length;
        int calledCount = filteredCustomers.where((c) => c['callMade'] == true).length;

        List<Map<String, dynamic>> sortedCustomers = List<Map<String, dynamic>>.from(filteredCustomers);
        sortedCustomers.sort((a, b) {
          final bool aNeedsRemarks =
              a['callMade'] == true && (a['remarks'] ?? '').toString().trim().isEmpty;
          final bool bNeedsRemarks =
              b['callMade'] == true && (b['remarks'] ?? '').toString().trim().isEmpty;

          if (aNeedsRemarks != bNeedsRemarks) {
            return aNeedsRemarks ? -1 : 1;
          }

          if (_sortCalledFirst) {
            return (b['callMade'] == true ? 1 : 0) - (a['callMade'] == true ? 1 : 0);
          } else {
            return (a['callMade'] == true ? 1 : 0) - (b['callMade'] == true ? 1 : 0);
          }
        });

        return Scaffold(
          backgroundColor: bgColor,
          appBar: AppBar(
            title: const Text('Customer List', style: TextStyle(color: Colors.white)),
            backgroundColor: isDark ? primaryBlue : primaryGreen,
            iconTheme: const IconThemeData(color: Colors.white),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit_note),
                tooltip: 'Remarks Pending List',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const CustomerCallingRemarksPendingPage(),
                    ),
                  ).then((_) => _fetchCustomerData());
                },
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Scan Call Log',
                onPressed: _scanCallLogAndShowMatches,
              ),
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
              if (_showSearchBar)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6),
                  child: TextField(
                    controller: _searchController,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Search customer name or contact',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() {
                            _searchText = '';
                            _searchController.clear();
                            _showSearchBar = false;
                          });
                        },
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 8),
                    ),
                    onChanged: (val) {
                      setState(() {
                        _searchText = val;
                      });
                    },
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8),
                child: Row(
                  children: [
                    Text(
                      'Called: $calledCount / $totalCount',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF8CC63F),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.search),
                      tooltip: 'Search',
                      color: isDark ? Colors.white : Colors.black,
                      onPressed: () {
                        setState(() {
                          _showSearchBar = !_showSearchBar;
                          if (!_showSearchBar) {
                            _searchText = '';
                            _searchController.clear();
                          }
                        });
                      },
                    ),
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
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: isDark ? Colors.black38 : Colors.black12,
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        itemCount: sortedCustomers.length + 1,
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: isDark
                                      ? [primaryBlue.withValues(alpha: 0.3), primaryBlue.withValues(alpha: 0.15)]
                                      : [primaryGreen.withValues(alpha: 0.25), primaryGreen.withValues(alpha: 0.1)],
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                ),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 4,
                                    child: Row(
                                      children: [
                                        Icon(Icons.person, size: 18, color: isDark ? primaryBlue : primaryGreen),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Customer',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: textColor,
                                            letterSpacing: 0.3,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Row(
                                      children: [
                                        Icon(Icons.location_on, size: 18, color: isDark ? primaryBlue : primaryGreen),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Address',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: textColor,
                                            letterSpacing: 0.3,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    flex: 1,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.call, size: 18, color: isDark ? primaryBlue : primaryGreen),
                                        const SizedBox(width: 4),
                                        Text(
                                          '',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: textColor,
                                            letterSpacing: 0.3,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }

                          final customerIndex = index - 1;
                          final customer = sortedCustomers[customerIndex];
                          final bool isPendingDeletion = customer['pendingDeletion'] == true;

                          void openViewer() {
                            if (isPendingDeletion) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('This customer is pending deletion approval.'),
                                  backgroundColor: Colors.orange,
                                ),
                              );
                              return;
                            }
                            _isTileViewerOpen = true;
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => SalesCustomerTileViewer(
                                  customer: customer,
                                  onStatusChanged: (remarks) async {
                                    if (mounted && customer.isNotEmpty) {
                                      setState(() {
                                        customer['callMade'] = true;
                                        if (customer['callDate'] == null) {
                                          customer['callDate'] = Timestamp.now();
                                        }
                                        customer['remarks'] = remarks;
                                      });
                                      await _updateFirestore();
                                    }
                                  },
                                ),
                              ),
                            ).then((_) {
                              _isTileViewerOpen = false;
                              _fetchCustomerData();
                            });
                          }

                          return CustomerListTileItem(
                            customer: customer,
                            customerIndex: customerIndex,
                            isDark: isDark,
                            primaryBlue: primaryBlue,
                            primaryGreen: primaryGreen,
                            needsRemarks: false,
                            openViewer: openViewer,
                            onCustomerUpdated: _fetchCustomerData,
                            onUpdateFirestore: _updateFirestore,
                            docId: _docId,
                          );
                        },
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