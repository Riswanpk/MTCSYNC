// Models representing the DME Database Tables

class DmeUser {
  final String id;
  final String? username;
  final String? email;
  final String role;
  final List<int> assignedBranches;
  final DateTime? createdAt;
  final String? firebaseUid;

  DmeUser({
    required this.id,
    this.username,
    this.email,
    this.role = 'sales',
    this.assignedBranches = const [],
    this.createdAt,
    this.firebaseUid,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'role': role,
      'assigned_branches': assignedBranches,
      'created_at': createdAt?.toIso8601String(),
      'firebase_uid': firebaseUid,
    };
  }

  factory DmeUser.fromMap(Map<String, dynamic> map) {
    return DmeUser(
      id: map['id']?.toString() ?? '',
      username: map['username'] as String?,
      email: map['email'] as String?,
      role: map['role'] as String? ?? 'sales',
      assignedBranches: (map['assigned_branches'] as List<dynamic>?)
              ?.map((e) => int.tryParse(e.toString()) ?? 0)
              .toList() ??
          [],
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString())
          : null,
      firebaseUid: map['firebase_uid'] as String?,
    );
  }
}

class DmeCustomer {
  final int? id;
  final String name;
  final String phone;
  final String? address;
  final String? pincode;
  final String? salesman;
  final String preference; // 'Call' or 'Whatsapp' (default: 'Call')
  final DateTime? lastPurchaseDate;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  DmeCustomer({
    this.id,
    required this.name,
    required this.phone,
    this.address,
    this.pincode,
    this.salesman,
    this.preference = 'Call',
    this.lastPurchaseDate,
    this.createdAt,
    this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'phone': phone,
      'address': address,
      'pincode': pincode,
      'salesman': salesman,
      'preference': preference,
      'last_purchase_date': lastPurchaseDate?.toIso8601String(),
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  factory DmeCustomer.fromMap(Map<String, dynamic> map) {
    return DmeCustomer(
      id: map['id'] != null ? int.tryParse(map['id'].toString()) : null,
      name: map['name'] as String? ?? '',
      phone: map['phone'] as String? ?? '',
      address: map['address'] as String?,
      pincode: map['pincode'] as String?,
      salesman: map['salesman'] as String?,
      preference: map['preference'] as String? ?? 'Call',
      lastPurchaseDate: map['last_purchase_date'] != null
          ? DateTime.tryParse(map['last_purchase_date'].toString())
          : null,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString())
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'].toString())
          : null,
    );
  }
}

class DmeSale {
  final int? id;
  final DateTime date;
  final int? customerId;
  final int? purchasedBranch;
  final String? salesman;
  final int? categoryId;
  final int? customerTypeId;
  final String? uploadedBy;
  final DateTime? createdAt;

