import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muvv_app/core/theme/app_theme.dart';
import 'package:muvv_app/screens/shared/freight_truck_loader.dart';
import 'package:muvv_app/widgets/muvv_mobile_ui.dart';

Widget _buttonPage({double textScale = 1, bool reduceMotion = false}) {
  return MaterialApp(
    theme: AppTheme.light,
    home: MediaQuery(
      data: MediaQueryData(
        textScaler: TextScaler.linear(textScale),
        disableAnimations: reduceMotion,
      ),
      child: Scaffold(
        body: Center(
          child: SizedBox(
            width: 280,
            child: MuvvGradientButton(
              label: 'Solicitar un flete',
              icon: Icons.local_shipping_outlined,
              onPressed: () {},
            ),
          ),
        ),
      ),
    ),
  );
}

Widget _introPage(ThemeData theme) => MaterialApp(
      theme: theme,
      home: const Scaffold(body: MuvvIntroSequence()),
    );

void main() {
  testWidgets('primary action fits at double system text size', (tester) async {
    await tester.pumpWidget(_buttonPage(textScale: 2));
    expect(tester.takeException(), isNull);
    final label = find.text('Solicitar un flete');
    final context = tester.element(label);
    expect(MediaQuery.textScalerOf(context).scale(15), 30);
    expect(tester.getSize(find.byType(MuvvGradientButton)).height,
        greaterThanOrEqualTo(50));
  });

  testWidgets('reduced motion keeps pressed button at its original scale',
      (tester) async {
    await tester.pumpWidget(_buttonPage(reduceMotion: true));
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Solicitar un flete')),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('intro reveals the name then moves the same identity upwards',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_introPage(AppTheme.light));
    await tester.pump();
    final name = find.text('Muvv');
    final identity = tester.element(name);
    final opacity = find.ancestor(of: name, matching: find.byType(Opacity));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.widget<Opacity>(opacity).opacity, 0);
    await tester.pump(const Duration(milliseconds: 800));
    expect(tester.widget<Opacity>(opacity).opacity, 1);
    final startingPosition = tester.getCenter(name);
    await tester.pump(const Duration(milliseconds: 1200));
    expect(tester.element(name), same(identity));
    expect(tester.getCenter(name).dy, lessThan(startingPosition.dy - 100));
    expect(tester.widget<Opacity>(opacity).opacity, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('compact theme preserves approved splash identity geometry',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final originalTheme = ThemeData(
      useMaterial3: true,
      fontFamily: AppTheme.fontFamily,
      colorScheme: ColorScheme.fromSeed(seedColor: AppTheme.primary),
    );
    await tester.pumpWidget(_introPage(originalTheme));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2800));
    final originalName = tester.getRect(find.text('Muvv'));
    final originalLogo = tester.getRect(find.byType(Image));
    await tester.pumpWidget(_introPage(AppTheme.light));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.text('Muvv')), originalName);
    expect(tester.getRect(find.byType(Image)), originalLogo);
    expect(tester.takeException(), isNull);
  });
}
