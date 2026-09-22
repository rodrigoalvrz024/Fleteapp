import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:muvv_app/models/freight_model.dart';
import 'package:muvv_app/providers/driver_provider.dart';
import 'package:muvv_app/screens/driver/available_freights_screen.dart';
import 'package:muvv_app/screens/driver/driver_freight_detail_screen.dart';
import 'package:muvv_app/services/freight_service.dart';
import 'package:muvv_app/widgets/driver_offer_guard.dart';

FreightModel offer(int id) => FreightModel.fromJson({
      'id': id,
      'client_id': 1,
      'origin_address': 'Test origin $id',
      'destination_address': 'Test destination',
      'cargo_description': 'Boxes',
      'cargo_weight_kg': 40,
      'service_type': 'home_office',
      'status': 'pending',
      'created_at': '2026-09-22T12:00:00Z',
      'scheduled_at': '2026-09-23T12:00:00Z',
      'payment_status': 'authorized',
    });

class Offers extends FreightService {
  final requests = <Completer<List<FreightModel>>>[];
  final details = <Completer<FreightModel>>[];

  @override
  Future<FreightModel> getFreight(int id) {
    final request = Completer<FreightModel>();
    details.add(request);
    return request.future;
  }

  @override
  Future<List<FreightModel>> listFreights({String? status}) {
    final request = Completer<List<FreightModel>>();
    requests.add(request);
    return request.future;
  }
}

class Driver extends DriverNotifier {
  Driver(Offers service) : super(freightService: service);

  void online() => state = state.copyWith(isOnline: true);
  void offline() =>
      state = state.copyWith(isOnline: false, clearIncoming: true);
  void incoming(int? id) => state = state.copyWith(
        isOnline: true,
        incomingFreight: id == null ? null : offer(id),
        clearIncoming: id == null,
      );
}

