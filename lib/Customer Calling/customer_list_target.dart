import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';

import '../Misc/theme_notifier.dart';
import 'customer_target_customer_tile_viewer.dart';
import 'customer_calling_remarks_pending.dart';
import 'customer_list_target_service.dart';
import 'customer_list_tile_item.dart';
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
  bool _isReloading = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _customerDocSub;
  String? _listeningDocPath;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchCustomerData();
  }

  void _startFirestoreListener(String monthYear, String docId) {
    final path = 'customer_target/$monthYear/users/$docId';
    if (_listeningDocPath == path && _customerDocSub != null) return;

    _customerDocSub?.cancel();
    _listeningDocPath = path;
    _customerDocSub = FirebaseFirestore.instance
        .collection('customer_target')
        .doc(monthYear)
        .collection('users')
        .doc(docId)
        .snapshots()
        .listen((docSnap) {
      if (!mounted) return;
      if (docSnap.exists && docSnap.data()?['customers'] is List) {
        final List<dynamic> data = docSnap.data()!['customers'];
        final customers =
            data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        setState(() {
          _customers = customers;
          _loading = false;
        });
        _firestoreConfirmed = true;
        _scheduleSaveToLocalCache();
      }
    }, onError: (e) {
      debugPrint('Customer target stream error: $e');
    });
  }

  Future<void> _fetchCustomerData({bool forceFirestore = false}) async {
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

      // Load from local cache for instant initial display if not yet loaded in memory
      if (_customers == null) {
        final cached = await _loadFromLocalCache();
        if (cached != null) {
          if (mounted) {
            setState(() {
              _customers = cached;
              _loading = false;
            });
          }
        } else {
          if (mounted) {
            setState(() {
              _loading = true;
            });
          }
        }
      }

      // Always verify latest from Firestore so Sync Head deletion/edit approvals
      // are reflected immediately and local cache never stays stale.
      final now = DateTime.now();
      final monthYear = "${CustomerListTargetService.monthName(now.month)} ${now.year}";

      final usersRef = FirebaseFirestore.instance
          .collection('customer_target')
          .doc(monthYear)
          .collection('users');

      var doc = await usersRef.doc(_docId).get(
            forceFirestore
                ? const GetOptions(source: Source.server)
                : const GetOptions(source: Source.serverAndCache),
          );

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
        _scheduleSaveToLocalCache();
        _startFirestoreListener(monthYear, _docId!);
      } else {
        _firestoreConfirmed = false;
        setState(() {
          _loading = false;
        });
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

  String _cacheKey() {
    final now = DateTime.now();
    final monthYear =
        "${CustomerListTargetService.monthName(now.month)} ${now.year}";
    return 'customer_list_${_docId}_$monthYear';
  }

  Timer? _cacheDebounceTimer;

  void _scheduleSaveToLocalCache() {
    _cacheDebounceTimer?.cancel();
    _cacheDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      _saveToLocalCache();
    });
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
    _cacheDebounceTimer?.cancel();
    _customerDocSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_isTileViewerOpen) return;
      _fetchCustomerData();
    }
  }

  static final RegExp _nonDigitRegex = RegExp(r'\D');

  static String _normalizePhone(dynamic phone) {
    if (phone == null) return '';
    final cleaned = phone.toString().replaceAll(_nonDigitRegex, '');
    if (cleaned.length > 10) {
      return cleaned.substring(cleaned.length - 10);
    }
    return cleaned;
  }

  Future<void> _updateFirestore() async {
    if (_docId == null || _customers == null) return;
    if (!_firestoreConfirmed) {
      debugPrint('Skipping Firestore write – data not confirmed from server');
      return;
    }
    try {
      final now = DateTime.now();
      final monthYear =
          "${CustomerListTargetService.monthName(now.month)} ${now.year}";

      final docRef = FirebaseFirestore.instance
          .collection('customer_target')
          .doc(monthYear)
          .collection('users')
          .doc(_docId);

      // Pre-compute normalized lookup maps for O(1) matching instead of O(N^2) regex in transaction
      final Map<String, Map<String, dynamic>> byPhone = {};
      final Map<String, Map<String, dynamic>> byName = {};
      for (final lc in _customers!) {
        final lcName = (lc['name'] ?? '').toString().trim().toLowerCase();
        final lc1 = _normalizePhone(lc['contact1'] ?? lc['contact'] ?? lc['phone']);
        final lc2 = _normalizePhone(lc['contact2']);
        if (lc1.isNotEmpty) byPhone[lc1] = lc;
        if (lc2.isNotEmpty) byPhone[lc2] = lc;
        if (lcName.isNotEmpty) byName[lcName] = lc;
      }

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snap = await transaction.get(docRef);
        if (!snap.exists || snap.data()?['customers'] is! List) return;

        final List<Map<String, dynamic>> serverCustomers =
            (snap.data()!['customers'] as List)
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();

        bool changed = false;
        for (final sc in serverCustomers) {
          final scName = (sc['name'] ?? '').toString().trim().toLowerCase();
          final sc1 = _normalizePhone(sc['contact1'] ?? sc['contact'] ?? sc['phone']);
          final sc2 = _normalizePhone(sc['contact2']);

          Map<String, dynamic>? match;
          if (sc1.isNotEmpty) match = byPhone[sc1];
          if (match == null && sc2.isNotEmpty) match = byPhone[sc2];
          if (match == null && scName.isNotEmpty) match = byName[scName];

          if (match != null && match.isNotEmpty) {
            if (match['callMade'] == true && sc['callMade'] != true) {
              sc['callMade'] = true;
              changed = true;
            }
            if (match['callDate'] != null && sc['callDate'] == null) {
              sc['callDate'] = match['callDate'];
              changed = true;
            }
            final localRemarks = (match['remarks'] ?? '').toString().trim();
            if (localRemarks.isNotEmpty && sc['remarks'] != match['remarks']) {
              sc['remarks'] = match['remarks'];
              changed = true;
            }
            if (match['leadAdded'] == true && sc['leadAdded'] != true) {
              sc['leadAdded'] = true;
              changed = true;
            }
            if (match['lastCalledNumber'] != null &&
                sc['lastCalledNumber'] != match['lastCalledNumber']) {
              sc['lastCalledNumber'] = match['lastCalledNumber'];
              changed = true;
            }
          }
        }

        if (changed) {
          transaction.update(docRef, {
            'customers': serverCustomers,
            'updated': FieldValue.serverTimestamp(),
          });
        }
      });
    } catch (e) {
      debugPrint('Failed to update Firestore: $e');
    }
    _scheduleSaveToLocalCache();
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
                  icon: const Icon(Icons.add),
                  tooltip: 'Add Customer',
                  onPressed: () async {
                    final added = await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => AddCustomerPage()),
                    );
                    if (added == true) {
                      _fetchCustomerData(forceFirestore: true);
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
        int pendingRemarksCount = _customers!.where((c) {
          final bool callMade = c['callMade'] == true;
          final bool isPendingDeletion = c['pendingDeletion'] == true;
          final bool isPendingEditing = c['pendingEditing'] == true;
          final String remarks = (c['remarks'] ?? '').toString().trim();
          return callMade && !isPendingDeletion && !isPendingEditing && remarks.isEmpty;
        }).length;

        List<Map<String, dynamic>> sortedCustomers = List<Map<String, dynamic>>.from(filteredCustomers);
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
            title: const Text('Customer List', style: TextStyle(color: Colors.white)),
            backgroundColor: isDark ? primaryBlue : primaryGreen,
            iconTheme: const IconThemeData(color: Colors.white),
            actions: [
              IconButton(
                icon: _isReloading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.refresh),
                tooltip: 'Refresh Customer List from Database',
                onPressed: _isReloading
                    ? null
                    : () async {
                        setState(() => _isReloading = true);
                        try {
                          await _fetchCustomerData(forceFirestore: true);
                          if (context.mounted) {
                            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                              const SnackBar(
                                content: Text('Customer list refreshed from database'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          }
                        } finally {
                          if (mounted) setState(() => _isReloading = false);
                        }
                      },
              ),
              IconButton(
                icon: Badge.count(
                  count: pendingRemarksCount,
                  isLabelVisible: pendingRemarksCount > 0,
                  backgroundColor: Colors.orange.shade700,
                  child: const Icon(Icons.rate_review_outlined),
                ),
                tooltip: pendingRemarksCount > 0
                    ? 'Remarks Pending ($pendingRemarksCount)'
                    : 'Remarks Pending List',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const CustomerCallingRemarksPendingPage(),
                    ),
                  ).then((_) => _fetchCustomerData(forceFirestore: true));
                },
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
                    _fetchCustomerData(forceFirestore: true);
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
                          if (mounted) { setState(() {
                            _searchText = '';
                            _searchController.clear();
                            _showSearchBar = false;
                          }); }
                        },
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 8),
                    ),
                    onChanged: (val) {
                      if (mounted) { setState(() {
                        _searchText = val;
                      }); }
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
                        if (mounted) { setState(() {
                          _showSearchBar = !_showSearchBar;
                          if (!_showSearchBar) {
                            _searchText = '';
                            _searchController.clear();
                          }
                        }); }
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
                          final bool isPendingEditing = customer['pendingEditing'] == true;

                          void openViewer() {
                            if (isPendingDeletion) {
                              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                                const SnackBar(
                                  content: Text('This customer is pending deletion approval.'),
                                  backgroundColor: Colors.orange,
                                ),
                              );
                              return;
                            }
                            if (isPendingEditing) {
                              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                                const SnackBar(
                                  content: Text('This customer is pending editing approval.'),
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
                                  docId: _docId,
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
                              if (mounted) {
                                setState(() {});
                              }
                            });
                          }

                          return CustomerListTileItem(
                            customer: customer,
                            customerIndex: customerIndex,
                            isDark: isDark,
                            primaryBlue: primaryBlue,
                            primaryGreen: primaryGreen,
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