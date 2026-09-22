import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../Misc/dme_constants.dart';

class DmeReminderDetailHelpers {
  static String formatDate(dynamic date) {
    if (date == null) return 'N/A';
    if (date is DateTime) {
      return DateFormat('dd-MM-yyyy').format(date);
    }
    final str = date.toString().trim();
    if (str.isEmpty) return 'N/A';
    final parsed = DateTime.tryParse(str);
    if (parsed != null) {
      return DateFormat('dd-MM-yyyy').format(parsed);
    }
    return str;
  }

  static DateTime? parseAttemptTimestamp(dynamic ts) {
    if (ts == null) return null;
    if (ts is DateTime) return ts;
    final str = ts.toString().trim();
    if (str.isEmpty) return null;
    final cleanStr = str.replaceAll(RegExp(r'(Z|[+-]\d{2}(:\d{2})?)$'), '');
    final parsed = DateTime.tryParse(cleanStr);
    if (parsed != null) {
      return DateTime(
        parsed.year,
        parsed.month,
        parsed.day,
        parsed.hour,
        parsed.minute,
        parsed.second,
      );
    }
    return null;
  }

  static String formatDateTime(dynamic date) {
    if (date == null) return 'N/A';
    final dt = parseAttemptTimestamp(date);
    if (dt != null) {
      return DateFormat('dd-MM-yyyy hh:mm a').format(dt);
    }
    final str = date.toString().trim();
    return str.isEmpty ? 'N/A' : str;
  }

  static String getUserDisplayName(
    dynamic userIdentifier,
    Map<String, String> userNames,
  ) {
    if (userIdentifier == null) return '';
    final raw = userIdentifier.toString().trim();
    if (raw.isEmpty) return '';
    if (userNames.containsKey(raw)) return userNames[raw]!;
    if (userNames.containsKey(raw.toLowerCase())) {
      return userNames[raw.toLowerCase()]!;
    }
    if (raw.contains('@')) {
      final prefix = raw.split('@').first;
      if (prefix.isNotEmpty) {
        return prefix[0].toUpperCase() + prefix.substring(1);
      }
      return prefix;
    }
    return raw;
  }

  static ResolvedTypeAndCategory resolveTypeAndCategory({
    required Map<String, dynamic> reminder,
    required List<Map<String, dynamic>> customerBranches,
    required List<Map<String, dynamic>> salesHistory,
  }) {
    int? resolvedTypeId;
    int? resolvedCatId;

    final currentBranchId = reminder['last_purchase_branch'] != null
        ? int.tryParse(reminder['last_purchase_branch'].toString())
        : (reminder['branch_id'] != null
            ? int.tryParse(reminder['branch_id'].toString())
            : null);

    if (customerBranches.isNotEmpty) {
      final match = customerBranches.firstWhere(
        (b) =>
            currentBranchId != null &&
            int.tryParse(b['branch_id']?.toString() ?? '') == currentBranchId,
        orElse: () => customerBranches.first,
      );
      resolvedTypeId = int.tryParse(match['customer_type_id']?.toString() ?? '');
      resolvedCatId = int.tryParse(match['category_id']?.toString() ?? '');
    }

    if (resolvedTypeId == null && salesHistory.isNotEmpty) {
      final saleMatch = salesHistory.firstWhere(
        (s) => s['customer_type_id'] != null,
        orElse: () => salesHistory.first,
      );
      resolvedTypeId = int.tryParse(saleMatch['customer_type_id']?.toString() ?? '');
    }

    if (resolvedCatId == null && salesHistory.isNotEmpty) {
      final saleMatch = salesHistory.firstWhere(
        (s) => s['category_id'] != null,
        orElse: () => salesHistory.first,
      );
      resolvedCatId = int.tryParse(saleMatch['category_id']?.toString() ?? '');
    }

    resolvedTypeId ??= int.tryParse(reminder['customer_type_id']?.toString() ?? '');
    resolvedCatId ??= int.tryParse(reminder['category_id']?.toString() ?? '');

    final bool hasPremiumBranch = customerBranches.any(
      (b) => int.tryParse(b['customer_type_id']?.toString() ?? '') == 1,
    );
    final bool hasPremiumSale = salesHistory.any(
      (s) => int.tryParse(s['customer_type_id']?.toString() ?? '') == 1,
    );
    final bool isPremiumCustomer = resolvedTypeId == 1 || hasPremiumBranch || hasPremiumSale;

    final String customerTypeName =
        isPremiumCustomer ? 'PREMIUM' : DmeConstants.getCustomerTypeName(resolvedTypeId);
    final String categoryName = DmeConstants.getCategoryName(resolvedCatId);

    return ResolvedTypeAndCategory(
      isPremiumCustomer: isPremiumCustomer,
      customerTypeName: customerTypeName,
      categoryName: categoryName,
    );
  }

