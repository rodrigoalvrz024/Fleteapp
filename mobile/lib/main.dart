import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/date_symbol_data_local.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'firebase_options.dart';
import 'services/notification_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (kIsWeb) return;
  try {
    await Firebase.initializeApp();
  } catch (_) {}
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: MuvvApp()));

  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_initializeAppServices());
  });
}

Future<void> _initializeAppServices() async {
  await initializeDateFormatting('es', null);

  try {
    if (kIsWeb) {
      if (!DefaultFirebaseOptions.isWebConfigured) {
        debugPrint('Firebase web config missing; notifications disabled');
        return;
      }
      await Firebase.initializeApp(options: DefaultFirebaseOptions.web);
    } else {
      await Firebase.initializeApp();
    }
    if (!kIsWeb) {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    }
    await NotificationService.initialize();
  } catch (e) {
    debugPrint('Firebase init error: $e');
  }
}

class MuvvApp extends ConsumerWidget {
  const MuvvApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Muvv',
      theme: AppTheme.light,
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      routerConfig: router,
      locale: const Locale('es'),
      debugShowCheckedModeBanner: false,
    );
  }
}
