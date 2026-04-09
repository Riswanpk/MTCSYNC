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
      id: map['id'] as String,
      firebaseUid: map['firebase_uid'] as String,
      email: map['email'] as String,
      username: map['username'] as String,
      role: map['role'] as String,
      branchNames: branches ?? [],
      branchId: branchId ?? (map['branch_id'] as int? ?? 0),
    );
  }

  Map<String, dynamic> toInsertMap() => {
        'firebase_uid': firebaseUid,
        'email': email,
        'username': username,
        'role': role,
        'branch_id': branchId,
      };
}
