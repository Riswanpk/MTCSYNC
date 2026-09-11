import 'package:mtcsync/DME/dme_config.dart';
import 'package:flutter/foundation.dart';

/// Manages per-user daily statistics stored in `dme_user_daily_stats`.
/// Each row is keyed by (user_uid, stat_date) — safe to upsert at any time.
class DmeUserStatsService {
  /// Increments `calls_count` for [userUid] on [statDate] (yyyy-MM-dd).
  static Future<void> incrementCallCount({
    required String userUid,
    required String userEmail,
    required String statDate,
  }) => _upsertStat(userUid: userUid, userEmail: userEmail, statDate: statDate, callsDelta: 1);

  /// Increments `whatsapp_count` for [userUid] on [statDate] (yyyy-MM-dd).
  static Future<void> incrementWhatsAppCount({
    required String userUid,
    required String userEmail,
    required String statDate,
  }) => _upsertStat(userUid: userUid, userEmail: userEmail, statDate: statDate, whatsAppDelta: 1);

  /// Sets (overwrites) `overdue_count` for [userUid] on [statDate].
  /// Called at assignment time to record how many reminders a user left pending from the previous day.
  static Future<void> setOverdueCount({
    required String userUid,
    required String userEmail,
    required String statDate,
    required int overdueCount,
  }) async {
    final client = DmeConfig.client;
    if (client == null) return;
    try {
      await client.from('dme_user_daily_stats').upsert(
        {
          'user_uid': userUid,
          'user_email': userEmail,
          'stat_date': statDate,
          'overdue_count': overdueCount,
          'updated_at': DateTime.now().toIso8601String(),
        },
        onConflict: 'user_uid,stat_date',
        ignoreDuplicates: false,
      );
    } catch (e) {
      debugPrint('DmeUserStatsService.setOverdueCount error: $e');
    }
  }

  /// Fetches aggregated stats per user_uid for the given date range.
  /// Returns: { uid -> { calls, whatsapp, overdue } }
  static Future<Map<String, Map<String, int>>> fetchStatsForRange({
    required String startDate,
    required String endDate,
  }) async {
    final client = DmeConfig.client;
    if (client == null) return {};
    try {
      final res = await client
          .from('dme_user_daily_stats')
          .select('user_uid, calls_count, whatsapp_count, overdue_count')
          .gte('stat_date', startDate)
          .lte('stat_date', endDate);

      final Map<String, Map<String, int>> result = {};
      for (final row in (res as List)) {
        final uid = row['user_uid']?.toString() ?? '';
        if (uid.isEmpty) continue;
        final e = result.putIfAbsent(uid, () => {'calls': 0, 'whatsapp': 0, 'overdue': 0});
        e['calls']    = e['calls']!    + (row['calls_count']    as int? ?? 0);
        e['whatsapp'] = e['whatsapp']! + (row['whatsapp_count'] as int? ?? 0);
        e['overdue']  = e['overdue']!  + (row['overdue_count']  as int? ?? 0);
      }
      return result;
    } catch (e) {
      debugPrint('DmeUserStatsService.fetchStatsForRange error: $e');
      return {};
    }
  }

  // -- Private ----------------------------------------------------------------

  static Future<void> _upsertStat({
    required String userUid,
    required String userEmail,
    required String statDate,
    int callsDelta = 0,
    int whatsAppDelta = 0,
  }) async {
    final client = DmeConfig.client;
    if (client == null) return;
    try {
      // Read current counts, then write back with delta applied.
      final existing = await client
          .from('dme_user_daily_stats')
          .select('calls_count, whatsapp_count')
          .eq('user_uid', userUid)
          .eq('stat_date', statDate)
          .maybeSingle();

      final currentCalls    = (existing?['calls_count']    as int?) ?? 0;
      final currentWhatsApp = (existing?['whatsapp_count'] as int?) ?? 0;

      await client.from('dme_user_daily_stats').upsert(
        {
          'user_uid':       userUid,
          'user_email':     userEmail,
          'stat_date':      statDate,
          'calls_count':    currentCalls    + callsDelta,
          'whatsapp_count': currentWhatsApp + whatsAppDelta,
          'updated_at':     DateTime.now().toIso8601String(),
        },
        onConflict: 'user_uid,stat_date',
        ignoreDuplicates: false,
      );
    } catch (e) {
      debugPrint('DmeUserStatsService._upsertStat error: $e');
    }
  }
}
