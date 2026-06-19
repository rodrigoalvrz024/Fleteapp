import '../models/payout_model.dart';
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
  final num pendingDriverPayoutClp;
  final num paidDriverPayoutClp;
  final Map<String, int> payoutsByStatus;
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
    required this.pendingDriverPayoutClp,
    required this.paidDriverPayoutClp,
    required this.payoutsByStatus,
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
      pendingDriverPayoutClp: json['pending_driver_payout_clp'] ?? 0,
      paidDriverPayoutClp: json['paid_driver_payout_clp'] ?? 0,
      payoutsByStatus: intMap('payouts_by_status'),
      totalRevenueClp:
          json['total_revenue_clp'] ?? json['authorized_payments_clp'] ?? 0,
    );
  }
}

class AdminOperationalAlert {
  final String severity;
  final String title;
  final String message;
  final int count;
  final String action;

  const AdminOperationalAlert({
    required this.severity,
    required this.title,
    required this.message,
    required this.count,
    required this.action,
  });

  factory AdminOperationalAlert.fromJson(Map<String, dynamic> json) =>
      AdminOperationalAlert(
        severity: json['severity'] ?? 'info',
        title: json['title'] ?? '',
        message: json['message'] ?? '',
        count: json['count'] ?? 0,
        action: json['action'] ?? '',
      );
}

class AdminInsightEventType {
  final String eventType;
  final int count;
  final int uniqueAuthenticatedUsers;

  const AdminInsightEventType({
    required this.eventType,
    required this.count,
    required this.uniqueAuthenticatedUsers,
  });

  factory AdminInsightEventType.fromJson(Map<String, dynamic> json) =>
      AdminInsightEventType(
        eventType: json['event_type'] ?? '',
        count: (json['count'] as num?)?.toInt() ?? 0,
        uniqueAuthenticatedUsers:
            (json['unique_authenticated_users'] as num?)?.toInt() ?? 0,
      );

  String get label => switch (eventType) {
        'public.page_view' => 'Vistas web publica',
        'public.cta_click' => 'Clicks comerciales',
        'public.audience_click' => 'Clicks por audiencia',
        'app.screen_view' => 'Pantallas app',
        'app.freight_detail_view' => 'Aperturas de flete',
        'app.driver_profile_view' => 'Aperturas perfil conductor',
        'app.driver_available_freight_view' => 'Fletes disponibles vistos',
        'user.registered' => 'Usuarios registrados',
        'freight.created' => 'Fletes creados',
        'freight.accepted' => 'Fletes aceptados',
        'freight.status_changed' => 'Cambios de estado',
        'payment.authorized' => 'Pagos autorizados',
        _ => eventType,
      };
}

class AdminInsightEntity {
  final String entityId;
  final int views;
  final int uniqueAuthenticatedUsers;

  const AdminInsightEntity({
    required this.entityId,
    required this.views,
    required this.uniqueAuthenticatedUsers,
  });

  factory AdminInsightEntity.fromJson(Map<String, dynamic> json) =>
      AdminInsightEntity(
        entityId: json['entity_id']?.toString() ?? '',
        views: (json['views'] as num?)?.toInt() ?? 0,
        uniqueAuthenticatedUsers:
            (json['unique_authenticated_users'] as num?)?.toInt() ?? 0,
      );
}

class AdminEventInsights {
  final int days;
  final String since;
  final List<AdminInsightEventType> eventsByType;
  final List<AdminInsightEntity> topPublicPages;
  final List<AdminInsightEntity> topPublicCtas;
  final List<AdminInsightEntity> topFreightDetailViews;
  final List<AdminInsightEntity> topDriverProfileViews;

  const AdminEventInsights({
    required this.days,
    required this.since,
    required this.eventsByType,
    required this.topPublicPages,
    required this.topPublicCtas,
    required this.topFreightDetailViews,
    required this.topDriverProfileViews,
  });