void main() {
  setUpAll(() => initializeDateFormatting('es_CL'));

  test('refresh removes withdrawn offer and advances to next available',
      () async {
    final service = Offers();
    final driver = Driver(service)..online();
    addTearDown(driver.dispose);
    var refresh = driver.refreshFreights();
    service.requests.last.complete([offer(1), offer(2)]);
    await refresh;
    expect(driver.state.incomingFreight?.id, 1);
    refresh = driver.refreshFreights();
    service.requests.last.complete([offer(2)]);
    await refresh;
    expect(driver.state.incomingFreight?.id, 2);
    refresh = driver.refreshFreights();
    service.requests.last.complete([]);
    await refresh;
    expect(driver.state.incomingFreight, isNull);
    expect(driver.state.availableFreights, isEmpty);
  });

  test('no duplicate requests or duplicate alert for dismissed offer',
      () async {
    final service = Offers();
    final driver = Driver(service)..online();
    addTearDown(driver.dispose);
    var refresh = driver.refreshFreights();
    await driver.refreshFreights();
    expect(service.requests.length, 1);
    service.requests.last.complete([offer(1)]);
    await refresh;
    driver.dismissIncoming();
    refresh = driver.refreshFreights();
    service.requests.last.complete([offer(1)]);
    await refresh;
    expect(driver.state.availableFreights, hasLength(1));
    expect(driver.state.incomingFreight, isNull);
  });

  test('connection failure withdraws actionable offer and allows recovery',
      () async {
    final service = Offers();
    final driver = Driver(service)..online();
    addTearDown(driver.dispose);
    var refresh = driver.refreshFreights();
    service.requests.last.complete([offer(1)]);
    await refresh;
    refresh = driver.refreshFreights();
    service.requests.last.completeError(Exception('offline'));
    await refresh;
    expect(driver.state.incomingFreight, isNull);
    expect(driver.state.availableFreights, isEmpty);
    refresh = driver.refreshFreights();
    service.requests.last.complete([offer(1)]);
    await refresh;
    expect(driver.state.incomingFreight?.id, 1);
  });

  test('response after going offline or disposal cannot restore an offer',
      () async {
    for (final disposed in [false, true]) {
      final service = Offers();
      final driver = Driver(service)..online();
      final refresh = driver.refreshFreights();
      if (disposed) {
        driver.dispose();
      } else {
        driver.offline();
      }
      service.requests.last.complete([offer(1)]);
      await refresh;
      if (!disposed) {
        expect(driver.state.incomingFreight, isNull);
        driver.dispose();
      }
    }
  });

  Future<(Driver, GlobalKey<NavigatorState>)> mountGuard(
      WidgetTester tester) async {
    final driver = Driver(Offers())..incoming(1);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(ProviderScope(
      overrides: [driverProvider.overrideWith((ref) => driver)],
      child: MaterialApp(
        navigatorKey: navigator,
        home: Builder(
            builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => const DriverOfferGuard(
                            freightId: 1,
                            child: AlertDialog(content: Text('Offer 1')))),
                    child: const Text('Open'),
                  ),
                )),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    return (driver, navigator);
  }

  testWidgets('withdrawn dialog closes automatically', (tester) async {
    final (driver, _) = await mountGuard(tester);
    expect(find.text('Offer 1'), findsOneWidget);
    driver.incoming(null);
    await tester.pumpAndSettle();
    expect(find.text('Offer 1'), findsNothing);
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('withdrawal never pops a newer route above the offer',
      (tester) async {
    final (driver, navigator) = await mountGuard(tester);
    unawaited(navigator.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('Another screen')),
    )));
    await tester.pumpAndSettle();
    driver.incoming(null);
    await tester.pumpAndSettle();
    expect(find.text('Another screen'), findsOneWidget);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Offer 1'), findsNothing);
  });

  testWidgets(
      'available list refreshes, removes old offers and pauses in background',
      (tester) async {
    final service = Offers();
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
        MaterialApp(home: AvailableFreightsScreen(freightService: service)));
    service.requests.first.complete([offer(1)]);
    await tester.pumpAndSettle();
    expect(find.text('Test origin 1'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    service.requests.last.complete([]);
    await tester.pumpAndSettle();
    expect(find.text('Test origin 1'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    final count = service.requests.length;
    await tester.pump(const Duration(seconds: 10));
    expect(service.requests.length, count);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(service.requests.length, count + 1);
    service.requests.last.complete([]);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  Future<Offers> mountDetail(WidgetTester tester) async {
    final service = Offers();
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home:
            DriverFreightDetailScreen(freightId: 1, freightService: service)));
    service.details.first.complete(offer(1));
    await tester.pumpAndSettle();
    return service;
  }

  testWidgets(
      'detail hides failed offer and automatically recovers after a transient error',
      (tester) async {
    final service = await mountDetail(tester);
    expect(find.text('Aceptar flete'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    service.details.last.completeError(Exception('offline'));
    await tester.pumpAndSettle();
    expect(find.text('Aceptar flete'), findsNothing);
    expect(find.text('Actualizar'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    expect(service.details, hasLength(3));
    service.details.last.complete(offer(1));
    await tester.pumpAndSettle();
    expect(find.text('Aceptar flete'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'definitive withdrawal removes acceptance and stops background retries',
      (tester) async {
    final service = await mountDetail(tester);
    await tester.pump(const Duration(seconds: 5));
    final options = RequestOptions(path: '/freights/1');
    service.details.last.completeError(DioException(
      requestOptions: options,
      response: Response(requestOptions: options, statusCode: 403),
      type: DioExceptionType.badResponse,
    ));
    await tester.pumpAndSettle();
    expect(find.text('Aceptar flete'), findsNothing);
    await tester.pump(const Duration(seconds: 10));
    expect(service.details, hasLength(2));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'cancelling safety confirmation never leaves pending refresh locked',
      (tester) async {
    final service = await mountDetail(tester);
    await tester.pump(const Duration(seconds: 5));
    final oldRequest = service.details.last;
    await tester.ensureVisible(find.text('Aceptar flete'));
    await tester.tap(find.text('Aceptar flete'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Volver'));
    await tester.pumpAndSettle();
    final options = RequestOptions(path: '/freights/1');
    oldRequest.completeError(DioException(
      requestOptions: options,
      response: Response(requestOptions: options, statusCode: 403),
      type: DioExceptionType.badResponse,
    ));
    await tester.pumpAndSettle();
    expect(find.text('Aceptar flete'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    expect(service.details, hasLength(3));
    service.details.last.complete(offer(1));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
