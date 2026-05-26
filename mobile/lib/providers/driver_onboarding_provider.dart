import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

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
  }) =>
      OnboardingState(
        driver: driver ?? this.driver,
        isLoading: isLoading ?? this.isLoading,
        error: error,
      );
}

class OnboardingNotifier extends StateNotifier<OnboardingState> {
  final _service = DriverOnboardingService();

  OnboardingNotifier() : super(const OnboardingState());

  Future<void> load() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final driver = await _service.getMyDriver();
      state = state.copyWith(driver: driver, isLoading: false);
    } catch (_) {
      state = const OnboardingState();
    }
  }

  Future<void> registerDriver({
    required String rut,
    required String licenseNumber,
    required DateTime licenseExpiry,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final driver = await _service.registerDriver(
        rut: rut,
        licenseNumber: licenseNumber,
        licenseExpiry: licenseExpiry,
      );
      state = state.copyWith(driver: driver, isLoading: false);
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        error: 'Error creando perfil de conductor',
      );
    }
  }

  Future<void> uploadProfileImage(XFile file) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _service.uploadImage(file, 'profile_image');
      await load();
    } catch (_) {
      state = state.copyWith(isLoading: false, error: 'Error subiendo foto');
    }
  }

  Future<void> uploadLicense(XFile file) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _service.uploadImage(file, 'license_image');
      await load();
    } catch (_) {
      state =
          state.copyWith(isLoading: false, error: 'Error subiendo licencia');
    }
  }

  Future<void> uploadVehicleDoc(XFile file) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _service.uploadImage(file, 'vehicle_doc');
      await load();
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        error: 'Error subiendo permiso de circulacion',
      );
    }
  }

  Future<void> uploadCirculationPermit(XFile file) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _service.uploadImage(file, 'circulation_permit');
      await load();
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        error: 'Error subiendo permiso de circulacion',
      );
    }
  }

  Future<void> uploadTechnicalReview(XFile file) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _service.uploadImage(file, 'technical_review');
      await load();
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        error: 'Error subiendo revision tecnica',
      );
    }
  }

  Future<void> uploadSoap(XFile file) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _service.uploadImage(file, 'soap');
      await load();
    } catch (_) {
      state = state.copyWith(isLoading: false, error: 'Error subiendo SOAP');
    }
  }

  Future<void> addVehicle(VehicleModel vehicle) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final updated = await _service.addVehicle(vehicle);
      state = state.copyWith(driver: updated, isLoading: false);
    } catch (_) {
      state =
          state.copyWith(isLoading: false, error: 'Error agregando vehiculo');
    }
  }

  Future<void> submitForReview() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final updated = await _service.submitForReview();
      state = state.copyWith(driver: updated, isLoading: false);
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        error: 'Error enviando solicitud',
      );
    }
  }
}

final onboardingProvider =
    StateNotifierProvider<OnboardingNotifier, OnboardingState>(
  (ref) => OnboardingNotifier(),
);
