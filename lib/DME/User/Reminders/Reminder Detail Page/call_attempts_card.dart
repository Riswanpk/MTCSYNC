import 'package:flutter/material.dart';

class CallAttemptsCard extends StatelessWidget {
  final List<Map<String, dynamic>> reminderCallLogs;
  final bool isLoadingReminderLogs;
  final int todayCallAttempts;
  final String Function(dynamic) formatDateTime;
  final String Function(dynamic) getUserDisplayName;

  const CallAttemptsCard({
    super.key,
    required this.reminderCallLogs,
    required this.isLoadingReminderLogs,
    required this.todayCallAttempts,
    required this.formatDateTime,
    required this.getUserDisplayName,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (isLoadingReminderLogs) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(8.0),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (reminderCallLogs.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.phone_in_talk_rounded, size: 20, color: Color(0xFF005BAC)),
                    const SizedBox(width: 8),
                    Text(
                      'Call Attempts & Logs (${reminderCallLogs.length})',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF005BAC).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$todayCallAttempts/2 today',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF005BAC),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: reminderCallLogs.length,
              separatorBuilder: (_, __) => const Divider(height: 14),
              itemBuilder: (context, idx) {
                final log = reminderCallLogs[idx];
                final ts = log['attempt_timestamp']?.toString();
                final dur = int.tryParse(log['ring_duration']?.toString() ?? '') ?? 0;
                final type = (log['call_type'] ?? 'outgoing').toString();
                final caller = getUserDisplayName(log['caller_email'] ?? log['caller_uid']);
                final isAnswered = dur > 0;
                final isLong = dur > 10;

                return Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: isLong
                            ? Colors.green.withValues(alpha: 0.12)
                            : isAnswered
                                ? Colors.teal.withValues(alpha: 0.12)
                                : Colors.orange.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        type == 'incoming'
                            ? Icons.call_received_rounded
                            : isAnswered
                                ? Icons.call_made_rounded
                                : Icons.call_missed_rounded,
                        size: 16,
                        color: isLong
                            ? Colors.green[800]
                            : isAnswered
                                ? Colors.teal[800]
                                : Colors.orange[900],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                formatDateTime(ts),
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isLong
                                      ? Colors.green.withValues(alpha: 0.15)
                                      : isAnswered
                                          ? Colors.teal.withValues(alpha: 0.15)
                                          : Colors.orange.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  dur > 0 ? '${dur}s Connected' : '0s Unanswered',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: isLong
                                        ? Colors.green[800]
                                        : isAnswered
                                            ? Colors.teal[800]
                                            : Colors.orange[900],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${type.toUpperCase()} • Attempt #${reminderCallLogs.length - idx}${caller.isNotEmpty ? " • by $caller" : ""}',
                            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
