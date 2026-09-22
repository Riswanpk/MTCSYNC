import 'package:flutter/material.dart';

class CallActionButtons extends StatelessWidget {
  final int todayCallAttempts;
  final int callAttempts;
  final int? callDuration;
  final DateTime? lastCallAttemptTimestamp;
  final List<Map<String, dynamic>> reminderCallLogs;
  final DateTime? Function(dynamic) parseAttemptTimestamp;
  final String preference;
  final bool hasShortAttendedCall;
  final bool isCheckingCall;
  final VoidCallback onMakeCall;
  final VoidCallback onCheckCallLog;
  final VoidCallback onSendWhatsApp;

  const CallActionButtons({
    super.key,
    required this.todayCallAttempts,
    required this.callAttempts,
    required this.callDuration,
    required this.lastCallAttemptTimestamp,
    required this.reminderCallLogs,
    required this.parseAttemptTimestamp,
    required this.preference,
    required this.hasShortAttendedCall,
    required this.isCheckingCall,
    required this.onMakeCall,
    required this.onCheckCallLog,
    required this.onSendWhatsApp,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final now = DateTime.now();
    final bool hasReachedDailyLimit = todayCallAttempts >= 2;

    // 1-hour gap logic between attempts:
    DateTime? effectiveLastCall = lastCallAttemptTimestamp?.toLocal();
    if (reminderCallLogs.isNotEmpty) {
      for (final log in reminderCallLogs) {
        final tsStr = log['attempt_timestamp']?.toString();
        if (tsStr == null) continue;
        final dt = parseAttemptTimestamp(tsStr);
        if (dt != null && (effectiveLastCall == null || dt.isAfter(effectiveLastCall))) {
          effectiveLastCall = dt;
        }
      }
    }

    int remainingCooldownSeconds = 0;
    bool has60MinsPassed = true;

    if (todayCallAttempts > 0 && effectiveLastCall != null) {
      final elapsed = now.difference(effectiveLastCall);
      if (elapsed.inSeconds < 3600) {
        remainingCooldownSeconds = 3600 - elapsed.inSeconds;
        has60MinsPassed = false;
      } else {
        has60MinsPassed = true;
        remainingCooldownSeconds = 0;
      }
    }

    final bool isCooldownActive = !has60MinsPassed && remainingCooldownSeconds > 0;
    final bool canMakeCall = !hasReachedDailyLimit && !isCooldownActive;
    final int minutesLeft = (remainingCooldownSeconds / 60).ceil();

    final bool isWhatsAppPreference = preference.trim().toLowerCase() == 'whatsapp';
    final bool hasShortCall = hasShortAttendedCall || (callDuration != null && callDuration! > 0 && callDuration! <= 10);
    final bool isWhatsAppUnlocked = isWhatsAppPreference || hasShortCall || callAttempts >= 3;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Status Notice Card for Attempts / Cooldown (hidden if customer preference is whatsapp)
        if (!isWhatsAppPreference && callAttempts > 0)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: hasReachedDailyLimit
                  ? Colors.red.withValues(alpha: 0.1)
                  : isCooldownActive
                      ? Colors.amber.withValues(alpha: 0.15)
                      : Colors.orange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: hasReachedDailyLimit
                    ? Colors.red.withValues(alpha: 0.4)
                    : isCooldownActive
                        ? Colors.amber.withValues(alpha: 0.5)
                        : Colors.orange.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  hasReachedDailyLimit
                      ? Icons.block_rounded
                      : isCooldownActive
                          ? Icons.hourglass_top_rounded
                          : Icons.phone_missed_rounded,
                  size: 20,
                  color: hasReachedDailyLimit
                      ? Colors.red[800]
                      : isCooldownActive
                          ? Colors.amber[900]
                          : Colors.orange[900],
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    hasReachedDailyLimit
                        ? 'Daily limit reached (2 calls today). If customer does not answer, this will be marked OVERDUE tomorrow for another 2 attempts.'
                        : isCooldownActive
                            ? '1-hour gap required between calls. Next attempt available in ~$minutesLeft minute${minutesLeft == 1 ? '' : 's'}.'
                            : todayCallAttempts > 0
                                ? 'Attempt #$todayCallAttempts made today. 60+ minutes have passed since last attempt — you can call again now.'
                                : 'Attempt #$todayCallAttempts made today ($callAttempts total lifetime attempts). Customer hasn\'t answered yet.',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: hasReachedDailyLimit
                          ? Colors.red[900]
                          : isCooldownActive
                              ? Colors.amber[900]
                              : Colors.orange[900],
                    ),
                  ),
                ),
              ],
            ),
          ),

        // Call Customer Button (hidden if preference is whatsapp)
        if (!isWhatsAppPreference) ...[
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: canMakeCall ? onMakeCall : null,
              icon: const Icon(Icons.call, size: 22),
              label: Text(
                hasReachedDailyLimit
                    ? 'Daily Call Limit Reached (2/2 Calls Today)'
                    : isCooldownActive
                        ? 'Call Again in $minutesLeft min (1-Hr Gap)'
                        : todayCallAttempts > 0
                            ? 'Call Customer Again (Attempt 2/2 Today)'
                            : 'Call Customer (Attempt 1/2 Today)',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: canMakeCall ? const Color(0xFF8CC63F) : Colors.grey[400],
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey[300],
                disabledForegroundColor: Colors.grey[600],
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: canMakeCall ? 2 : 0,
              ),
            ),
          ),
          if (isCheckingCall)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 10),
                  Text('Checking Android call log...', style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            )
          else
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onCheckCallLog,
                icon: const Icon(Icons.sync_rounded, size: 16),
                label: const Text('Check Call Log', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: const Color(0xFF005BAC),
                ),
              ),
            ),
          const SizedBox(height: 6),
        ],

        // WhatsApp Button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: isWhatsAppUnlocked ? onSendWhatsApp : null,
            icon: Icon(
              isWhatsAppUnlocked ? Icons.chat_rounded : Icons.lock_outline_rounded,
              size: 22,
            ),
            label: Text(
              isWhatsAppUnlocked
                  ? (isWhatsAppPreference
                      ? 'Send WhatsApp Message (Customer Preference)'
                      : hasShortCall
                          ? 'Send WhatsApp Message (Call under 10s)'
                          : 'Send WhatsApp Message & Upload Proof')
                  : 'WhatsApp unlocks after 3 call attempts ($callAttempts/3 made)',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: isWhatsAppUnlocked ? const Color(0xFF25D366) : Colors.grey[300],
              foregroundColor: isWhatsAppUnlocked ? Colors.white : Colors.grey[600],
              disabledBackgroundColor: isDark ? Colors.grey[800] : Colors.grey[200],
              disabledForegroundColor: isDark ? Colors.grey[500] : Colors.grey[600],
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: isWhatsAppUnlocked ? 2 : 0,
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
