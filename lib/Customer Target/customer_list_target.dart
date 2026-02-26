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
  String _searchText = '';
  bool _showSearchBar = false;
  final TextEditingController _searchController = TextEditingController();

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
      _docId = user.email!.toLowerCase();
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

  /// Scan today's call log and find customers where:
  /// 1. The user made an outgoing call to the customer today (any duration)
  /// 2. There is at least one call (incoming or outgoing) > 15 seconds
  /// This ensures customer-initiated-only calls are NOT detected.
  Future<void> _scanCallLogAndShowMatches() async {
    if (_customers == null || _customers!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No customers to check.'), backgroundColor: Colors.orange),
      );
      return;
    }

    // Request phone permission
    var status = await Permission.phone.request();
    if (!status.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Phone permission denied')),
      );
      return;
    }

    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final Iterable<CallLogEntry> entries = await CallLog.query(
        dateFrom: startOfDay.millisecondsSinceEpoch,
        dateTo: now.millisecondsSinceEpoch,
      );

      bool _numberMatches(String logNumber, String? contact) {
        if (contact == null || contact.isEmpty) return false;
        String clean = contact.replaceAll(RegExp(r'\D'), '');
        return logNumber.endsWith(clean) || clean.endsWith(logNumber);
      }

      // Find customers that match the two-step criteria
      List<Map<String, dynamic>> matchedCustomers = [];

      for (var customer in _customers!) {
        if (customer['callMade'] == true) continue; // already ticked

        String? c1 = customer['contact1'] ?? customer['contact'];
        String? c2 = customer['contact2'];

        // Step 1: Find the latest outgoing call to this customer today
        int latestOutgoingTime = -1;
        for (final entry in entries) {
          if (entry.callType != CallType.outgoing) continue;
          String logNumber = entry.number?.replaceAll(RegExp(r'\\D'), '') ?? '';
          if (logNumber.isEmpty) continue;
          if (_numberMatches(logNumber, c1) || _numberMatches(logNumber, c2)) {
            if (entry.timestamp != null && entry.timestamp! > latestOutgoingTime) {
              latestOutgoingTime = entry.timestamp!;
            }
          }
        }
        if (latestOutgoingTime == -1) continue; // No outgoing call found

        // Step 2: Find any call (incoming or outgoing) > 15s AFTER the outgoing call
        bool hasLongCallAfter = entries.any((entry) {
          if (entry.timestamp == null || entry.timestamp! <= latestOutgoingTime) return false;
          String logNumber = entry.number?.replaceAll(RegExp(r'\\D'), '') ?? '';
          if (logNumber.isEmpty) return false;
          bool longEnough = (entry.duration ?? 0) > 15;
          return (_numberMatches(logNumber, c1) || _numberMatches(logNumber, c2)) && longEnough;
        });

        if (hasLongCallAfter) {
          matchedCustomers.add(customer);
        }
      }

      // Dismiss loading
      if (mounted) Navigator.of(context).pop();

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

      // Show dialog with matched customers
      if (mounted) {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Row(
              children: const [
                Icon(Icons.phone_callback, color: Colors.green),
                SizedBox(width: 8),
                Expanded(child: Text('Calls Detected', style: TextStyle(fontSize: 18))),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${matchedCustomers.length} customer(s) have calls (>15s) today. Tap to add remarks.',
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: matchedCustomers.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final c = matchedCustomers[i];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.green.shade50,
                            child: const Icon(Icons.check_circle, color: Colors.green),
                          ),
                          title: Text(
                            (c['name'] ?? '').toString().toUpperCase(),
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                          subtitle: Text(
                            c['contact1'] ?? c['contact'] ?? '',
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                          onTap: () {
                            // Mark as called
                            setState(() {
                              c['callMade'] = true;
                            });
                            _updateFirestore();
                            Navigator.of(ctx).pop();
                            // Navigate to tile viewer for remarks
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => SalesCustomerTileViewer(
                                  customer: c,
                                  onStatusChanged: (remarks) async {
                                    setState(() {
                                      c['callMade'] = true;
                                      c['remarks'] = remarks;
                                    });
                                    await _updateFirestore();
                                  },
                                ),
                              ),
                            ).then((_) => _fetchCustomerData());
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      // Dismiss loading if still showing
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

        // Filter customers by search
        List<Map<String, dynamic>> filteredCustomers = _customers!;
        if (_searchText.isNotEmpty) {
          filteredCustomers = filteredCustomers
              .where((c) =>
                  (c['name'] ?? '').toString().toLowerCase().contains(_searchText.toLowerCase()) ||
                  (c['contact'] ?? '').toString().toLowerCase().contains(_searchText.toLowerCase()))
              .toList();
        }

        // Calculate calledCount and totalCount
        int totalCount = filteredCustomers.length;
        int calledCount = filteredCustomers.where((c) => c['callMade'] == true).length;

        // Sort customers based on called status
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
            title: Text('Customer List', style: TextStyle(color: Colors.white)),
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
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF8CC63F), // changed to green
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
                        itemCount: sortedCustomers.length + 1, // +1 for header
                        itemBuilder: (context, index) {
                          // Header row
                          if (index == 0) {
                            return Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: isDark
                                      ? [primaryBlue.withOpacity(0.3), primaryBlue.withOpacity(0.15)]
                                      : [primaryGreen.withOpacity(0.25), primaryGreen.withOpacity(0.1)],
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

                          // Data rows
                          final customerIndex = index - 1;
                          final customer = sortedCustomers[customerIndex];
                          final bool callMade = customer['callMade'] == true;
                          final bool isEven = customerIndex % 2 == 0;

                          void openViewer() {
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
                          }

                          return Material(
                            color: isEven
                                ? (isDark ? const Color(0xFF1E2128) : Colors.white)
                                : (isDark ? const Color(0xFF23272E) : const Color(0xFFF5F9FF)),
                            child: InkWell(
                              onTap: openViewer,
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
                              splashColor: (isDark ? primaryBlue : primaryGreen).withOpacity(0.15),
                              highlightColor: (isDark ? primaryBlue : primaryGreen).withOpacity(0.08),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                decoration: BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                      color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                                      width: 0.5,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 4,
                                      child: Row(
                                        children: [
                                          CircleAvatar(
                                            radius: 14,
                                            backgroundColor: Color(0xFFE3F2FD), // light blue background for contrast
                                            child: Text(
                                              (customer['name'] ?? '?').toString().toUpperCase().isNotEmpty
                                                  ? (customer['name'] ?? '?').toString().toUpperCase()[0]
                                                  : '?',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.black, // black text for avatar
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              (customer['name'] ?? '').toString().toUpperCase(),
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w500,
                                                color: Color.fromARGB(255, 108, 186, 5), // green as in login.dart
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        (customer['address'] ?? '-').toString().toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Color(0xFF005BAC).withOpacity(0.9), // blue as in login.dart
                                        ),
                                        textAlign: TextAlign.center,
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 2,
                                      ),
                                    ),
                                    Expanded(
                                      flex: 1,
                                      child: Center(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                          decoration: BoxDecoration(
                                            color: callMade
                                                ? Colors.green.withOpacity(0.15)
                                                : Colors.orange.withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(20),
                                            border: Border.all(
                                              color: callMade
                                                  ? Colors.green.withOpacity(0.4)
                                                  : Colors.orange.withOpacity(0.4),
                                              width: 1,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                callMade ? Icons.check_circle : Icons.pending,
                                                size: 14,
                                                color: callMade ? Colors.green : Colors.orange,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
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