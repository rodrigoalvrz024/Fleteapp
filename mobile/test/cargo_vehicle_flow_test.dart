import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:muvv_app/core/theme/app_theme.dart';
import 'package:muvv_app/models/cargo_guidance.dart';
import 'package:muvv_app/models/user_model.dart';
import 'package:muvv_app/providers/auth_provider.dart';
import 'package:muvv_app/screens/client/create_freight_screen.dart';
import 'package:muvv_app/screens/client/widgets/cargo_vehicle_widgets.dart';
import 'package:muvv_app/services/api_service.dart';
import 'package:muvv_app/widgets/muvv_mobile_ui.dart';

class FakePricingApi implements ApiService {
  final List<Map<String, dynamic>> estimates = [];
  Map<String, dynamic>? created;
  bool manual = false;
  bool fail = false;
  Completer<Response>? pending;

  @override
  Future<Response> post(String path, Map<String, dynamic> data) async {
    if (path.contains('pricing')) {
      estimates.add(Map.of(data));
      if (pending != null) return pending!.future;
      if (fail) throw DioException(requestOptions: RequestOptions(path: path));
      return estimateResponse(data);
    }
    created = Map.of(data);
    return Response(requestOptions: RequestOptions(path: path), data: {
      ...data,
      'id': 999,
      'client_id': 1,
      'status': 'pending',
      'created_at': '2026-09-14T12:00:00Z',
    });
  }

  Response estimateResponse(Map<String, dynamic> data) => Response(
          requestOptions: RequestOptions(path: '/pricing/estimate'),
          data: {
            'requires_manual_quote': manual,
            'recommended_vehicle_type': 'van',
            'recommended_vehicle_name': 'Furgon',
            'selected_vehicle_type':
                manual ? null : data['requested_vehicle_type'] ?? 'van',
            'customer_price':
                data['requested_vehicle_type'] == 'truck_small' ? 42000 : 31000,
            'quote_id': manual ? null : 'test-quote-${estimates.length}',
          });

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ClientAuth extends AuthNotifier {
  _ClientAuth() {
    state = AuthState(
        user: UserModel(
            id: 1,
            email: 'test@example.com',
            phone: '',
            fullName: 'Test',
            role: 'client',
            roles: ['client'],
            isActive: true));
  }
}

Future<void> mount(WidgetTester tester, FakePricingApi api,
    {Size size = const Size(393, 852), double scale = 1}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(initialLocation: '/create', routes: [
    GoRoute(
        path: '/create',
        builder: (_, __) => CreateFreightScreen(
            api: api,
            originAddress: 'Origen de prueba',
            originLat: -33.4,
            originLng: -70.6,
            destAddress: 'Destino de prueba',
            destLat: -33.5,
            destLng: -70.7,
            initialServiceType: 'Hogar u oficina',
            initialUrgent: true)),
    GoRoute(
        path: '/app/client/freights/999',
        builder: (_, __) => const Scaffold(body: Text('Solicitud de prueba'))),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
      overrides: [
        authProvider.overrideWith((_) => _ClientAuth()),
      ],
      child: MaterialApp.router(
          theme: AppTheme.light,
          routerConfig: router,
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(scale),
                  disableAnimations: scale > 1),
              child: child!))));
  await tester.pumpAndSettle();
}