  factory AdminEventInsights.fromJson(Map<String, dynamic> json) {
    final period = json['period'] as Map<String, dynamic>? ?? {};
    List<AdminInsightEventType> eventList(String key) =>
        ((json[key] ?? []) as List)
            .map((item) => AdminInsightEventType.fromJson(item))
            .toList();
    List<AdminInsightEntity> entityList(String key) =>
        ((json[key] ?? []) as List)
            .map((item) => AdminInsightEntity.fromJson(item))
            .toList();

    return AdminEventInsights(
      days: (period['days'] as num?)?.toInt() ?? 30,
      since: period['since'] ?? '',
      eventsByType: eventList('events_by_type'),
      topPublicPages: entityList('top_public_pages'),
      topPublicCtas: entityList('top_public_ctas'),
      topFreightDetailViews: entityList('top_freight_detail_views'),
      topDriverProfileViews: entityList('top_driver_profile_views'),
    );
  }

  int get totalEvents =>
      eventsByType.fold(0, (total, event) => total + event.count);

  int countFor(String eventType) => eventsByType
      .where((event) => event.eventType == eventType)
      .fold(0, (total, event) => total + event.count);

  int get publicEngagement =>
      countFor('public.page_view') +
      countFor('public.cta_click') +
      countFor('public.audience_click');

  int get appEngagement =>
      countFor('app.screen_view') +
      countFor('app.freight_detail_view') +
      countFor('app.driver_profile_view') +
      countFor('app.driver_available_freight_view');
}

class AdminOperationBucket {
  final String bucket;
  final int count;
  final int completed;
  final int cancelled;
  final num clientPaysClp;
  final num platformFeeClp;

  const AdminOperationBucket({
    required this.bucket,
    required this.count,
    this.completed = 0,
    this.cancelled = 0,
    required this.clientPaysClp,
    required this.platformFeeClp,
  });

  factory AdminOperationBucket.fromJson(Map<String, dynamic> json) =>
      AdminOperationBucket(
        bucket: json['bucket'] ?? '',
        count: (json['count'] as num?)?.toInt() ?? 0,
        completed: (json['completed'] as num?)?.toInt() ?? 0,
        cancelled: (json['cancelled'] as num?)?.toInt() ?? 0,
        clientPaysClp: json['client_pays_clp'] ?? 0,
        platformFeeClp: json['platform_fee_clp'] ?? 0,
      );
}

class AdminOperationsRealtime {
  final int freightsLastMinute;
  final int freightsLastHour;
  final int freightsLast24h;
  final num averageFreightsPerMinute60m;
  final num averageFreightsPerHour24h;
  final int activeFreights;
  final int pendingFreights;
  final int acceptedFreights;
  final int inProgressFreights;
  final int completed24h;
  final int cancelled24h;
  final int onlineDrivers;
  final int approvedDrivers;
  final int pendingDrivers;
  final int activeClients24h;
  final num grossRequested24hClp;
  final num platformFeePotential24hClp;

  const AdminOperationsRealtime({
    required this.freightsLastMinute,
    required this.freightsLastHour,
    required this.freightsLast24h,
    required this.averageFreightsPerMinute60m,
    required this.averageFreightsPerHour24h,
    required this.activeFreights,
    required this.pendingFreights,
    required this.acceptedFreights,
    required this.inProgressFreights,
    required this.completed24h,
    required this.cancelled24h,
    required this.onlineDrivers,
    required this.approvedDrivers,
    required this.pendingDrivers,
    required this.activeClients24h,
    required this.grossRequested24hClp,
    required this.platformFeePotential24hClp,
  });

