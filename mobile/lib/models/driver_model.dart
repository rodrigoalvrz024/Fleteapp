class DriverModel {
  final int    id;
  final int    userId;
  final String status;
  final String? profileImageUrl;
  final String? licenseImageUrl;
  final String? vehicleDocUrl;
  final String? rejectionReason;
  final List<VehicleModel> vehicles;

  const DriverModel({
    required this.id,
    required this.userId,
    required this.status,
    this.profileImageUrl,
    this.licenseImageUrl,
    this.vehicleDocUrl,
    this.rejectionReason,
    this.vehicles = const [],
  });

  factory DriverModel.fromJson(Map<String, dynamic> j) => DriverModel(
    id:               j['id'],
    userId:           j['user_id'],
    status:           j['status'] ?? 'pending',
    profileImageUrl:  j['profile_image_url'],
    licenseImageUrl:  j['license_image_url'],
    vehicleDocUrl:    j['vehicle_doc_url'],
    rejectionReason:  j['rejection_reason'],
    vehicles:         (j['vehicles'] as List? ?? [])
        .map((v) => VehicleModel.fromJson(v))
        .toList(),
  );

  bool get isPending     => status == 'pending';
  bool get isUnderReview => status == 'under_review';
  bool get isApproved    => status == 'approved';
  bool get isRejected    => status == 'rejected';

  bool get onboardingComplete =>
      profileImageUrl != null &&
      licenseImageUrl != null &&
      vehicleDocUrl   != null &&
      vehicles.isNotEmpty;
}

class VehicleModel {
  final int?   id;
  final String brand;
  final String model;
  final int    year;
  final String plate;
  final String color;

  const VehicleModel({
    this.id,
    required this.brand,
    required this.model,
    required this.year,
    required this.plate,
    required this.color,
  });

  factory VehicleModel.fromJson(Map<String, dynamic> j) => VehicleModel(
    id:    j['id'],
    brand: j['brand'],
    model: j['model'],
    year:  j['year'],
    plate: j['plate'],
    color: j['color'],
  );

  Map<String, dynamic> toJson() => {
    'brand': brand,
    'model': model,
    'year':  year,
    'plate': plate,
    'color': color,
  };
}