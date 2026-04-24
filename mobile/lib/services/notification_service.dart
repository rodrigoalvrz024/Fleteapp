import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

class NotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  static Future<void> initialize() async {
    // NO llamar Firebase.initializeApp() aquí — ya se hace en main.dart
    try {
      await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint(
            'Notificación recibida: ${message.notification?.title}');
      });

      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('Usuario abrió notificación: ${message.data}');
      });
    } catch (e) {
      debugPrint('NotificationService error: $e');
    }
  }

  static Future<String?> getToken() async {
    try {
      return await _messaging.getToken();
    } catch (_) {
      return null;
    }
  }

  static Future<void> registerTokenOnBackend(
      Function(String token) onToken) async {
    try {
      final token = await getToken();
      if (token != null) onToken(token);
      _messaging.onTokenRefresh.listen((newToken) => onToken(newToken));
    } catch (_) {}
  }
}