  factory AdminOperationsRealtime.fromJson(Map<String, dynamic> json) =>
      AdminOperationsRealtime(
        freightsLastMinute:
            (json['freights_last_minute'] as num?)?.toInt() ?? 0,
        freightsLastHour: (json['freights_last_hour'] as num?)?.toInt() ?? 0,
        freightsLast24h: (json['freights_last_24h'] as num?)?.toInt() ?? 0,
        averageFreightsPerMinute60m:
            json['average_freights_per_minute_60m'] ?? 0,
        averageFreightsPerHour24h:
            json['average_freights_per_hour_24h'] ?? 0,
        activeFreights: (json['active_freights'] as num?)?.toInt() ?? 0,
        pendingFreights: (json['pending_freights'] as num?)?.toInt() ?? 0,
        acceptedFreights: (json['accepted_freights'] as num?)?.toInt() ?? 0,
        inProgressFreights:
            (json['in_progress_freights'] as num?)?.toInt() ?? 0,
        completed24h: (json['completed_24h'] as num?)?.toInt() ?? 0,
        cancelled24h: (json['cancelled_24h'] as num?)?.toInt() ?? 0,
        onlineDrivers: (json['online_drivers'] as num?)?.toInt() ?? 0,
        approvedDrivers: (json['approved_drivers'] as num?)?.toInt() ?? 0,
        pendingDrivers: (json['pending_drivers'] as num?)?.toInt() ?? 0,
        activeClients24h: (json['active_clients_24h'] as num?)?.toInt() ?? 0,
        grossRequested24hClp: json['gross_requested_24h_clp'] ?? 0,
        platformFeePotential24hClp:
            json['platform_fee_potential_24h_clp'] ?? 0,
      );
}

class AdminOperationsFunnel {
  final int created;
  final int accepted;
  final int started;
  final int completed;
  final int cancelled;
  final num acceptanceRate;
  final num startRate;
  final num completionRate;
  final num cancellationRate;

  const AdminOperationsFunnel({
    required this.created,
    required this.accepted,
    required this.started,
    required this.completed,
    required this.cancelled,
    required this.acceptanceRate,
    required this.startRate,
    required this.completionRate,
    required this.cancellationRate,
  });

  factory AdminOperationsFunnel.fromJson(Map<String, dynamic> json) =>
      AdminOperationsFunnel(
        created: (json['created'] as num?)?.toInt() ?? 0,
        accepted: (json['accepted'] as num?)?.toInt() ?? 0,
        started: (json['started'] as num?)?.toInt() ?? 0,
        completed: (json['completed'] as num?)?.toInt() ?? 0,
        cancelled: (json['cancelled'] as num?)?.toInt() ?? 0,
        acceptanceRate: json['acceptance_rate'] ?? 0,
        startRate: json['start_rate'] ?? 0,
        completionRate: json['completion_rate'] ?? 0,
        cancellationRate: json['cancellation_rate'] ?? 0,
      );
}

class AdminOperationsFinancial {
  final num grossRequestedClp;
  final num grossCompletedClp;
  final num platformFeePotentialClp;
  final num platformFeeCompletedClp;
  final num authorizedPaymentsClp;

  const AdminOperationsFinancial({
    required this.grossRequestedClp,
    required this.grossCompletedClp,
    required this.platformFeePotentialClp,
    required this.platformFeeCompletedClp,
    required this.authorizedPaymentsClp,
  });

  factory AdminOperationsFinancial.fromJson(Map<String, dynamic> json) =>
      AdminOperationsFinancial(
        grossRequestedClp: json['gross_requested_clp'] ?? 0,
        grossCompletedClp: json['gross_completed_clp'] ?? 0,
        platformFeePotentialClp: json['platform_fee_potential_clp'] ?? 0,
        platformFeeCompletedClp: json['platform_fee_completed_clp'] ?? 0,
        authorizedPaymentsClp: json['authorized_payments_clp'] ?? 0,
      );
}

class AdminOperations {
  final String generatedAt;
  final AdminOperationsRealtime realtime;
  final AdminOperationsFunnel funnel14d;
  final AdminOperationsFinancial financial14d;
  final List<AdminOperationBucket> minute;
  final List<AdminOperationBucket> hourly;
  final List<AdminOperationBucket> daily;

