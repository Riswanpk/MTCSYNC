class DmeProduct {
  final int? id;
  final String name;
  final String unit;

  DmeProduct({
    this.id,
    required this.name,
    required this.unit,
  });

  factory DmeProduct.fromMap(Map<String, dynamic> map) {
    return DmeProduct(
      id: map['id'] as int?,
      name: map['name'] as String,
      unit: map['unit'] as String,
    );
  }

  Map<String, dynamic> toInsertMap() => {
        'name': name,
        'unit': unit,
      };
}
