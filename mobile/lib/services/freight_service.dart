import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';

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
    bool isUrgent = false,
    DateTime? scheduledAt,
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
      'is_urgent': isUrgent,
      if (scheduledAt != null) 'scheduled_at': scheduledAt.toIso8601String(),
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

  Future<FreightModel> updateStatus(
    int id,
    String status, {
    String? note,
    String? confirmationPin,
  }) async {
    final res = await _api.put('${ApiConstants.freights}/$id/status', {
      'status': status,
      if (note != null) 'note': note,
      if (confirmationPin != null) 'confirmation_pin': confirmationPin,
    });
    return FreightModel.fromJson(res.data);
  }

  Future<String> generateDeliveryPin(int id) async {
    final res =
        await _api.post('${ApiConstants.freights}/$id/delivery-pin', {});
    return res.data['pin'] as String;
  }

  Future<FreightModel> uploadEvidence(int id, String kind, XFile file) async {
    final bytes = await file.readAsBytes();
    final contentType = _imageContentType(bytes, file.name);
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        bytes,
        filename: _safeImageFilename(file.name, contentType),
        contentType: contentType,
      ),
    });
    final res = await _api.uploadForm(
      '${ApiConstants.freights}/$id/evidence/$kind',
      form,
    );
    return FreightModel.fromJson(res.data);
  }

  Future<String> getEvidenceViewUrl(int id, String kind) async {
    final res = await _api.get(
      '${ApiConstants.freights}/$id/evidence/$kind/view-url',
    );
    return res.data['url'] as String;
  }
}

MediaType _imageContentType(List<int> bytes, String filename) {
  if (_startsWith(bytes, [0xFF, 0xD8, 0xFF])) {
    return MediaType('image', 'jpeg');
  }
  if (_startsWith(bytes, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
    return MediaType('image', 'png');
  }
  if (bytes.length >= 12 &&
      _startsWith(bytes, [0x52, 0x49, 0x46, 0x46]) &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return MediaType('image', 'webp');
  }

  final lower = filename.toLowerCase();
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
    return MediaType('image', 'jpeg');
  }
  if (lower.endsWith('.png')) return MediaType('image', 'png');
  if (lower.endsWith('.webp')) return MediaType('image', 'webp');

  return MediaType('application', 'octet-stream');
}

String _safeImageFilename(String filename, MediaType contentType) {
  final lower = filename.toLowerCase();
  if (lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.png') ||
      lower.endsWith('.webp')) {
    return filename;
  }

  final extension = switch (contentType.mimeType) {
    'image/jpeg' => '.jpg',
    'image/png' => '.png',
    'image/webp' => '.webp',
    _ => '.bin',
  };
  return 'evidencia$extension';
}

bool _startsWith(List<int> bytes, List<int> signature) {
  if (bytes.length < signature.length) return false;
  for (var i = 0; i < signature.length; i++) {
    if (bytes[i] != signature[i]) return false;
  }
  return true;
}
