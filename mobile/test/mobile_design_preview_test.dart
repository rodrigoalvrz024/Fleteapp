import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muvv_app/core/theme/app_theme.dart';
import 'package:muvv_app/screens/auth/forgot_password_screen.dart';
import 'package:muvv_app/screens/shared/mobile_utility_screens.dart';

// Optional real-widget previews, never screenshots of customer data.
const _captureDirectory = String.fromEnvironment('MUVV_UI_CAPTURE');

void main() {
  testWidgets('render mobile design previews', (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final entry in manifest) {
      final fonts = FontLoader(entry['family'] as String);
      for (final font in entry['fonts'] as List) {
        fonts.addFont(rootBundle.load(font['asset'] as String));
      }
      await fonts.load();
    }
    // Flutter tests replace unspecified platform fonts with Ahem squares.
    final fallback = FontLoader('Ahem')
      ..addFont(rootBundle.load('assets/fonts/Inter-Variable.ttf'));
    await fallback.load();
    final pages = <String, Widget>{
      for (final page in MuvvUtilityPage.values)
        page.name: MuvvUtilityScreen(key: ValueKey(page), page: page),
      'client-profile': const MuvvAccountHubScreen(),
      'driver-profile': const MuvvAccountHubScreen(driver: true),
      'recovery': const ForgotPasswordScreen(),
    };
    for (final entry in pages.entries) {
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(ProviderScope(
          child: RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            home: entry.value),
      )));
      await tester.pumpAndSettle();
      if (entry.key == 'recovery') {
        await tester.runAsync(() => precacheImage(
              const AssetImage('assets/branding/muvv-app-icon.png'),
              tester.element(find.byType(ForgotPasswordScreen)),
            ));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull, reason: entry.key);
      await tester.runAsync(() async {
        final boundary = boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final directory =
            await Directory(_captureDirectory).create(recursive: true);
        await File('${directory.path}/${entry.key}.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
  }, skip: _captureDirectory.isEmpty);
}