  static DateTime? extractLatestCallTime({
    dynamic qualifyingEntry,
    dynamic latestEntry,
    required List<Map<String, dynamic>> recordedLogs,
    DateTime? fallbackTimestamp,
  }) {
    DateTime? latestCallTime;
    final entry = qualifyingEntry ?? latestEntry;
    if (entry != null) {
      final int ts = (entry.timestamp is int)
          ? (entry.timestamp > 1000000000000 ? entry.timestamp : entry.timestamp * 1000)
          : 0;
      if (ts > 0) latestCallTime = DateTime.fromMillisecondsSinceEpoch(ts);
    }
    for (final log in recordedLogs) {
      final tsStr = log['attempt_timestamp']?.toString();
      if (tsStr == null) continue;
      final dt = parseAttemptTimestamp(tsStr);
      if (dt != null && (latestCallTime == null || dt.isAfter(latestCallTime))) {
        latestCallTime = dt;
      }
    }
    if (fallbackTimestamp != null) {
      final fTs = fallbackTimestamp.toLocal();
      if (latestCallTime == null || fTs.isAfter(latestCallTime)) latestCallTime = fTs;
    }
    return latestCallTime;
  }

  static (int total, int today) calculateAttempts({
    required int currentCallAttempts,
    required int currentTodayAttempts,
    required String? lastCallDay,
    required String todayStr,
    required int totalTodayAttempts,
  }) {
    final int previousDaysAttempts = (lastCallDay == todayStr)
        ? (currentCallAttempts - currentTodayAttempts).clamp(0, 9999)
        : currentCallAttempts;
    final newToday = totalTodayAttempts;
    final newTotal = previousDaysAttempts + newToday;
    return (newTotal, newToday);
  }

  static Future<bool> openCustomerDialer(String? phone) async {
    if (phone == null || phone.isEmpty) return false;
    final Uri launchUri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(launchUri)) {
      return await launchUrl(launchUri);
    }
    return false;
  }

  static Future<void> launchWhatsAppChat(String? phone) async {
    if (phone == null || phone.isEmpty) return;
    String cleanDigits = phone.replaceAll(RegExp(r'\D'), '');
    if (cleanDigits.length == 10) cleanDigits = '91$cleanDigits';

    final whatsappUrl = Uri.parse('https://wa.me/$cleanDigits');
    try {
      await launchUrl(whatsappUrl, mode: LaunchMode.externalApplication);
    } catch (_) {
      final fallbackUrl = Uri.parse('https://api.whatsapp.com/send?phone=$cleanDigits');
      await launchUrl(fallbackUrl, mode: LaunchMode.externalApplication);
    }
  }

  static void showCallFeedbackSnackBar(
    BuildContext context, {
    required bool isAttended,
    required bool isShortAttended,
    required int duration,
    required int todayCallAttempts,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(isAttended
            ? 'Call attended ($duration sec)! Remarks & Contact Person unlocked.'
            : (isShortAttended
                ? 'Call was under 10s (${duration}s). WhatsApp messaging is now enabled!'
                : 'Customer did not pick up (0s). Attempt $todayCallAttempts/2 recorded.')),
        backgroundColor: isAttended
            ? Colors.green
            : (isShortAttended ? const Color(0xFF25D366) : Colors.orange[900]!),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  static Widget buildCompletedBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF4CAF50).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF4CAF50).withValues(alpha: 0.4)),
      ),
      child: const Row(
        children: [
          Icon(Icons.check_circle_rounded, color: Color(0xFF4CAF50), size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'This reminder is completed. Actions are locked. You can still raise a Complaint or Request using the top bar buttons.',
              style: TextStyle(fontSize: 12, color: Color(0xFF1B5E20), fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}




class ResolvedTypeAndCategory {
  final bool isPremiumCustomer;
  final String customerTypeName;
  final String categoryName;

  const ResolvedTypeAndCategory({
    required this.isPremiumCustomer,
    required this.customerTypeName,
    required this.categoryName,
  });
}
