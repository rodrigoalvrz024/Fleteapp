import 'dart:io';
import 'package:dio/dio.dart';
import 'api_service.dart';
import '../models/driver_model.dart';
import '../core/constants/api_constants.dart';

class DriverOnboardingService {
  final _api = ApiService();

  Future<DriverModel> getMyDriver() async {
    final res = await _api.get(ApiConstants.driverMe);
    return DriverModel.fromJson(res.data);
  }

  Future<DriverModel> registerDriver() async {
    final res = await _api.post(ApiConstants.driverReg, {});
    return DriverModel.fromJson(res.data);
  }

  Future<String> uploadImage(File file, String field) async {
    final name     = file.path.split('/').last;
    final formData = FormData.fromMap({
      field: await MultipartFile.fromFile(
        file.path,
        filename: name,
      ),
    });
    final res = await ApiService().uploadForm(
        '${ApiConstants.driverMe}/upload', formData);
    return res.data['url'] as String;
  }

  Future<DriverModel> addVehicle(VehicleModel vehicle) async {
    final res = await _api.post(
        ApiConstants.driverVehicle, vehicle.toJson());
    return DriverModel.fromJson(res.data);
  }

  Future<DriverModel> submitForReview() async {
    final res = await _api.put('${ApiConstants.driverMe}/submit');
    return DriverModel.fromJson(res.data);
  }
}