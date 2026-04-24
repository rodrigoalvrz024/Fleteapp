import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/driver_model.dart';
import '../services/driver_onboarding_service.dart';

class OnboardingState {
  final DriverModel? driver;
  final bool isLoading;
  final String? error;

  const OnboardingState({
    this.driver,
    this.isLoading = false,
    this.error,
  });

  OnboardingState copyWith({
    DriverModel? driver,
    bool? isLoading,
    String? error,
  }) => OnboardingState(
    driver:    driver    ?? this.driver,
    isLoading: isLoading ?? this.isLoading,
    error:     error,
  );
}

class OnboardingNotifier extends StateNotifier<OnboardingState> {
  final _service = DriverOnboardingService();
  OnboardingNotifier() : super(const OnboardingState());

  Future<void> load() async {
    state = state.copyWith(isLoading: true);
    try {
      final driver = await _service.getMyDriver();
      state = state.copyWith(driver: driver, isLoading: false);
    } catch (_) {
      // No existe aún → registrar
      try {
        final driver = await _service.registerDriver();
        state = state.copyWith(driver: driver, isLoading: false);
      } catch (e) {
        state = state.copyWith(
            isLoading: false, error: e.toString());
      }
    }
  }

  Future<void> uploadProfileImage(dynamic file) async {
    state = state.copyWith(isLoading: true);
    try {
      await _service.uploadImage(file, 'profile_image');
      await load();
    } catch (e) {
      state = state.copyWith(
          isLoading: false, error: 'Error subiendo foto');
    }
  }

  Future<void> uploadLicense(dynamic file) async {
    state = state.copyWith(isLoading: true);
    try {
      await _service.uploadImage(file, 'license_image');
      await load();
    } catch (e) {
      state = state.copyWith(
          isLoading: false, error: 'Error subiendo licencia');
    }
  }

  Future<void> uploadVehicleDoc(dynamic file) async {
    state = state.copyWith(isLoading: true);
    try {
      await _service.uploadImage(file, 'vehicle_doc');
      await load();
    } catch (e) {
      state = state.copyWith(
          isLoading: false, error: 'Error subiendo padrón');
    }
  }

  Future<void> addVehicle(VehicleModel vehicle) async {
    state = state.copyWith(isLoading: true);
    try {
      final updated = await _service.addVehicle(vehicle);
      state = state.copyWith(driver: updated, isLoading: false);
    } catch (e) {
      state = state.copyWith(
          isLoading: false, error: 'Error agregando vehículo');
    }
  }

  Future<void> submitForReview() async {
    state = state.copyWith(isLoading: true);
    try {
      final updated = await _service.submitForReview();
      state = state.copyWith(driver: updated, isLoading: false);
    } catch (e) {
      state = state.copyWith(
          isLoading: false, error: 'Error enviando solicitud');
    }
  }
}

final onboardingProvider =
    StateNotifierProvider<OnboardingNotifier, OnboardingState>(
        (ref) => OnboardingNotifier());