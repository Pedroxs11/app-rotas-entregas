import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/screens/load_screen.dart';
import 'package:app_rotas_entregas/services/package_store.dart';

class _ConfigurationStore implements PackageStore {
  _ConfigurationStore(this.items);

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

DeliveryPackage _package(int number, {String? zone}) => DeliveryPackage(
      id: 'p$number',
      scanNumber: number,
      physicalZone: zone,
      address: AddressData(
        raw: 'Rua Teste, $number',
        street: 'Rua Teste',
        number: '$number',
        city: 'São Paulo',
        state: 'SP',
        confidence: 1,
        validation: ValidationStatus.confirmed,
      ),
      scannedAt: DateTime.utc(2026, 11, 18, 10, number),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('disabling a car compartment clears its active packages in the UI',
      (tester) async {
    final state = AppState(
      store: _ConfigurationStore([
        _package(1, zone: 'Porta-malas'),
        _package(2, zone: 'Frente esquerda'),
      ]),
    );
    await state.init();

    await tester.pumpWidget(MaterialApp(home: LoadScreen(state: state)));
    await tester.pumpAndSettle();

    expect(find.text('2 de 2 pacotes posicionados'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );

    await tester.tap(find.byTooltip('Configurar compartimentos'));
    await tester.pumpAndSettle();
    expect(find.text('Compartimentos do carro'), findsOneWidget);

    await tester.tap(find.widgetWithText(CheckboxListTile, 'Porta-malas'));
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(state.activePhysicalZones, isNot(contains('Porta-malas')));
    expect(state.packages[0].physicalZone, isNull);
    expect(state.packages[1].physicalZone, 'Frente esquerda');
    expect(find.text('1 de 2 pacotes posicionados'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('motorcycle configuration shows only motorcycle compartments',
      (tester) async {
    final state = AppState(
      store: _ConfigurationStore([_package(7)]),
    );
    await state.init();
    await state.setVehicleType(VehicleType.motorcycle);

    await tester.pumpWidget(MaterialApp(home: LoadScreen(state: state)));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Configurar compartimentos'));
    await tester.pumpAndSettle();

    expect(find.text('Compartimentos da moto'), findsOneWidget);
    expect(find.text('Baú traseiro'), findsOneWidget);
    expect(find.text('Bolsa lateral esquerda'), findsOneWidget);
    expect(find.text('Bolsa lateral direita'), findsOneWidget);
    expect(find.text('Mochila de entrega'), findsOneWidget);
    expect(find.text('Porta-malas'), findsNothing);
    expect(find.text('Frente esquerda'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
