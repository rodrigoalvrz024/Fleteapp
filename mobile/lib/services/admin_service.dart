import 'api_service.dart';

class AdminMetrics {
  final int totalUsers;
  final int activeUsers;
  final int inactiveUsers;
  final Map<String, int> usersByRole;
  final int totalDrivers;
  final Map<String, int> driversByStatus;
  final int pendingDrivers;
  final int approvedDrivers;
  final int suspendedDrivers;
  final int totalFreights;
  final Map<String, int> freightsByStatus;
  final int activeFreights;
  final int completedFreights;
  final num completionRate;
  final Map<String, int> paymentsByStatus;
  final int authorizedPaymentsCount;
  final num authorizedPaymentsClp;
  final num averageAuthorizedTicketClp;
  final num grossCompletedClp;
  final num platformCommissionClp;
  final num pendingPlatformCommissionClp;
  final num driverPayoutClp;
  final num totalRevenueClp;

  const AdminMetrics({
    required this.totalUsers,
    required this.activeUsers,
    required this.inactiveUsers,
    required this.usersByRole,
    required this.totalDrivers,
    required this.driversByStatus,
    required this.pendingDrivers,
    required this.approvedDrivers,
    required this.suspendedDrivers,
    required this.totalFreights,
    required this.freightsByStatus,
    required this.activeFreights,
    required this.completedFreights,
    required this.completionRate,
    required this.paymentsByStatus,
    required this.authorizedPaymentsCount,
    required this.authorizedPaymentsClp,
    required this.averageAuthorizedTicketClp,
    required this.grossCompletedClp,
    required this.platformCommissionClp,
    required this.pendingPlatformCommissionClp,
    required this.driverPayoutClp,
    required this.totalRevenueClp,
  });

  factory AdminMetrics.fromJson(Map<String, dynamic> json) {
    Map<String, int> intMap(String key) =>
        ((json[key] ?? {}) as Map<String, dynamic>).map(
          (k, v) => MapEntry(k, (v as num?)?.toInt() ?? 0),
        );

    return AdminMetrics(
      totalUsers: json['total_users'] ?? 0,
      activeUsers: json['active_users'] ?? 0,
      inactiveUsers: json['inactive_users'] ?? 0,
      usersByRole: intMap('users_by_role'),
      totalDrivers: json['total_drivers'] ?? 0,
      driversByStatus: intMap('drivers_by_status'),
      pendingDrivers: json['pending_drivers'] ?? 0,
      approvedDrivers: json['approved_drivers'] ?? 0,
      suspendedDrivers: json['suspended_drivers'] ?? 0,
      totalFreights: json['total_freights'] ?? 0,
      freightsByStatus: intMap('freights_by_status'),
      activeFreights: json['active_freights'] ?? 0,
      completedFreights: json['completed_freights'] ?? 0,
      completionRate: json['completion_rate'] ?? 0,
      paymentsByStatus: intMap('payments_by_status'),
      authorizedPaymentsCount: json['authorized_payments_count'] ?? 0,
      authorizedPaymentsClp: json['authorized_payments_clp'] ?? 0,
      averageAuthorizedTicketClp: json['average_authorized_ticket_clp'] ?? 0,
      grossCompletedClp: json['gross_completed_clp'] ?? 0,
      platformCommissionClp: json['platform_commission_clp'] ?? 0,
      pendingPlatformCommissionClp:
          json['pending_platform_commission_clp'] ?? 0,
      driverPayoutClp: json['driver_payout_clp'] ?? 0,
      totalRevenueClp:
          json['total_revenue_clp'] ?? json['authorized_payments_clp'] ?? 0,
    );
  }
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
