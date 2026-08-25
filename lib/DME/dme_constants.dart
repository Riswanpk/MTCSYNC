// DME Constants and Models
// Based on database schema and master reference tables.

class DmeCategory {
  final int id;
  final String name;

  const DmeCategory({required this.id, required this.name});

  Map<String, dynamic> toMap() => {'id': id, 'name': name};

  factory DmeCategory.fromMap(Map<String, dynamic> map) {
    return DmeCategory(
      id: map['id'] as int,
      name: map['name'] as String,
    );
  }

  @override
  String toString() => name;
}

class DmeBranch {
  final int id;
  final String name;

  const DmeBranch({required this.id, required this.name});

  Map<String, dynamic> toMap() => {'id': id, 'name': name};

  factory DmeBranch.fromMap(Map<String, dynamic> map) {
    return DmeBranch(
      id: map['id'] as int,
      name: map['name'] as String,
    );
  }

  @override
  String toString() => name;
}

class DmeCustomerType {
  final int id;
  final String name;

  const DmeCustomerType({required this.id, required this.name});

  Map<String, dynamic> toMap() => {'id': id, 'name': name};

  factory DmeCustomerType.fromMap(Map<String, dynamic> map) {
    return DmeCustomerType(
      id: map['id'] as int,
      name: map['name'] as String,
    );
  }

  @override
  String toString() => name;
}

class DmeConstants {
  // Table Names
  static const String tableBranches = 'dme_branches';
  static const String tableCustomerTypes = 'dme_customer_types';
  static const String tableCategories = 'dme_categories';
  static const String tableUsers = 'dme_users';
  static const String tableCustomers = 'dme_customers';
  static const String tableSales = 'dme_sales';
  static const String tableSalesDetail = 'dme_sales_detail';
  static const String tableReminders = 'dme_reminders';
  static const String tableCustomerBranches = 'dme_customer_branches';

  /// Master Categories
  static const List<DmeCategory> categories = [
    DmeCategory(id: 1, name: 'EVENT'),
    DmeCategory(id: 2, name: 'CATERING'),
    DmeCategory(id: 3, name: 'RESTAURANT'),
    DmeCategory(id: 4, name: 'PANTHAL'),
    DmeCategory(id: 5, name: 'STAGE DECORATION'),
    DmeCategory(id: 6, name: 'AUDITORIUM'),
    DmeCategory(id: 7, name: 'TRUST'),
    DmeCategory(id: 8, name: 'INSTITUTION'),
    DmeCategory(id: 9, name: 'RENTAL'),
    DmeCategory(id: 10, name: 'HIRING'),
    DmeCategory(id: 11, name: 'VEHICLE SHOWROOM'),
    DmeCategory(id: 12, name: 'RESORT'),
    DmeCategory(id: 13, name: 'GENERAL & OTHERS'),
  ];

  /// Master Branches
  static const List<DmeBranch> branches = [
    DmeBranch(id: 1, name: 'BGR'),
    DmeBranch(id: 2, name: 'CBE'),
    DmeBranch(id: 3, name: 'CHN'),
    DmeBranch(id: 4, name: 'CLT'),
    DmeBranch(id: 5, name: 'EKM'),
    DmeBranch(id: 6, name: 'JBL'),
    DmeBranch(id: 7, name: 'KKM'),
    DmeBranch(id: 8, name: 'KSD'),
    DmeBranch(id: 9, name: 'KTM'),
    DmeBranch(id: 10, name: 'PKD'),
    DmeBranch(id: 11, name: 'PKT'),
    DmeBranch(id: 12, name: 'PMN'),
    DmeBranch(id: 13, name: 'TRR'),
    DmeBranch(id: 14, name: 'TSR'),
    DmeBranch(id: 15, name: 'TLY'),
    DmeBranch(id: 16, name: 'TVM'),
    DmeBranch(id: 17, name: 'UDP'),
    DmeBranch(id: 18, name: 'VDK'),
    DmeBranch(id: 19, name: 'WND'),
  ];

