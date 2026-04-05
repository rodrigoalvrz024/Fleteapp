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
  }) async {
    final res = await _api.post(ApiConstants.register, {
      'email': email,
      'phone': phone,
      'full_name': fullName,
      'password': password,
      'role': role,
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

  Future<UserModel> getMe() async {
    final res = await _api.get(ApiConstants.me);
    return UserModel.fromJson(res.data);
  }

  Future<void> logout() async {
    await _api.clearToken();
  }

  Future<bool> isLoggedIn() async {
    final token = await _api.getToken();
    return token != null;
  }
}
