import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muvv_app/models/freight_model.dart';
import 'package:muvv_app/services/api_service.dart';
import 'package:muvv_app/services/freight_service.dart';
import 'package:muvv_app/widgets/freight_cargo_safety_notice.dart';

Map<String, dynamic> _json(String service) => {
      'id': 109,
      'client_id': 1,
      'origin_address': 'Origen',
      'destination_address': 'Destino',
      'cargo_description': 'Lavadora de prueba',
      'cargo_weight_kg': 80,
      'service_type': service,
      'status': 'pending',
      'created_at': '2026-09-15T12:00:00Z',
    };

class _Api implements ApiService {
  final bodies = <Map<String, dynamic>?>[];

  @override
  Future<Response<dynamic>> put(String path,
      [Map<String, dynamic>? data]) async {
    bodies.add(data);
    return Response(
      data: _json('home_office'),
      requestOptions: RequestOptions(path: path),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final cancel in [true, false]) {
    testWidgets('warning gates acceptance (cancel=$cancel)', (tester) async {
      final api = _Api();
      final service = FreightService(api: api);
      final freight = FreightModel.fromJson(_json('home_office'));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Builder(builder: (context) {
          return FilledButton(
            onPressed: () async {
              if (await confirmFreightCargoSafety(context, freight)) {
                await service.acceptFreight(freight.id,
                    cargoSafetyAcknowledged: needsCargoSafetyNotice(freight));
              }
            },
            child: const Text('Aceptar flete'),
          );
        })),
      ));
      await tester.tap(find.text('Aceptar flete'));
      await tester.pumpAndSettle();
      expect(api.bodies, isEmpty);
      expect(find.text('Antes de aceptar'), findsOneWidget);
      expect(find.textContaining('caja abierta'), findsOneWidget);
      await tester.tap(find.text(cancel ? 'Volver' : 'Entendido, continuar'));
      await tester.pumpAndSettle();
      expect(
          api.bodies,
          cancel
              ? isEmpty
              : equals([
                  {'cargo_safety_acknowledged': true}
                ]));
    });
  }

  test('acceptance never sends acknowledgement by default', () async {
    final api = _Api();
    await FreightService(api: api).acceptFreight(109);
    expect(api.bodies, [null]);
    for (final kind in ['package', 'urgent', 'moving']) {
      expect(
          needsCargoSafetyNotice(FreightModel.fromJson(_json(kind))), isFalse);
    }
  });

  testWidgets('dismissing the warning does not confirm it', (tester) async {
    bool? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) {
        return TextButton(
          onPressed: () async => result = await confirmFreightCargoSafety(
              context, FreightModel.fromJson(_json('home_office'))),
          child: const Text('Abrir'),
        );
      })),
    ));
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  testWidgets('warning fits a small screen with enlarged text', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
      home: Scaffold(body: Builder(builder: (context) {
        return TextButton(
          onPressed: () => confirmFreightCargoSafety(
              context, FreightModel.fromJson(_json('home_office'))),
          child: const Text('Abrir'),
        );
      })),
    ));
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Entendido, continuar'), findsOneWidget);
    expect(tester.getRect(find.text('Entendido, continuar')).bottom,
        lessThanOrEqualTo(640));
  });
}
