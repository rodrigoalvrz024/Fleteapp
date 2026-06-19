import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import 'api_service.dart';
import '../models/driver_model.dart';
import '../core/constants/api_constants.dart';

class DriverOnboardingService {
  final _api = ApiService();

  Future<DriverModel> getMyDriver() async {
    final res = await _api.get(ApiConstants.driverMe);
    return DriverModel.fromJson(res.data);
  }

  Future<DriverModel> registerDriver({
    required String rut,
    required String licenseNumber,
    required DateTime licenseExpiry,
  }) async {
    final res = await _api.post(ApiConstants.driverReg, {
      'rut': rut,
      'license_number': licenseNumber,
      'license_expiry': licenseExpiry.toIso8601String(),
    });
    return DriverModel.fromJson(res.data);
  }

  Future<String> uploadImage(
    XFile file,
    String field, {
    DateTime? expiresAt,
  }) async {
    final bytes = await file.readAsBytes();
    final formData = FormData.fromMap({
      field: MultipartFile.fromBytes(
        bytes,
        filename: file.name,
      ),
      if (expiresAt != null)
        '${field}_expiry': expiresAt.toUtc().toIso8601String(),
    });
    final res = await ApiService()
        .uploadForm('${ApiConstants.driverMe}/upload', formData);
    return res.data['url'] as String;
  }

  Future<DriverModel> addVehicle(VehicleModel vehicle) async {
    await _api.post(ApiConstants.driverVehicle, vehicle.toJson());
    return getMyDriver();
  }

  Future<DriverModel> submitForReview() async {
    final res = await _api.put('${ApiConstants.driverMe}/submit');
    return DriverModel.fromJson(res.data);
  }

  Future<DriverModel> updateAvailability(bool isAvailable) async {
    final res = await _api.put(ApiConstants.driverMe, {
      'is_available': isAvailable,
    });
    return DriverModel.fromJson(res.data);
  }
}
