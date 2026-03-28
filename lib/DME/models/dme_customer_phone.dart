class DmeCustomerPhone {
  final int? id;
  final int customerId;
  final String phoneNumber; // Normalized phone (last 10 digits)
  final DateTime createdAt;

  DmeCustomerPhone({
    this.id,
    required this.customerId,
    required this.phoneNumber,
    required this.createdAt,
  });

  factory DmeCustomerPhone.fromMap(Map<String, dynamic> map) {
    return DmeCustomerPhone(
      id: map['id'] as int?,
      customerId: map['customer_id'] as int,
      phoneNumber: map['phone_number'] as String? ?? '',
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toInsertMap() => {
        'customer_id': customerId,
        'phone_number': phoneNumber,
        'created_at': createdAt.toIso8601String(),
      };
}
