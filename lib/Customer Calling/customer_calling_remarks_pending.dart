import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';

import '../Misc/theme_notifier.dart';
import 'customer_target_customer_tile_viewer.dart';

class CustomerCallingRemarksPendingPage extends StatefulWidget {
  const CustomerCallingRemarksPendingPage({super.key});

  @override
  State<CustomerCallingRemarksPendingPage> createState() =>
      _CustomerCallingRemarksPendingPageState();
}

class _CustomerCallingRemarksPendingPageState
    extends State<CustomerCallingRemarksPendingPage> {
  List<Map<String, dynamic>> _pendingCustomers = [];
  List<Map<String, dynamic>> _allCustomers = [];
  bool _loading = true;
  String? _error;
  String? _docId;

  String _monthName(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return months[month - 1];
  }

  @override
  void initState() {
    super.initState();
    _fetchPendingRemarks();
  }

  Future<void> _fetchPendingRemarks() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
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
      final now = DateTime.now();
      final monthYear = "${_monthName(now.month)} ${now.year}";

      final usersRef = FirebaseFirestore.instance
          .collection('customer_target')
          .doc(monthYear)
          .collection('users');

      var doc = await usersRef.doc(_docId).get();

      if (!doc.exists || doc.data()?['customers'] == null) {
        final querySnap = await usersRef.get();
        for (final d in querySnap.docs) {
          if (d.id.toLowerCase() == _docId!.toLowerCase()) {
            doc = d;
            _docId = d.id;
            break;
          }
        }
      }

      if (doc.exists && doc.data()?['customers'] != null) {
        final List<dynamic> data = doc.data()!['customers'];
        _allCustomers = data.map((e) => Map<String, dynamic>.from(e)).toList();

        // Filter: callMade == true AND remarks is empty AND not pendingDeletion
        _pendingCustomers = _allCustomers.where((c) {
          final bool callMade = c['callMade'] == true;
          final bool isPendingDeletion = c['pendingDeletion'] == true;
          final String remarks = (c['remarks'] ?? '').toString().trim();
          return callMade && !isPendingDeletion && remarks.isEmpty;
        }).toList();
      } else {
        _allCustomers = [];
        _pendingCustomers = [];
      }

      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = "Error loading pending remarks: $e";
        _loading = false;
      });
    }
  }

  Future<void> _updateFirestore() async {
    if (_docId == null) return;
    try {
      final now = DateTime.now();
      final monthYear = "${_monthName(now.month)} ${now.year}";

      await FirebaseFirestore.instance
          .collection('customer_target')
          .doc(monthYear)
          .collection('users')
          .doc(_docId)
          .update({'customers': _allCustomers});
    } catch (e) {
      debugPrint('Failed to update Firestore from pending remarks page: $e');
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
            (themeProvider.themeMode == ThemeMode.system &&
                theme.brightness == Brightness.dark);

        final bgColor = isDark
            ? const Color(0xFF181A20)
            : const Color(0xFFE3F2FD);
        final cardColor = isDark ? const Color(0xFF23262B) : Colors.white;
        final textColor = isDark ? Colors.white : Colors.black;

        return Scaffold(
          backgroundColor: bgColor,
          appBar: AppBar(
            title: const Text(
              'Remarks Pending',
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: isDark ? primaryBlue : primaryGreen,
            iconTheme: const IconThemeData(color: Colors.white),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh Pending List',
                onPressed: _fetchPendingRemarks,
              ),
            ],
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Text(_error!, style: TextStyle(color: textColor)))
                  : _pendingCustomers.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.check_circle_outline,
                                size: 64,
                                color: Colors.green.shade400,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No pending remarks!',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: textColor,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'All detected calls have remarks added.',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        )
                      : Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.warning_amber_rounded,
                                    color: Colors.orange.shade700,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Pending Remarks: ${_pendingCustomers.length}',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: isDark
                                          ? Colors.orange.shade300
                                          : Colors.orange.shade800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: ListView.separated(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                itemCount: _pendingCustomers.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, i) {
                                  final customer = _pendingCustomers[i];
                                  return Card(
                                    color: cardColor,
                                    elevation: 2,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(
                                        color: Colors.orange.withValues(alpha: 0.5),
                                        width: 1,
                                      ),
                                    ),
                                    child: ListTile(
                                      contentPadding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 8),
                                      leading: CircleAvatar(
                                        backgroundColor:
                                            Colors.orange.withValues(alpha: 0.2),
                                        child: const Icon(Icons.edit_note,
                                            color: Colors.orange),
                                      ),
                                      title: Text(
                                        (customer['name'] ?? '')
                                            .toString()
                                            .toUpperCase(),
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                          color: textColor,
                                        ),
                                      ),
                                      subtitle: Text(
                                        customer['contact1'] ??
                                            customer['contact'] ??
                                            '',
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                      trailing: const Icon(
                                          Icons.arrow_forward_ios,
                                          size: 16),
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                SalesCustomerTileViewer(
                                              customer: customer,
                                              onStatusChanged:
                                                  (remarks) async {
                                                setState(() {
                                                  customer['remarks'] = remarks;
                                                });
                                                await _updateFirestore();
                                              },
                                            ),
                                          ),
                                        ).then((_) {
                                          _fetchPendingRemarks();
                                        });
                                      },
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
        );
      },
    );
  }
}
