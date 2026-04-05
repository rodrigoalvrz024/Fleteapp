import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/api_service.dart';

class AuthState {
  final UserModel? user;
  final bool isLoading;
  final String? error;

  const AuthState({this.user, this.isLoading = false, this.error});

  AuthState copyWith({UserModel? user, bool? isLoading, String? error}) =>
      AuthState(
          user: user ?? this.user,
          isLoading: isLoading ?? this.isLoading,
          error: error);

  bool get isAuthenticated => user != null;
}

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthService _service = AuthService();
  AuthNotifier() : super(const AuthState());

  Future<void> checkAuth() async {
    if (await _service.isLoggedIn()) {
      try {
        final user = await _service.getMe();
        state = AuthState(user: user);
      } catch (_) {
        await _service.logout();
        state = const AuthState();
      }
    }
  }

  Future<bool> login(String email, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final data = await _service.login(email: email, password: password);
      final user = UserModel.fromJson(data['user']);

      //  Setear usuario
      state = AuthState(user: user);

      // NUEVO: enviar token FCM al backend
      NotificationService.registerTokenOnBackend((token) async {
        await ApiService().put('/users/me', {'fcm_token': token});
      });

      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: _parseError(e));
      return false;
    }
  }

  Future<bool> register(String email, String phone, String name,
      String password, String role) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final data = await _service.register(
        email: email,
        phone: phone,
        fullName: name,
        password: password,
        role: role,
      );
      final user = UserModel.fromJson(data['user']);
      state = AuthState(user: user);
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: _parseError(e));
      return false;
    }
  }

  Future<void> logout() async {
    await _service.logout();
    state = const AuthState();
  }

  String _parseError(dynamic e) {
    if (e.toString().contains('400'))
      return 'El correo o teléfono ya está registrado';
    if (e.toString().contains('401')) return 'Credenciales incorrectas';
    if (e.toString().contains('403')) return 'Cuenta suspendida';
    return 'Error de conexión. Intenta de nuevo.';
  }
}

final authProvider =
    StateNotifierProvider<AuthNotifier, AuthState>((ref) => AuthNotifier());
