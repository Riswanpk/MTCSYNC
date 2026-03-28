class DmeComplaint {
  final String? id;
  final String customerName;
  final String customerPhone;
  final String branch;
  final String complaintText;
  final String category; // Quality, Delivery, Payment, Other
  final String status; // raised, case_resolved, verified_closed
  final String createdBy; // DME user ID
  final DateTime createdAt;
  final String? resolvedBy; // Branch user ID
  final DateTime? resolvedAt;
  final String? closedBy; // DME user ID
  final DateTime? closedAt;

  DmeComplaint({
    this.id,
    required this.customerName,
    required this.customerPhone,
    required this.branch,
    required this.complaintText,
    required this.category,
    required this.status,
    required this.createdBy,
    required this.createdAt,
    this.resolvedBy,
    this.resolvedAt,
    this.closedBy,
    this.closedAt,
  });

  factory DmeComplaint.fromMap(Map<String, dynamic> map) {
    return DmeComplaint(
      id: map['id'] as String?,
      customerName: map['customer_name'] as String? ?? '',
      customerPhone: map['customer_phone'] as String? ?? '',
      branch: map['branch'] as String? ?? '',
      complaintText: map['complaint_text'] as String? ?? '',
      category: map['category'] as String? ?? 'Other',
      status: map['status'] as String? ?? 'raised',
      createdBy: map['created_by'] as String? ?? '',
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      resolvedBy: map['resolved_by'] as String?,
      resolvedAt: map['resolved_at'] != null
          ? DateTime.tryParse(map['resolved_at'].toString())
          : null,
      closedBy: map['closed_by'] as String?,
      closedAt: map['closed_at'] != null
          ? DateTime.tryParse(map['closed_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toMap() => {
        'customer_name': customerName,
        'customer_phone': customerPhone,
        'branch': branch,
        'complaint_text': complaintText,
        'category': category,
        'status': status,
        'created_by': createdBy,
        'created_at': createdAt.toIso8601String(),
        'resolved_by': resolvedBy,
        'resolved_at': resolvedAt?.toIso8601String(),
        'closed_by': closedBy,
        'closed_at': closedAt?.toIso8601String(),
      };

  /// Check if a user can transition to a new status based on their role
  bool canTransitionTo(String newStatus, String userRole) {
    // Workflow: raised -> case_resolved -> verified_closed
    if (status == 'raised' && newStatus == 'case_resolved') {
      // Branch users can mark case resolved
      return userRole == 'branch_manager' ||
          userRole == 'branch_user' ||
          userRole == 'dme_admin';
    }
    if (status == 'case_resolved' && newStatus == 'verified_closed') {
      // DME users can verify and close
      return userRole == 'dme_user' || userRole == 'dme_admin';
    }
    return false;
  }

  /// Create a copy with updated fields
  DmeComplaint copyWith({
    String? id,
    String? customerName,
    String? customerPhone,
    String? branch,
    String? complaintText,
    String? category,
    String? status,
    String? createdBy,
    DateTime? createdAt,
    String? resolvedBy,
    DateTime? resolvedAt,
    String? closedBy,
    DateTime? closedAt,
  }) {
    return DmeComplaint(
      id: id ?? this.id,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      branch: branch ?? this.branch,
      complaintText: complaintText ?? this.complaintText,
      category: category ?? this.category,
      status: status ?? this.status,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      resolvedBy: resolvedBy ?? this.resolvedBy,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      closedBy: closedBy ?? this.closedBy,
      closedAt: closedAt ?? this.closedAt,
    );
  }
}
