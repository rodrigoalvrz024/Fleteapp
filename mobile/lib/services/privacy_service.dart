import 'api_service.dart';

class PrivacyService {
  final _api = ApiService();

  Future<void> createRequest({
    required String requestType,
    String? message,
  }) async {
    await _api.post('/users/me/privacy-requests', {
      'request_type': requestType,
      if (message != null && message.trim().isNotEmpty)
        'message': message.trim(),
    });
  }
}
