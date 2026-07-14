import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../Navigation/user_cache_service.dart';
import 'supersale_user_form.dart';

const Color primaryBlue = Color(0xFF005BAC);
const Color primaryGreen = Color(0xFF8CC63F);

class SupersaleUserMainPage extends StatefulWidget {
  const SupersaleUserMainPage({Key? key}) : super(key: key);

  @override
  State<SupersaleUserMainPage> createState() => _SupersaleUserMainPageState();
}

class _SupersaleUserMainPageState extends State<SupersaleUserMainPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? _userBranch;
  String? _userEmail;
  bool _isLoadingBranch = true;
  bool _isLoadingEntries = true;

  // Multi-stream listener variables
  final List<StreamSubscription> _subscriptions = [];
  final Map<String, List<QueryDocumentSnapshot>> _entriesMap = {};
  List<QueryDocumentSnapshot> _allUserEntries = [];
  List<String> _lastItemNames = [];

  @override
  void initState() {
    super.initState();
    _loadUserBranch();
  }

  @override
  void dispose() {
    for (var sub in _subscriptions) {
      sub.cancel();
    }
    super.dispose();
  }

  Future<void> _loadUserBranch() async {
    try {
      final cache = UserCacheService.instance;
      await cache.ensureLoaded();
      setState(() {
        _userBranch = cache.branch;
        _userEmail = cache.email ?? _auth.currentUser?.email;
      });
    } catch (e) {
      debugPrint('Error loading user branch: $e');
    } finally {
      setState(() => _isLoadingBranch = false);
    }
  }

  bool _areListsEqual(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (final item in a) {
      if (!b.contains(item)) return false;
    }
    return true;
  }

  void _listenToUserBookings(List<String> itemNames) {
    // Cancel old subscriptions
    for (var sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    _entriesMap.clear();

    if (itemNames.isEmpty) {
      setState(() {
        _allUserEntries = [];
        _isLoadingEntries = false;
      });
      return;
    }

    final uid = _auth.currentUser?.uid;
    if (uid == null || _userBranch == null) return;

    setState(() => _isLoadingEntries = true);

    int activeSubscriptions = itemNames.length;

    for (var itemName in itemNames) {
      final sub = _firestore
          .collection('supersale_user_entries')
          .doc(_userBranch)
          .collection(itemName)
          .where('userId', isEqualTo: uid)
          .snapshots()
          .listen(
        (snapshot) {
          _entriesMap[itemName] = snapshot.docs;
          _updateAllEntries();
          if (activeSubscriptions > 0) {
            activeSubscriptions--;
            if (activeSubscriptions == 0) {
              setState(() => _isLoadingEntries = false);
            }
          }
        },
        onError: (err) {
          debugPrint('Error listening to entries for $itemName: $err');
          if (activeSubscriptions > 0) {
            activeSubscriptions--;
            if (activeSubscriptions == 0) {
              setState(() => _isLoadingEntries = false);
            }
          }
        },
      );
      _subscriptions.add(sub);
    }
  }

  void _updateAllEntries() {
    final merged = <QueryDocumentSnapshot>[];
    _entriesMap.forEach((key, list) {
      merged.addAll(list);
    });

    // Sort bookings in-memory by created_at descending to avoid custom index creation requirements
    merged.sort((a, b) {
      final aData = a.data() as Map<String, dynamic>;
      final bData = b.data() as Map<String, dynamic>;
      final Timestamp? aTime = aData['created_at'];
      final Timestamp? bTime = bData['created_at'];
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return bTime.compareTo(aTime);
    });

    if (mounted) {
      setState(() {
        _allUserEntries = merged;
        // In case update occurs after initial loading
        _isLoadingEntries = false;
      });
    }
  }

  Future<void> _cancelBooking(DocumentReference ref, String reason) async {
    try {
      await ref.update({
        'status': 'cancelled',
        'cancelReason': reason,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Booking entry cancelled successfully'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to cancel booking: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatDate(dynamic dateField) {
    if (dateField == null) return 'N/A';
    DateTime dt;
    if (dateField is Timestamp) {
      dt = dateField.toDate();
    } else if (dateField is String) {
      dt = DateTime.tryParse(dateField) ?? DateTime.now();
    } else {
      return 'N/A';
    }
    return DateFormat('dd MMM yyyy').format(dt.toLocal());
  }

  String _formatSimpleDate(dynamic dateField) {
    if (dateField == null) return 'N/A';
    DateTime dt;
    if (dateField is Timestamp) {
      dt = dateField.toDate();
    } else if (dateField is String) {
      dt = DateTime.tryParse(dateField) ?? DateTime.now();
    } else {
      return 'N/A';
    }
    return DateFormat('dd/MM/yyyy').format(dt.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textTheme = Theme.of(context).textTheme;
    final user = _auth.currentUser;

    if (_isLoadingBranch || user == null) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF0A1628) : Colors.grey[50],
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('supersales').snapshots(),
      builder: (context, adminSnapshot) {
        final postings = adminSnapshot.data?.docs ?? [];
        final now = DateTime.now();

        // 1. Collect all unique item names from all postings (active or inactive)
        final itemNames = postings
            .map((doc) => (doc.data() as Map<String, dynamic>)['item'] as String? ?? '')
            .where((item) => item.isNotEmpty)
            .toSet()
            .toList();

        // 2. Trigger multi-stream listener if item list changes
        if (!_areListsEqual(_lastItemNames, itemNames)) {
          _lastItemNames = itemNames;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _listenToUserBookings(itemNames);
          });
        }

        // 3. Check if there's at least one active posting covering the user's branch right now
        final isBookingOpen = postings.any((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final List<dynamic> branches = data['branches'] ?? [];
          final Timestamp? start = data['bookingStart'];
          final Timestamp? end = data['bookingEnd'];
          if (start == null || end == null) return false;

          final startTime = start.toDate();
          final endTime = end.toDate();

          final isBranchEligible = branches.contains(_userBranch) || branches.contains('all');
          final isTimeEligible = now.isAfter(startTime) && now.isBefore(endTime);

          return isBranchEligible && isTimeEligible;
        });

        // Filter local booking entries by tab types
        final pendingEntries = _allUserEntries.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return (data['status'] ?? 'pending') == 'pending';
        }).toList();

        final deliveredEntries = _allUserEntries.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return (data['status'] ?? 'pending') == 'delivered';
        }).toList();

        return DefaultTabController(
          length: 2,
          child: Scaffold(
            backgroundColor: isDark ? const Color(0xFF0A1628) : Colors.grey[50],
            appBar: AppBar(
              title: const Text(
                'My Supersale Bookings',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              elevation: 0,
              backgroundColor: primaryBlue,
              foregroundColor: Colors.white,
              centerTitle: true,
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isBookingOpen
                            ? primaryGreen.withOpacity(0.2)
                            : Colors.red.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        isBookingOpen ? 'BOOKING OPEN' : 'BOOKING CLOSED',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isBookingOpen ? primaryGreen : Colors.redAccent,
                        ),
                      ),
                    ),
                  ),
                )
              ],
              bottom: const TabBar(
                indicatorColor: primaryGreen,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                tabs: [
                  Tab(text: 'Pending'),
                  Tab(text: 'Delivered'),
                ],
              ),
            ),
            body: _isLoadingEntries
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    children: [
                      _buildBookingsList(pendingEntries, isBookingOpen, isDark, textTheme, now),
                      _buildBookingsList(deliveredEntries, isBookingOpen, isDark, textTheme, now),
                    ],
                  ),
            floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
            floatingActionButton: FloatingActionButton.extended(
              onPressed: isBookingOpen
                  ? () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const SupersaleUserFormPage()),
                      );
                    }
                  : null,
              backgroundColor: isBookingOpen ? primaryBlue : Colors.grey,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded, size: 24),
              label: const Text('Add Booking', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBookingsList(
    List<QueryDocumentSnapshot> entries,
    bool isBookingOpen,
    bool isDark,
    TextTheme textTheme,
    DateTime now,
  ) {
    if (entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.bookmark_outline_rounded,
              size: 64,
              color: primaryBlue.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No Bookings Yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                isBookingOpen
                    ? 'Tap the + button below to add your first supersale booking.'
                    : 'Booking is currently closed. You can add bookings when an active supersale period is open for your branch.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark ? Colors.white38 : Colors.black45,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final doc = entries[index];
        final data = doc.data() as Map<String, dynamic>;
        final docId = doc.id;
        final item = doc.reference.parent.id;

        final customerName = data['customerName'] ?? 'No Customer Name';
        final phone = data['phone'] ?? 'No Phone';
        final quantity = data['quantity'] ?? 0;
        final rate = data['rate'] ?? 0.0;
        final advance = data['advance'] ?? 0.0;
        final createdAt = data['created_at'];
        final status = data['status'] ?? 'pending';
        final billedPhone = data['billedPhone'];

        final Timestamp? bookingStart = data['bookingStart'] as Timestamp?;
        final Timestamp? bookingEnd = data['bookingEnd'] as Timestamp?;
        final Timestamp? deliveryEnd = data['deliveryEnd'] as Timestamp?;

        final bool isActionAllowed = bookingStart != null &&
            bookingEnd != null &&
            now.isAfter(bookingStart.toDate()) &&
            now.isBefore(bookingEnd.toDate());

        return Dismissible(
          key: Key(docId),
          direction: DismissDirection.horizontal,
          background: Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(left: 20),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.green,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white, size: 28),
                SizedBox(width: 8),
                Text(
                  'Delivered',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ],
            ),
          ),
          secondaryBackground: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.orangeAccent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  'Cancel',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                ),
                SizedBox(width: 8),
                Icon(Icons.cancel_rounded, color: Colors.white, size: 28),
              ],
            ),
          ),
          onDismissed: (direction) {},
          confirmDismiss: (direction) async {
            if (direction == DismissDirection.endToStart) {
              // Swipe to Cancel booking (only allowed during booking interval)
              if (!isActionAllowed) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Booking period has ended. You cannot cancel this entry.'),
                    backgroundColor: Colors.red,
                  ),
                );
                return false;
              }

              final cancelController = TextEditingController();
              final formKey = GlobalKey<FormState>();

              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Cancel Booking'),
                  content: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Enter the cancellation reason (mandatory):'),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: cancelController,
                          decoration: const InputDecoration(
                            labelText: 'Cancellation Reason',
                            hintText: 'Enter reason',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter cancellation reason';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Keep Booking'),
                    ),
                    TextButton(
                      onPressed: () {
                        if (formKey.currentState!.validate()) {
                          Navigator.pop(context, true);
                        }
                      },
                      child: const Text('Cancel Booking', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              );

              if (confirmed == true) {
                await _cancelBooking(doc.reference, cancelController.text.trim());
              }
              return false; // Slides back, will be removed from lists dynamically by status filters
            } else {
              // Mark as Delivered (Left-to-right swipe)
              final phoneController = TextEditingController();
              final formKey = GlobalKey<FormState>();

              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Mark as Delivered'),
                  content: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Enter billed phone number (mandatory):'),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: phoneController,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Billed Phone',
                            hintText: 'Enter phone number',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter phone number';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () {
                        if (formKey.currentState!.validate()) {
                          Navigator.pop(context, true);
                        }
                      },
                      child: const Text('Deliver', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              );

              if (confirmed == true) {
                try {
                  await doc.reference.update({
                    'status': 'delivered',
                    'billedPhone': phoneController.text.trim(),
                  });
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Booking marked as Delivered successfully'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to update status: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              }
              return false; // Slides back, will shift to Delivered tab dynamically
            }
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? Colors.white12 : Colors.grey[200]!,
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  // Edit Booking (only allowed during booking interval)
                  if (!isActionAllowed) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Booking period has ended. You cannot edit this entry.'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SupersaleUserFormPage(bookingDoc: doc),
                      ),
                    );
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              item,
                              style: textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                'Booking ${_formatSimpleDate(bookingEnd)}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark ? Colors.white60 : Colors.black87,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Delivery ${_formatSimpleDate(deliveryEnd)}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark ? Colors.white60 : Colors.black87,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: status == 'delivered'
                                      ? Colors.green.withOpacity(0.15)
                                      : Colors.orange.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  status == 'delivered' ? 'Delivered' : 'Pending',
                                  style: TextStyle(
                                    color: status == 'delivered' ? Colors.green : Colors.orange,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Customer Info
                      Row(
                        children: [
                          Icon(Icons.person_rounded, size: 16, color: Colors.grey[400]),
                          const SizedBox(width: 8),
                          Text(
                            'Customer: $customerName',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.phone_rounded, size: 16, color: Colors.grey[400]),
                          const SizedBox(width: 8),
                          Text(
                            'Phone: $phone',
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                      if (status == 'delivered' && billedPhone != null) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(Icons.receipt_rounded, size: 16, color: primaryGreen),
                            const SizedBox(width: 8),
                            Text(
                              'Billed Phone: $billedPhone',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.greenAccent : Colors.green[800],
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 12),
                      const Divider(height: 1, thickness: 0.5),
                      const SizedBox(height: 10),
                      // Booking details
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Quantity',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark ? Colors.white38 : Colors.black45,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$quantity',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white70 : Colors.black87,
                                ),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Rate',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark ? Colors.white38 : Colors.black45,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '₹$rate',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white70 : Colors.black87,
                                ),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Advance',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark ? Colors.white38 : Colors.black45,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '₹$advance',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: primaryGreen,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
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
