class DmeUser {
  final String id;
  final String firebaseUid;
  final String email;
  final String username;
  final String role;
  final List<String> branchNames;
  final int branchId; // Primary branch ID for the user

  DmeUser({
    required this.id,
    required this.firebaseUid,
    required this.email,
    required this.username,
    required this.role,
    this.branchNames = const [],
    this.branchId = 0,
  });

  bool get isAdmin => role == 'dme_admin';

  factory DmeUser.fromMap(Map<String, dynamic> map, {List<String>? branches, int? branchId}) {
    return DmeUser(
      id: map['id']?.toString() ?? '',
      firebaseUid: (map['firebase_uid'] ?? map['id'])?.toString() ?? '',
      email: map['email'] as String? ?? '',
      username: map['username'] as String? ?? '',
      role: map['role'] as String? ?? 'sales',
      branchNames: branches ?? [],
      branchId: branchId ?? (map['branch_id'] as int? ?? 0),
    );
  }

  Map<String, dynamic> toInsertMap() => {
        'id': firebaseUid,
        'email': email,
        'username': username,
        'role': role,
        'branch_id': branchId,
      };
}
