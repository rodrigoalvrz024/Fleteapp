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
import 'services/analytics_service.dart';

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
  } catch (_) {
    debugPrint('Firebase initialization failed');
  }
}

class MuvvApp extends ConsumerStatefulWidget {
  const MuvvApp({super.key});

  @override
  ConsumerState<MuvvApp> createState() => _MuvvAppState();
}

class _MuvvAppState extends ConsumerState<MuvvApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(AnalyticsService().handleLifecycle(state));
  }

  @override
  Widget build(BuildContext context) {
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