  DmeSale({
    this.id,
    required this.date,
    this.customerId,
    this.purchasedBranch,
    this.salesman,
    this.categoryId,
    this.customerTypeId,
    this.uploadedBy,
    this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'date': date.toIso8601String(),
      'customer_id': customerId,
      'purchased_branch': purchasedBranch,
      'salesman': salesman,
      'category_id': categoryId,
      'customer_type_id': customerTypeId,
      'uploaded_by': uploadedBy,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  factory DmeSale.fromMap(Map<String, dynamic> map) {
    return DmeSale(
      id: map['id'] != null ? int.tryParse(map['id'].toString()) : null,
      date: map['date'] != null
          ? DateTime.tryParse(map['date'].toString()) ?? DateTime.now()
          : DateTime.now(),
      customerId: map['customer_id'] != null
          ? int.tryParse(map['customer_id'].toString())
          : null,
      purchasedBranch: map['purchased_branch'] != null
          ? int.tryParse(map['purchased_branch'].toString())
          : null,
      salesman: map['salesman'] as String?,
      categoryId: map['category_id'] != null
          ? int.tryParse(map['category_id'].toString())
          : null,
      customerTypeId: map['customer_type_id'] != null
          ? int.tryParse(map['customer_type_id'].toString())
          : null,
      uploadedBy: map['uploaded_by'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString())
          : null,
    );
  }
}

class DmeSaleDetail {
  final int? id;
  final int saleId;
  final List<dynamic> products;
  final DateTime? createdAt;

  DmeSaleDetail({
    this.id,
    required this.saleId,
    this.products = const [],
    this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'sale_id': saleId,
      'products': products,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  factory DmeSaleDetail.fromMap(Map<String, dynamic> map) {
    return DmeSaleDetail(
      id: map['id'] != null ? int.tryParse(map['id'].toString()) : null,
      saleId: int.tryParse(map['sale_id'].toString()) ?? 0,
      products: (map['products'] as List<dynamic>?) ?? [],
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString())
          : null,
    );
  }
}

class DmeReminder {
  final int? id;
  final int customerId;
  final DateTime reminderDate;
  final DateTime? lastPurchaseDate;
  final int? lastPurchaseBranch;
  final String status;
  final String? remarks;
  final DateTime? updatedAt;
  final int? callDuration;
  final DateTime? calledTimestamp;
  final String? assignedTo;
  final String? assignedDate;
  final bool isOverdueLeftover;
  final int callAttempts;
  final int todayCallAttempts;
  final DateTime? lastCallAttemptTimestamp;

  DmeReminder({
    this.id,
    required this.customerId,
    required this.reminderDate,
    this.lastPurchaseDate,
    this.lastPurchaseBranch,
    this.status = 'pending',
    this.remarks,
    this.updatedAt,
    this.callDuration,
    this.calledTimestamp,
    this.assignedTo,
    this.assignedDate,
    this.isOverdueLeftover = false,
    this.callAttempts = 0,
    this.todayCallAttempts = 0,
    this.lastCallAttemptTimestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'customer_id': customerId,
      'reminder_date': reminderDate.toIso8601String(),
      'last_purchase_date': lastPurchaseDate?.toIso8601String(),
      'last_purchase_branch': lastPurchaseBranch,
      'status': status,
      'remarks': remarks,
      'updated_at': updatedAt?.toIso8601String(),
      'call_duration': callDuration,
      'called_timestamp': calledTimestamp?.toIso8601String(),
      'assigned_to': assignedTo,
      'assigned_date': assignedDate,
      'is_overdue_leftover': isOverdueLeftover,
      'call_attempts': callAttempts,
      'today_call_attempts': todayCallAttempts,
      'last_call_attempt_timestamp': lastCallAttemptTimestamp?.toIso8601String(),
    };
  }

  factory DmeReminder.fromMap(Map<String, dynamic> map) {
    return DmeReminder(
      id: map['id'] != null ? int.tryParse(map['id'].toString()) : null,
      customerId: int.tryParse(map['customer_id'].toString()) ?? 0,
      reminderDate: map['reminder_date'] != null
          ? DateTime.tryParse(map['reminder_date'].toString()) ?? DateTime.now()
          : DateTime.now(),
      lastPurchaseDate: map['last_purchase_date'] != null
          ? DateTime.tryParse(map['last_purchase_date'].toString())
          : null,
      lastPurchaseBranch: map['last_purchase_branch'] != null
          ? int.tryParse(map['last_purchase_branch'].toString())
          : null,
      status: map['status'] as String? ?? 'pending',
      remarks: map['remarks'] as String?,
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'].toString())
          : null,
      callDuration: map['call_duration'] != null
          ? int.tryParse(map['call_duration'].toString())
          : null,
      calledTimestamp: map['called_timestamp'] != null
          ? DateTime.tryParse(map['called_timestamp'].toString())
          : null,
      assignedTo: map['assigned_to'] as String?,
      assignedDate: map['assigned_date']?.toString(),
      isOverdueLeftover: map['is_overdue_leftover'] == true ||
          map['is_overdue_leftover'] == 'true' ||
          map['is_overdue_leftover'] == 1,
      callAttempts: int.tryParse(map['call_attempts']?.toString() ?? '') ?? 0,
      todayCallAttempts: int.tryParse(map['today_call_attempts']?.toString() ?? '') ?? 0,
      lastCallAttemptTimestamp: map['last_call_attempt_timestamp'] != null
          ? DateTime.tryParse(map['last_call_attempt_timestamp'].toString())
          : null,
    );
  }
}

class DmeCustomerBranch {
  final int? id;
  final int customerId;
  final int branchId;
  final int? categoryId;
  final int? customerTypeId;
  final DateTime? createdAt;

  DmeCustomerBranch({
    this.id,
    required this.customerId,
    required this.branchId,
    this.categoryId,
    this.customerTypeId,
    this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'customer_id': customerId,
      'branch_id': branchId,
      'category_id': categoryId,
      'customer_type_id': customerTypeId,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  factory DmeCustomerBranch.fromMap(Map<String, dynamic> map) {
    return DmeCustomerBranch(
      id: map['id'] != null ? int.tryParse(map['id'].toString()) : null,
      customerId: int.tryParse(map['customer_id'].toString()) ?? 0,
      branchId: int.tryParse(map['branch_id'].toString()) ?? 0,
      categoryId: map['category_id'] != null
          ? int.tryParse(map['category_id'].toString())
          : null,
      customerTypeId: map['customer_type_id'] != null
          ? int.tryParse(map['customer_type_id'].toString())
          : null,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString())
          : null,
    );
  }
}

class DmeChangeRequest {
  final int? id;
  final int? reminderId;
  final int customerId;
  final String? customerName;
  final String? customerPhone;
  final String requestType; // 'phone_number_change' or 'preference_change'
  final String? currentValue;
  final String? newValue;
  final String? reason;
  final String status; // 'pending', 'approved', 'rejected'
  final String? requestedBy;
  final String? reviewedBy;
  final String? adminNotes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  DmeChangeRequest({
    this.id,
    this.reminderId,
    required this.customerId,
    this.customerName,
    this.customerPhone,
    required this.requestType,
    this.currentValue,
    this.newValue,
    this.reason,
    this.status = 'pending',
    this.requestedBy,
    this.reviewedBy,
    this.adminNotes,
    this.createdAt,
    this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      if (reminderId != null) 'reminder_id': reminderId,
      'customer_id': customerId,
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'request_type': requestType,
      'current_value': currentValue,
      'new_value': newValue,
      'reason': reason,
      'status': status,
      'requested_by': requestedBy,
      'reviewed_by': reviewedBy,
      'admin_notes': adminNotes,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  factory DmeChangeRequest.fromMap(Map<String, dynamic> map) {
    return DmeChangeRequest(
      id: map['id'] != null ? int.tryParse(map['id'].toString()) : null,
      reminderId: map['reminder_id'] != null ? int.tryParse(map['reminder_id'].toString()) : null,
      customerId: int.tryParse(map['customer_id']?.toString() ?? '') ?? 0,
      customerName: map['customer_name'] as String?,
      customerPhone: map['customer_phone'] as String?,
      requestType: map['request_type'] as String? ?? 'phone_number_change',
      currentValue: map['current_value'] as String?,
      newValue: map['new_value'] as String?,
      reason: map['reason'] as String?,
      status: map['status'] as String? ?? 'pending',
      requestedBy: map['requested_by'] as String?,
      reviewedBy: map['reviewed_by'] as String?,
      adminNotes: map['admin_notes'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString())
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'].toString())
          : null,
    );
  }
}

