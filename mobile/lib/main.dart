import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/date_symbol_data_local.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'firebase_options.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es', null);
  runApp(const ProviderScope(child: FleteApp()));
  _initializeFirebaseServices();
}

Future<void> _initializeFirebaseServices() async {
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
    await NotificationService.initialize();
  } catch (e) {
    debugPrint('Firebase init error: $e');
  }
}

class FleteApp extends ConsumerWidget {
  const FleteApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'FleteApp',
      theme: AppTheme.light,
      routerConfig: router,
      locale: const Locale('es'),
      debugShowCheckedModeBanner: false,
    );
  }
}