  /// Master Customer Types
  static const List<DmeCustomerType> customerTypes = [
    DmeCustomerType(id: 1, name: 'PREMIUM'),
    DmeCustomerType(id: 2, name: 'REGULAR'),
    DmeCustomerType(id: 3, name: 'BARGAIN'),
    DmeCustomerType(id: 4, name: 'INSTITUTION'),
    DmeCustomerType(id: 5, name: 'DEALERS'),
    DmeCustomerType(id: 6, name: 'GENERAL'),
  ];

  // Helper Maps & Lookup functions
  static final Map<int, String> categoryMap = {
    for (var c in categories) c.id: c.name,
  };

  static final Map<int, String> branchMap = {
    for (var b in branches) b.id: b.name,
  };

  static final Map<int, String> customerTypeMap = {
    for (var ct in customerTypes) ct.id: ct.name,
  };

  static String getCategoryName(int? id) => id != null ? (categoryMap[id] ?? 'Unknown') : 'N/A';
  static String getBranchName(int? id) => id != null ? (branchMap[id] ?? 'Unknown') : 'N/A';
  static String getCustomerTypeName(int? id) => id != null ? (customerTypeMap[id] ?? 'Unknown') : 'N/A';

  static int? getCategoryIdByName(String name) {
    final clean = name.trim().toLowerCase().replaceAll('&', 'and').replaceAll(RegExp(r'\s+'), ' ');
    if (clean.isEmpty) return null;
    for (var c in categories) {
      final cName = c.name.toLowerCase().replaceAll('&', 'and').replaceAll(RegExp(r'\s+'), ' ');
      if (cName == clean || clean.contains(cName) || cName.contains(clean)) {
        return c.id;
      }
    }
    return null;
  }

  static final Map<String, int> _branchAliases = {
    // Exact Codes
    'bgr': 1, 'cbe': 2, 'chn': 3, 'clt': 4, 'ekm': 5,
    'jbl': 6, 'kkm': 7, 'ksd': 8, 'ktm': 9, 'pkd': 10,
    'pkt': 11, 'pmn': 12, 'trr': 13, 'tsr': 14, 'tly': 15,
    'tvm': 16, 'udp': 17, 'vdk': 18, 'wnd': 19,

    // City / Town / Regional Names
    'bangalore': 1, 'bengaluru': 1,
    'coimbatore': 2,
    'chennai': 3, 'madras': 3,
    'calicut': 4, 'kozhikode': 4,
    'ernakulam': 5, 'cochin': 5, 'kochi': 5,
    'jabalpur': 6,
    'kanyakumari': 7, 'nagercoil': 7,
    'kasaragod': 8, 'kasargod': 8,
    'kottayam': 9,
    'palakkad': 10, 'palghat': 10,
    'pattambi': 11,
    'perinthalmanna': 12, 'perinthamanna': 12,
    'tirur': 13,
    'thrissur': 14, 'trichur': 14,
    'thalassery': 15, 'tellicherry': 15,
    'trivandrum': 16, 'thiruvananthapuram': 16,
    'udupi': 17,
    'vadakara': 18, 'badagara': 18,
    'wayanad': 19, 'sulthan bathery': 19, 'kalpetta': 19, 'mananthavady': 19,
  };

  static int? getBranchIdByName(String name) {
    final clean = name.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (clean.isEmpty) return null;

    // 1. Direct alias or code match
    if (_branchAliases.containsKey(clean)) {
      return _branchAliases[clean];
    }

    // 2. Direct branch list code match
    for (var b in branches) {
      if (b.name.toLowerCase() == clean) return b.id;
    }

    // 3. Partial contains match
    for (var entry in _branchAliases.entries) {
      if (clean.contains(entry.key) || entry.key.contains(clean)) {
        return entry.value;
      }
    }

    return null;
  }

  static int? getCustomerTypeIdByName(String name) {
    final clean = name.trim().toLowerCase();
    if (clean.isEmpty) return null;
    for (var ct in customerTypes) {
      final ctName = ct.name.toLowerCase();
      if (ctName == clean || clean.contains(ctName) || ctName.contains(clean)) {
        return ct.id;
      }
    }
    return null;
  }
}
