class DmeCustomer {
  final int? id;
  final String name;
  final String? purchasedFor; // comma-separated alternate names for same phone
  final String phone;
  final String? address;
  final int? branchId;
  final String? branchName;
  final int? purchasedForBranchId;  // Branch ID if customer was purchased from a different branch
  final String? category;
  final String? customerType;
  final int? categoryId;      // ← NEW: FK to dme_categories
  final int? customerTypeId;  // ← NEW: FK to dme_customer_types
  final String? salesman;
  final DateTime? lastPurchaseDate;

  DmeCustomer({
    this.id,
    required this.name,
    this.purchasedFor,
    required this.phone,
    this.address,
    this.branchId,
    this.branchName,
    this.purchasedForBranchId,
    this.category,
    this.customerType,
    this.categoryId,
    this.customerTypeId,
    this.salesman,
    this.lastPurchaseDate,
  });

  factory DmeCustomer.fromMap(Map<String, dynamic> map) {
    return DmeCustomer(
      id: map['id'] as int?,
      name: map['name'] as String? ?? '',
      purchasedFor: map['purchased_for'] as String?,
      phone: map['phone'] as String? ?? '',
      address: map['address'] as String?,
      branchId: map['branch_id'] as int?,
      branchName: (map['dme_branches'] is Map)
          ? map['dme_branches']['name'] as String?
          : null,
      category: map['category'] as String?,
      customerType: map['customer_type'] as String?,
      categoryId: map['category_id'] as int?,      // ← NEW
      customerTypeId: map['customer_type_id'] as int?,  // ← NEW
      salesman: map['salesman'] as String?,
      lastPurchaseDate: map['last_purchase_date'] != null
          ? DateTime.tryParse(map['last_purchase_date'].toString())
          : null,
    );
  }

  Map<String, dynamic> toInsertMap() => {
        'name': name,
        'purchased_for': purchasedFor,
        'phone': normalizePhone(phone),
        'address': address,
        'branch_id': branchId,
        'category_id': categoryId,        // FK only (TEXT column removed from DB)
        'customer_type_id': customerTypeId,  // FK only (TEXT column removed from DB)
        'salesman': salesman,
        'last_purchase_date': lastPurchaseDate?.toIso8601String().split('T')[0],
      };

  /// Normalize phone to last 10 digits for consistent matching
  static String normalizePhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    return digits.length > 10 ? digits.substring(digits.length - 10) : digits;
  }
}
