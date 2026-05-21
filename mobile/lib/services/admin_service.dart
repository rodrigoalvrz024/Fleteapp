import 'api_service.dart';

class AdminMetrics {
  final int totalUsers;
  final int totalDrivers;
  final int totalFreights;
  final num totalRevenueClp;

  const AdminMetrics({
    required this.totalUsers,
    required this.totalDrivers,
    required this.totalFreights,
    required this.totalRevenueClp,
  });

  factory AdminMetrics.fromJson(Map<String, dynamic> json) => AdminMetrics(
        totalUsers: json['total_users'] ?? 0,
        totalDrivers: json['total_drivers'] ?? 0,
        totalFreights: json['total_freights'] ?? 0,
        totalRevenueClp: json['total_revenue_clp'] ?? 0,
      );
}

class AdminUser {
  final int id;
  final String email;
  final String phone;
  final String fullName;
  final String role;
  final bool isActive;
  final String createdAt;

  const AdminUser({
    required this.id,
    required this.email,
    required this.phone,
    required this.fullName,
    required this.role,
    required this.isActive,
    required this.createdAt,
  });

  factory AdminUser.fromJson(Map<String, dynamic> json) => AdminUser(
        id: json['id'],
        email: json['email'] ?? '',
        phone: json['phone'] ?? '',
        fullName: json['full_name'] ?? '',
        role: json['role'] ?? '',
        isActive: json['is_active'] ?? false,
        createdAt: json['created_at'] ?? '',
      );
}

class AdminVehicle {
  final int id;
  final String brand;
  final String model;
  final int year;
  final String plate;
  final String color;

  const AdminVehicle({
    required this.id,
    required this.brand,
    required this.model,
    required this.year,
    required this.plate,
    required this.color,
  });

  factory AdminVehicle.fromJson(Map<String, dynamic> json) => AdminVehicle(
        id: json['id'],
        brand: json['brand'] ?? '',
        model: json['model'] ?? '',
        year: json['year'] ?? 0,
        plate: json['plate'] ?? '',
        color: json['color'] ?? '',
      );
}

class AdminDriver {
  final int id;
  final int userId;
  final String fullName;
  final String email;
  final String phone;
  final String status;
  final String createdAt;
  final List<AdminVehicle> vehicles;

  const AdminDriver({
    required this.id,
    required this.userId,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.status,
    required this.createdAt,
    required this.vehicles,
  });

  factory AdminDriver.fromJson(Map<String, dynamic> json) => AdminDriver(
        id: json['driver_id'] ?? json['id'],
        userId: json['user_id'] ?? 0,
        fullName: json['full_name'] ?? '',
        email: json['email'] ?? '',
        phone: json['phone'] ?? '',
        status: json['status'] ?? '',
        createdAt: json['created_at'] ?? '',
        vehicles: ((json['vehicles'] ?? []) as List)
            .map((item) => AdminVehicle.fromJson(item))
            .toList(),
      );
}

class AdminService {
  final _api = ApiService();

  Future<AdminMetrics> getMetrics() async {
    final res = await _api.get('/admin/metrics');
    return AdminMetrics.fromJson(res.data);
  }

  Future<List<AdminUser>> listUsers() async {
    final res = await _api.get('/admin/users', params: {'limit': 100});
    return (res.data as List).map((item) => AdminUser.fromJson(item)).toList();
  }

  Future<List<AdminDriver>> listDrivers() async {
    final res = await _api.get('/admin/drivers');
    return (res.data as List)
        .map((item) => AdminDriver.fromJson(item))
        .toList();
  }

  Future<void> approveDriver(int driverId) async {
    await _api.put('/admin/drivers/$driverId/approve');
  }

  Future<void> rejectDriver(int driverId, String reason) async {
    await _api.put('/admin/drivers/$driverId/reject', {'reason': reason});
  }
}
