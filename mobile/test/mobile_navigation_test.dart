import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:muvv_app/core/router/app_router.dart';
import 'package:muvv_app/core/theme/app_theme.dart';
import 'package:muvv_app/screens/shared/mobile_utility_screens.dart';
import 'package:muvv_app/widgets/muvv_mobile_ui.dart';
import 'package:muvv_app/widgets/muvv_page_scaffold.dart';

const _home = Scaffold(
  body: Text('Mapa del cliente'),
  bottomNavigationBar:
      MuvvBottomNavigation(selected: MuvvNavigationSection.home),
);

GoRouter _router({String initial = '/app/client/payments'}) => GoRouter(
      initialLocation: initial,
      routes: [
        GoRoute(path: '/app/client', builder: (_, __) => _home, routes: [
          GoRoute(
              path: 'payments',
              builder: (_, __) =>
                  const MuvvUtilityScreen(page: MuvvUtilityPage.payments)),
          GoRoute(
              path: 'freights',
              builder: (_, __) => const MuvvPageScaffold(
                    title: 'Mis fletes',
                    bottomNavigationBar: MuvvBottomNavigation(
                        selected: MuvvNavigationSection.activity),
                    child: Text('Historial de fletes'),
                  )),
          GoRoute(
              path: 'account',
              builder: (_, __) => const MuvvAccountHubScreen()),
        ]),
        GoRoute(
            path: '/app/settings/help',
            builder: (_, __) =>
                const MuvvUtilityScreen(page: MuvvUtilityPage.help)),
      ],
    );

Future<void> _mount(WidgetTester tester, GoRouter router,
    {double scale = 1}) async {
  await tester.binding.setSurfaceSize(const Size(393, 852));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
      child: MaterialApp.router(
    theme: AppTheme.light,
    routerConfig: router,
    builder: (context, child) => MediaQuery(
      data:
          MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
  )));
  await tester.pumpAndSettle();
}

void main() {
  test('every real primary tab has its own role home below it', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final router = container.read(routerProvider);
    for (final role in ['client', 'driver']) {
      final tabs = role == 'client'
          ? ['payments', 'freights', 'account']
          : ['payouts', 'trips', 'account'];
      for (final tab in tabs) {
        final matches = router.configuration.findMatch('/app/$role/$tab');
        expect(matches.isError, isFalse);
        expect(matches.matches.length, 2);
        expect(matches.matches.first.matchedLocation, '/app/$role');
      }
    }
    for (final path in [
      '/app/client/create-freight',
      '/app/client/freights/95',
      '/app/client/freights/95/chat',
      '/app/driver/freights/95/chat',
      '/app/driver/onboarding',
      '/app/profile',
      '/auth/login',
      '/'
    ]) {
      expect(router.configuration.findMatch(path).isError, isFalse);
    }
  });

  testWidgets('payments retains the menu and can navigate home',
      (tester) async {
    await _mount(tester, _router());
    expect(
        tester
            .widget<MuvvBottomNavigation>(find.byType(MuvvBottomNavigation))
            .selected,
        MuvvNavigationSection.wallet);
    await tester.tap(find.text('Inicio'));
    await tester.pumpAndSettle();
    expect(find.text('Mapa del cliente'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Android back from a payments direct link returns home',
      (tester) async {
    await _mount(tester, _router());
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Mapa del cliente'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'payments can switch to every other tab without a navigation trap',
      (tester) async {
    final router = _router();
    await _mount(tester, router);
    for (final label in ['Mis fletes', 'Perfil', 'Inicio']) {
      router.go('/app/client/payments');
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(find.byType(MuvvBottomNavigation), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('payments pushed from profile returns to profile',
      (tester) async {
    final router = _router(initial: '/app/client/account');
    await _mount(tester, router);
    router.push('/app/client/payments');
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(MuvvAccountHubScreen), findsOneWidget);
  });

  testWidgets('secondary direct link always has an explicit exit',
      (tester) async {
    await _mount(tester, _router(initial: '/app/settings/help'));
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Mapa del cliente'), findsOneWidget);
  });

  testWidgets(
      'card availability sheet dismisses without losing the payments tab',
      (tester) async {
    await _mount(tester, _router());
    await tester.tap(find.text('Agregar tarjeta'));
    await tester.pumpAndSettle();
    expect(find.text('Tarjetas con Webpay'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('Entendido'));
    await tester.pumpAndSettle();
    expect(find.byType(MuvvBottomNavigation), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(320, 640), const Size(393, 852)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('utility pages fit $size at text scale $scale',
          (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        for (final page in MuvvUtilityPage.values) {
          await tester.pumpWidget(ProviderScope(
              child: MaterialApp(
            theme: AppTheme.light,
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: MuvvUtilityScreen(key: ValueKey(page), page: page),
            ),
          )));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: page.name);
          await tester.drag(find.byType(ListView), const Offset(0, -600));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: page.name);
        }
      });
    }
  }
}
