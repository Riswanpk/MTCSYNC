import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'customer_target_customer_tile_viewer.dart';

class CallDetectedRemarksDialog extends StatelessWidget {
  final List<Map<String, dynamic>> customers;
  final String titleText;
  final String subtitleText;
  final Function(Map<String, dynamic> customer, String remarks)? onStatusChanged;
  final Function()? onCustomerSelected;

  const CallDetectedRemarksDialog({
    super.key,
    required this.customers,
    this.titleText = 'Call Detected! Add Remarks',
    this.subtitleText = 'customer(s) were called today. Tap to add remarks.',
    this.onStatusChanged,
    this.onCustomerSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final dialogBg = isDark ? const Color(0xFF1E2128) : Colors.white;
    final primaryGradient = const LinearGradient(
      colors: [Color(0xFF005BAC), Color(0xFF8CC63F)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: dialogBg,
      elevation: 10,
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header with gradient
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              gradient: primaryGradient,
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.phone_callback, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titleText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${customers.length} $subtitleText',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Customer list
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                shrinkWrap: true,
                itemCount: customers.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                ),
                itemBuilder: (context, i) {
                  final c = customers[i];
                  final name = (c['name'] ?? '').toString().toUpperCase();
                  final contact = c['contact1'] ?? c['contact'] ?? '';

                  return Material(
                    color: Colors.transparent,
                    child: ListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      leading: CircleAvatar(
                        radius: 18,
                        backgroundColor: const Color(0xFF8CC63F).withValues(alpha: 0.15),
                        child: const Icon(Icons.check_circle_rounded,
                            color: Color(0xFF8CC63F), size: 20),
                      ),
                      title: Text(
                        name,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      subtitle: Text(
                        contact,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                        ),
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF2C3038) : Colors.grey.shade100,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 12,
                          color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                        ),
                      ),
                      onTap: () {
                        Navigator.of(context).pop();
                        if (onCustomerSelected != null) {
                          onCustomerSelected!();
                        }
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => SalesCustomerTileViewer(
                              customer: c,
                              onStatusChanged: (remarks) async {
                                c['callMade'] = true;
                                if (c['callDate'] == null) {
                                  c['callDate'] = Timestamp.now();
                                }
                                c['remarks'] = remarks;
                                if (onStatusChanged != null) {
                                  await onStatusChanged!(c, remarks);
                                }
                              },
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ),

          // Footer action
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    foregroundColor: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                  child: const Text('Close', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
