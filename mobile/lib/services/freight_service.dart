import 'package:dio/dio.dart';
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
    double? cargoVolumeM3,
    String? serviceType,
    String? quoteId,
    int requiresHelpers = 0,
    bool isUrgent = false,
    DateTime? scheduledAt,
    List<String> cargoPhotoRefs = const [],
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
      if (cargoVolumeM3 != null) 'cargo_volume_m3': cargoVolumeM3,
      if (serviceType != null) 'service_type': serviceType,
      if (quoteId != null) 'quote_id': quoteId,
      'requires_helpers': requiresHelpers,
      'is_urgent': isUrgent,
      if (cargoPhotoRefs.isNotEmpty) 'cargo_photo_refs': cargoPhotoRefs,
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

  Future<List<String>> cargoPhotoUrls(int id) async {
    final res = await _api.get('${ApiConstants.freights}/$id/cargo-photos');
    final photos = res.data['photos'] as List? ?? const [];
    return photos
        .map((photo) => (photo as Map)['url']?.toString() ?? '')
        .where((url) => url.isNotEmpty)
        .toList();
  }

  Future<String> uploadCargoPhoto(XFile file) async {
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) throw StateError('La foto seleccionada esta vacia.');
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        bytes,
        filename: _safeImageFilename(file.name, bytes),
      ),
    });
    final res =
        await _api.uploadForm('${ApiConstants.freights}/cargo-photos', form);
    return res.data['reference'] as String;
  }

  Future<void> declineFreight(int id) async {
    await _api.post('${ApiConstants.freights}/$id/decline', {});
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
    return uploadEvidenceBytes(id, kind, bytes, file.name);
  }

  Future<FreightModel> uploadEvidenceBytes(
    int id,
    String kind,
    List<int> bytes,
    String filename,
  ) async {
    if (bytes.isEmpty) {
      throw StateError('El archivo seleccionado esta vacio.');
    }
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        bytes,
        filename: _safeImageFilename(filename, bytes),
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

String _safeImageFilename(String filename, List<int> bytes) {
  final cleanName = filename.trim();
  final lower = cleanName.toLowerCase();
  if (lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.png') ||
      lower.endsWith('.webp') ||
      lower.endsWith('.heic') ||
      lower.endsWith('.heif')) {
    return cleanName;
  }

  return 'evidencia${_imageExtension(bytes, lower)}';
}

String _imageExtension(List<int> bytes, String filename) {
  if (_startsWith(bytes, [0xFF, 0xD8, 0xFF])) {
    return '.jpg';
  }
  if (_startsWith(bytes, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
    return '.png';
  }
  if (bytes.length >= 12 &&
      _startsWith(bytes, [0x52, 0x49, 0x46, 0x46]) &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return '.webp';
  }
  if (_isHeifContent(bytes)) {
    if (filename.endsWith('.heif')) return '.heif';
    return '.heic';
  }

  return '.jpg';
}

bool _startsWith(List<int> bytes, List<int> signature) {
  if (bytes.length < signature.length) return false;
  for (var i = 0; i < signature.length; i++) {
    if (bytes[i] != signature[i]) return false;
  }
  return true;
}

bool _isHeifContent(List<int> bytes) {
  if (bytes.length < 12) return false;
  if (bytes[4] != 0x66 ||
      bytes[5] != 0x74 ||
      bytes[6] != 0x79 ||
      bytes[7] != 0x70) {
    return false;
  }

  const brands = {
    'heic',
    'heix',
    'hevc',
    'hevx',
    'heim',
    'heis',
    'hevm',
    'hevs',
    'mif1',
    'msf1',
  };
  final majorBrand = String.fromCharCodes(bytes.sublist(8, 12));
  if (brands.contains(majorBrand)) return true;
  for (var i = 16; i + 4 <= bytes.length; i += 4) {
    final brand = String.fromCharCodes(bytes.sublist(i, i + 4));
    if (brands.contains(brand)) return true;
  }
  return false;
}
