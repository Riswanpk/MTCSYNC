class DmeComplaint {
  final String? id;
  final String customerName;
  final String customerPhone;
  final String branchName;
  final String complaintText;
  final String status; // 'raised', 'case_resolved', 'verified_closed'
  final String createdById;
  final String? createdByUsername;
  final DateTime createdAt;
  final String? resolvedById;
  final String? resolvedByUsername;
  final DateTime? resolvedAt;
  final String? closedById;
  final String? closedByUsername;
  final DateTime? closedAt;
  final DateTime updatedAt;

  DmeComplaint({
    this.id,
    required this.customerName,
    required this.customerPhone,
    required this.branchName,
    required this.complaintText,
    required this.status,
    required this.createdById,
    this.createdByUsername,
    required this.createdAt,
    this.resolvedById,
    this.resolvedByUsername,
    this.resolvedAt,
    this.closedById,
    this.closedByUsername,
    this.closedAt,
    required this.updatedAt,
  });

  factory DmeComplaint.fromMap(Map<String, dynamic> map) {
    return DmeComplaint(
      id: map['id'] as String?,
      customerName: map['customer_name'] as String? ?? '',
      customerPhone: map['customer_phone'] as String? ?? '',
      branchName: map['branch_name'] as String? ?? '',
      complaintText: map['complaint_text'] as String? ?? '',
      status: map['status'] as String? ?? 'raised',
      createdById: map['created_by'] as String? ?? '',
      createdByUsername: _extractUsername(map['created_by_user']),
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      resolvedById: map['resolved_by'] as String?,
      resolvedByUsername: _extractUsername(map['resolved_by_user']),
      resolvedAt: map['resolved_at'] != null
          ? DateTime.tryParse(map['resolved_at'].toString())
          : null,
      closedById: map['closed_by'] as String?,
      closedByUsername: _extractUsername(map['closed_by_user']),
      closedAt: map['closed_at'] != null
          ? DateTime.tryParse(map['closed_at'].toString())
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  static String? _extractUsername(dynamic userMap) {
    if (userMap is Map) {
      return userMap['username'] as String?;
    }
    return null;
  }

  Map<String, dynamic> toMap() => {
        'customer_name': customerName,
        'customer_phone': customerPhone,
        'branch_name': branchName,
        'complaint_text': complaintText,
        'created_by': createdById,
      };

  /// Check status helpers
  bool get isRaised => status == 'raised';
  bool get isCaseResolved => status == 'case_resolved';
  bool get isClosed => status == 'verified_closed';

  /// Create a copy with updated fields
  DmeComplaint copyWith({
    String? id,
    String? customerName,
    String? customerPhone,
    String? branchName,
    String? complaintText,
    String? status,
    String? createdById,
    String? createdByUsername,
    DateTime? createdAt,
    String? resolvedById,
    String? resolvedByUsername,
    DateTime? resolvedAt,
    String? closedById,
    String? closedByUsername,
    DateTime? closedAt,
    DateTime? updatedAt,
  }) {
    return DmeComplaint(
      id: id ?? this.id,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      branchName: branchName ?? this.branchName,
      complaintText: complaintText ?? this.complaintText,
      status: status ?? this.status,
      createdById: createdById ?? this.createdById,
      createdByUsername: createdByUsername ?? this.createdByUsername,
      createdAt: createdAt ?? this.createdAt,
      resolvedById: resolvedById ?? this.resolvedById,
      resolvedByUsername: resolvedByUsername ?? this.resolvedByUsername,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      closedById: closedById ?? this.closedById,
      closedByUsername: closedByUsername ?? this.closedByUsername,
      closedAt: closedAt ?? this.closedAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
