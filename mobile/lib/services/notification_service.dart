import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/router/app_router.dart';

class NotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static StreamSubscription<RemoteMessage>? _foregroundSubscription;
  static StreamSubscription<RemoteMessage>? _openedSubscription;
  static StreamSubscription<String>? _tokenRefreshSubscription;
  static Timer? _bannerTimer;

  static Future<void> initialize() async {
    try {
      if (!kIsWeb) {
        final settings = await _messaging.requestPermission(
          alert: true,
          announcement: false,
          badge: true,
          carPlay: false,
          criticalAlert: false,
          provisional: false,
          sound: true,
        );
        debugPrint(
          'Notification permission: ${settings.authorizationStatus.name}',
        );

        await _messaging.setForegroundNotificationPresentationOptions(
          alert: false,
          badge: true,
          sound: true,
        );
      }

      await _foregroundSubscription?.cancel();
      _foregroundSubscription =
          FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('Notificacion recibida: ${message.notification?.title}');
        _showForegroundBanner(message);
      });

      await _openedSubscription?.cancel();
      _openedSubscription =
          FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _handleNotificationTap(initialMessage);
        });
      }
    } catch (e) {
      debugPrint('NotificationService error: $e');
    }
  }

  static Future<String?> getToken() async {
    try {
      if (!kIsWeb) {
        final settings = await _messaging.getNotificationSettings();
        if (settings.authorizationStatus == AuthorizationStatus.denied) {
          return null;
        }
      }
      return await _messaging.getToken();
    } catch (e) {
      debugPrint('FCM token error: $e');
      return null;
    }
  }

  static Future<void> registerTokenOnBackend(
    Future<void> Function(String token) onToken,
  ) async {
    try {
      final token = await getToken();
      if (token != null && token.isNotEmpty) {
        await onToken(token);
      }

      await _tokenRefreshSubscription?.cancel();
      _tokenRefreshSubscription = _messaging.onTokenRefresh.listen(
        (newToken) => onToken(newToken),
      );
    } catch (e) {
      debugPrint('FCM backend registration error: $e');
    }
  }

  static void _handleNotificationTap(RemoteMessage message) {
    final data = message.data;
    if (data.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      openRouteFromNotification(data);
    });
  }

  static void _showForegroundBanner(RemoteMessage message) {
    final messenger = rootScaffoldMessengerKey.currentState;
    if (messenger == null) return;

    final notification = message.notification;
    final title = notification?.title?.trim().isNotEmpty == true
        ? notification!.title!.trim()
        : 'Nuevo aviso de Muvv';
    final body = notification?.body?.trim().isNotEmpty == true
        ? notification!.body!.trim()
        : 'Tienes una actualizacion disponible.';

    _bannerTimer?.cancel();
    messenger.clearMaterialBanners();
    messenger.showMaterialBanner(
      MaterialBanner(
        elevation: 0,
        backgroundColor: AppTheme.surface,
        surfaceTintColor: Colors.transparent,
        dividerColor: AppTheme.slate200,
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.local_shipping_outlined,
            color: AppTheme.primary,
            size: 20,
          ),
        ),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.midnight,
                fontSize: 13,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              body,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.slate600,
                fontSize: 12,
                height: 1.25,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              messenger.hideCurrentMaterialBanner();
              _handleNotificationTap(message);
            },
            child: const Text('Ver'),
          ),
          IconButton(
            tooltip: 'Cerrar',
            onPressed: messenger.hideCurrentMaterialBanner,
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ],
      ),
    );

    _bannerTimer = Timer(const Duration(seconds: 7), () {
      rootScaffoldMessengerKey.currentState?.hideCurrentMaterialBanner();
    });
  }
}
