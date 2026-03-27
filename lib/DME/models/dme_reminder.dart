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
}
