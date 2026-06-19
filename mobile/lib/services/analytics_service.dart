import 'package:flutter/foundation.dart';

import '../core/constants/api_constants.dart';
import 'api_service.dart';

class AnalyticsService {
  static final AnalyticsService _instance = AnalyticsService._internal();
  factory AnalyticsService() => _instance;
  AnalyticsService._internal();

  final _api = ApiService();

  Future<void> trackScreen(String path) async {
    final isPublicAppRoute =
        path.startsWith('/auth') || path.startsWith('/legal');
    await trackEvent(
      eventType: isPublicAppRoute ? 'public.page_view' : 'app.screen_view',
      entityType: isPublicAppRoute ? 'public_page' : 'screen',
      entityId: isPublicAppRoute ? 'app:$path' : path,
      metadata: {
        'source': kIsWeb ? 'app_web' : 'app_mobile',
        'platform': defaultTargetPlatform.name,
        'path': path,
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