Future<void> tapText(WidgetTester tester, String text) async {
  final finder = find.text(text).last;
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> addCargo(WidgetTester tester) async {
  await tapText(tester, 'Continuar');
  await tapText(tester, 'Agregar objetos');
  await tester.ensureVisible(find.byTooltip('Agregar Lavadora'));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Agregar Lavadora'));
  await tester.pump();
  await tapText(tester, 'Guardar objetos');
}

void main() {
  test(
      'inventory totals are explicit planning estimates and quantities bounded',
      () {
    final load = CargoInventory({'washer': 1, 'box': 2, 'unknown': 40});
    expect(load.weightKg, 110);
    expect(load.volumeM3, 1.1);
    expect(load.summary, contains('1 x Lavadora'));
    expect(CargoInventory({'box': 99}).quantities['box'], 30);
    expect(CargoInventory({'box': -1}).isEmpty, isTrue);
  });

  test('only server recommendation or larger known classes are candidates', () {
    expect(isVehicleCandidate('pickup', 'van'), isFalse);
    expect(isVehicleCandidate('truck_small', 'van'), isTrue);
    expect(isVehicleCandidate('pickup', null), isFalse);
    expect(isVehicleCandidate('car', 'pickup'), isFalse);
    final knownItems = cargoReferenceItems.map((item) => item.id).toSet();
    expect(freightVehicleGuides.map((guide) => guide.cargoLabel).toSet().length, 5);
    for (final guide in freightVehicleGuides) {
      expect(guide.exampleItems, isNotEmpty);
      expect(guide.exampleItems.every(knownItems.contains), isTrue);
    }
  });

  testWidgets(
      'objects -> vehicle -> time -> price preserves chosen category and quote',
      (tester) async {
    final api = FakePricingApi();
    await mount(tester, api);
    await addCargo(tester);
    await tapText(tester, 'Ver vehículos');
    expect(api.estimates.single['cargo_weight_kg'], 80);
    expect(api.estimates.single['cargo_volume_m3'], 0.8);
    expect(api.estimates.single['cargo_description'], contains('Lavadora'));
    expect(find.text('El espacio que necesitas'), findsOneWidget);
    final recommended =
        tester.widget<FreightVehicleChoice>(find.byType(FreightVehicleChoice));
    expect(recommended.recommended, isTrue);
    expect(recommended.selected, isTrue);
    expect(find.text('Cajas y muebles pequeños'), findsOneWidget);
    await tapText(tester, 'Comparar otras opciones');
    final pickup = tester.widget<FreightVehicleChoice>(find.byWidgetPredicate(
        (w) => w is FreightVehicleChoice && w.guide.type == 'pickup'));
    expect(pickup.enabled, isFalse);
    expect(find.text('Muebles y cajas'), findsOneWidget);
    await tapText(tester, 'Camión pequeño');
    expect(api.estimates.last['requested_vehicle_type'], 'truck_small');
    await tapText(tester, 'Elegir horario');
    await tapText(tester, 'Revisar flete');
    expect(find.text('Revisa tu flete'), findsOneWidget);
    await tapText(tester, 'Solicitar flete');
    expect(api.created!['requested_vehicle_type'], 'truck_small');
    expect(api.created!['quote_id'], 'test-quote-3');
    expect(api.created!['cargo_description'],
        api.estimates.last['cargo_description']);
    expect(api.created!.containsKey('customer_price'), isFalse);
    expect(find.text('Solicitud de prueba'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('customer can keep recommendation without comparing vehicles',
      (tester) async {
    final api = FakePricingApi();
    await mount(tester, api);
    await addCargo(tester);
    await tapText(tester, 'Ver vehículos');
    expect(find.byType(FreightVehicleChoice), findsOneWidget);
    await tapText(tester, 'Elegir horario');
    await tapText(tester, 'Revisar flete');
    expect(api.estimates.last['requested_vehicle_type'], isNull);
    expect(find.text('Revisa tu flete'), findsOneWidget);
    expect(api.created, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('manual review cannot submit an automatic freight',
      (tester) async {
    final api = FakePricingApi()..manual = true;
    await mount(tester, api);
    await addCargo(tester);
    await tapText(tester, 'Ver vehículos');
    final button =
        tester.widget<MuvvGradientButton>(find.byType(MuvvGradientButton).last);
    expect(button.onPressed, isNull);
    expect(api.created, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('old quote cannot restore price after cargo changes',
      (tester) async {
    final api = FakePricingApi()..pending = Completer<Response>();
    await mount(tester, api);
    await addCargo(tester);
    await tester.tap(find.text('Ver vehículos'));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.byTooltip('Paso anterior'));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.ensureVisible(find.byType(TextFormField).first);
    await tester.enterText(find.byType(TextFormField).first, 'Otra carga');
    api.pending!.complete(api.estimateResponse(api.estimates.first));
    await tester.pumpAndSettle();
    api.pending = null;
    await tapText(tester, 'Ver vehículos');
    expect(api.estimates.length, 2);
    expect(api.estimates.last['cargo_description'], contains('Otra carga'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('vehicle descriptions fit large text on a narrow screen',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
                body: SingleChildScrollView(
                    child: SizedBox(
                        width: 320,
                        child: FreightVehicleChoice(
                            guide: freightVehicleGuides[3],
                            selected: true,
                            recommended: true,
                            enabled: true,
                            price: r'$54.000 CLP estimados',
                            onTap: () {})))))));
    expect(tester.takeException(), isNull);
  });

  testWidgets('all request steps support a small phone with enlarged text',
      (tester) async {
    final api = FakePricingApi();
    await mount(tester, api, size: const Size(320, 640), scale: 1.6);
    await addCargo(tester);
    expect(tester.takeException(), isNull);
    await tapText(tester, 'Ver vehículos');
    expect(tester.takeException(), isNull);
    await tapText(tester, 'Elegir horario');
    expect(tester.takeException(), isNull);
    await tapText(tester, 'Revisar flete');
    expect(tester.takeException(), isNull);
  });
}
