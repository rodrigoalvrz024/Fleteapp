class DriverModel {
  final int id;
  final int userId;
  final String rut;
  final String? licenseNumber;
  final DateTime? licenseExpiry;
  final String status;
  final String? profileImageUrl;
  final String? licenseImageUrl;
  final String? vehicleDocUrl;
  final String? circulationPermitUrl;
  final String? technicalReviewUrl;
  final String? soapUrl;
  final String? rejectionReason;
  final DateTime? submittedAt;
  final List<VehicleModel> vehicles;

  const DriverModel({
    required this.id,
    required this.userId,
    required this.rut,
    this.licenseNumber,
    this.licenseExpiry,
    required this.status,
    this.profileImageUrl,
    this.licenseImageUrl,
    this.vehicleDocUrl,
    this.circulationPermitUrl,
    this.technicalReviewUrl,
    this.soapUrl,
    this.rejectionReason,
    this.submittedAt,
    this.vehicles = const [],
  });

  factory DriverModel.fromJson(Map<String, dynamic> j) => DriverModel(
        id: j['id'],
        userId: j['user_id'],
        rut: j['rut'] ?? '',
        licenseNumber: j['license_number'],
        licenseExpiry: j['license_expiry'] != null
            ? DateTime.tryParse(j['license_expiry'].toString())
            : null,
        status: j['status'] ?? 'pending',
        profileImageUrl: j['profile_image_url'],
        licenseImageUrl: j['license_image_url'],
        vehicleDocUrl: j['vehicle_doc_url'],
        circulationPermitUrl: j['circulation_permit_url'],
        technicalReviewUrl: j['technical_review_url'],
        soapUrl: j['soap_url'],
        rejectionReason: j['rejection_reason'],
        submittedAt: j['submitted_at'] != null
            ? DateTime.tryParse(j['submitted_at'].toString())
            : null,
        vehicles: _vehiclesFromJson(j)
            .map((v) => VehicleModel.fromJson(Map<String, dynamic>.from(v)))
            .toList(),
      );

  bool get isPending => status == 'pending' && submittedAt == null;
  bool get isUnderReview =>
      status == 'under_review' || (status == 'pending' && submittedAt != null);
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected' || status == 'suspended';

  bool get onboardingComplete =>
      licenseImageUrl != null &&
      (vehicleDocUrl != null || circulationPermitUrl != null) &&
      technicalReviewUrl != null &&
      soapUrl != null &&
      vehicles.isNotEmpty;

  static List<dynamic> _vehiclesFromJson(Map<String, dynamic> j) {
    final vehicles = j['vehicles'];
    if (vehicles is List) return vehicles;
    final vehicle = j['vehicle'];
    if (vehicle is Map<String, dynamic>) return [vehicle];
    return [];
  }
}

class VehicleModel {
  final int? id;
  final String brand;
  final String model;
  final int year;
  final String plate;
  final String color;
  final String type;
  final double maxWeightKg;
  final double? maxVolumeM3;

  const VehicleModel({
    this.id,
    required this.brand,
    required this.model,
    required this.year,
    required this.plate,
    required this.color,
    this.type = 'pickup',
    this.maxWeightKg = 1000,
    this.maxVolumeM3,
  });

  factory VehicleModel.fromJson(Map<String, dynamic> j) => VehicleModel(
        id: j['id'],
        brand: j['brand'],
        model: j['model'],
        year: j['year'],
        plate: j['plate'],
        color: j['color'],
        type: j['type'] ?? 'pickup',
        maxWeightKg: (j['max_weight_kg'] as num?)?.toDouble() ?? 1000,
        maxVolumeM3: (j['max_volume_m3'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'type': type,
        'brand': brand,
        'model': model,
        'year': year,
        'plate': plate,
        'color': color,
        'max_weight_kg': maxWeightKg,
        if (maxVolumeM3 != null) 'max_volume_m3': maxVolumeM3,
      };
}
