import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/api_service.dart';
import '../services/analytics_service.dart';

class AuthState {
  final UserModel? user;
  final bool isLoading;
  final String? error;

  const AuthState({this.user, this.isLoading = false, this.error});

  AuthState copyWith({UserModel? user, bool? isLoading, String? error}) =>
      AuthState(
        user: user ?? this.user,
        isLoading: isLoading ?? this.isLoading,
        error: error,
      );

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
        await _syncNotificationToken();
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
      state = AuthState(user: user);
      await _syncNotificationToken();

      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: _parseError(e));
      return false;
    }
  }

  Future<bool> loginWithGoogle(String idToken) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final data = await _service.loginWithGoogle(idToken);
      final user = UserModel.fromJson(data['user']);
      state = AuthState(user: user);
      await _syncNotificationToken();
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: _parseError(e));
      return false;
    }
  }

  Future<bool> register(
    String email,
    String phone,
    String name,
    String password,
    String role, {
    required bool acceptsTerms,
    required bool acceptsPrivacy,
    required bool acceptsDriverDocuments,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final data = await _service.register(
        email: email,
        phone: phone,
        fullName: name,
        password: password,
        role: role,
        acceptsTerms: acceptsTerms,
        acceptsPrivacy: acceptsPrivacy,
        acceptsDriverDocuments: acceptsDriverDocuments,
      );
      final user = UserModel.fromJson(data['user']);
      state = AuthState(user: user);
      await _syncNotificationToken();
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: _parseError(e));
      return false;
    }
  }

  Future<void> logout() async {
    try {
      await ApiService().put('/users/me', {'fcm_token': ''});
    } catch (_) {}
    await AnalyticsService().endSession();
    await _service.logout();
    // Limpiar estado completamente — el router detecta
    // isAuthenticated=false y redirige a /login sin splash
    state = const AuthState();
  }

  Future<bool> acceptLegalUpdate() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final user = await _service.acceptLegalUpdate();
      state = AuthState(user: user);
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: _parseError(e));
      return false;
    }
  }

  String _parseError(dynamic e) {
    if (e is DioException) {
      final status = e.response?.statusCode;
      final data = e.response?.data;
      final detail = data is Map ? data['detail']?.toString() : null;

      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        return 'El servicio se esta iniciando. Espera un minuto e intenta de nuevo.';
      }
      if (status == 400) {
        return detail?.isNotEmpty == true
            ? detail!
            : 'Revisa los datos ingresados.';
      }
      if (status == 401) return 'Credenciales incorrectas';
      if (status == 403) return detail ?? 'Cuenta suspendida';
      if (status == 422) return 'Revisa el formato de los datos.';
      if (status == 429) {
        return detail ?? 'Demasiados intentos. Intenta nuevamente mas tarde.';
      }
      if (status != null) {
        return detail ?? 'No se pudo completar la solicitud. Codigo $status.';
      }
    }
    final msg = e.toString();
    if (msg.contains('400')) {
      return 'El correo o teléfono ya está registrado';
    }
    if (msg.contains('429')) {
      return 'Demasiados intentos. Intenta nuevamente mas tarde.';
    }
    if (msg.contains('401')) return 'Credenciales incorrectas';
    if (msg.contains('403')) return 'Cuenta suspendida';
    return 'Error de conexión. Intenta de nuevo.';
  }

  Future<void> _syncNotificationToken() async {
    await NotificationService.registerTokenOnBackend((token) async {
      await ApiService().put('/users/me', {'fcm_token': token});
    });
  }
}

final authProvider =
    StateNotifierProvider<AuthNotifier, AuthState>((ref) => AuthNotifier());
