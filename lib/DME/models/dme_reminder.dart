class DmeReminder {
  final int? id;
  final int customerId;
  final String? customerName;
  final String? customerPhone;
  final String? customerAddress;
  final String? salesman;
  final DateTime reminderDate;
  final DateTime lastPurchaseDate;
  final String status;
  final String? assignedTo;
  final String? notes;
  final int purchasedForBranchId;
  final String purchasedForBranchName;
  final DateTime? updatedAt;

  DmeReminder({
    this.id,
    required this.customerId,
    this.customerName,
    this.customerPhone,
    this.customerAddress,
    this.salesman,
    required this.reminderDate,
    required this.lastPurchaseDate,
    this.status = 'pending',
    this.assignedTo,
    this.notes,
    this.purchasedForBranchId = 0,
    this.purchasedForBranchName = '',
    this.updatedAt,
  });

  factory DmeReminder.fromMap(Map<String, dynamic> map) {
    return DmeReminder(
      id: map['id'] as int?,
      customerId: map['customer_id'] as int,
      customerName: (map['dme_customers'] is Map)
          ? map['dme_customers']['name'] as String?
          : null,
      customerPhone: (map['dme_customers'] is Map)
          ? map['dme_customers']['phone'] as String?
          : null,
      customerAddress: (map['dme_customers'] is Map)
          ? map['dme_customers']['address'] as String?
          : null,
      salesman: (map['dme_customers'] is Map)
          ? map['dme_customers']['salesman'] as String?
          : null,
      reminderDate: DateTime.parse(map['reminder_date'].toString()),
      lastPurchaseDate: DateTime.parse(map['last_purchase_date'].toString()),
      status: map['status'] as String? ?? 'pending',
      assignedTo: map['assigned_to'] as String?,
      notes: map['notes'] as String?,
      purchasedForBranchId: map['purchased_for_branch_id'] as int? ?? 0,
      purchasedForBranchName: map['purchased_for_branch_name'] as String? ?? '',
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toInsertMap() => {
        'customer_id': customerId,
        'reminder_date': reminderDate.toIso8601String().split('T')[0],
        'last_purchase_date': lastPurchaseDate.toIso8601String().split('T')[0],
        'status': status,
        'assigned_to': assignedTo,
        'notes': notes,
      };

  /// Copy with updated fields
  DmeReminder copyWith({
    int? id,
    int? customerId,
    String? customerName,
    String? customerPhone,
    String? customerAddress,
    String? salesman,
    DateTime? reminderDate,
    DateTime? lastPurchaseDate,
    String? status,
    String? assignedTo,
    String? notes,
    int? purchasedForBranchId,
    String? purchasedForBranchName,
    DateTime? updatedAt,
  }) {
    return DmeReminder(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      customerAddress: customerAddress ?? this.customerAddress,
      salesman: salesman ?? this.salesman,
      reminderDate: reminderDate ?? this.reminderDate,
      lastPurchaseDate: lastPurchaseDate ?? this.lastPurchaseDate,
      status: status ?? this.status,
      assignedTo: assignedTo ?? this.assignedTo,
      notes: notes ?? this.notes,
      purchasedForBranchId: purchasedForBranchId ?? this.purchasedForBranchId,
      purchasedForBranchName: purchasedForBranchName ?? this.purchasedForBranchName,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Check if this reminder should be rescheduled based on new purchase date
  bool shouldReschedule(DateTime newPurchaseDate) {
    return newPurchaseDate.isAfter(reminderDate);
  }
}
