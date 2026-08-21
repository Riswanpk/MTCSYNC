class DmeCustomer {
  final int? id;
  final String name;
  final String phone;
  final String? address;
  final String? salesman;
  final DateTime? lastPurchaseDate;

  DmeCustomer({
    this.id,
    required this.name,
    required this.phone,
    this.address,
    this.salesman,
    this.lastPurchaseDate,
  });

  factory DmeCustomer.fromMap(Map<String, dynamic> map) {
    return DmeCustomer(
      id: map['id'] as int?,
      name: map['name'] as String? ?? '',
      phone: map['phone'] as String? ?? '',
      address: map['address'] as String?,
      salesman: map['salesman'] as String?,
      lastPurchaseDate: map['last_purchase_date'] != null
          ? DateTime.tryParse(map['last_purchase_date'].toString())
          : null,
    );
  }

  Map<String, dynamic> toInsertMap() => {
        'name': name,
        'phone': normalizePhone(phone),
        'address': address,
        'salesman': salesman,
        'last_purchase_date': lastPurchaseDate?.toIso8601String().split('T')[0],
      };

  /// Normalize phone to last 10 digits for consistent matching
  static String normalizePhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    return digits.length > 10 ? digits.substring(digits.length - 10) : digits;
  }
}
