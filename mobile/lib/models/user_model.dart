class UserModel {
  final int id;
  final String email;
  final String phone;
  final String fullName;
  final String role;
  final List<String> roles;
  final bool isActive;
  final String? avatarUrl;
  final bool legalReacceptanceRequired;

  UserModel({
    required this.id,
    required this.email,
    required this.phone,
    required this.fullName,
    required this.role,
    this.roles = const [],
    required this.isActive,
    this.avatarUrl,
    this.legalReacceptanceRequired = false,
  });

  factory UserModel.fromJson(Map<String, dynamic> j) {
    final activeRole = j['role'] as String;
    final suppliedRoles = (j['roles'] as List?)
            ?.map((value) => value.toString())
            .toList(growable: false) ??
        <String>[];
    final roles = suppliedRoles.isNotEmpty
        ? suppliedRoles
        : activeRole == 'driver'
            ? const ['client', 'driver']
            : [activeRole];
    return UserModel(
      id: j['id'],
      email: j['email'],
      phone: j['phone'],
      fullName: j['full_name'],
      role: activeRole,
      roles: roles,
      isActive: j['is_active'],
      avatarUrl: j['avatar_url'],
      legalReacceptanceRequired: j['legal_reacceptance_required'] == true,
    );
  }

  bool hasRole(String value) => roles.contains(value);
}
