import 'package:flutter/material.dart';

class FreightModel {
  final int id;
  final int clientId;
  final int? driverId;
  final String originAddress;
  final String destinationAddress;
  final double? distanceKm;
  final String cargoDescription;
  final double cargoWeightKg;
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

  FreightModel({
    required this.id,
    required this.clientId,
    this.driverId,
    required this.originAddress,
    required this.destinationAddress,
    this.distanceKm,
    required this.cargoDescription,
    required this.cargoWeightKg,
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
  });

  factory FreightModel.fromJson(Map<String, dynamic> j) => FreightModel(
    id:                 j['id'],
    clientId:           j['client_id'],
    driverId:           j['driver_id'],
    originAddress:      j['origin_address'],
    destinationAddress: j['destination_address'],
    distanceKm:         (j['distance_km'] as num?)?.toDouble(),
    cargoDescription:   j['cargo_description'],
    cargoWeightKg:      (j['cargo_weight_kg'] as num).toDouble(),
    requiresHelpers:    j['requires_helpers'] ?? 0,
    estimatedPrice:     (j['estimated_price'] as num?)?.toDouble(),
    finalPrice:         (j['final_price'] as num?)?.toDouble(),
    status:             j['status'],
    createdAt:          DateTime.parse(j['created_at']),
    isUrgent:           j['is_urgent'] ?? false,
    mode:               j['mode'],
    clientPays:         (j['client_pays'] as num?)?.toDouble(),
    driverReceives:     (j['driver_receives'] as num?)?.toDouble(),
    platformFee:        (j['platform_fee'] as num?)?.toDouble(),
    helpersCost:        (j['helpers_cost'] as num?)?.toDouble(),
    scheduledAt:        j['scheduled_at'] != null
                          ? DateTime.parse(j['scheduled_at'])
                          : null,
  );

  String get statusLabel {
    const labels = {
      'pending':     'Pendiente',
      'accepted':    'Aceptado',
      'in_progress': 'En camino',
      'completed':   'Completado',
      'cancelled':   'Cancelado',
    };
    return labels[status] ?? status;
  }

  Color get statusColor {
    const Map<String, Color> colors = {
      'pending':     Color(0xFFC2410C),
      'accepted':    Color(0xFF1D4ED8),
      'in_progress': Color(0xFF0369A1),
      'completed':   Color(0xFF15803D),
      'cancelled':   Color(0xFFBE123C),
    };
    return colors[status] ?? const Color(0xFF94A3B8);
  }
}