  const AdminOperations({
    required this.generatedAt,
    required this.realtime,
    required this.funnel14d,
    required this.financial14d,
    required this.minute,
    required this.hourly,
    required this.daily,
  });

  factory AdminOperations.fromJson(Map<String, dynamic> json) {
    List<AdminOperationBucket> buckets(String key) =>
        ((json[key] ?? []) as List)
            .map((item) => AdminOperationBucket.fromJson(item))
            .toList();

    return AdminOperations(
      generatedAt: json['generated_at'] ?? '',
      realtime: AdminOperationsRealtime.fromJson(
        json['realtime'] as Map<String, dynamic>? ?? {},
      ),
      funnel14d: AdminOperationsFunnel.fromJson(
        json['funnel_14d'] as Map<String, dynamic>? ?? {},
      ),
      financial14d: AdminOperationsFinancial.fromJson(
        json['financial_14d'] as Map<String, dynamic>? ?? {},
      ),
      minute: buckets('minute'),
      hourly: buckets('hourly'),
      daily: buckets('daily'),
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

class AdminAuditEvent {
  final int id;
  final String? occurredAt;
  final int? actorUserId;
  final String? actorName;
  final String? actorRole;
  final String entityType;
  final String? entityId;
  final String eventType;
  final Map<String, dynamic> beforeData;
  final Map<String, dynamic> afterData;
  final String? reason;
  final String? ipAddress;
  final String? userAgent;
  final String? requestId;
  final Map<String, dynamic> metadata;

  const AdminAuditEvent({
    required this.id,
    this.occurredAt,
    this.actorUserId,
    this.actorName,
    this.actorRole,
    required this.entityType,
    this.entityId,
    required this.eventType,
    required this.beforeData,
    required this.afterData,
    this.reason,
    this.ipAddress,
    this.userAgent,
    this.requestId,
    required this.metadata,
  });

  factory AdminAuditEvent.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> asMap(Object? value) {
      if (value is Map<String, dynamic>) return value;
      if (value is Map) {
        return value.map((key, value) => MapEntry('$key', value));
      }
      return const <String, dynamic>{};
    }

    int? asInt(Object? value) => value is num ? value.toInt() : null;

    return AdminAuditEvent(
      id: json['id'] ?? 0,
      occurredAt: json['occurred_at'],
      actorUserId: asInt(json['actor_user_id']),
      actorName: json['actor_name'],
      actorRole: json['actor_role'],
      entityType: json['entity_type'] ?? '',
      entityId: json['entity_id']?.toString(),
      eventType: json['event_type'] ?? '',
      beforeData: asMap(json['before_data']),
      afterData: asMap(json['after_data']),
      reason: json['reason'],
      ipAddress: json['ip_address'],
      userAgent: json['user_agent'],
      requestId: json['request_id'],
      metadata: asMap(json['metadata']),
    );
  }

  String get entityLabel => switch (entityType) {
        'user' => 'Usuario',
        'driver' => 'Conductor',
        'vehicle' => 'Vehiculo',
        'freight' => 'Flete',
        'payment' => 'Pago',
        'driver_payout' => 'Liquidacion',
        'system' => 'Sistema',
        'privacy_request' => 'Privacidad',
        'data_privacy_request' => 'Privacidad',
        'user_consent' => 'Consentimiento',
        _ => entityType.isEmpty ? 'Sistema' : entityType,
      };

  String get eventLabel => switch (eventType) {
        'user.registered' => 'Registro',
        'user.updated' => 'Perfil actualizado',
        'user.suspended' => 'Usuario suspendido',
        'user.activated' => 'Usuario activado',
        'driver.registered' => 'Conductor registrado',
        'driver.updated' => 'Conductor actualizado',
        'driver.approved' => 'Conductor aprobado',
        'driver.rejected' => 'Conductor rechazado',
        'driver.document_uploaded' => 'Documento subido',
        'driver.submitted_for_review' => 'Enviado a revision',
        'driver.documents_deleted' => 'Documentos eliminados',
        'vehicle.created' => 'Vehiculo creado',
        'freight.created' => 'Flete creado',
        'freight.accepted' => 'Flete aceptado',
        'freight.status_changed' => 'Estado de flete',
        'payment.initiated' => 'Pago iniciado',
        'payment.authorized' => 'Pago autorizado',
        'driver_payout.created' => 'Liquidacion creada',
        'driver_payout.pending' => 'Liquidacion pendiente',
        'driver_payout.scheduled' => 'Liquidacion programada',
        'driver_payout.paid' => 'Liquidacion pagada',
        'driver_payout.failed' => 'Liquidacion fallida',
        'privacy_request.created' => 'Solicitud creada',
        'privacy_request.status_changed' => 'Solicitud actualizada',
        'legal.terms_accepted' => 'Terminos aceptados',
        'legal.privacy_accepted' => 'Privacidad aceptada',
        'legal.driver_document_verification_accepted' =>
          'Revision documentos aceptada',
        'system.backend_error' => 'Error backend',
        _ => eventType,
      };

  String get targetLabel => entityId == null || entityId!.isEmpty
      ? entityLabel
      : '$entityLabel #$entityId';

  String get actorLabel {
    if (actorRole == null || actorRole!.isEmpty) return 'Sistema';
    final label = switch (actorRole) {
      'admin' => 'Admin',
      'driver' => 'Conductor',
      'client' => 'Cliente',
      _ => actorRole!,
    };
    if (actorName != null && actorName!.isNotEmpty) {
      return '$label - $actorName';
    }
    return actorUserId == null ? label : '$label #$actorUserId';
  }

  String get detailSummary {
    final trimmedReason = reason?.trim();
    if (trimmedReason != null && trimmedReason.isNotEmpty) {
      return trimmedReason;
    }

    final beforeStatus = beforeData['status'];
    final afterStatus = afterData['status'];
    if (beforeStatus != null && afterStatus != null) {
      return 'Estado: $beforeStatus -> $afterStatus';
    }

    final documentType = metadata['document_type'];
    if (documentType != null) return 'Documento: $documentType';

    final keys = afterData.keys.take(3).toList();
    if (keys.isNotEmpty) return 'Campos: ${keys.join(', ')}';

    return '';
  }
}

class AdminLegalConsent {
  final int id;
  final int userId;
  final String fullName;
  final String email;
  final String role;
  final String consentType;
  final String version;
  final String? ipAddress;
  final String? userAgent;
  final String? acceptedAt;

  const AdminLegalConsent({
    required this.id,
    required this.userId,
    required this.fullName,
    required this.email,
    required this.role,
    required this.consentType,
    required this.version,
    this.ipAddress,
    this.userAgent,
    this.acceptedAt,
  });

  factory AdminLegalConsent.fromJson(Map<String, dynamic> json) =>
      AdminLegalConsent(
        id: json['id'] ?? 0,
        userId: json['user_id'] ?? 0,
        fullName: json['full_name'] ?? '',
        email: json['email'] ?? '',
        role: json['role'] ?? '',
        consentType: json['consent_type'] ?? '',
        version: json['version'] ?? '',
        ipAddress: json['ip_address'],
        userAgent: json['user_agent'],
        acceptedAt: json['accepted_at'],
      );

  String get typeLabel => switch (consentType) {
        'terms' => 'Terminos y condiciones',
        'privacy' => 'Politica de privacidad',
        'driver_document_verification' => 'Revision de documentos',
        _ => consentType,
      };
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

  Map<String, dynamic> _auditParams({
    int limit = 100,
    String? entityType,
    String? entityId,
    String? eventType,
    String? actorUserId,
    String? actorRole,
    String? occurredFrom,
    String? occurredTo,
  }) =>
      {
        'limit': limit,
        if (entityType != null && entityType.isNotEmpty)
          'entity_type': entityType,
        if (entityId != null && entityId.isNotEmpty) 'entity_id': entityId,
        if (eventType != null && eventType.isNotEmpty) 'event_type': eventType,
        if (actorUserId != null && actorUserId.isNotEmpty)
          'actor_user_id': actorUserId,
        if (actorRole != null && actorRole.isNotEmpty) 'actor_role': actorRole,
        if (occurredFrom != null && occurredFrom.isNotEmpty)
          'occurred_from': occurredFrom,
        if (occurredTo != null && occurredTo.isNotEmpty)
          'occurred_to': occurredTo,
      };

  Future<AdminMetrics> getMetrics() async {
    final res = await _api.get('/admin/metrics');
    return AdminMetrics.fromJson(res.data);
  }

  Future<AdminEventInsights> getEventInsights({
    int days = 30,
    int limit = 10,
  }) async {
    final res = await _api.get(
      '/admin/insights/events',
      params: {'days': days, 'limit': limit},
    );
    return AdminEventInsights.fromJson(res.data);
  }

  Future<AdminOperations> getOperations() async {
    final res = await _api.get('/admin/operations');
    return AdminOperations.fromJson(res.data);
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

  Future<List<AdminAuditEvent>> listAuditEvents({
    int limit = 100,
    String? entityType,
    String? entityId,
    String? eventType,
    String? actorUserId,
    String? actorRole,
    String? occurredFrom,
    String? occurredTo,
  }) async {
    final res = await _api.get(
      '/admin/audit-events',
      params: _auditParams(
        limit: limit,
        entityType: entityType,
        entityId: entityId,
        eventType: eventType,
        actorUserId: actorUserId,
        actorRole: actorRole,
        occurredFrom: occurredFrom,
        occurredTo: occurredTo,
      ),
    );
    return (res.data as List)
        .map((item) => AdminAuditEvent.fromJson(item))
        .toList();
  }

  Future<String> exportAuditEventsCsv({
    int limit = 1000,
    String? entityType,
    String? entityId,
    String? eventType,
    String? actorUserId,
    String? actorRole,
    String? occurredFrom,
    String? occurredTo,
  }) async {
    final res = await _api.getText(
      '/admin/audit-events/export',
      params: _auditParams(
        limit: limit,
        entityType: entityType,
        entityId: entityId,
        eventType: eventType,
        actorUserId: actorUserId,
        actorRole: actorRole,
        occurredFrom: occurredFrom,
        occurredTo: occurredTo,
      ),
    );
    return res.data ?? '';
  }

  Future<List<AdminOperationalAlert>> listOperationalAlerts() async {
    final res = await _api.get('/admin/operational-alerts');
    return (res.data as List)
        .map((item) => AdminOperationalAlert.fromJson(item))
        .toList();
  }

  Future<List<PayoutModel>> listPayouts({String? status}) async {
    final res = await _api.get(
      '/payouts',
      params: {
        if (status != null && status.isNotEmpty) 'status': status,
      },
    );
    return (res.data as List)
        .map((item) => PayoutModel.fromJson(item))
        .toList();
  }

  Future<void> updatePayout({
    required int payoutId,
    required String status,
    DateTime? scheduledFor,
    String? transferReference,
    String? note,
  }) async {
    await _api.put('/payouts/$payoutId', {
      'status': status,
      if (scheduledFor != null)
        'scheduled_for': scheduledFor.toUtc().toIso8601String(),
      if (transferReference != null && transferReference.trim().isNotEmpty)
        'transfer_reference': transferReference.trim(),
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    });
  }

  Future<List<AdminLegalConsent>> listLegalConsents() async {
    final res = await _api.get('/admin/legal-consents', params: {'limit': 100});
    return (res.data as List)
        .map((item) => AdminLegalConsent.fromJson(item))
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
