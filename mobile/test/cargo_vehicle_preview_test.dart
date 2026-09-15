import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muvv_app/screens/client/create_freight_screen.dart';
import 'cargo_vehicle_flow_test.dart' as flow;

const _directory = String.fromEnvironment('MUVV_UI_CAPTURE');

void main() {
  testWidgets('preview the actual request widgets with fictitious data', (tester) async {
    final manifest = jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final entry in manifest) {
      final loader = FontLoader(entry['family'] as String);
      for (final font in entry['fonts'] as List) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
    for (final family in ['Inter', 'Ahem', 'Roboto']) {
      await (FontLoader(family)..addFont(rootBundle.load('assets/fonts/Inter-Variable.ttf'))).load();
    }
    await flow.mount(tester, flow.FakePricingApi());
    Future<void> capture(String name) async {
      await tester.pumpAndSettle();
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.ancestor(of: find.byType(CreateFreightScreen), matching: find.byType(RepaintBoundary)).first);
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(_directory).create(recursive: true);
        await File('$_directory/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await capture('01-route');
    await flow.addCargo(tester);
    await capture('02-cargo');
    await flow.tapText(tester, 'Ver vehículos');
    await capture('03-vehicle');
    await flow.tapText(tester, 'Comparar otras opciones');
    await tester.ensureVisible(find.text('Camión pequeño'));
    await capture('03b-comparison');
    await flow.tapText(tester, 'Elegir horario');
    await capture('04-time');
    await flow.tapText(tester, 'Revisar flete');
    await capture('05-price');
    expect(tester.takeException(), isNull);
  }, skip: _directory.isEmpty);
}
