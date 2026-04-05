import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../screens/auth/login_screen.dart';
import '../../screens/auth/register_screen.dart';
import '../../screens/client/client_home_screen.dart';
import '../../screens/client/create_freight_screen.dart';
import '../../screens/client/freight_list_screen.dart';
import '../../screens/client/freight_detail_screen.dart';
import '../../screens/driver/driver_home_screen.dart';
import '../../screens/driver/available_freights_screen.dart';
import '../../screens/driver/driver_freight_detail_screen.dart';
import '../../screens/shared/profile_screen.dart';
import '../../screens/shared/splash_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authProvider);

  return GoRouter(
    initialLocation: '/splash',
    redirect: (context, state) {
      final loggedIn = auth.isAuthenticated;
      final onAuth = state.matchedLocation == '/login' ||
          state.matchedLocation == '/register' ||
          state.matchedLocation == '/splash';

      if (!loggedIn && !onAuth) return '/login';
      if (loggedIn && state.matchedLocation == '/splash') {
        return auth.user?.role == 'driver' ? '/driver' : '/client';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),

      // Cliente
      GoRoute(path: '/client', builder: (_, __) => const ClientHomeScreen()),
      GoRoute(
          path: '/client/create-freight',
          builder: (_, __) => const CreateFreightScreen()),
      GoRoute(
          path: '/client/freights',
          builder: (_, __) => const FreightListScreen()),
      GoRoute(
        path: '/client/freights/:id',
        builder: (_, state) => FreightDetailScreen(
            freightId: int.parse(state.pathParameters['id']!)),
      ),
      GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),

      // Conductor
      GoRoute(path: '/driver', builder: (_, __) => const DriverHomeScreen()),
      GoRoute(
          path: '/driver/available',
          builder: (_, __) => const AvailableFreightsScreen()),
      GoRoute(
        path: '/driver/freights/:id',
        builder: (_, state) => DriverFreightDetailScreen(
            freightId: int.parse(state.pathParameters['id']!)),
      ),
    ],
  );
});
