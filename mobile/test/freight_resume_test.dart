import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:muvv_app/models/freight_model.dart';
import 'package:muvv_app/screens/client/freight_detail_screen.dart';
import 'package:muvv_app/services/api_service.dart';
import 'package:muvv_app/services/freight_service.dart';

Map<String, dynamic> _json({String payment = 'pending'}) => {
      'id': 109,
      'client_id': 1,
      'origin_address': 'Origen de prueba',
      'destination_address': 'Destino de prueba',
      'cargo_description': 'Carga de prueba',
      'cargo_weight_kg': 80,
      'status': 'pending',
      'created_at': '2026-09-16T00:05:00Z',
      'scheduled_at': '2026-09-17T13:00:00Z',
      'payment_status': payment,
    };

class _Freights extends FreightService {
  final pending = <Completer<FreightModel>>[];

  @override
  Future<FreightModel> getFreight(int id) {
    final request = Completer<FreightModel>();
    pending.add(request);
    return request.future;
  }
}

class _Api implements ApiService {
  Map<String, dynamic>? body;

  @override
  Future<Response<dynamic>> post(String path, Map<String, dynamic> data) async {
    body = data;
    return Response(data: _json(), requestOptions: RequestOptions(path: path));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() => initializeDateFormatting('es_CL'));

  test('API dates become local without changing their instant', () {
    for (final date in [
      '2026-09-17T13:00:00Z',
      '2026-09-17T10:00:00-03:00',
      '2026-07-17T09:00:00-04:00',
    ]) {
      final freight = FreightModel.fromJson({
        ..._json(),
        'created_at': date,
        'scheduled_at': date,
      });
      expect(freight.scheduledAt!.isUtc, isFalse);
      expect(freight.createdAt.isUtc, isFalse);
      expect(freight.scheduledAt, DateTime.parse(date).toLocal());
      expect(freight.createdAt.toUtc(), DateTime.parse(date).toUtc());
    }
  });

  test('an urgent freight can omit its schedule', () {
    expect(
      FreightModel.fromJson({..._json(), 'scheduled_at': null}).scheduledAt,
      isNull,
    );
  });

  test('creating a freight always sends an explicit UTC schedule', () async {
    final api = _Api();
    final localDate = DateTime(2026, 9, 17, 10);
    await FreightService(api: api).createFreight(
      originAddress: 'Origen de prueba',
      originLat: -33.4,
      originLng: -70.6,
      destinationAddress: 'Destino de prueba',
      destinationLat: -33.5,
      destinationLng: -70.5,
      cargoDescription: 'Prueba',
      cargoWeightKg: 80,
      scheduledAt: localDate,
    );
    expect(api.body!['scheduled_at'], localDate.toUtc().toIso8601String());
    expect(api.body!['scheduled_at'], endsWith('Z'));
  });

  Future<_Freights> mount(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final service = _Freights();
    await tester.pumpWidget(MaterialApp(
      home: FreightDetailScreen(freightId: 109, freightService: service),
    ));
    return service;
  }

  Future<void> resume(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
  }

  testWidgets('returning from checkout reloads the backend payment state',
      (tester) async {
    final service = await mount(tester);
    service.pending.first.complete(FreightModel.fromJson(_json()));
    await tester.pumpAndSettle();
    expect(find.text('Confirmar pago con Webpay'), findsOneWidget);
    await resume(tester);
    expect(service.pending, hasLength(2));
    service.pending.last.complete(
      FreightModel.fromJson(_json(payment: 'authorized')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Confirmado y resguardado'), findsOneWidget);
    expect(find.text('Confirmar pago con Webpay'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await resume(tester);
    expect(service.pending, hasLength(2));
  });

  testWidgets('a pre-checkout response cannot overwrite the refreshed payment',
      (tester) async {
    final service = await mount(tester);
    await resume(tester);
    service.pending.last.complete(
      FreightModel.fromJson(_json(payment: 'authorized')),
    );
    await tester.pumpAndSettle();
    service.pending.first.complete(FreightModel.fromJson(_json()));
    await tester.pumpAndSettle();
    expect(find.text('Confirmado y resguardado'), findsOneWidget);
    expect(find.text('Confirmar pago con Webpay'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('failed refresh never invents an authorized payment',
      (tester) async {
    final service = await mount(tester);
    service.pending.first.complete(FreightModel.fromJson(_json()));
    await tester.pumpAndSettle();
    await resume(tester);
    service.pending.last.completeError(Exception('Offline test'));
    await tester.pumpAndSettle();
    expect(find.text('Confirmado y resguardado'), findsNothing);
    expect(find.text('Confirmar pago con Webpay'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
