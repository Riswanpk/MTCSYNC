class DmeComplaint {
  final String? id;
  final String customerName;
  final String customerPhone;
  final int branchId;
  final String branchName; // Display name, fetched from branches table
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
  final String assignedToId; // MANDATORY - Every complaint must be assigned
  final String? assignedToUsername;
  final String? remarks;
  final String? remarkedByUsername;
  final DateTime? remarkedAt;
  final bool hasNewRemarks;
  final String? voiceFileUrl; // Optional voice file URL

  DmeComplaint({
    this.id,
    required this.customerName,
    required this.customerPhone,
    required this.branchId,
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
    required this.assignedToId, // MANDATORY
    this.assignedToUsername,
    this.remarks,
    this.remarkedByUsername,
    this.remarkedAt,
    this.hasNewRemarks = false,
    this.voiceFileUrl,
  });

  factory DmeComplaint.fromMap(Map<String, dynamic> map) {
    return DmeComplaint(
      id: map['id'] as String?,
      customerName: map['customer_name'] as String? ?? '',
      customerPhone: map['customer_phone'] as String? ?? '',
      branchId: map['branch_id'] as int? ?? 0,
      branchName: _extractBranchName(map['dme_branches']) ?? 'Unknown Branch',
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
      assignedToId: map['assigned_to'] as String? ?? '', // MANDATORY - provide default if missing
      assignedToUsername: _extractUsername(map['assigned_to_user']),
      remarks: map['remarks'] as String?,
      remarkedByUsername: _extractUsername(map['remarked_by_user']),
      remarkedAt: map['remarked_at'] != null
          ? DateTime.tryParse(map['remarked_at'].toString())
          : null,
      hasNewRemarks: map['has_new_remarks'] as bool? ?? false,
      voiceFileUrl: map['voice_file_url'] as String?,
    );
  }

  static String? _extractUsername(dynamic userMap) {
    if (userMap is Map) {
      return userMap['username'] as String?;
    }
    return null;
  }

  static String? _extractBranchName(dynamic branchMap) {
    if (branchMap is Map) {
      return branchMap['name'] as String?;
    }
    return null;
  }

  Map<String, dynamic> toMap() => {
        'customer_name': customerName,
        'customer_phone': customerPhone,
        'branch_id': branchId,
        'complaint_text': complaintText,
        'created_by': createdById,
        'assigned_to': assignedToId, // MANDATORY
        'remarks': remarks,
        'remarked_by': remarkedByUsername,
        'remarked_at': remarkedAt,
        'has_new_remarks': hasNewRemarks,
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
    int? branchId,
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
    String? assignedToId, // MANDATORY - but allow override in copyWith
    String? assignedToUsername,
    String? remarks,
    String? remarkedByUsername,
    DateTime? remarkedAt,
    bool? hasNewRemarks,
    String? voiceFileUrl,
  }) {
    return DmeComplaint(
      id: id ?? this.id,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      branchId: branchId ?? this.branchId,
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
      assignedToId: assignedToId ?? this.assignedToId,
      assignedToUsername: assignedToUsername ?? this.assignedToUsername,
      remarks: remarks ?? this.remarks,
      remarkedByUsername: remarkedByUsername ?? this.remarkedByUsername,
      remarkedAt: remarkedAt ?? this.remarkedAt,
      hasNewRemarks: hasNewRemarks ?? this.hasNewRemarks,
      voiceFileUrl: voiceFileUrl ?? this.voiceFileUrl,
    );
  }
}
