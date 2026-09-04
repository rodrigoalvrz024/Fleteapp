import 'api_service.dart';
import '../models/user_model.dart';
import '../core/constants/api_constants.dart';

class AuthService {
  final _api = ApiService();

  Future<Map<String, dynamic>> register({
    required String email,
    required String phone,
    required String fullName,
    required String password,
    required String role,
    required bool alsoDriver,
    required bool acceptsTerms,
    required bool acceptsPrivacy,
    required bool acceptsDriverDocuments,
  }) async {
    final res = await _api.post(ApiConstants.register, {
      'email': email,
      'phone': phone,
      'full_name': fullName,
      'password': password,
      'role': role,
      'also_driver': alsoDriver,
      'accepts_terms': acceptsTerms,
      'accepts_privacy': acceptsPrivacy,
      'accepts_driver_documents': acceptsDriverDocuments,
    });
    await _api.saveToken(res.data['access_token']);
    return res.data;
  }

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final res = await _api.post(ApiConstants.login, {
      'email': email,
      'password': password,
    });
    await _api.saveToken(res.data['access_token']);
    return res.data;
  }

  Future<Map<String, dynamic>> loginWithGoogle(String idToken) async {
    final res = await _api.post(ApiConstants.googleLogin, {
      'id_token': idToken,
    });
    await _api.saveToken(res.data['access_token']);
    return res.data;
  }

  Future<Map<String, dynamic>> registerWithGoogle({
    required String idToken,
    required String phone,
    required String role,
    required bool alsoDriver,
    required bool acceptsTerms,
    required bool acceptsPrivacy,
    required bool acceptsDriverDocuments,
  }) async {
    final res = await _api.post(ApiConstants.googleRegister, {
      'id_token': idToken,
      'phone': phone,
      'role': role,
      'also_driver': alsoDriver,
      'accepts_terms': acceptsTerms,
      'accepts_privacy': acceptsPrivacy,
      'accepts_driver_documents': acceptsDriverDocuments,
    });
    await _api.saveToken(res.data['access_token']);
    return res.data;
  }

  Future<Map<String, dynamic>> switchRole(String role) async {
    final res = await _api.post(ApiConstants.switchRole, {'role': role});
    await _api.saveToken(res.data['access_token']);
    return res.data;
  }

  Future<UserModel> getMe() async {
    final res = await _api.get(ApiConstants.me);
    return UserModel.fromJson(res.data);
  }

  Future<UserModel> updateProfile({
    required String fullName,
    required String phone,
  }) async {
    final res = await _api.put(ApiConstants.updateMe, {
      'full_name': fullName,
      'phone': phone,
    });
    return UserModel.fromJson(Map<String, dynamic>.from(res.data as Map));
  }

  Future<UserModel> acceptLegalUpdate() async {
    final res = await _api.post('/auth/accept-legal-update', {
      'accepts_terms': true,
      'accepts_privacy': true,
    });
    return UserModel.fromJson(Map<String, dynamic>.from(res.data as Map));
  }

  Future<String> forgotPassword(String email) async {
    final res = await _api.post(ApiConstants.forgotPassword, {
      'email': email,
    });
    return res.data['message'] as String;
  }

  Future<String> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    final res = await _api.post(ApiConstants.resetPassword, {
      'token': token,
      'new_password': newPassword,
    });
    return res.data['message'] as String;
  }

  Future<void> logout() async {
    await _api.clearToken();
  }

  Future<bool> isLoggedIn() async {
    final token = await _api.getToken();
    return token != null;
  }
}
