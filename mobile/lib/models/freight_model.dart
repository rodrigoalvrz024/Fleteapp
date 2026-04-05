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
  final int requiresHelpers;
  final double? estimatedPrice;
  final double? finalPrice;
  final String status;
  final DateTime createdAt;

  FreightModel({
    required this.id,
    required this.clientId,
    this.driverId,
    required this.originAddress,
    required this.destinationAddress,
    this.distanceKm,
    required this.cargoDescription,
    required this.cargoWeightKg,
    required this.requiresHelpers,
    this.estimatedPrice,
    this.finalPrice,
    required this.status,
    required this.createdAt,
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
        requiresHelpers: j['requires_helpers'] ?? 0,
        estimatedPrice: (j['estimated_price'] as num?)?.toDouble(),
        finalPrice: (j['final_price'] as num?)?.toDouble(),
        status: j['status'],
        createdAt: DateTime.parse(j['created_at']),
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
      'pending': Color(0xFFFF6F00),
      'accepted': Color(0xFF1565C0),
      'in_progress': Color(0xFF0288D1),
      'completed': Color(0xFF2E7D32),
      'cancelled': Color(0xFFC62828),
    };
    return colors[status] ?? const Color(0xFF6B7280);
  }
}
