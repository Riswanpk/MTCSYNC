// DME Complaints Models
// Represents complaint entities and history log in Supabase

class DmeComplaint {
  final int id;
  final int? reminderId;
  final int? customerId;
  final String customerName;
  final String customerPhone;
  final String? customerAddress;
  final String branch;
  final String description;
  final String createdByUid;
  final String? createdByName;
  final String? createdByEmail;
  final String assignedToUid;
  final String? assignedToName;
  final String? assignedToEmail;
  final String? assignedToRole;
  final String? initialAudioUrl;
  final String status; // 'assigned', 'action_taken', 'not_resolved', 'resolved'
  final String? actionRemarks;
  final String? actionAudioUrl;
  final DateTime? actionTakenAt;
  final String? actionTakenByUid;
  final String? actionTakenByName;
  final String? dmeResolutionRemarks;
  final DateTime? resolvedAt;
  final bool isEscalated;
  final String? formerAssignedToUid;
  final String? formerAssignedToName;
  final String? formerAssignedToEmail;
  final String? escalatedByUid;
  final DateTime? escalatedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  DmeComplaint({
    required this.id,
    this.reminderId,
    this.customerId,
    required this.customerName,
    required this.customerPhone,
    this.customerAddress,
    required this.branch,
    required this.description,
    required this.createdByUid,
    this.createdByName,
    this.createdByEmail,
    required this.assignedToUid,
    this.assignedToName,
    this.assignedToEmail,
    this.assignedToRole,
    this.initialAudioUrl,
    required this.status,
    this.actionRemarks,
    this.actionAudioUrl,
    this.actionTakenAt,
    this.actionTakenByUid,
    this.actionTakenByName,
    this.dmeResolutionRemarks,
    this.resolvedAt,
    this.isEscalated = false,
    this.formerAssignedToUid,
    this.formerAssignedToName,
    this.formerAssignedToEmail,
    this.escalatedByUid,
    this.escalatedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DmeComplaint.fromMap(Map<String, dynamic> map) {
    return DmeComplaint(
      id: map['id'] is int ? map['id'] : int.tryParse(map['id']?.toString() ?? '0') ?? 0,
      reminderId: map['reminder_id'] != null ? int.tryParse(map['reminder_id'].toString()) : null,
      customerId: map['customer_id'] != null ? int.tryParse(map['customer_id'].toString()) : null,
      customerName: map['customer_name']?.toString() ?? 'Unknown Customer',
      customerPhone: map['customer_phone']?.toString() ?? '',
      customerAddress: map['customer_address']?.toString(),
      branch: map['branch']?.toString() ?? '',
      description: map['description']?.toString() ?? '',
      createdByUid: map['created_by_uid']?.toString() ?? '',
      createdByName: map['created_by_name']?.toString(),
      createdByEmail: map['created_by_email']?.toString(),
      assignedToUid: map['assigned_to_uid']?.toString() ?? '',
      assignedToName: map['assigned_to_name']?.toString(),
      assignedToEmail: map['assigned_to_email']?.toString(),
      assignedToRole: map['assigned_to_role']?.toString(),
      initialAudioUrl: map['initial_audio_url']?.toString(),
      status: map['status']?.toString() ?? 'assigned',
      actionRemarks: map['action_remarks']?.toString(),
      actionAudioUrl: map['action_audio_url']?.toString(),
      actionTakenAt: map['action_taken_at'] != null ? DateTime.tryParse(map['action_taken_at'].toString()) : null,
      actionTakenByUid: map['action_taken_by_uid']?.toString(),
      actionTakenByName: map['action_taken_by_name']?.toString(),
      dmeResolutionRemarks: map['dme_resolution_remarks']?.toString(),
      resolvedAt: map['resolved_at'] != null ? DateTime.tryParse(map['resolved_at'].toString()) : null,
      isEscalated: map['is_escalated'] == true,
      formerAssignedToUid: map['former_assigned_to_uid']?.toString(),
      formerAssignedToName: map['former_assigned_to_name']?.toString(),
      formerAssignedToEmail: map['former_assigned_to_email']?.toString(),
      escalatedByUid: map['escalated_by_uid']?.toString(),
      escalatedAt: map['escalated_at'] != null ? DateTime.tryParse(map['escalated_at'].toString()) : null,
      createdAt: map['created_at'] != null ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now() : DateTime.now(),
      updatedAt: map['updated_at'] != null ? DateTime.tryParse(map['updated_at'].toString()) ?? DateTime.now() : DateTime.now(),
    );
  }

  Map<String, dynamic> toInsertMap() {
    final map = <String, dynamic>{
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'branch': branch,
      'description': description,
      'created_by_uid': createdByUid,
      'assigned_to_uid': assignedToUid,
      'status': status,
      'is_escalated': isEscalated,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
    if (reminderId != null) map['reminder_id'] = reminderId;
    if (customerId != null) map['customer_id'] = customerId;
    if (customerAddress != null && customerAddress!.isNotEmpty) map['customer_address'] = customerAddress;
    if (createdByName != null) map['created_by_name'] = createdByName;
    if (createdByEmail != null) map['created_by_email'] = createdByEmail;
    if (assignedToName != null) map['assigned_to_name'] = assignedToName;
    if (assignedToEmail != null) map['assigned_to_email'] = assignedToEmail;
    if (assignedToRole != null) map['assigned_to_role'] = assignedToRole;
    if (initialAudioUrl != null && initialAudioUrl!.isNotEmpty) map['initial_audio_url'] = initialAudioUrl;
    return map;
  }
}

class DmeComplaintUpdate {
  final int? id;
  final int complaintId;
  final String actionType; // 'created', 'action_taken', 'not_resolved', 'resolved', 'escalated'
  final String actionByUid;
  final String? actionByName;
  final String? actionByRole;
  final String? remarks;
  final String? audioUrl;
  final DateTime createdAt;

  DmeComplaintUpdate({
    this.id,
    required this.complaintId,
    required this.actionType,
    required this.actionByUid,
    this.actionByName,
    this.actionByRole,
    this.remarks,
    this.audioUrl,
    required this.createdAt,
  });

  factory DmeComplaintUpdate.fromMap(Map<String, dynamic> map) {
    return DmeComplaintUpdate(
      id: map['id'] is int ? map['id'] : int.tryParse(map['id']?.toString() ?? ''),
      complaintId: map['complaint_id'] is int ? map['complaint_id'] : int.tryParse(map['complaint_id']?.toString() ?? '0') ?? 0,
      actionType: map['action_type']?.toString() ?? 'unknown',
      actionByUid: map['action_by_uid']?.toString() ?? '',
      actionByName: map['action_by_name']?.toString(),
      actionByRole: map['action_by_role']?.toString(),
      remarks: map['remarks']?.toString(),
      audioUrl: map['audio_url']?.toString(),
      createdAt: map['created_at'] != null ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now() : DateTime.now(),
    );
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'complaint_id': complaintId,
      'action_type': actionType,
      'action_by_uid': actionByUid,
      'action_by_name': actionByName,
      'action_by_role': actionByRole,
      'remarks': remarks,
      'audio_url': audioUrl,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
