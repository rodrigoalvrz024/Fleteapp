import 'package:dio/dio.dart';

import '../core/constants/api_constants.dart';
import '../models/chat_message_model.dart';
import 'api_service.dart';

abstract class FreightChatRepository {
  Future<FreightChatSummary> getSummary(int freightId);
  Future<List<FreightChatMessage>> listMessages(
    int freightId, {
    int? beforeId,
    int? limit,
  });
  Future<FreightChatMessage> sendMessage(int freightId, String message);
  Future<FreightChatMessage> sendImage(
    int freightId,
    List<int> bytes,
    String filename, {
    String caption,
  });
  Future<void> markRead(int freightId);
}

class FreightChatService implements FreightChatRepository {
  final _api = ApiService();

  String _basePath(int freightId) => '${ApiConstants.freights}/$freightId/chat';

  @override
  Future<FreightChatSummary> getSummary(int freightId) async {
    final response = await _api.get('${_basePath(freightId)}/summary');
    return FreightChatSummary.fromJson(
        Map<String, dynamic>.from(response.data));
  }

  @override
  Future<List<FreightChatMessage>> listMessages(
    int freightId, {
    int? beforeId,
    int? limit,
  }) async {
    final response = await _api.get(
      '${_basePath(freightId)}/messages',
      params: {
        if (beforeId != null) 'before_id': beforeId,
        if (limit != null) 'limit': limit,
      },
    );
    return (response.data as List)
        .map((item) => FreightChatMessage.fromJson(
              Map<String, dynamic>.from(item as Map),
            ))
        .toList();
  }

  @override
  Future<FreightChatMessage> sendMessage(
    int freightId,
    String message,
  ) async {
    final response = await _api.post('${_basePath(freightId)}/messages', {
      'message_text': message,
      'message_type': 'text',
    });
    return FreightChatMessage.fromJson(
        Map<String, dynamic>.from(response.data));
  }

  @override
  Future<FreightChatMessage> sendImage(
    int freightId,
    List<int> bytes,
    String filename, {
    String caption = '',
  }) async {
    if (bytes.isEmpty) {
      throw StateError('La foto seleccionada esta vacia.');
    }
    final safeFilename = filename.trim().split(RegExp(r'[\\/]')).last;
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        bytes,
        filename: safeFilename.isEmpty ? 'foto.jpg' : safeFilename,
      ),
      if (caption.trim().isNotEmpty) 'caption': caption.trim(),
    });
    final response = await _api.uploadForm(
      '${_basePath(freightId)}/images',
      form,
    );
    return FreightChatMessage.fromJson(
      Map<String, dynamic>.from(response.data),
    );
  }

  @override
  Future<void> markRead(int freightId) async {
    await _api.post('${_basePath(freightId)}/read', {});
  }
}
