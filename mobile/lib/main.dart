import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es', null);
  try {
    await Firebase.initializeApp();
    await NotificationService.initialize();
  } catch (e) {
    debugPrint('Firebase init error: $e');
  }
  runApp(const ProviderScope(child: FleteApp()));
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