import 'package:flutter/material.dart';

class CustomerInfoCard extends StatelessWidget {
  final Map<String, dynamic> reminder;
  final String customerName;
  final String customerPhone;
  final String customerAddress;
  final String salesman;
  final String branchName;
  final String preference;
  final String customerTypeName;
  final bool isPremiumCustomer;
  final String categoryName;
  final String? reminderDateStr;
  final String? lastPurchaseDateStr;
  final int callAttempts;
  final int todayCallAttempts;
  final bool callMade;
  final String Function(dynamic) formatDate;
  final String Function(dynamic) getUserDisplayName;

  const CustomerInfoCard({
    super.key,
    required this.reminder,
    required this.customerName,
    required this.customerPhone,
    required this.customerAddress,
    required this.salesman,
    required this.branchName,
    required this.preference,
    required this.customerTypeName,
    required this.isPremiumCustomer,
    required this.categoryName,
    required this.reminderDateStr,
    required this.lastPurchaseDateStr,
    required this.callAttempts,
    required this.todayCallAttempts,
    required this.callMade,
    required this.formatDate,
    required this.getUserDisplayName,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isWhatsApp = preference.trim().toLowerCase() == 'whatsapp';

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: const Color(0xFF005BAC).withValues(alpha: 0.1),
                  foregroundColor: const Color(0xFF005BAC),
                  child: const Icon(Icons.person, size: 30),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        customerName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF005BAC).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              branchName,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF005BAC),
                              ),
                            ),
                          ),
                          if (salesman.isNotEmpty)
                            Text(
                              'Salesman: $salesman',
                              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              children: [
                const Icon(Icons.phone, size: 18, color: Colors.grey),
                const SizedBox(width: 8),
                Text(
                  'Phone: $customerPhone',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  isWhatsApp ? Icons.chat_bubble_outline_rounded : Icons.phone_in_talk_rounded,
                  size: 18,
                  color: isWhatsApp ? Colors.green : const Color(0xFF005BAC),
                ),
                const SizedBox(width: 8),
                Text('Preference: ', style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: isWhatsApp
                        ? Colors.green.withValues(alpha: 0.1)
                        : const Color(0xFF005BAC).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isWhatsApp
                          ? Colors.green.withValues(alpha: 0.5)
                          : const Color(0xFF005BAC).withValues(alpha: 0.5),
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    preference,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isWhatsApp ? Colors.green[800] : const Color(0xFF005BAC),
                    ),
                  ),
                ),
              ],
            ),
            if (customerAddress.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.location_on, size: 18, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      customerAddress,
                      style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                    ),
                  ),
                ],
              ),
            ],
            // Customer Type & Category
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.category_outlined, size: 18, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Type: ',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[700],
                            ),
                          ),
                          Text(
                            customerTypeName,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: isPremiumCustomer
                                  ? const Color(0xFFD97706)
                                  : (isDark ? Colors.white : Colors.black87),
                            ),
                          ),
                          if (isPremiumCustomer) ...[
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.workspace_premium,
                              size: 16,
                              color: Color(0xFFD97706),
                            ),
                          ],
                        ],
                      ),
                      Text('•', style: TextStyle(fontSize: 12, color: Colors.grey[400])),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Category: ',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[700],
                            ),
                          ),
                          Text(
                            categoryName,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white70 : Colors.grey[800],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 8,
              runSpacing: 4,
              children: [
                Text(
                  'Due Date: ${formatDate(reminderDateStr)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Color(0xFF005BAC),
                  ),
                ),
                Text(
                  'Last Purchase: ${formatDate(lastPurchaseDateStr)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
              ],
            ),
            if (reminder['called_by'] != null && reminder['called_by'].toString().isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.person_pin_rounded, size: 16, color: Colors.green),
                  const SizedBox(width: 6),
                  Text(
                    'Called by: ${getUserDisplayName(reminder['called_by'])}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
            ],
            if (callAttempts > 0) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    callMade ? Icons.phone_callback_rounded : Icons.phone_missed_rounded,
                    size: 16,
                    color: callMade ? Colors.green : Colors.orange[800],
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      callMade
                          ? 'Connected today ($todayCallAttempts/2 today, $callAttempts total)'
                          : 'Attempted today: $todayCallAttempts/2 ($callAttempts total attempted across days)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: callMade ? Colors.green[800] : Colors.orange[900],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
