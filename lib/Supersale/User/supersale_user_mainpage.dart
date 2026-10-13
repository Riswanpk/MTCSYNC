// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../Navigation/user_cache_service.dart';
import 'supersale_booking_card.dart';
import 'supersale_notification_service.dart';
import 'supersale_user_dialogs.dart';
import 'supersale_user_form.dart';

// Re-export phone utils for any legacy or external consumers
export 'supersale_phone_utils.dart';

const Color primaryBlue = Color(0xFF005BAC);
const Color primaryGreen = Color(0xFF8CC63F);

class SupersaleUserMainPage extends StatefulWidget {
  const SupersaleUserMainPage({super.key});

  @override
  State<SupersaleUserMainPage> createState() => _SupersaleUserMainPageState();
}

class _SupersaleUserMainPageState extends State<SupersaleUserMainPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? _userBranch;
  // ignore: unused_field
  String? _userEmail;
  bool _isLoadingBranch = true;
  bool _isLoadingEntries = true;

  // Multi-stream listener variables
  final List<StreamSubscription> _subscriptions = [];
  final Map<String, List<QueryDocumentSnapshot>> _entriesMap = {};
  List<QueryDocumentSnapshot> _allUserEntries = [];
  List<String> _lastItemNames = [];
  bool _hasInitializedBookings = false;

  String? _lastPostingsSignature;

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
      if (mounted) {
        setState(() {
          _userBranch = cache.branch;
          _userEmail = cache.email ?? _auth.currentUser?.email;
        });
      }
    } catch (e) {
      debugPrint('Error loading user branch: $e');
    } finally {
      if (mounted) setState(() => _isLoadingBranch = false);
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
      if (mounted) {
        setState(() {
          _allUserEntries = [];
          _isLoadingEntries = false;
        });
      }
      return;
    }

    final uid = _auth.currentUser?.uid;
    if (uid == null || _userBranch == null) {
      if (mounted) {
        setState(() {
          _isLoadingEntries = false;
        });
      }
      return;
    }

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
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text('Booking entry cancelled successfully'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text('Failed to cancel booking: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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

        // 2. Trigger multi-stream listener on initial load or if item list changes
        if (!_hasInitializedBookings || !_areListsEqual(_lastItemNames, itemNames)) {
          _hasInitializedBookings = true;
          _lastItemNames = itemNames;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _listenToUserBookings(itemNames);
          });
        }

        // 3. Sync local scheduled notifications for booking open & close times safely post-frame
        final postingsSignature = postings.map((d) {
          final data = d.data() as Map<String, dynamic>;
          return '${d.id}_${data['item']}_${data['bookingStart']}_${data['bookingEnd']}';
        }).join(';');
        if (_lastPostingsSignature != postingsSignature) {
          _lastPostingsSignature = postingsSignature;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            SupersaleNotificationService.instance.syncScheduledNotifications(postings, _userBranch);
          });
        }

        // 4. Check if there's at least one active posting covering the user's branch right now
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
                            ? primaryGreen.withValues(alpha: 0.2)
                            : Colors.red.withValues(alpha: 0.2),
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
                  ? () async {
                      final saleType = await SupersaleDialogs.showSaleTypeDialog(context);
                      if (saleType != null && context.mounted) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => SupersaleUserFormPage(
                              isSpotSale: saleType == 'spot_sale',
                            ),
                          ),
                        );
                      }
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
              color: primaryBlue.withValues(alpha: 0.3),
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
        return SupersaleBookingCard(
          doc: doc,
          isBookingOpen: isBookingOpen,
          isDark: isDark,
          textTheme: textTheme,
          now: now,
          userBranch: _userBranch,
          onConfirmDismiss: (direction) async {
            return await _handleDismiss(doc, direction, now);
          },
        );
      },
    );
  }

  Future<bool> _handleDismiss(
    QueryDocumentSnapshot doc,
    DismissDirection direction,
    DateTime now,
  ) async {
    final data = doc.data() as Map<String, dynamic>;
    final item = doc.reference.parent.id;
    final customerName = data['customerName'] ?? 'No Customer Name';
    final quantity = data['quantity'] ?? 0;

    final Timestamp? bookingStart = data['bookingStart'] as Timestamp?;
    final Timestamp? deliveryEnd = data['deliveryEnd'] as Timestamp?;
    final bool isCancelAllowed = bookingStart != null &&
        deliveryEnd != null &&
        now.isAfter(bookingStart.toDate()) &&
        now.isBefore(deliveryEnd.toDate());

    if (direction == DismissDirection.endToStart) {
      // Swipe to Cancel booking (allowed during booking and delivery period)
      if (!isCancelAllowed) {
        if (mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            const SnackBar(
              content: Text('Delivery period has ended. You cannot cancel this entry.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return false;
      }

      final reason = await SupersaleDialogs.showCancelBookingDialog(context);
      if (reason != null && reason.isNotEmpty) {
        await _cancelBooking(doc.reference, reason);
      }
      return false; // Slides back, will be removed dynamically
    } else {
      // Mark as Delivered (Left-to-right swipe)
      final result = await SupersaleDialogs.showConfirmDeliveryDialog(
        context: context,
        customerName: customerName,
        item: item,
        quantity: quantity,
        initialDeliveryReminder: data['deliveryReminder'],
      );

      if (result != null) {
        try {
          final int deliveredQty = result.deliveredQty;
          final String billedPhoneText = result.billedPhone;
          final DateTime? nextReminderDate = result.nextReminderDate;

          if (deliveredQty >= quantity) {
            // Full delivery
            await doc.reference.update({
              'status': 'delivered',
              'billedPhone': billedPhoneText,
              'deliveredAt': FieldValue.serverTimestamp(),
            });
            if (mounted) {
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                const SnackBar(
                  content: Text('Booking marked as Delivered successfully'),
                  backgroundColor: Colors.green,
                ),
              );
            }
          } else {
            // Partial delivery: Split booking
            final int remainingQty = quantity - deliveredQty;
            final double originalAdvance = (data['advance'] ?? 0.0).toDouble();
            final double unitAdvance = quantity > 0 ? (originalAdvance / quantity) : 0.0;
            final double deliveredAdvance = unitAdvance * deliveredQty;
            final double remainingAdvance = originalAdvance - deliveredAdvance;

            // 1. Create child record for delivered portion
            final deliveredData = Map<String, dynamic>.from(data);
            deliveredData['quantity'] = deliveredQty;
            deliveredData['advance'] = deliveredAdvance;
            deliveredData['status'] = 'delivered';
            deliveredData['billedPhone'] = billedPhoneText;
            deliveredData['deliveredAt'] = FieldValue.serverTimestamp();
            deliveredData['parentBookingId'] = doc.id;
            deliveredData['isPartialSplit'] = true;

            await doc.reference.parent.add(deliveredData);

            // 2. Update parent booking with remaining quantity
            final Map<String, dynamic> updateRemainingData = {
              'quantity': remainingQty,
              'advance': remainingAdvance,
              'status': 'pending',
              'hasPartialDelivery': true,
            };
            if (nextReminderDate != null) {
              updateRemainingData['deliveryReminder'] = Timestamp.fromDate(nextReminderDate);
            }

            await doc.reference.update(updateRemainingData);

            // 3. Reschedule reminder notification if next date was selected
            if (nextReminderDate != null) {
              await SupersaleNotificationService.instance.scheduleRemainingDeliveryReminder(
                docId: doc.id,
                item: item,
                customerName: customerName,
                remainingQty: remainingQty,
                userBranch: _userBranch,
                nextReminderDate: nextReminderDate,
              );
            }

            if (mounted) {
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                SnackBar(
                  content: Text('Delivered $deliveredQty units. $remainingQty units remain pending.'),
                  backgroundColor: Colors.green,
                ),
              );
            }
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              SnackBar(content: Text('Failed to process delivery: $e'), backgroundColor: Colors.red),
            );
          }
        }
      }
      return false; // Slides back, will shift to Delivered / update pending dynamically
    }
  }
}
