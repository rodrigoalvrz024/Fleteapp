class UserModel {
  final int id;
  final String email;
  final String phone;
  final String fullName;
  final String role;
  final bool isActive;
  final String? avatarUrl;

  UserModel({
    required this.id,
    required this.email,
    required this.phone,
    required this.fullName,
    required this.role,
    required this.isActive,
    this.avatarUrl,
  });

  factory UserModel.fromJson(Map<String, dynamic> j) => UserModel(
        id: j['id'],
        email: j['email'],
        phone: j['phone'],
        fullName: j['full_name'],
        role: j['role'],
        isActive: j['is_active'],
        avatarUrl: j['avatar_url'],
      );
}
