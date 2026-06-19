class DriverModel {
  final int id;
  final int userId;
  final String rut;
  final String? licenseNumber;
  final DateTime? licenseExpiry;
  final String status;
  final bool isAvailable;
  final String? profileImageUrl;
  final String? licenseImageUrl;
  final String? vehicleDocUrl;
  final DateTime? vehicleDocExpiry;
  final String? circulationPermitUrl;
  final DateTime? circulationPermitExpiry;
  final String? technicalReviewUrl;
  final DateTime? technicalReviewExpiry;
  final String? soapUrl;
  final DateTime? soapExpiry;
  final String? rejectionReason;
  final DateTime? submittedAt;
  final DateTime? documentsRetentionUntil;
  final DateTime? documentsDeletedAt;
  final double ratingAverage;
  final int ratingCount;
  final int totalTrips;
  final bool canOperate;
  final List<String> operationalBlockers;
  final List<VehicleModel> vehicles;

  const DriverModel({
    required this.id,
    required this.userId,
    required this.rut,
    this.licenseNumber,
    this.licenseExpiry,
    required this.status,
    this.isAvailable = false,
    this.profileImageUrl,
    this.licenseImageUrl,
    this.vehicleDocUrl,
    this.vehicleDocExpiry,
    this.circulationPermitUrl,
    this.circulationPermitExpiry,
    this.technicalReviewUrl,
    this.technicalReviewExpiry,
    this.soapUrl,
    this.soapExpiry,
    this.rejectionReason,
    this.submittedAt,
    this.documentsRetentionUntil,
    this.documentsDeletedAt,
    this.ratingAverage = 0,
    this.ratingCount = 0,
    this.totalTrips = 0,
    this.canOperate = false,
    this.operationalBlockers = const [],
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
        isAvailable: j['is_available'] == true,
        profileImageUrl: j['profile_image_url'],
        licenseImageUrl: j['license_image_url'],
        vehicleDocUrl: j['vehicle_doc_url'],
        vehicleDocExpiry: j['vehicle_doc_expiry'] != null
            ? DateTime.tryParse(j['vehicle_doc_expiry'].toString())
            : null,
        circulationPermitUrl: j['circulation_permit_url'],
        circulationPermitExpiry: j['circulation_permit_expiry'] != null
            ? DateTime.tryParse(j['circulation_permit_expiry'].toString())
            : null,
        technicalReviewUrl: j['technical_review_url'],
        technicalReviewExpiry: j['technical_review_expiry'] != null
            ? DateTime.tryParse(j['technical_review_expiry'].toString())
            : null,
        soapUrl: j['soap_url'],
        soapExpiry: j['soap_expiry'] != null
            ? DateTime.tryParse(j['soap_expiry'].toString())
            : null,
        rejectionReason: j['rejection_reason'],
        submittedAt: j['submitted_at'] != null
            ? DateTime.tryParse(j['submitted_at'].toString())
            : null,
        documentsRetentionUntil: j['documents_retention_until'] != null
            ? DateTime.tryParse(j['documents_retention_until'].toString())
            : null,
        documentsDeletedAt: j['documents_deleted_at'] != null
            ? DateTime.tryParse(j['documents_deleted_at'].toString())
            : null,
        ratingAverage: (j['rating_average'] as num?)?.toDouble() ?? 0,
        ratingCount: (j['rating_count'] as num?)?.toInt() ?? 0,
        totalTrips: (j['total_trips'] as num?)?.toInt() ?? 0,
        canOperate: j.containsKey('can_operate')
            ? j['can_operate'] == true
            : j['status'] == 'approved',
        operationalBlockers: _stringsFromJson(j['operational_blockers']),
        vehicles: _vehiclesFromJson(j)
            .map((v) => VehicleModel.fromJson(Map<String, dynamic>.from(v)))
            .toList(),
      );

  bool get isPending => status == 'pending' && submittedAt == null;
  bool get isUnderReview =>
      status == 'under_review' || (status == 'pending' && submittedAt != null);
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected' || status == 'suspended';

  int? get licenseDaysUntilExpiry {
    return daysUntil(licenseExpiry);
  }

  int? daysUntil(DateTime? expiry) {
    if (expiry == null) return null;
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final expiryDate = DateTime(expiry.year, expiry.month, expiry.day);
    return expiryDate.difference(todayDate).inDays;
  }

  bool get isLicenseExpired {
    final days = licenseDaysUntilExpiry;
    return days != null && days < 0;
  }

  bool get isLicenseExpiringSoon {
    final days = licenseDaysUntilExpiry;
    return days != null && days >= 0 && days <= 30;
  }

  bool get onboardingComplete =>
      licenseImageUrl != null &&
      (vehicleDocUrl != null || circulationPermitUrl != null) &&
      (vehicleDocExpiry != null || circulationPermitExpiry != null) &&
      technicalReviewUrl != null &&
      technicalReviewExpiry != null &&
      soapUrl != null &&
      soapExpiry != null &&
      vehicles.isNotEmpty;

  static List<dynamic> _vehiclesFromJson(Map<String, dynamic> j) {
    final vehicles = j['vehicles'];
    if (vehicles is List) return vehicles;
    final vehicle = j['vehicle'];
    if (vehicle is Map<String, dynamic>) return [vehicle];
    return [];
  }

  static List<String> _stringsFromJson(dynamic value) {
    if (value is! List) return const [];
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
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
