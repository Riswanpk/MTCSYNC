class DmeProduct {
  final int? id;
  final String code;
  final String name;
  final String unit;

  DmeProduct({
    this.id,
    required this.code,
    required this.name,
    required this.unit,
  });

  factory DmeProduct.fromMap(Map<String, dynamic> map) {
    return DmeProduct(
      id: map['id'] as int?,
      code: map['code'] as String,
      name: map['name'] as String,
      unit: map['unit'] as String,
    );
  }

  Map<String, dynamic> toInsertMap() => {
        'code': code,
        'name': name,
        'unit': unit,
      };
}
