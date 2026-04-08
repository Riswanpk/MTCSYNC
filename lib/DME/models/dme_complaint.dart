class DmeComplaint {
  final int? id;
  final int customerId;
  final String customerName;
  final String customerPhone;
  final int branchId;
  final String branchName;
  final String complaintText;
  final String status; // OPEN or CLOSED
  final String? createdByUserName;
  final DateTime createdAt;
  final String? closedByUserName;
  final DateTime? closedAt;

  DmeComplaint({
    this.id,
    required this.customerId,
    required this.customerName,
    required this.customerPhone,
    required this.branchId,
    required this.branchName,
    required this.complaintText,
    required this.status,
    this.createdByUserName,
    required this.createdAt,
    this.closedByUserName,
    this.closedAt,
  });

  factory DmeComplaint.fromMap(Map<String, dynamic> map) {
    return DmeComplaint(
      id: map['id'] as int?,
      customerId: map['customer_id'] as int? ?? 0,
      customerName: map['customer_name'] as String? ?? '',
      customerPhone: map['customer_phone'] as String? ?? '',
      branchId: map['branch_id'] as int? ?? 0,
      branchName: map['branch_name'] as String? ?? '',
      complaintText: map['complaint_text'] as String? ?? '',
      status: map['status'] as String? ?? 'OPEN',
      createdByUserName: map['created_by_user_name'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      closedByUserName: map['closed_by_user_name'] as String?,
      closedAt: map['closed_at'] != null
          ? DateTime.tryParse(map['closed_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toMap() => {
        'customer_id': customerId,
        'branch_id': branchId,
        'complaint_text': complaintText,
        'status': status,
        'created_at': createdAt.toIso8601String(),
        'closed_at': closedAt?.toIso8601String(),
      };

  /// Check if complaint is open
  bool get isOpen => status == 'OPEN';

  /// Create a copy with updated fields
  DmeComplaint copyWith({
    int? id,
    int? customerId,
    String? customerName,
    String? customerPhone,
    int? branchId,
    String? branchName,
    String? complaintText,
    String? status,
    String? createdByUserName,
    DateTime? createdAt,
    String? closedByUserName,
    DateTime? closedAt,
  }) {
    return DmeComplaint(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      branchId: branchId ?? this.branchId,
      branchName: branchName ?? this.branchName,
      complaintText: complaintText ?? this.complaintText,
      status: status ?? this.status,
      createdByUserName: createdByUserName ?? this.createdByUserName,
      createdAt: createdAt ?? this.createdAt,
      closedByUserName: closedByUserName ?? this.closedByUserName,
      closedAt: closedAt ?? this.closedAt,
    );
  }
}
