import 'package:intl/intl.dart';

/// Single completed call or WhatsApp message record in DME
class DmeCustomerCallItem {
  final int reminderId;
  final int customerId;
  final String customerName;
  final String customerPhone;
  final String customerAddress;
  final String customerSalesman;
  final int branchId;
  final String branchName;
  final String status;
  final String remarks;
  final bool isWhatsApp;
  final DateTime completedAt;
  final DateTime? reminderDate;
  final String? uploadedBy;
  final String? calledBy;
  final String? assignedTo;
  final String? proofImageUrl;
  final int? callDuration;
  final DateTime? calledTimestamp;

  DmeCustomerCallItem({
    required this.reminderId,
    required this.customerId,
    required this.customerName,
    required this.customerPhone,
    required this.customerAddress,
    required this.customerSalesman,
    required this.branchId,
    required this.branchName,
    required this.status,
    required this.remarks,
    required this.isWhatsApp,
    required this.completedAt,
    this.reminderDate,
    this.uploadedBy,
    this.calledBy,
    this.assignedTo,
    this.proofImageUrl,
    this.callDuration,
    this.calledTimestamp,
  });

  /// The authoritative DateTime when this call or action was performed.
  DateTime get actionDate => calledTimestamp ?? completedAt;

  DateTime get completedAtIst {
    final d = actionDate;
    final utc = d.isUtc ? d : d.toUtc();
    return utc.add(const Duration(hours: 5, minutes: 30));
  }

  int get dayKey => (reminderDate ?? completedAtIst).day;
  String get formattedDate => DateFormat('dd-MM-yyyy').format(reminderDate ?? completedAtIst);
  String get formattedTime => '${DateFormat('hh:mm a').format(completedAtIst)} IST';

  String get formattedCallTime {
    if (calledTimestamp != null) {
      final utc = calledTimestamp!.isUtc ? calledTimestamp! : calledTimestamp!.toUtc();
      final ist = utc.add(const Duration(hours: 5, minutes: 30));
      return '${DateFormat('hh:mm a').format(ist)} IST';
    }
    return formattedTime;
  }

  String? get formattedCallDuration {
    if (callDuration == null) return null;
    final dur = callDuration!;
    if (dur <= 0) return '0s (Not Attended)';
    if (dur < 60) return '${dur}s';
    final mins = dur ~/ 60;
    final secs = dur % 60;
    return secs > 0 ? '${mins}m ${secs}s' : '${mins}m';
  }
}

/// Statistics and action list for a specific DME User in the reporting period
class DmeUserCallStat {
  final String uid;
  final String email;
  final String username;
  final String role;
  final List<int> assignedBranches;
  final List<DmeCustomerCallItem> callItems;

  /// Counts from dme_user_daily_stats table.
  final int? statsCallsCount;
  final int? statsWhatsAppCount;
  final int? statsOverdueCount;

  DmeUserCallStat({
    required this.uid,
    required this.email,
    required this.username,
    required this.role,
    required this.assignedBranches,
    required this.callItems,
    this.statsCallsCount,
    this.statsWhatsAppCount,
    this.statsOverdueCount,
  });

  int get totalCalls    => callItems.where((i) => !i.isWhatsApp).length;
  int get totalWhatsApp => callItems.where((i) => i.isWhatsApp).length;
  int get totalActions  => totalCalls + totalWhatsApp;
  int get overdueCount  => statsOverdueCount ?? 0;

  List<int> get activeDays {
    final days = callItems.map((i) => i.dayKey).toSet().toList();
    days.sort();
    return days;
  }

  List<DmeCustomerCallItem> getItemsForDay(int day) {
    final list = callItems.where((i) => i.dayKey == day).toList();
    list.sort((a, b) => b.actionDate.compareTo(a.actionDate));
    return list;
  }
}
