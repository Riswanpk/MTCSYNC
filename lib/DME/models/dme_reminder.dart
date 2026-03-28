class DmeReminder {
  final int? id;
  final int customerId;
  final String? customerName;
  final String? customerPhone;
  final String? customerAddress;
  final DateTime reminderDate;
  final DateTime lastPurchaseDate;
  final String status;
  final String? assignedTo;
  final String? notes;

  DmeReminder({
    this.id,
    required this.customerId,
    this.customerName,
    this.customerPhone,
    this.customerAddress,
    required this.reminderDate,
    required this.lastPurchaseDate,
    this.status = 'pending',
    this.assignedTo,
    this.notes,
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
      reminderDate: DateTime.parse(map['reminder_date'].toString()),
      lastPurchaseDate: DateTime.parse(map['last_purchase_date'].toString()),
      status: map['status'] as String? ?? 'pending',
      assignedTo: map['assigned_to'] as String?,
      notes: map['notes'] as String?,
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
    DateTime? reminderDate,
    DateTime? lastPurchaseDate,
    String? status,
    String? assignedTo,
    String? notes,
  }) {
    return DmeReminder(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      customerAddress: customerAddress ?? this.customerAddress,
      reminderDate: reminderDate ?? this.reminderDate,
      lastPurchaseDate: lastPurchaseDate ?? this.lastPurchaseDate,
      status: status ?? this.status,
      assignedTo: assignedTo ?? this.assignedTo,
      notes: notes ?? this.notes,
    );
  }

  /// Check if this reminder should be rescheduled based on new purchase date
  bool shouldReschedule(DateTime newPurchaseDate) {
    // Reschedule if new purchase is after current reminder date
    return newPurchaseDate.isAfter(reminderDate);
  }
}
