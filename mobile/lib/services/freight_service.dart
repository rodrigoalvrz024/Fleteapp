import 'api_service.dart';
import '../models/freight_model.dart';
import '../core/constants/api_constants.dart';

class FreightService {
  final _api = ApiService();

  Future<FreightModel> createFreight({
    required String originAddress,
    required double originLat,
    required double originLng,
    required String destinationAddress,
    required double destinationLat,
    required double destinationLng,
    required String cargoDescription,
    required double cargoWeightKg,
    int requiresHelpers = 0,
  }) async {
    final res = await _api.post(ApiConstants.freights, {
      'origin_address': originAddress,
      'origin_lat': originLat,
      'origin_lng': originLng,
      'destination_address': destinationAddress,
      'destination_lat': destinationLat,
      'destination_lng': destinationLng,
      'cargo_description': cargoDescription,
      'cargo_weight_kg': cargoWeightKg,
      'requires_helpers': requiresHelpers,
    });
    return FreightModel.fromJson(res.data);
  }

  Future<List<FreightModel>> listFreights({String? status}) async {
    final res = await _api.get(ApiConstants.freights,
        params: status != null ? {'status': status} : null);
    return (res.data as List).map((e) => FreightModel.fromJson(e)).toList();
  }

  Future<FreightModel> getFreight(int id) async {
    final res = await _api.get('${ApiConstants.freights}/$id');
    return FreightModel.fromJson(res.data);
  }

  Future<FreightModel> acceptFreight(int id) async {
    final res = await _api.put('${ApiConstants.freights}/$id/accept');
    return FreightModel.fromJson(res.data);
  }

  Future<FreightModel> updateStatus(int id, String status,
      {String? note}) async {
    final res = await _api.put('${ApiConstants.freights}/$id/status', {
      'status': status,
      if (note != null) 'note': note,
    });
    return FreightModel.fromJson(res.data);
  }
}
