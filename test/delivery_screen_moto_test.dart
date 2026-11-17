import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/screens/delivery_screen.dart';
import 'package:app_rotas_entregas/services/package_store.dart';

class _DeliveryStore implements PackageStore {
  _DeliveryStore(this.items);
  List<DeliveryPackage> items;

  @override
  Future<void> clear() async {}

  @override
  Future<List<DeliveryPackage>> load() async => [...items];

  @override
  Future<bool> loadRouteOptimized() async => true;

  @override
  Future<void> save(List<DeliveryPackage> value, {bool? routeOptimized}) async {
    items = [...value];
  }
}

DeliveryPackage _package(int n, String street, {String? physicalZone}) => DeliveryPackage(
      id: 'p$n',
      scanNumber: n,
      physicalZone: physicalZone,
      address: AddressData(
        raw: '$street, $n',
        street: street,
        number: '$n',
        city: 'São Paulo',
        state: 'SP',
        confidence: 1,
        validation: ValidationStatus.confirmed,
      ),
      scannedAt: DateTime.utc(2026, 10, 5, 10, n),
    );

Future<AppState> _motoState(List<DeliveryPackage> packages) async {
  final state = AppState(store: _DeliveryStore(packages));
  await state.init();
  await state.setVehicleType(VehicleType.motorcycle);
  return state;
}

void main() {
  setUp(() { SharedPreferences.setMockInitialValues({}); });
  testWidgets('moto highlights the next package number and address', (tester) async {
    // Existing physical zones must be ignored when a route is used in Moto mode.
    final first = _package(7, 'Rua Teste', physicalZone: 'Frente esquerda');
    final second = _package(12, 'Avenida Próxima', physicalZone: 'Porta-malas');
    final state = await _motoState([first, second]);

    await tester.pumpWidget(MaterialApp(home: DeliveryScreen(state: state)));
    await tester.pump();

    expect(find.text('PEGUE ESTE PACOTE'), findsOneWidget);
    expect(find.text(first.label), findsWidgets);
    expect(find.text('Rua Teste, 7, São Paulo, SP'), findsOneWidget);
    expect(find.textContaining('Entrega 1 de 2'), findsOneWidget);
    expect(find.text('Frente esquerda'), findsNothing);
    expect(find.text('Porta-malas'), findsNothing);

    final packageTexts = tester.widgetList<Text>(find.text(first.label));
    expect(packageTexts.any((text) => text.style?.fontSize == 34), isTrue);
  });


  testWidgets('moto shows assigned compartment and package number during delivery', (tester) async {
    final package = _package(7, 'Rua Teste');
    final state = await _motoState([package]);
    await state.setPhysicalZone(package.id, 'Baú traseiro');

    await tester.pumpWidget(MaterialApp(home: DeliveryScreen(state: state)));
    await tester.pump();

    expect(find.text('Baú traseiro'), findsOneWidget);
    expect(find.text(package.label), findsWidgets);
    final compartmentTexts = tester.widgetList<Text>(find.text('Baú traseiro'));
    expect(compartmentTexts.any((text) => text.style?.fontSize == 34), isTrue);
  });

  testWidgets('moto advances to the next package after delivery', (tester) async {
    final first = _package(7, 'Rua Teste');
    final second = _package(12, 'Avenida Próxima');
    final state = await _motoState([first, second]);

    await tester.pumpWidget(MaterialApp(home: DeliveryScreen(state: state)));
    await tester.pump();

    await tester.tap(find.text('ENTREGUE • PRÓXIMO'));
    await tester.pump();
    expect(find.text('Quem recebeu?'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Maria');
    await tester.tap(find.text('Confirmar entrega'));
    await tester.pump();

    expect(find.text('Indo para a próxima entrega…'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.textContaining('Entrega 2 de 2'), findsOneWidget);
    expect(find.text(second.label), findsWidgets);
    expect(find.text('Avenida Próxima, 12, São Paulo, SP'), findsOneWidget);

    final packageTexts = tester.widgetList<Text>(find.text(second.label));
    expect(packageTexts.any((text) => text.style?.fontSize == 34), isTrue);
  });


  testWidgets('delivery screen remains scrollable on a compact phone viewport', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = await _motoState([_package(7, 'Rua Teste')]);
    await tester.pumpWidget(MaterialApp(home: DeliveryScreen(state: state)));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('ENTREGUE • PRÓXIMO'), findsOneWidget);
    await tester.ensureVisible(find.text('ENTREGUE • PRÓXIMO'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('car keeps using the physical loading position', (tester) async {
    final first = _package(7, 'Rua Teste', physicalZone: 'Frente esquerda');
    final second = _package(12, 'Avenida Próxima', physicalZone: 'Frente direita');
    final state = AppState(store: _DeliveryStore([first, second]));
    await state.init();

    await tester.pumpWidget(MaterialApp(home: DeliveryScreen(state: state)));
    await tester.pump();

    expect(find.text('PEGUE ESTE PACOTE'), findsOneWidget);
    expect(find.text('Frente esquerda'), findsOneWidget);
    expect(find.text('Rua Teste, 7, São Paulo, SP'), findsOneWidget);
  });
}
