import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:muvv_app/core/theme/app_theme.dart';
import 'package:muvv_app/providers/auth_provider.dart';
import 'package:muvv_app/screens/auth/login_screen.dart';
import 'package:muvv_app/services/auth_service.dart';

const _captureDirectory = String.fromEnvironment('MUVV_UI_CAPTURE');

Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
  if (_captureDirectory.isEmpty) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(_captureDirectory).create(recursive: true);
    await File('$_captureDirectory/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

class TestAuthService extends AuthService {
  String activeRole = 'client';
  List<String> roles = ['client', 'driver'];
  String? requestedRole;
  bool loggedOut = false;
  bool failSwitch = false;
  bool legalRequired = false;

  Map<String, dynamic> response() => {
        'user': {
          'id': 1,
          'email': 'test@example.com',
          'phone': '',
          'full_name': 'Test',
          'is_active': true,
          'role': activeRole,
          'roles': roles,
          'legal_reacceptance_required': legalRequired,
        },
      };

  @override
  Future<Map<String, dynamic>> login(
          {required String email, required String password}) async =>
      response();

  @override
  Future<Map<String, dynamic>> loginWithGoogle(String idToken) async =>
      response();

  @override
  Future<Map<String, dynamic>> switchRole(String role) async {
    requestedRole = role;
    if (failSwitch) throw StateError('Server rejected switch');
    activeRole = role;
    return response();
  }

  @override
  Future<void> logout() async {
    loggedOut = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final google in [false, true]) {
    test('select authorized driver before publishing session (Google=$google)',
        () async {
      final service = TestAuthService();
      final notifier = AuthNotifier(service: service);
      addTearDown(notifier.dispose);
      final ok = google
          ? await notifier.loginWithGoogle('test-token',
              preferredRole: 'driver')
          : await notifier.login('test@example.com', 'test-password',
              preferredRole: 'driver');
      expect(ok, isTrue);
      expect(service.requestedRole, 'driver');
      expect(notifier.state.user!.role, 'driver');
    });
  }

  test('client cannot acquire driver permissions from selector', () async {
    final service = TestAuthService()..roles = ['client'];
    final notifier = AuthNotifier(service: service);
    addTearDown(notifier.dispose);
    expect(
        await notifier.login('test@example.com', 'test-password',
            preferredRole: 'driver'),
        isFalse);
    expect(service.requestedRole, isNull);
    expect(service.loggedOut, isTrue);
    expect(notifier.state.isAuthenticated, isFalse);
    expect(notifier.state.error, contains('Ingresa como cliente'));
  });

  test('server role switch rejection discards initial session', () async {
    final service = TestAuthService()..failSwitch = true;
    final notifier = AuthNotifier(service: service);
    addTearDown(notifier.dispose);
    expect(
        await notifier.loginWithGoogle('test-token', preferredRole: 'driver'),
        isFalse);
    expect(service.loggedOut, isTrue);
    expect(notifier.state.isAuthenticated, isFalse);
  });

  test('admin login is preserved', () async {
    final service = TestAuthService()
      ..activeRole = 'admin'
      ..roles = ['admin'];
    final notifier = AuthNotifier(service: service);
    addTearDown(notifier.dispose);
    expect(
        await notifier.login('test@example.com', 'test-password',
            preferredRole: 'driver'),
        isTrue);
    expect(service.requestedRole, isNull);
    expect(notifier.state.user!.role, 'admin');
  });

  test('dual role can enter client mode and retains legal requirement',
      () async {
    final service = TestAuthService()
      ..activeRole = 'driver'
      ..legalRequired = true;
    final notifier = AuthNotifier(service: service);
    addTearDown(notifier.dispose);
    expect(
        await notifier.login('test@example.com', 'test-password',
            preferredRole: 'client'),
        isTrue);
    expect(notifier.state.user!.role, 'client');
    expect(notifier.state.user!.legalReacceptanceRequired, isTrue);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets(
        'role selector keeps fields and registration choice at scale $scale',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      if (_captureDirectory.isNotEmpty && scale == 1) {
        final manifest =
            jsonDecode(await rootBundle.loadString('FontManifest.json'))
                as List;
        for (final entry in manifest) {
          final loader = FontLoader(entry['family'] as String);
          for (final font in entry['fonts'] as List) {
            loader.addFont(rootBundle.load(font['asset'] as String));
          }
          await loader.load();
        }
        for (final family in [
          'Ahem',
          'Roboto',
          '.SF UI Text',
          '.SF UI Display'
        ]) {
          await (FontLoader(family)
                ..addFont(rootBundle.load('assets/fonts/Inter-Variable.ttf')))
              .load();
        }
      }
      final boundaryKey = GlobalKey();
      final router = GoRouter(initialLocation: '/auth/login', routes: [
        GoRoute(path: '/auth/login', builder: (_, __) => const LoginScreen()),
        GoRoute(
            path: '/auth/register',
            builder: (_, state) => Scaffold(
                body: Text('register:${state.uri.queryParameters['role']}'))),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(RepaintBoundary(
          key: boundaryKey,
          child: ProviderScope(
              child: MaterialApp.router(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            routerConfig: router,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                  size: const Size(393, 852),
                  padding: const EdgeInsets.only(top: 44, bottom: 24),
                  textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
          ))));
      await tester.pumpAndSettle();
      if (_captureDirectory.isNotEmpty && scale == 1) {
        await tester.runAsync(() => precacheImage(
            const AssetImage('assets/branding/muvv-app-icon.png'),
            tester.element(find.byType(LoginScreen))));
        await tester.pumpAndSettle();
        await capture(tester, boundaryKey, 'login-client-$scale');
      }
      final selector = find.byType(CupertinoSlidingSegmentedControl<String>);
      expect(tester.getBottomLeft(selector).dy,
          lessThan(tester.getTopLeft(find.text('Correo electr\u00f3nico')).dy));
      await tester.enterText(
          find.byType(TextFormField).first, 'test@example.com');
      await tester.ensureVisible(find.text('Conductor'));
      await tester.tap(find.text('Conductor'));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<CupertinoSlidingSegmentedControl<String>>(selector)
              .groupValue,
          'driver');
      expect(find.text('test@example.com'), findsOneWidget);
      if (scale == 1) await capture(tester, boundaryKey, 'login-driver-$scale');
      expect(tester.takeException(), isNull);
      if (scale == 1) {
        expect(
            tester.getBottomLeft(find.text('Crear cuenta')).dy, lessThan(852));
      }
      await tester.ensureVisible(find.text('Crear cuenta'));
      await tester.tap(find.text('Crear cuenta'));
      await tester.pumpAndSettle();
      expect(find.text('register:driver'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final size in [const Size(360, 720), const Size(393, 852)]) {
    testWidgets('complete mobile login fits without scrolling at $size',
        (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      // Real font metrics are necessary for the no-scroll layout contract.
      for (final family in [
        'Inter',
        'Ahem',
        'Roboto',
        '.SF UI Text',
        '.SF UI Display'
      ]) {
        await (FontLoader(family)
              ..addFont(rootBundle.load('assets/fonts/Inter-Variable.ttf')))
            .load();
      }
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
          key: boundaryKey,
          child: ProviderScope(
              child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            home: MediaQuery(
              data: MediaQueryData(
                  size: size,
                  padding: const EdgeInsets.only(top: 44, bottom: 24)),
              child: const LoginScreen(),
            ),
          ))));
      await tester.pumpAndSettle();
      final scroll =
          tester.state<ScrollableState>(find.byType(Scrollable).first);
      expect(scroll.position.maxScrollExtent, 0);
      expect(tester.getCenter(find.text('o continúa con')).dx,
          closeTo(size.width / 2, 0.5));
      for (final label in ['Continuar con Google', 'Continuar con Apple']) {
        expect(tester.getCenter(find.text(label)).dx,
            closeTo(size.width / 2, 0.5));
      }
      final logo = find.byWidgetPredicate((widget) =>
          widget is Image &&
          widget.image is AssetImage &&
          (widget.image as AssetImage).assetName ==
              'assets/branding/muvv-app-icon.png');
      expect(tester.getSize(logo).width, greaterThanOrEqualTo(56));
      expect(find.text('Cliente'), findsOneWidget);
      expect(find.text('Conductor'), findsOneWidget);
      expect(tester.getBottomLeft(find.text('Política de privacidad.')).dy,
          lessThanOrEqualTo(size.height - 24));
      expect(tester.takeException(), isNull);
      await capture(tester, boundaryKey, 'login-compact-${size.width.toInt()}');
    });
  }
}
