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
  final String? uploadedBy;
  final String? proofImageUrl;

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
    this.uploadedBy,
    this.proofImageUrl,
  });

  /// Convert completedAt to Indian Standard Time (UTC+05:30)
  DateTime get completedAtIst {
    final utc = completedAt.isUtc ? completedAt : completedAt.toUtc();
    return utc.add(const Duration(hours: 5, minutes: 30));
  }

  int get dayKey => completedAtIst.day;

  String get formattedDate => DateFormat('dd-MM-yyyy').format(completedAtIst);
  String get formattedTime => '${DateFormat('hh:mm a').format(completedAtIst)} IST';
}

/// Statistics and action list for a specific DME User in the reporting period
class DmeUserCallStat {
  final String uid;
  final String email;
  final String username;
  final String role;
  final List<int> assignedBranches;
  final List<DmeCustomerCallItem> callItems;

  DmeUserCallStat({
    required this.uid,
    required this.email,
    required this.username,
    required this.role,
    required this.assignedBranches,
    required this.callItems,
  });

  int get totalCalls => callItems.where((i) => !i.isWhatsApp).length;
  int get totalWhatsApp => callItems.where((i) => i.isWhatsApp).length;
  int get totalActions => callItems.length;

  /// Returns sorted unique days (e.g. [1, 2, 4, 15, 28]) where actions occurred
  List<int> get activeDays {
    final days = callItems.map((i) => i.dayKey).toSet().toList();
    days.sort();
    return days;
  }

  /// Get list of customer actions performed on a specific day of month
  List<DmeCustomerCallItem> getItemsForDay(int day) {
    final list = callItems.where((i) => i.dayKey == day).toList();
    list.sort((a, b) => b.completedAt.compareTo(a.completedAt)); // latest first
    return list;
  }
}
