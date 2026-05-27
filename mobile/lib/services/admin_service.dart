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
  final int pendingPrivacyRequests;
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
    required this.pendingPrivacyRequests,
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
      pendingPrivacyRequests: json['pending_privacy_requests'] ?? 0,
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

class AdminPrivacyRequest {
  final int id;
  final int userId;
  final String fullName;
  final String email;
  final String phone;
  final String role;
  final String requestType;
  final String status;
  final String? message;
  final String? adminResponse;
  final String? resolvedAt;
  final String? createdAt;

  const AdminPrivacyRequest({
    required this.id,
    required this.userId,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.role,
    required this.requestType,
    required this.status,
    this.message,
    this.adminResponse,
    this.resolvedAt,
    this.createdAt,
  });

  factory AdminPrivacyRequest.fromJson(Map<String, dynamic> json) =>
      AdminPrivacyRequest(
        id: json['id'] ?? 0,
        userId: json['user_id'] ?? 0,
        fullName: json['full_name'] ?? '',
        email: json['email'] ?? '',
        phone: json['phone'] ?? '',
        role: json['role'] ?? '',
        requestType: json['request_type'] ?? '',
        status: json['status'] ?? '',
        message: json['message'],
        adminResponse: json['admin_response'],
        resolvedAt: json['resolved_at'],
        createdAt: json['created_at'],
      );

  String get typeLabel => switch (requestType) {
        'account_deletion' => 'Eliminar cuenta',
        'data_export' => 'Copia de datos',
        'data_rectification' => 'Rectificar datos',
        _ => requestType,
      };

  String get statusLabel => switch (status) {
        'pending' => 'Pendiente',
        'in_review' => 'En revision',
        'resolved' => 'Resuelta',
        'rejected' => 'Rechazada',
        _ => status,
      };

  bool get isOpen => status == 'pending' || status == 'in_review';
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
  final Map<String, bool> documents;
  final String? documentsRetentionUntil;
  final String? documentsDeletedAt;
  final String? rejectionReason;
  final List<AdminDriverReview> reviewHistory;
  final List<AdminVehicle> vehicles;

  const AdminDriver({
    required this.id,
    required this.userId,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.status,
    required this.createdAt,
    required this.documents,
    this.documentsRetentionUntil,
    this.documentsDeletedAt,
    this.rejectionReason,
    this.reviewHistory = const [],
    required this.vehicles,
  });

  factory AdminDriver.fromJson(Map<String, dynamic> json) {
    final documents = (json['documents'] as Map<String, dynamic>? ?? {}).map(
      (key, value) => MapEntry(key, value == true),
    );
    bool legacyHas(String key) {
      final value = json[key];
      return value is String && value.isNotEmpty;
    }

    return AdminDriver(
      id: json['driver_id'] ?? json['id'],
      userId: json['user_id'] ?? 0,
      fullName: json['full_name'] ?? '',
      email: json['email'] ?? '',
      phone: json['phone'] ?? '',
      status: json['status'] ?? '',
      createdAt: json['created_at'] ?? '',
      documents: {
        'license_image':
            documents['license_image'] ?? legacyHas('license_image_url'),
        'vehicle_doc': documents['vehicle_doc'] ?? legacyHas('vehicle_doc_url'),
        'circulation_permit': documents['circulation_permit'] ??
            legacyHas('circulation_permit_url'),
        'technical_review':
            documents['technical_review'] ?? legacyHas('technical_review_url'),
        'soap': documents['soap'] ?? legacyHas('soap_url'),
      },
      documentsRetentionUntil: json['documents_retention_until'],
      documentsDeletedAt: json['documents_deleted_at'],
      rejectionReason: json['rejection_reason'],
      reviewHistory: ((json['review_history'] ?? []) as List)
          .map((item) => AdminDriverReview.fromJson(item))
          .toList(),
      vehicles: ((json['vehicles'] ?? []) as List)
          .map((item) => AdminVehicle.fromJson(item))
          .toList(),
    );
  }

  bool get hasAnyDocument => documents.values.any((value) => value);
  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isSuspended => status == 'suspended';
}

class AdminDriverReview {
  final int id;
  final int adminId;
  final String? adminName;
  final String action;
  final String statusBefore;
  final String statusAfter;
  final String? reason;
  final Map<String, bool> documentsSnapshot;
  final String? createdAt;

  const AdminDriverReview({
    required this.id,
    required this.adminId,
    this.adminName,
    required this.action,
    required this.statusBefore,
    required this.statusAfter,
    this.reason,
    required this.documentsSnapshot,
    this.createdAt,
  });

  factory AdminDriverReview.fromJson(Map<String, dynamic> json) {
    final docs =
        (json['documents_snapshot'] as Map<String, dynamic>? ?? {}).map(
      (key, value) => MapEntry(key, value == true),
    );
    return AdminDriverReview(
      id: json['id'] ?? 0,
      adminId: json['admin_id'] ?? 0,
      adminName: json['admin_name'],
      action: json['action'] ?? '',
      statusBefore: json['status_before'] ?? '',
      statusAfter: json['status_after'] ?? '',
      reason: json['reason'],
      documentsSnapshot: docs,
      createdAt: json['created_at'],
    );
  }

  String get actionLabel => switch (action) {
        'approved' => 'Aprobado',
        'rejected' => 'Rechazado',
        'documents_deleted' => 'Docs eliminados',
        _ => action,
      };
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

  Future<List<AdminPrivacyRequest>> listPrivacyRequests() async {
    final res = await _api.get('/admin/privacy-requests');
    return (res.data as List)
        .map((item) => AdminPrivacyRequest.fromJson(item))
        .toList();
  }

  Future<void> approveDriver(int driverId) async {
    await _api.put('/admin/drivers/$driverId/approve');
  }

  Future<void> rejectDriver(int driverId, String reason) async {
    await _api.put('/admin/drivers/$driverId/reject', {'reason': reason});
  }

  Future<void> deleteDriverDocuments(int driverId, {String? reason}) async {
    await _api.delete(
      '/admin/drivers/$driverId/documents',
      {
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
    );
  }

  Future<void> updatePrivacyRequest({
    required int requestId,
    required String status,
    String? response,
  }) async {
    await _api.put('/admin/privacy-requests/$requestId', {
      'status': status,
      if (response != null && response.trim().isNotEmpty)
        'admin_response': response.trim(),
    });
  }

  Future<String> getDriverDocumentViewUrl({
    required int driverId,
    required String documentType,
  }) async {
    final res = await _api.get(
      '/admin/drivers/$driverId/documents/$documentType/view-url',
    );
    return res.data['url'] as String;
  }
}
