import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'supersale_user_form.dart';

const Color primaryBlue = Color(0xFF005BAC);
const Color primaryGreen = Color(0xFF8CC63F);

/// Card widget to display individual Supersale booking in pending or delivered lists.
class SupersaleBookingCard extends StatelessWidget {
  final QueryDocumentSnapshot doc;
  final bool isBookingOpen;
  final bool isDark;
  final TextTheme textTheme;
  final DateTime now;
  final String? userBranch;
  final Future<bool> Function(DismissDirection direction) onConfirmDismiss;

  const SupersaleBookingCard({
    super.key,
    required this.doc,
    required this.isBookingOpen,
    required this.isDark,
    required this.textTheme,
    required this.now,
    required this.userBranch,
    required this.onConfirmDismiss,
  });

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
    final d = dt.toLocal();
    final day = d.day.toString().padLeft(2, '0');
    final month = d.month.toString().padLeft(2, '0');
    final year = d.year.toString();
    return '$day/$month/$year';
  }

  @override
  Widget build(BuildContext context) {
    final data = doc.data() as Map<String, dynamic>;
    final docId = doc.id;
    final item = doc.reference.parent.id;

    final customerName = data['customerName'] ?? 'No Customer Name';
    final phone = data['phone'] ?? 'No Phone';
    final description = data['description']?.toString() ?? '';
    final quantity = data['quantity'] ?? 0;
    final rate = data['rate'] ?? 0.0;
    final advance = data['advance'] ?? 0.0;
    final status = data['status'] ?? 'pending';
    final billedPhone = data['billedPhone'];

    final Timestamp? bookingStart = data['bookingStart'] as Timestamp?;
    final Timestamp? bookingEnd = data['bookingEnd'] as Timestamp?;
    final dynamic bookedAt = data['created_at'];
    final dynamic deliveredAt = data['deliveredAt'];
    final bool isSpot = data['isSpotSale'] == true || data['saleType'] == 'spot_sale';

    final bool isActionAllowed = bookingStart != null &&
        bookingEnd != null &&
        now.isAfter(bookingStart.toDate()) &&
        now.isBefore(bookingEnd.toDate());
    final bool isDelivered = status == 'delivered';

    return Dismissible(
      key: Key(docId),
      direction: isDelivered ? DismissDirection.none : DismissDirection.horizontal,
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
      confirmDismiss: onConfirmDismiss,
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
              color: Colors.black.withValues(alpha: 0.04),
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
                ScaffoldMessenger.maybeOf(context)?.showSnackBar(
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
                          style: (textTheme.titleMedium ?? const TextStyle(fontSize: 16)).copyWith(
                            fontSize: ((textTheme.titleMedium?.fontSize ?? 16) + 2),
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'Booked ${_formatSimpleDate(bookedAt)}',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? Colors.white60 : Colors.black87,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (!isSpot && isDelivered && deliveredAt != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              'Delivered ${_formatSimpleDate(deliveredAt)}',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? Colors.white60 : Colors.black87,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                          const SizedBox(height: 4),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (data['isPartialSplit'] == true) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                  margin: const EdgeInsets.only(right: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'Part Split',
                                    style: TextStyle(
                                      color: Colors.blue,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 9,
                                    ),
                                  ),
                                ),
                              ] else if (data['hasPartialDelivery'] == true && status != 'delivered') ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                  margin: const EdgeInsets.only(right: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.purple.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'Part Remaining',
                                    style: TextStyle(
                                      color: Colors.purple,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 9,
                                    ),
                                  ),
                                ),
                              ],
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: status == 'delivered'
                                      ? Colors.green.withValues(alpha: 0.15)
                                      : Colors.orange.withValues(alpha: 0.15),
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
                    ],
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.notes_rounded, size: 16, color: Colors.grey[400]),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            description,
                            style: TextStyle(
                              fontSize: 13,
                              fontStyle: FontStyle.italic,
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  // Customer Info
                  Row(
                    children: [
                      Icon(Icons.person_rounded, size: 16, color: Colors.grey[400]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          customerName,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
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
                        phone,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  if (status == 'delivered' && billedPhone != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.receipt_rounded, size: 16, color: Color(0xFF8CC63F)),
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
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF8CC63F),
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
  }
}
