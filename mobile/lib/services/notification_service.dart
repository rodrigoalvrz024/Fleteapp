import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

class NotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  static Future<void> initialize() async {
    await Firebase.initializeApp();

    // Pedir permisos
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Manejar notificación cuando la app está en primer plano
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('Notificación recibida: ${message.notification?.title}');
      // Aquí puedes mostrar un SnackBar o dialog en la app
    });

    // Manejar cuando el usuario toca la notificación
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('Usuario abrió notificación: ${message.data}');
      // Navegar según message.data['route']
    });
  }

  static Future<String?> getToken() async {
    return await _messaging.getToken();
  }

  /// Llama esto después del login para registrar el token en el backend
  static Future<void> registerTokenOnBackend(
      Function(String token) onToken) async {
    final token = await getToken();
    if (token != null) {
      onToken(token);
    }

    // Escuchar refresh del token
    _messaging.onTokenRefresh.listen((newToken) {
      onToken(newToken);
    });
  }
}
