import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'supersale_admin_form.dart';
import 'supersale_admin_dashboard.dart';

const Color primaryBlue = Color(0xFF005BAC);
const Color primaryGreen = Color(0xFF8CC63F);

class SupersalePage extends StatefulWidget {
  const SupersalePage({Key? key}) : super(key: key);

  @override
  State<SupersalePage> createState() => _SupersalePageState();
}

class _SupersalePageState extends State<SupersalePage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  DateTime _parseDate(dynamic dateField) {
    if (dateField is Timestamp) {
      return dateField.toDate();
    } else if (dateField is String) {
      return DateTime.tryParse(dateField) ?? DateTime.now();
    }
    return DateTime.now();
  }

  String _formatDate(dynamic dateField) {
    if (dateField == null) return 'N/A';
    DateTime dt = _parseDate(dateField);
    return DateFormat('dd MMM yyyy, hh:mm a').format(dt.toLocal());
  }

  Future<void> _deleteSupersale(String docId, String itemName, List<dynamic> branches) async {
    try {
      final openNotifId = (docId + '_open').hashCode & 0x7FFFFFFF;
      final preCloseNotifId = (docId + '_preclose').hashCode & 0x7FFFFFFF;
      final closedNotifId = (docId + '_closed').hashCode & 0x7FFFFFFF;
      await AwesomeNotifications().cancel(openNotifId);
      await AwesomeNotifications().cancel(preCloseNotifId);
      await AwesomeNotifications().cancel(closedNotifId);

      // Clean up user entries associated with this specific posting
      final List<String> fallbackBranches = [
        'BGR', 'CBE', 'CHN', 'CLT', 'EKM', 'JBL', 'KKM', 'KSD',
        'KTM', 'PKD', 'PKT', 'PMN', 'TRR', 'TSR', 'TLY', 'TVM',
        'UDP', 'VDK', 'WND', 'PKTR', 'PLA', 'PMNA'
      ];
      final targetBranches = branches.contains('all') || branches.isEmpty
          ? fallbackBranches
          : branches.map((e) => e.toString()).toList();

      for (final branch in targetBranches) {
        final entries = await _firestore
            .collection('supersale_user_entries')
            .doc(branch)
            .collection(itemName)
            .where('adminPostingId', isEqualTo: docId)
            .get();

        for (final entry in entries.docs) {
          await entry.reference.delete();
        }
      }

      await _firestore.collection('supersales').doc(docId).delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Supersale entry deleted'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete entry: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildEmptyState(bool isDark, bool isExpiredTab) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isExpiredTab ? Icons.history_rounded : Icons.flash_off_rounded,
            size: 64,
            color: primaryBlue.withOpacity(0.4),
          ),
          const SizedBox(height: 16),
          Text(
            isExpiredTab ? 'No Expired Supersales' : 'No Active Supersales',
            style: TextStyle(
              fontFamily: 'Times New Roman',
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isExpiredTab
                ? 'Supersales whose delivery period has ended will appear here.'
                : 'Tap the + button to add a new supersale schedule.',
            style: TextStyle(
              fontFamily: 'Times New Roman',
              color: isDark ? Colors.white38 : Colors.black45,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSupersaleList(
      BuildContext context, List<QueryDocumentSnapshot> docs, bool isDark, bool isExpired) {
    final textTheme = Theme.of(context).textTheme;

    if (docs.isEmpty) {
      return _buildEmptyState(isDark, isExpired);
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      itemCount: docs.length,
      itemBuilder: (context, index) {
        final doc = docs[index];
        final data = doc.data() as Map<String, dynamic>;
        final docId = doc.id;

        final item = data['item'] ?? 'Unnamed Item';
        final bookingStart = data['bookingStart'];
        final bookingEnd = data['bookingEnd'];
        final deliveryStart = data['deliveryStart'];
        final deliveryEnd = data['deliveryEnd'];
        final List<dynamic> branches = data['branches'] ?? [];

        return Dismissible(
          key: Key(docId),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.redAccent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.delete_rounded,
                color: Colors.white, size: 28),
          ),
          onDismissed: (direction) => _deleteSupersale(docId, item, branches),
          confirmDismiss: (direction) async {
            return await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text(
                  'Delete Supersale',
                  style: TextStyle(fontFamily: 'Times New Roman'),
                ),
                content: Text(
                  'Are you sure you want to delete "$item"?',
                  style: const TextStyle(fontFamily: 'Times New Roman'),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(fontFamily: 'Times New Roman'),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text(
                      'Delete',
                      style: TextStyle(
                        fontFamily: 'Times New Roman',
                        color: Colors.red,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
          child: InkWell(
            onTap: () {
              final bStart = _parseDate(bookingStart);
              final bEnd = _parseDate(bookingEnd);
              final dStart = _parseDate(deliveryStart);
              final dEnd = _parseDate(deliveryEnd);

              final validBookingRange = bStart.isAfter(bEnd)
                  ? DateTimeRange(start: bEnd, end: bStart)
                  : DateTimeRange(start: bStart, end: bEnd);

              final validDeliveryRange = dStart.isAfter(dEnd)
                  ? DateTimeRange(start: dEnd, end: dStart)
                  : DateTimeRange(start: dStart, end: dEnd);

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SupersaleFormPage(
                    docId: docId,
                    item: item,
                    bookingRange: validBookingRange,
                    deliveryRange: validDeliveryRange,
                    branches: branches.map((e) => e.toString()).toList(),
                  ),
                ),
              );
            },
            borderRadius: BorderRadius.circular(16),
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
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        width: 6,
                        color: isExpired ? Colors.grey : primaryBlue,
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      item,
                                      style:
                                          textTheme.titleMedium?.copyWith(
                                        fontFamily: 'Times New Roman',
                                        fontWeight: FontWeight.bold,
                                        color: isDark
                                            ? Colors.white
                                            : Colors.black87,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isExpired
                                          ? Colors.grey.withOpacity(0.15)
                                          : primaryGreen.withOpacity(0.15),
                                      borderRadius:
                                          BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      isExpired ? 'Expired' : 'Active',
                                      style: TextStyle(
                                        fontFamily: 'Times New Roman',
                                        color: isExpired
                                            ? (isDark ? Colors.grey[400] : Colors.grey[700])
                                            : primaryGreen,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  const Icon(Icons.date_range_rounded,
                                      size: 16, color: primaryBlue),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Booking: ${_formatDate(bookingStart)} - ${_formatDate(bookingEnd)}',
                                      style: TextStyle(
                                        fontFamily: 'Times New Roman',
                                        fontSize: 13,
                                        color: isDark
                                            ? Colors.white70
                                            : Colors.black87,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Icon(Icons.local_shipping_rounded,
                                      size: 16,
                                      color: isExpired ? Colors.grey : primaryGreen),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Delivery: ${_formatDate(deliveryStart)} - ${_formatDate(deliveryEnd)}',
                                      style: TextStyle(
                                        fontFamily: 'Times New Roman',
                                        fontSize: 13,
                                        color: isDark
                                            ? Colors.white70
                                            : Colors.black87,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              const Divider(height: 1, thickness: 0.5),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  Icon(Icons.location_on_rounded,
                                      size: 14, color: Colors.grey[500]),
                                  const SizedBox(width: 2),
                                  ...branches.map((b) => Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: isDark
                                              ? const Color(0xFF334155)
                                              : Colors.grey[100],
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          b.toString(),
                                          style: TextStyle(
                                            fontFamily: 'Times New Roman',
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500,
                                            color: isDark
                                                ? Colors.white70
                                                : Colors.black54,
                                          ),
                                        ),
                                      )),
                                ],
                              ),
                            ],
                          ),
                        ),
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Theme(
      data: Theme.of(context).copyWith(
        textTheme: Theme.of(context).textTheme.apply(
          fontFamily: 'Times New Roman',
        ),
      ),
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          backgroundColor: isDark ? const Color(0xFF0A1628) : Colors.grey[50],
          appBar: AppBar(
            title: const Text(
              'SUPERSALE LIST',
              style: TextStyle(
                fontFamily: 'Times New Roman',
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
            elevation: 0,
            backgroundColor: primaryBlue,
            foregroundColor: Colors.white,
            centerTitle: true,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.assessment_rounded),
                tooltip: 'Supersale Dashboard',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SupersaleAdminDashboard(),
                    ),
                  );
                },
              ),
            ],
            bottom: const TabBar(
              indicatorColor: primaryGreen,
              indicatorWeight: 3,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              labelStyle: TextStyle(
                fontFamily: 'Times New Roman',
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
              unselectedLabelStyle: TextStyle(
                fontFamily: 'Times New Roman',
                fontWeight: FontWeight.normal,
                fontSize: 15,
              ),
              tabs: [
                Tab(
                  text: 'Active',
                  icon: Icon(Icons.flash_on_rounded, size: 20),
                ),
                Tab(
                  text: 'Expired',
                  icon: Icon(Icons.history_rounded, size: 20),
                ),
              ],
            ),
          ),
          body: StreamBuilder<QuerySnapshot>(
            stream: _firestore
                .collection('supersales')
                .orderBy('created_at', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Text(
                    'Error loading supersales: ${snapshot.error}',
                    style: const TextStyle(
                      fontFamily: 'Times New Roman',
                      color: Colors.red,
                    ),
                  ),
                );
              }

              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs = snapshot.data?.docs ?? [];
              final now = DateTime.now();

              final activeDocs = <QueryDocumentSnapshot>[];
              final expiredDocs = <QueryDocumentSnapshot>[];

              for (final doc in docs) {
                final data = doc.data() as Map<String, dynamic>;
                final deliveryEndRaw = data['deliveryEnd'];
                DateTime deliveryEnd = _parseDate(deliveryEndRaw);

                if (deliveryEnd.isBefore(now)) {
                  expiredDocs.add(doc);
                } else {
                  activeDocs.add(doc);
                }
              }

              return TabBarView(
                children: [
                  _buildSupersaleList(context, activeDocs, isDark, false),
                  _buildSupersaleList(context, expiredDocs, isDark, true),
                ],
              );
            },
          ),
          floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SupersaleFormPage()),
              );
            },
            backgroundColor: primaryBlue,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add_rounded, size: 24),
            label: const Text(
              'Add Supersale',
              style: TextStyle(
                fontFamily: 'Times New Roman',
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
