import 'dart:async';

import 'package:geolocator/geolocator.dart';

import 'freight_service.dart';

/// Keeps a driver's live location running while an assigned freight is active.
///
/// This deliberately has no UI toggle: location is an operational requirement
/// for accepted freights and is cleared when the freight closes.
class DriverLiveLocationService {
  DriverLiveLocationService._();

  static final DriverLiveLocationService instance =
      DriverLiveLocationService._();

  final FreightService _freights = FreightService();
  StreamSubscription<Position>? _subscription;
  Timer? _heartbeat;
  DateTime? _lastSentAt;
  Future<void> _writeTail = Future.value();
  int _session = 0;
  int? _freightId;

  bool get isTracking => _freightId != null;

  static const String permissionRequiredMessage =
      'La ubicacion es obligatoria para conectarte y realizar fletes.';

  Future<bool> ensurePermission({bool requestIfNeeded = true}) async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied && requestIfNeeded) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  Future<bool> start(int freightId) async {
    if (_freightId == freightId && _subscription != null) return true;
    if (!await ensurePermission(requestIfNeeded: false)) return false;

    if (_freightId != null && _freightId != freightId) {
      await stop(clearServer: false);
    }

    final session = ++_session;
    _freightId = freightId;
    _lastSentAt = null;

    try {
      final initial = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      await _send(initial, freightId: freightId, session: session, force: true);

      _subscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 25,
        ),
      ).listen(
        (position) => unawaited(
          _send(position, freightId: freightId, session: session),
        ),
      );

      _heartbeat?.cancel();
      _heartbeat = Timer.periodic(const Duration(seconds: 30), (_) {
        unawaited(_sendHeartbeat(freightId: freightId, session: session));
      });
      return true;
    } catch (_) {
      await stop(freightId: freightId, clearServer: false);
      return false;
    }
  }

  Future<void> _send(
    Position position, {
    required int freightId,
    required int session,
    bool force = false,
  }) async {
    if (_session != session || _freightId != freightId) return;
    final now = DateTime.now();
    if (!force &&
        _lastSentAt != null &&
        now.difference(_lastSentAt!).inSeconds < 10) {
      return;
    }
    _lastSentAt = now;
    _writeTail = _writeTail.then((_) async {
      if (_session != session || _freightId != freightId) return;
      try {
        await _freights.updateDriverLiveLocation(
          freightId,
          latitude: position.latitude,
          longitude: position.longitude,
          accuracyM: position.accuracy < 0 ? 0 : position.accuracy,
          heading: position.heading >= 0 && position.heading < 360
              ? position.heading
              : null,
        );
      } catch (_) {
        // A later GPS point or heartbeat retries without interrupting the trip.
      }
    });
    await _writeTail;
  }

  Future<void> _sendHeartbeat({
    required int freightId,
    required int session,
  }) async {
    if (_session != session || _freightId != freightId) return;
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      await _send(position,
          freightId: freightId, session: session, force: true);
    } catch (_) {
      // The stream remains active and retries on the next update.
    }
  }

  Future<void> stop({int? freightId, bool clearServer = true}) async {
    if (freightId != null && freightId != _freightId) return;
    final activeFreightId = _freightId;
    if (activeFreightId == null) return;

    _session++;
    _freightId = null;
    _lastSentAt = null;
    await _subscription?.cancel();
    _subscription = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    await _writeTail;

    if (clearServer) {
      try {
        await _freights.stopDriverLiveLocation(activeFreightId);
      } catch (_) {
        // Closing a freight server-side also clears the last live position.
      }
    }
  }
}
