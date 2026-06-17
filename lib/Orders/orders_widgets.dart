import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:intl/intl.dart';
import 'present_order.dart';

Color getOrderPriorityColor(String priority) {
  switch (priority) {
    case 'High':
      return Colors.red;
    case 'Medium':
      return Colors.amber;
    case 'Low':
      return Colors.green;
    default:
      return Colors.grey;
  }
}

String formatOrderDate(dynamic value) {
  DateTime? parsed;
  if (value is Timestamp) {
    parsed = value.toDate();
  } else if (value is DateTime) {
    parsed = value;
  } else if (value is String && value.isNotEmpty) {
    try {
      parsed = DateFormat('dd-MM-yyyy hh:mm a').parse(value);
    } catch (_) {
      try {
        parsed = DateTime.parse(value);
      } catch (_) {
        parsed = null;
      }
    }
  }

  if (parsed == null) return 'N/A';
  return DateFormat('dd-MM-yyyy hh:mm a').format(parsed);
}

class OrderCard extends StatelessWidget {
  final String name;
  final String status;
  final dynamic createdAt;
  final String docId;
  final String createdBy;
  final String priority;
  final dynamic deliveryDate;
  final VoidCallback? onStatusChanged;

  const OrderCard({
    super.key,
    required this.name,
    required this.status,
    required this.createdAt,
    required this.docId,
    required this.createdBy,
    required this.priority,
    required this.deliveryDate,
    this.onStatusChanged,
  });

  Future<void> _markCompleted(BuildContext context) async {
    await FirebaseFirestore.instance.collection('follow_ups').doc(docId).update({
      'status': 'Completed',
      'completed_at': FieldValue.serverTimestamp(),
    });
    onStatusChanged?.call();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Order marked as Completed')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCompleted = status == 'Completed';
    final createdText = formatOrderDate(createdAt);
    final deliveryText = formatOrderDate(deliveryDate);

    return Slidable(
      key: ValueKey(docId),
      startActionPane: isCompleted
          ? null
          : ActionPane(
              motion: const DrawerMotion(),
              extentRatio: 0.28,
              children: [
                SlidableAction(
                  onPressed: (_) => _markCompleted(context),
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  icon: Icons.check_circle,
                  label: 'Completed',
                  borderRadius: BorderRadius.circular(20),
                ),
              ],
            ),
      child: GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PresentOrderPage(docId: docId),
            ),
          ).then((_) => onStatusChanged?.call());
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: isCompleted ? Colors.green : getOrderPriorityColor(priority),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$name ($status)',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Text('Created: $createdText', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                    Text('Delivery: $deliveryText', style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
                    Text('Created by: $createdBy', style: const TextStyle(fontSize: 12, color: Colors.black45)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
