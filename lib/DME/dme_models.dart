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
  final String? salesman;
  final DateTime? lastPurchaseDate;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  DmeCustomer({
    this.id,
    required this.name,
    required this.phone,
    this.address,
    this.salesman,
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
      'salesman': salesman,
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
      salesman: map['salesman'] as String?,
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

  DmeReminder({
    this.id,
    required this.customerId,
    required this.reminderDate,
    this.lastPurchaseDate,
    this.lastPurchaseBranch,
    this.status = 'pending',
    this.remarks,
    this.updatedAt,
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
