import 'package:flutter/material.dart';

import 'customer_list_target_service.dart';

class CustomerListTileItem extends StatelessWidget {
  final Map<String, dynamic> customer;
  final int customerIndex;
  final bool isDark;
  final Color primaryBlue;
  final Color primaryGreen;
  final Function() openViewer;
  final Function() onCustomerUpdated;
  final Future<void> Function() onUpdateFirestore;
  final String? docId;

  const CustomerListTileItem({
    super.key,
    required this.customer,
    required this.customerIndex,
    required this.isDark,
    required this.primaryBlue,
    required this.primaryGreen,
    required this.openViewer,
    required this.onCustomerUpdated,
    required this.onUpdateFirestore,
    required this.docId,
  });

  @override
  Widget build(BuildContext context) {
    final bool callMade = customer['callMade'] == true;
    final bool isEven = customerIndex % 2 == 0;
    final bool isPendingDeletion = customer['pendingDeletion'] == true;
    final bool isPendingEditing = customer['pendingEditing'] == true;
    final bool isPending = isPendingDeletion || isPendingEditing;

    return Opacity(
      opacity: isPending ? 0.45 : 1.0,
      child: Material(
        color: isPending
            ? (isDark ? Colors.grey.shade900 : Colors.grey.shade300)
            : (isEven
                ? (isDark ? const Color(0xFF1E2128) : Colors.white)
                : (isDark ? const Color(0xFF23272E) : const Color(0xFFF5F9FF))),
        child: InkWell(
          onTap: openViewer,
          onLongPress: isPending
              ? null
              : () async {
                  final action = await showModalBottomSheet<String>(
                    context: context,
                    builder: (context) => SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ListTile(
                            leading: const Icon(Icons.delete, color: Colors.red),
                            title: const Text('Delete'),
                            onTap: () => Navigator.pop(context, 'delete'),
                          ),
                        ],
                      ),
                    ),
                  );
                  if (action == 'delete') {
                    if (!context.mounted) return;
                    await CustomerListTargetService.requestCustomerDeletion(
                      context: context,
                      customer: customer,
                      docId: docId,
                      onUpdateFirestore: onUpdateFirestore,
                    );
                    onCustomerUpdated();
                  }
                },
          splashColor: (isDark ? primaryBlue : primaryGreen).withValues(alpha: 0.15),
          highlightColor: (isDark ? primaryBlue : primaryGreen).withValues(alpha: 0.08),
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
                        backgroundColor: isPending
                            ? Colors.grey.shade400
                            : const Color(0xFFE3F2FD),
                        child: Text(
                          (customer['name'] ?? '?').toString().toUpperCase().isNotEmpty
                              ? (customer['name'] ?? '?').toString().toUpperCase()[0]
                              : '?',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
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
                            color: isPending
                                ? Colors.grey
                                : const Color.fromARGB(255, 108, 186, 5),
                            decoration: isPending ? TextDecoration.lineThrough : null,
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
                      color: isPending
                          ? Colors.grey
                          : const Color(0xFF005BAC).withValues(alpha: 0.9),
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
                        color: isPending
                            ? (isPendingDeletion ? Colors.red.withValues(alpha: 0.15) : Colors.orange.withValues(alpha: 0.15))
                            : (callMade
                                ? Colors.green.withValues(alpha: 0.15)
                                : Colors.orange.withValues(alpha: 0.15)),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isPending
                              ? (isPendingDeletion ? Colors.red.withValues(alpha: 0.4) : Colors.orange.withValues(alpha: 0.4))
                              : (callMade
                                  ? Colors.green.withValues(alpha: 0.4)
                                  : Colors.orange.withValues(alpha: 0.4)),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isPending
                                ? Icons.hourglass_top_rounded
                                : (callMade ? Icons.check_circle : Icons.pending),
                            size: 14,
                            color: isPending
                                ? (isPendingDeletion ? Colors.red : Colors.orange)
                                : (callMade ? Colors.green : Colors.orange),
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
      ),
    );
  }
}
