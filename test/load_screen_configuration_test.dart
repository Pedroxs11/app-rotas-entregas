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

  testWidgets('car and motorcycle keep independent compartment preferences',
      (tester) async {
    final state = AppState(
      store: _ConfigurationStore([_package(8)]),
    );
    await state.init();

    await tester.pumpWidget(MaterialApp(home: LoadScreen(state: state)));
    await tester.pumpAndSettle();

    Future<void> keepOnly(List<String> zones, String retainedZone) async {
      await tester.tap(find.byTooltip('Configurar compartimentos'));
      await tester.pumpAndSettle();
      for (final zone in zones.where((zone) => zone != retainedZone)) {
        await tester.tap(find.widgetWithText(CheckboxListTile, zone));
        await tester.pump();
      }
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
    }

    Future<void> selectVehicle(VehicleType vehicle) async {
      await tester.tap(find.byTooltip('Veículo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(
        vehicle == VehicleType.car ? '🚗 Carro' : '🏍️ Moto',
      ));
      await tester.pumpAndSettle();
      expect(state.vehicleType, vehicle);
    }

    await keepOnly(AppState.carPhysicalZones, 'Frente esquerda');
    expect(state.activePhysicalZones, ['Frente esquerda']);

    await selectVehicle(VehicleType.motorcycle);
    await keepOnly(AppState.motorcyclePhysicalZones, 'Baú traseiro');
    expect(state.activePhysicalZones, ['Baú traseiro']);

    await selectVehicle(VehicleType.car);
    expect(state.activePhysicalZones, ['Frente esquerda']);
    await tester.tap(find.byTooltip('Configurar compartimentos'));
    await tester.pumpAndSettle();
    for (final zone in AppState.carPhysicalZones) {
      final tile = tester.widget<CheckboxListTile>(
        find.widgetWithText(CheckboxListTile, zone),
      );
      expect(tile.value, zone == 'Frente esquerda', reason: zone);
    }
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    await selectVehicle(VehicleType.motorcycle);
    expect(state.activePhysicalZones, ['Baú traseiro']);
    await tester.tap(find.byTooltip('Configurar compartimentos'));
    await tester.pumpAndSettle();
    for (final zone in AppState.motorcyclePhysicalZones) {
      final tile = tester.widget<CheckboxListTile>(
        find.widgetWithText(CheckboxListTile, zone),
      );
      expect(tile.value, zone == 'Baú traseiro', reason: zone);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty package search can be cleared in car and motorcycle modes',
      (tester) async {
    for (final vehicle in [VehicleType.car, VehicleType.motorcycle]) {
      SharedPreferences.setMockInitialValues({});
      final state = AppState(
        store: _ConfigurationStore([_package(9)]),
      );
      await state.init();
      if (vehicle == VehicleType.motorcycle) {
        await state.setVehicleType(VehicleType.motorcycle);
      }

      await tester.pumpWidget(MaterialApp(home: LoadScreen(state: state)));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'pacote inexistente');
      await tester.pumpAndSettle();

      expect(
        find.text('Nenhum pacote encontrado para essa busca.'),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('Limpar busca'));
      await tester.pumpAndSettle();

      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
          isEmpty);
      expect(
        find.text('Nenhum pacote encontrado para essa busca.'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });

  testWidgets('motorcycle side bags stay on their configured physical sides',
      (tester) async {
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Future<void> verifySide({
      required String zone,
      required String label,
      required bool isLeft,
    }) async {
      SharedPreferences.setMockInitialValues({});
      final state = AppState(
        store: _ConfigurationStore([_package(10)]),
      );
      await state.init();
      await state.setVehicleType(VehicleType.motorcycle);
      await state.setActivePhysicalZones([zone]);

      await tester.pumpWidget(MaterialApp(home: LoadScreen(state: state)));
      await tester.pumpAndSettle();

      final bagCenter = tester.getCenter(find.text(label));
      final motorcycleCenter = tester.getCenter(find.byIcon(Icons.two_wheeler));
      if (isLeft) {
        expect(bagCenter.dx, lessThan(motorcycleCenter.dx));
      } else {
        expect(bagCenter.dx, greaterThan(motorcycleCenter.dx));
      }
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }

    await verifySide(
      zone: 'Bolsa lateral esquerda',
      label: 'BOLSA ESQUERDA',
      isLeft: true,
    );
    await verifySide(
      zone: 'Bolsa lateral direita',
      label: 'BOLSA DIREITA',
      isLeft: false,
    );
  });
}
