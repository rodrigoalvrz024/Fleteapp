import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/freight_model.dart';
import '../services/driver_onboarding_service.dart';
import '../services/freight_service.dart';

class DriverState {
  final bool isOnline;
  final bool isLoading;
  final List<FreightModel> availableFreights;
  final FreightModel? incomingFreight;
  final FreightModel? activeFreight;
  final int completedToday;
  final double earningsToday;
  final double rating;
  final String? error;

  const DriverState({
    this.isOnline = false,
    this.isLoading = false,
    this.availableFreights = const [],
    this.incomingFreight,
    this.activeFreight,
    this.completedToday = 0,
    this.earningsToday = 0,
    this.rating = 5.0,
    this.error,
  });

  DriverState copyWith({
    bool? isOnline,
    bool? isLoading,
    List<FreightModel>? availableFreights,
    FreightModel? incomingFreight,
    bool clearIncoming = false,
    FreightModel? activeFreight,
    bool clearActive = false,
    int? completedToday,
    double? earningsToday,
    double? rating,
    String? error,
    bool clearError = false,
  }) =>
      DriverState(
        isOnline: isOnline ?? this.isOnline,
        isLoading: isLoading ?? this.isLoading,
        availableFreights: availableFreights ?? this.availableFreights,
        incomingFreight:
            clearIncoming ? null : (incomingFreight ?? this.incomingFreight),
        activeFreight:
            clearActive ? null : (activeFreight ?? this.activeFreight),
        completedToday: completedToday ?? this.completedToday,
        earningsToday: earningsToday ?? this.earningsToday,
        rating: rating ?? this.rating,
        error: clearError ? null : (error ?? this.error),
      );
}

class DriverNotifier extends StateNotifier<DriverState> {
  final FreightService _service = FreightService();
  final DriverOnboardingService _driverService = DriverOnboardingService();
  Timer? _pollingTimer;
  final Set<int> _seenFreightIds = {};

  DriverNotifier() : super(const DriverState());

  // ── Online/Offline ──────────────────────────────────────

  Future<void> goOnline() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _driverService.updateAvailability(true);
      state = state.copyWith(isOnline: true, isLoading: false);
      _startPolling();
    } catch (e) {
      state = state.copyWith(
        isOnline: false,
        isLoading: false,
        availableFreights: [],
        clearIncoming: true,
        error: _parseAvailabilityError(e),
      );
    }
  }

  Future<void> goOffline() async {
    _stopPolling();
    try {
      await _driverService.updateAvailability(false);
    } catch (_) {}
    state = state.copyWith(
      isOnline: false,
      availableFreights: [],
      clearIncoming: true,
      clearError: true,
    );
  }

  // ── Polling ─────────────────────────────────────────────

  void _startPolling() {
    _fetchFreights();
    _pollingTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _fetchFreights(),
    );
  }

  void _stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  String _parseAvailabilityError(Object error) {
    if (error is DioException) {
      final status = error.response?.statusCode;
      final data = error.response?.data;
      final detail = data is Map ? data['detail'] : null;

      if (detail is Map) {
        final message = detail['message']?.toString().trim();
        final blockers = detail['blockers'];
        if (blockers is List && blockers.isNotEmpty) {
          final items = blockers
              .map((item) => item.toString().trim())
              .where((item) => item.isNotEmpty)
              .take(4)
              .join(', ');
          if (items.isNotEmpty) {
            return '${message?.isNotEmpty == true ? message : 'No puedes conectarte'}: $items.';
          }
        }
        if (message?.isNotEmpty == true) return message!;
      }

      if (detail is String && detail.trim().isNotEmpty) {
        return detail.trim();
      }
      if (status == 403) {
        return 'No puedes conectarte. Revisa tu aprobacion y documentos.';
      }
      if (status != null) {
        return 'No pudimos cambiar tu disponibilidad. Codigo $status.';
      }
    }

    return 'No puedes conectarte. Revisa tu aprobacion y vencimientos.';
  }

  Future<void> _fetchFreights() async {
    if (!state.isOnline) return;
    try {
      final list = await _service.listFreights(status: 'available');
      final newOnes =
          list.where((f) => !_seenFreightIds.contains(f.id)).toList();

      state = state.copyWith(availableFreights: list);

      // Mostrar alerta solo si hay uno nuevo
      if (newOnes.isNotEmpty && state.incomingFreight == null) {
        state = state.copyWith(incomingFreight: newOnes.first);
        _seenFreightIds.add(newOnes.first.id);
      }
    } catch (_) {}
  }

  Future<void> refreshFreights() => _fetchFreights();

  // ── Aceptar flete ───────────────────────────────────────

  Future<bool> acceptFreight(int id) async {
    try {
      final freight = await _service.acceptFreight(id);
      state = state.copyWith(
        activeFreight: freight,
        clearIncoming: true,
      );
      _stopPolling();
      return true;
    } catch (_) {
      return false;
    }
  }

  void dismissIncoming() {
    state = state.copyWith(clearIncoming: true);
  }

  // ── Actualizar estado del viaje ─────────────────────────

  Future<void> updateFreightStatus(int id, String status) async {
    try {
      final updated = await _service.updateStatus(id, status);
      if (status == 'completed') {
        state = state.copyWith(
          clearActive: true,
          completedToday: state.completedToday + 1,
          earningsToday:
              state.earningsToday + (updated.estimatedPrice ?? 0) * 0.925,
        );
        if (state.isOnline) _startPolling();
      } else {
        state = state.copyWith(activeFreight: updated);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }
}

final driverProvider = StateNotifierProvider<DriverNotifier, DriverState>(
    (ref) => DriverNotifier());
