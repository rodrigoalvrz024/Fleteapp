import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../screens/admin/admin_dashboard_screen.dart';
import '../../screens/auth/forgot_password_screen.dart';
import '../../screens/auth/login_screen.dart';
import '../../screens/auth/register_screen.dart';
import '../../screens/auth/reset_password_screen.dart';
import '../../screens/client/client_home_screen.dart';
import '../../screens/client/create_freight_screen.dart';
import '../../screens/client/freight_detail_screen.dart';
import '../../screens/client/freight_list_screen.dart';
import '../../screens/driver/available_freights_screen.dart';
import '../../screens/driver/driver_freight_detail_screen.dart';
import '../../screens/driver/driver_home_screen.dart';
import '../../screens/driver/driver_onboarding_screen.dart';
import '../../screens/driver/driver_payouts_screen.dart';
import '../../screens/driver/driver_trips_screen.dart';
import '../../screens/legal/legal_document_screen.dart';
import '../../screens/shared/profile_screen.dart';
import '../../screens/shared/splash_screen.dart';

String _withQuery(String path, GoRouterState state) {
  final query = state.uri.queryParameters;
  return query.isEmpty
      ? path
      : Uri(path: path, queryParameters: query).toString();
}

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    // Public marketing lives in the Next.js site. The Flutter app starts here.
    GoRoute(
      path: '/',
      redirect: (_, state) => _withQuery('/auth/login', state),
    ),
    GoRoute(
      path: '/legal/terms',
      builder: (_, __) => const LegalDocumentScreen(
        type: LegalDocumentType.terms,
      ),
    ),
    GoRoute(
      path: '/legal/privacy',
      builder: (_, __) => const LegalDocumentScreen(
        type: LegalDocumentType.privacy,
      ),
    ),

    // Auth web.
    GoRoute(
      path: '/auth/login',
      builder: (_, state) => LoginScreen(
        redirectPath: state.uri.queryParameters['next'],
      ),
    ),
    GoRoute(
      path: '/auth/register',
      builder: (_, state) => RegisterScreen(
        redirectPath: state.uri.queryParameters['next'],
        initialRole: state.uri.queryParameters['role'],
      ),
    ),
    GoRoute(
      path: '/auth/forgot-password',
      builder: (_, __) => const ForgotPasswordScreen(),
    ),
    GoRoute(
      path: '/auth/reset-password',
      builder: (_, state) => ResetPasswordScreen(
        token: state.uri.queryParameters['token'],
      ),
    ),

    // App web.
    GoRoute(
      path: '/app/splash',
      builder: (_, __) => const SplashScreen(),
    ),
    GoRoute(
      path: '/app/client',
      builder: (_, __) => const ClientHomeScreen(),
    ),
    GoRoute(
      path: '/app/client/freights',
      builder: (_, __) => const FreightListScreen(),
    ),
    GoRoute(
      path: '/app/client/freights/:id',
      builder: (_, state) => FreightDetailScreen(
        freightId: int.parse(state.pathParameters['id']!),
      ),
    ),
    GoRoute(
      path: '/app/client/create-freight',
      builder: (context, state) {
        final q = state.uri.queryParameters;
        return CreateFreightScreen(
          destAddress: q['dest_address'],
          destLat: double.tryParse(q['dest_lat'] ?? ''),
          destLng: double.tryParse(q['dest_lng'] ?? ''),
          originAddress: q['origin_address'],
          originLat: double.tryParse(q['origin_lat'] ?? ''),
          originLng: double.tryParse(q['origin_lng'] ?? ''),
        );
      },
    ),
    GoRoute(
      path: '/app/profile',
      builder: (_, __) => const ProfileScreen(),
    ),
    GoRoute(
      path: '/app/driver',
      builder: (_, __) => const DriverHomeScreen(),
    ),
    GoRoute(
      path: '/app/driver/available',
      builder: (_, __) => const AvailableFreightsScreen(),
    ),
    GoRoute(
      path: '/app/driver/trips',
      builder: (_, __) => const DriverTripsScreen(),
    ),
    GoRoute(
      path: '/app/driver/freights/:id',
      builder: (_, state) => DriverFreightDetailScreen(
        freightId: int.parse(state.pathParameters['id']!),
      ),
    ),
    GoRoute(
      path: '/app/driver/onboarding',
      builder: (_, __) => const DriverOnboardingScreen(),
    ),
    GoRoute(
      path: '/app/driver/payouts',
      builder: (_, __) => const DriverPayoutsScreen(),
    ),

    // Admin web.
    GoRoute(
      path: '/admin',
      builder: (_, __) => const AdminDashboardScreen(),
    ),

    // Legacy redirects.
    GoRoute(
      path: '/splash',
      redirect: (_, state) => _withQuery('/app/splash', state),
    ),
    GoRoute(
      path: '/login',
      redirect: (_, state) => _withQuery('/auth/login', state),
    ),
    GoRoute(
      path: '/register',
      redirect: (_, state) => _withQuery('/auth/register', state),
    ),
    GoRoute(
      path: '/forgot-password',
      redirect: (_, state) => _withQuery('/auth/forgot-password', state),
    ),
    GoRoute(
      path: '/reset-password',
      redirect: (_, state) => _withQuery('/auth/reset-password', state),
    ),
    GoRoute(
      path: '/client',
      redirect: (_, state) => _withQuery('/app/client', state),
    ),
    GoRoute(
      path: '/client/freights',
      redirect: (_, state) => _withQuery('/app/client/freights', state),
    ),
    GoRoute(
      path: '/client/freights/:id',
      redirect: (_, state) => _withQuery(
        '/app/client/freights/${state.pathParameters['id']}',
        state,
      ),
    ),
    GoRoute(
      path: '/client/create-freight',
      redirect: (_, state) => _withQuery('/app/client/create-freight', state),
    ),
    GoRoute(
      path: '/profile',
      redirect: (_, state) => _withQuery('/app/profile', state),
    ),
    GoRoute(
      path: '/driver',
      redirect: (_, state) => _withQuery('/app/driver', state),
    ),
    GoRoute(
      path: '/driver/available',
      redirect: (_, state) => _withQuery('/app/driver/available', state),
    ),
    GoRoute(
      path: '/driver/trips',
      redirect: (_, state) => _withQuery('/app/driver/trips', state),
    ),
    GoRoute(
      path: '/driver/freights/:id',
      redirect: (_, state) => _withQuery(
        '/app/driver/freights/${state.pathParameters['id']}',
        state,
      ),
    ),
    GoRoute(
      path: '/driver/onboarding',
      redirect: (_, state) => _withQuery('/app/driver/onboarding', state),
    ),
    GoRoute(
      path: '/driver/payouts',
      redirect: (_, state) => _withQuery('/app/driver/payouts', state),
    ),
  ],
);

final routerProvider = Provider<GoRouter>((_) => _router);
