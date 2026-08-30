import 'package:flutter/material.dart';

class FreightDriverVehicleSummary {
  final String? type;
  final String? brand;
  final String? model;
  final int? year;
  final String? plate;
  final String? color;

  const FreightDriverVehicleSummary({
    this.type,
    this.brand,
    this.model,
    this.year,
    this.plate,
    this.color,
  });

  factory FreightDriverVehicleSummary.fromJson(Map<String, dynamic> json) =>
      FreightDriverVehicleSummary(
        type: json['type'],
        brand: json['brand'],
        model: json['model'],
        year: (json['year'] as num?)?.toInt(),
        plate: json['plate'],
        color: json['color'],
      );

  String get displayName {
    final parts = [brand, model, if (year != null) '$year']
        .where((part) => part != null && part.trim().isNotEmpty)
        .join(' ');
    return parts.isEmpty ? 'Vehiculo registrado' : parts;
  }

  String get displayDetail {
    final parts = [plate, color]
        .where((part) => part != null && part.trim().isNotEmpty)
        .join(' - ');
    return parts.isEmpty ? 'Datos del vehiculo verificados' : parts;
  }
}

class FreightDriverSummary {
  final int id;
  final String fullName;
  final double ratingAverage;
  final int ratingCount;
  final int totalTrips;
  final bool isVerified;
  final String? profileImageUrl;
  final FreightDriverVehicleSummary? vehicle;

  const FreightDriverSummary({
    required this.id,
    required this.fullName,
    this.ratingAverage = 0,
    this.ratingCount = 0,
    this.totalTrips = 0,
    this.isVerified = false,
    this.profileImageUrl,
    this.vehicle,
  });

  factory FreightDriverSummary.fromJson(Map<String, dynamic> json) =>
      FreightDriverSummary(
        id: json['id'],
        fullName: json['full_name'] ?? 'Conductor',
        ratingAverage: (json['rating_average'] as num?)?.toDouble() ?? 0,
        ratingCount: (json['rating_count'] as num?)?.toInt() ?? 0,
        totalTrips: (json['total_trips'] as num?)?.toInt() ?? 0,
        isVerified: json['is_verified'] == true,
        profileImageUrl: json['profile_image_url'],
        vehicle: json['vehicle'] is Map
            ? FreightDriverVehicleSummary.fromJson(
                Map<String, dynamic>.from(json['vehicle'] as Map),
              )
            : null,
      );

  String get firstName {
    final clean = fullName.trim();
    if (clean.isEmpty) return 'Conductor';
    return clean.split(' ').first;
  }
}

class FreightModel {
  final int id;
  final int clientId;
  final int? driverId;
  final String originAddress;
  final String destinationAddress;
  final double? distanceKm;
  final String cargoDescription;
  final double cargoWeightKg;
  final String? serviceType;
  final int? requiresHelpers;
  final double? estimatedPrice;
  final double? finalPrice;
  final String status;
  final DateTime createdAt;
  final bool? isUrgent;
  final String? mode;
  final double? clientPays;
  final double? driverReceives;
  final double? platformFee;
  final double? helpersCost;
  final DateTime? scheduledAt;
  final bool hasPickupPhoto;
  final bool hasDeliveryPhoto;
  final bool deliveryPinReady;
  final bool deliveryPinVerified;
  final int cargoPhotoCount;
  final bool clientFeedbackSubmitted;
  final bool driverFeedbackSubmitted;
  final int? paymentId;
  final String? paymentStatus;
  final double? ratingScore;
  final String? ratingComment;
  final FreightDriverSummary? driverSummary;

  FreightModel({
    required this.id,
    required this.clientId,
    this.driverId,
    required this.originAddress,
    required this.destinationAddress,
    this.distanceKm,
    required this.cargoDescription,
    required this.cargoWeightKg,
    this.serviceType,
    this.requiresHelpers,
    this.estimatedPrice,
    this.finalPrice,
    required this.status,
    required this.createdAt,
    this.isUrgent,
    this.mode,
    this.clientPays,
    this.driverReceives,
    this.platformFee,
    this.helpersCost,
    this.scheduledAt,
    this.hasPickupPhoto = false,
    this.hasDeliveryPhoto = false,
    this.deliveryPinReady = false,
    this.deliveryPinVerified = false,
    this.cargoPhotoCount = 0,
    this.clientFeedbackSubmitted = false,
    this.driverFeedbackSubmitted = false,
    this.paymentId,
    this.paymentStatus,
    this.ratingScore,
    this.ratingComment,
    this.driverSummary,
  });

  factory FreightModel.fromJson(Map<String, dynamic> j) => FreightModel(
        id: j['id'],
        clientId: j['client_id'],
        driverId: j['driver_id'],
        originAddress: j['origin_address'],
        destinationAddress: j['destination_address'],
        distanceKm: (j['distance_km'] as num?)?.toDouble(),
        cargoDescription: j['cargo_description'],
        cargoWeightKg: (j['cargo_weight_kg'] as num).toDouble(),
        serviceType: j['service_type']?.toString(),
        requiresHelpers: j['requires_helpers'] ?? 0,
        estimatedPrice: (j['estimated_price'] as num?)?.toDouble(),
        finalPrice: (j['final_price'] as num?)?.toDouble(),
        status: j['status'],
        createdAt: DateTime.parse(j['created_at']),
        isUrgent: j['is_urgent'] ?? false,
        mode: j['mode'],
        clientPays: (j['client_pays'] as num?)?.toDouble(),
        driverReceives: (j['driver_receives'] as num?)?.toDouble(),
        platformFee: (j['platform_fee'] as num?)?.toDouble(),
        helpersCost: (j['helpers_cost'] as num?)?.toDouble(),
        scheduledAt: j['scheduled_at'] != null
            ? DateTime.parse(j['scheduled_at'])
            : null,
        hasPickupPhoto: j['has_pickup_photo'] ?? false,
        hasDeliveryPhoto: j['has_delivery_photo'] ?? false,
        deliveryPinReady: j['delivery_pin_ready'] ?? false,
        deliveryPinVerified: j['delivery_pin_verified'] ?? false,
        cargoPhotoCount: (j['cargo_photo_count'] as num?)?.toInt() ?? 0,
        clientFeedbackSubmitted: j['client_feedback_submitted'] == true,
        driverFeedbackSubmitted: j['driver_feedback_submitted'] == true,
        paymentId: j['payment_id'],
        paymentStatus: j['payment_status'],
        ratingScore: (j['rating_score'] as num?)?.toDouble(),
        ratingComment: j['rating_comment'],
        driverSummary: j['driver_summary'] is Map
            ? FreightDriverSummary.fromJson(
                Map<String, dynamic>.from(j['driver_summary'] as Map),
              )
            : null,
      );

  String get statusLabel {
    const labels = {
      'pending': 'Pendiente',
      'accepted': 'Aceptado',
      'in_progress': 'En camino',
      'completed': 'Completado',
      'cancelled': 'Cancelado',
    };
    return labels[status] ?? status;
  }

  Color get statusColor {
    const Map<String, Color> colors = {
      'pending': Color(0xFFC2410C),
      'accepted': Color(0xFF1D4ED8),
      'in_progress': Color(0xFF0369A1),
      'completed': Color(0xFF15803D),
      'cancelled': Color(0xFFBE123C),
    };
    return colors[status] ?? const Color(0xFF94A3B8);
  }
}
