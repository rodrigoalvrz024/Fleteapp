import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../core/constants/api_constants.dart';
import 'api_service.dart';

class AnalyticsService {
  static final AnalyticsService _instance = AnalyticsService._internal();
  factory AnalyticsService() => _instance;
  AnalyticsService._internal();

  final _api = ApiService();
  String? _activeScreen;
  DateTime? _screenOpenedAt;
  Timer? _presenceTimer;
  bool _isForeground = true;

  static const _presenceInterval = Duration(seconds: 45);

  String _normalizeScreen(String path) {
    final segments = path
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .map((segment) => int.tryParse(segment) == null ? segment : ':id')
        .toList();
    return '/${segments.join('/')}';
  }

  bool _isPublicRoute(String path) =>
      path.startsWith('/auth') || path.startsWith('/legal') || path == '/';

  Future<void> trackScreen(String path) async {
    final screen = _normalizeScreen(path);
    final isPublicAppRoute = _isPublicRoute(screen);
    if (_activeScreen == screen) {
      unawaited(_reportPresence());
      return;
    }

    await _recordScreenDwell();
    _activeScreen = screen;
    _screenOpenedAt = DateTime.now();
    unawaited(trackEvent(
      eventType: isPublicAppRoute ? 'public.page_view' : 'app.screen_view',
      entityType: isPublicAppRoute ? 'public_page' : 'screen',
      entityId: isPublicAppRoute ? 'app:$screen' : screen,
      metadata: {
        'source': kIsWeb ? 'app_web' : 'app_mobile',
        'platform': defaultTargetPlatform.name,
        'screen': screen,
      },
    ));

    if (isPublicAppRoute) {
      _stopPresenceTimer();
    } else {
      unawaited(_reportPresence());
      _startPresenceTimer();
    }
  }

  Future<void> handleLifecycle(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      _isForeground = true;
      _screenOpenedAt ??= DateTime.now();
      unawaited(_reportPresence());
      _startPresenceTimer();
      return;
    }

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _isForeground = false;
      _stopPresenceTimer();
      await _recordScreenDwell();
      _screenOpenedAt = null;
    }
  }

  Future<void> endSession() async {
    _stopPresenceTimer();
    await _recordScreenDwell();
    _activeScreen = null;
    _screenOpenedAt = null;
  }

  void _startPresenceTimer() {
    final screen = _activeScreen;
    if (!_isForeground || screen == null || _isPublicRoute(screen)) return;
    _presenceTimer ??= Timer.periodic(
      _presenceInterval,
      (_) => unawaited(_reportPresence()),
    );
  }

  void _stopPresenceTimer() {
    _presenceTimer?.cancel();
    _presenceTimer = null;
  }

  Future<void> _reportPresence() async {
    final screen = _activeScreen;
    if (!_isForeground || screen == null || _isPublicRoute(screen)) return;
    try {
      await _api.post(ApiConstants.analyticsPresence, {'screen': screen});
    } catch (_) {
      // Presence must never interrupt customer or driver workflows.
    }
  }

  Future<void> _recordScreenDwell() async {
    final screen = _activeScreen;
    final openedAt = _screenOpenedAt;
    if (screen == null || openedAt == null || _isPublicRoute(screen)) return;
    final seconds = DateTime.now().difference(openedAt).inSeconds;
    if (seconds < 1) return;
    await trackEvent(
      eventType: 'app.screen_dwell',
      entityType: 'screen',
      entityId: screen,
      metadata: {
        'source': kIsWeb ? 'app_web' : 'app_mobile',
        'platform': defaultTargetPlatform.name,
        'screen': screen,
        'duration_seconds': seconds,
      },
    );
  }

  Future<void> trackEvent({
    required String eventType,
    required String entityType,
    required String entityId,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      await _api.post(ApiConstants.analyticsEvents, {
        'event_type': eventType,
        'entity_type': entityType,
        'entity_id': entityId,
        if (metadata != null) 'metadata': metadata,
      });
    } catch (_) {
      // Analytics is intentionally best-effort and must not affect UX.
    }
  }
}
