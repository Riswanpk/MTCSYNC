class DmeSaleItem {
  final int? id;
  final int? saleId;
  final String productName;
  final double quantity;
  final String? unit;

  DmeSaleItem({
    this.id,
    this.saleId,
    required this.productName,
    required this.quantity,
    this.unit,
  });

  factory DmeSaleItem.fromMap(Map<String, dynamic> map) {
    return DmeSaleItem(
      id: map['id'] as int?,
      saleId: map['sale_id'] as int?,
      productName: map['product_name'] as String? ?? '',
      quantity: (map['quantity'] as num?)?.toDouble() ?? 0,
      unit: map['unit'] as String?,
    );
  }

  Map<String, dynamic> toInsertMap(int saleId) => {
        'sale_id': saleId,
        'product_name': productName,
        'quantity': quantity,
        'unit': unit,
      };
}

class DmeSale {
  final int? id;
  final DateTime date;
  final int? customerId;
  final String? customerName;
  final String? customerPhone;
  final String? salesman;
  final String? category;
  final String? customerType;
  final double? totalQuantity;
  final String? uploadedBy;
  final List<DmeSaleItem> items;

  DmeSale({
    this.id,
    required this.date,
    this.customerId,
    this.customerName,
    this.customerPhone,
    this.salesman,
    this.category,
    this.customerType,
    this.totalQuantity,
    this.uploadedBy,
    this.items = const [],
  });

  factory DmeSale.fromMap(Map<String, dynamic> map) {
    final itemsList = (map['dme_sale_items'] as List?)
            ?.map((e) => DmeSaleItem.fromMap(e as Map<String, dynamic>))
            .toList() ??
        [];
    return DmeSale(
      id: map['id'] as int?,
      date: DateTime.parse(map['date'].toString()),
      customerId: map['customer_id'] as int?,
      customerName: (map['dme_customers'] is Map)
          ? map['dme_customers']['name'] as String?
          : null,
      customerPhone: (map['dme_customers'] is Map)
          ? map['dme_customers']['phone'] as String?
          : null,
      salesman: map['salesman'] as String?,
      category: map['category'] as String?,
      customerType: map['customer_type'] as String?,
      totalQuantity: (map['total_quantity'] as num?)?.toDouble(),
      uploadedBy: map['uploaded_by'] as String?,
      items: itemsList,
    );
  }

  Map<String, dynamic> toInsertMap() => {
        'date': date.toIso8601String().split('T')[0],
        'customer_id': customerId,
        'salesman': salesman,
        'category': category,
        'customer_type': customerType,
        'total_quantity': totalQuantity,
        'uploaded_by': uploadedBy,
      };
}

/// Parsed from Excel before DB insertion — contains raw text fields
class DmeSaleRecord {
  final DateTime date;
  final String customerName;
  final String? address;
  final String? phone;
  final String? category;
  final String? customerType;
  final String? salesman;
  final double? headerQuantity;
  final List<DmeSaleItem> items;

  DmeSaleRecord({
    required this.date,
    required this.customerName,
    this.address,
    this.phone,
    this.category,
    this.customerType,
    this.salesman,
    this.headerQuantity,
    this.items = const [],
  });
}
