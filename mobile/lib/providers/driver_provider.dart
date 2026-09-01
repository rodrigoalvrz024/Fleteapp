import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/freight_model.dart';
import '../services/driver_onboarding_service.dart';
import '../services/driver_live_location_service.dart';
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
      final locationReady =
          await DriverLiveLocationService.instance.ensurePermission();
      if (!locationReady) {
        state = state.copyWith(
          isOnline: false,
          isLoading: false,
          error: DriverLiveLocationService.permissionRequiredMessage,
        );
        return;
      }
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

      // Present one available request at a time. Dismissed requests stay hidden
      // for this online session while the driver reviews the next one.
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
      final locationReady =
          await DriverLiveLocationService.instance.ensurePermission();
      if (!locationReady) {
        state = state.copyWith(
          error: DriverLiveLocationService.permissionRequiredMessage,
        );
        return false;
      }
      final freight = await _service.acceptFreight(id);
      final trackingStarted =
          await DriverLiveLocationService.instance.start(freight.id);
      if (!trackingStarted) {
        state = state.copyWith(
          error: 'No pudimos iniciar tu ubicacion para este flete.',
        );
      }
      state = state.copyWith(
        activeFreight: freight,
        availableFreights: state.availableFreights
            .where((candidate) => candidate.id != id)
            .toList(),
        clearIncoming: true,
      );
      _stopPolling();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> declineFreight(int id) async {
    try {
      await _service.declineFreight(id);
      state = state.copyWith(
        availableFreights:
            state.availableFreights.where((freight) => freight.id != id).toList(),
        clearIncoming: true,
      );
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
        unawaited(
          DriverLiveLocationService.instance.stop(
            freightId: id,
            clearServer: false,
          ),
        );
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
