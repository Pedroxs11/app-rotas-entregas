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
  int saves = 0;
  bool failSaves = false;

  @override
  Future<void> clear() async {}

  @override
  Future<List<DeliveryPackage>> load() async => [...items];

  @override
  Future<bool> loadRouteOptimized() async => true;

  @override
  Future<void> save(List<DeliveryPackage> value, {bool? routeOptimized}) async {
    if (failSaves) throw StateError('simulated package store failure');
    items = [...value];
    saves++;
  }
}

DeliveryPackage _package(
  int number, {
  String? zone,
  DeliveryStatus status = DeliveryStatus.pending,
}) => DeliveryPackage(
      id: 'p$number',
      scanNumber: number,
      physicalZone: zone,
      status: status,
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

  test('startup reconciles saved compartments for the selected vehicle', () async {
    SharedPreferences.setMockInitialValues({
      'load_vehicle_type': 'motorcycle',
      'load_zones_motorcycle': [
        'Mochila de entrega',
        'Baú traseiro',
      ],
      'load_zones_car': [
        'Porta-malas',
        'Frente direita',
      ],
    });

    final store = _ConfigurationStore([
      _package(13, zone: 'Porta-malas'),
      _package(14, zone: ' Baú traseiro '),
      _package(
        15,
        zone: 'Porta-malas',
        status: DeliveryStatus.delivered,
      ),
    ]);
    final state = AppState(store: store);
    await state.init();

    expect(state.vehicleType, VehicleType.motorcycle);
    expect(
      state.activePhysicalZones,
      ['Baú traseiro', 'Mochila de entrega'],
    );
    expect(state.packages[0].physicalZone, isNull);
    expect(state.packages[1].physicalZone, 'Baú traseiro');
    expect(state.packages[2].physicalZone, 'Porta-malas');
    expect(store.saves, 1);

    await state.setVehicleType(VehicleType.car);

    expect(
      state.activePhysicalZones,
      ['Frente direita', 'Porta-malas'],
    );
    expect(state.packages[0].physicalZone, isNull);
    expect(state.packages[1].physicalZone, isNull);
    expect(state.packages[2].physicalZone, 'Porta-malas');

    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getStringList('load_zones_car'),
      ['Frente direita', 'Porta-malas'],
    );
  });

  test('startup preserves legacy custom load labels', () async {
    final store = _ConfigurationStore([
      _package(17, zone: 'A-01'),
    ]);
    final state = AppState(store: store);

    await state.init();

    expect(state.packages.single.physicalZone, 'A-01');
    expect(store.saves, 0);
  });

  test('startup clears empty active load labels but preserves delivered history', () async {
    final store = _ConfigurationStore([
      _package(18, zone: '   '),
      _package(19, zone: '  Frente esquerda  '),
      _package(
        20,
        zone: '   ',
        status: DeliveryStatus.delivered,
      ),
    ]);
    final state = AppState(store: store);

    await state.init();

    expect(state.packages[0].physicalZone, isNull);
    expect(state.packages[1].physicalZone, 'Frente esquerda');
    expect(state.packages[2].physicalZone, '   ');
    expect(store.saves, 1);
  });

  test('corrupt saved compartments fall back to the selected vehicle defaults', () async {
    SharedPreferences.setMockInitialValues({
      'load_vehicle_type': 'motorcycle',
      'load_zones_motorcycle': 'invalid preference value',
    });

    final store = _ConfigurationStore([
      _package(16, zone: 'Porta-malas'),
    ]);
    final state = AppState(store: store);
    await state.init();

    expect(state.vehicleType, VehicleType.motorcycle);
    expect(state.activePhysicalZones, AppState.motorcyclePhysicalZones);
    expect(state.packages.single.physicalZone, isNull);
    expect(store.saves, 1);
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getStringList('load_zones_motorcycle'),
      AppState.motorcyclePhysicalZones,
      reason: 'Invalidly typed compartment preferences should be repaired.',
    );
  });

  test('switching vehicles repairs an incorrectly typed compartment preference', () async {
    SharedPreferences.setMockInitialValues({
      'load_vehicle_type': 'car',
      'load_zones_motorcycle': 'invalid preference value',
    });
    final state = AppState(store: _ConfigurationStore([_package(21)]));
    await state.init();

    await state.setVehicleType(VehicleType.motorcycle);

    expect(state.activePhysicalZones, AppState.motorcyclePhysicalZones);
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getStringList('load_zones_motorcycle'),
      AppState.motorcyclePhysicalZones,
    );
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
  testWidgets('car seats stay on their configured physical sides when only one is enabled',
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
      await state.setActivePhysicalZones([zone]);

      await tester.pumpWidget(MaterialApp(home: LoadScreen(state: state)));
      await tester.pumpAndSettle();

      final seatCenter = tester.getCenter(find.text(label));
      final vehicleCenter = tester.getCenter(find.text('FRENTE'));
      if (isLeft) {
        expect(seatCenter.dx, lessThan(vehicleCenter.dx));
      } else {
        expect(seatCenter.dx, greaterThan(vehicleCenter.dx));
      }
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }

    await verifySide(
      zone: 'Frente esquerda',
      label: 'FRENTE E',
      isLeft: true,
    );
    await verifySide(
      zone: 'Frente direita',
      label: 'FRENTE D',
      isLeft: false,
    );
    await verifySide(
      zone: 'Traseira esquerda',
      label: 'TRASEIRA E',
      isLeft: true,
    );
    await verifySide(
      zone: 'Traseira direita',
      label: 'TRASEIRA D',
      isLeft: false,
    );
  });

  test('switching vehicles clears active positions but preserves delivered history',
      () async {
    final state = AppState(
      store: _ConfigurationStore([
        _package(11, zone: 'Porta-malas'),
        _package(
          12,
          zone: 'Porta-malas',
          status: DeliveryStatus.delivered,
        ),
      ]),
    );
    await state.init();

    await state.setVehicleType(VehicleType.motorcycle);

    expect(state.packages, hasLength(2));
    expect(state.packages[0].status, DeliveryStatus.pending);
    expect(state.packages[0].physicalZone, isNull);
    expect(state.packages[1].status, DeliveryStatus.delivered);
    expect(state.packages[1].physicalZone, 'Porta-malas');
    expect(state.activePhysicalZones, AppState.motorcyclePhysicalZones);

    await state.setVehicleType(VehicleType.car);

    expect(state.packages, hasLength(2));
    expect(state.packages[0].physicalZone, isNull);
    expect(state.packages[1].physicalZone, 'Porta-malas');
    expect(state.activePhysicalZones, AppState.carPhysicalZones);
  });

  test('compartment changes roll back in-memory state and preferences when package persistence fails',
      () async {
    SharedPreferences.setMockInitialValues({
      'load_vehicle_type': 'car',
      'load_zones_car': ['Frente esquerda', 'Porta-malas'],
    });
    final store = _ConfigurationStore([
      _package(30, zone: 'Porta-malas'),
    ])..failSaves = true;
    final state = AppState(store: store);
    await state.init();
    final preferences = await SharedPreferences.getInstance();

    await expectLater(
      state.setActivePhysicalZones(['Frente esquerda']),
      throwsA(isA<StateError>()),
    );

    expect(state.activePhysicalZones, ['Frente esquerda', 'Porta-malas']);
    expect(state.packages.single.physicalZone, 'Porta-malas');
    expect(store.items.single.physicalZone, 'Porta-malas');
    expect(
      preferences.getStringList('load_zones_car'),
      ['Frente esquerda', 'Porta-malas'],
    );
    expect(store.saves, 0);
  });

  test('vehicle switch rolls back vehicle, compartments and packages when persistence fails',
      () async {
    SharedPreferences.setMockInitialValues({
      'load_vehicle_type': 'car',
      'load_zones_car': ['Frente esquerda', 'Porta-malas'],
      'load_zones_motorcycle': ['Baú traseiro', 'Mochila de entrega'],
    });
    final store = _ConfigurationStore([
      _package(31, zone: 'Porta-malas'),
    ])..failSaves = true;
    final state = AppState(store: store);
    await state.init();
    final preferences = await SharedPreferences.getInstance();

    await expectLater(
      state.setVehicleType(VehicleType.motorcycle),
      throwsA(isA<StateError>()),
    );

    expect(state.vehicleType, VehicleType.car);
    expect(state.activePhysicalZones, ['Frente esquerda', 'Porta-malas']);
    expect(state.packages.single.physicalZone, 'Porta-malas');
    expect(store.items.single.physicalZone, 'Porta-malas');
    expect(preferences.getString('load_vehicle_type'), 'car');
    expect(
      preferences.getStringList('load_zones_motorcycle'),
      ['Baú traseiro', 'Mochila de entrega'],
    );
    expect(store.saves, 0);
  });


  testWidgets(
      'vehicle switch storage failure shows feedback and keeps the previous vehicle',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'load_vehicle_type': 'car',
      'load_zones_car': ['Frente esquerda', 'Porta-malas'],
      'load_zones_motorcycle': ['Baú traseiro', 'Mochila de entrega'],
    });
    final store = _ConfigurationStore([
      _package(32, zone: 'Porta-malas'),
    ])..failSaves = true;
    final state = AppState(store: store);
    await state.init();
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(MaterialApp(home: LoadScreen(state: state)));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Veículo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('🏍️ Moto'));
    await tester.pumpAndSettle();

    expect(state.vehicleType, VehicleType.car);
    expect(state.activePhysicalZones, ['Frente esquerda', 'Porta-malas']);
    expect(state.packages.single.physicalZone, 'Porta-malas');
    expect(preferences.getString('load_vehicle_type'), 'car');
    expect(find.text('Organizar o carro'), findsOneWidget);
    expect(find.textContaining('Não foi possível trocar o veículo:'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });


  testWidgets(
      'configuration cannot save when every car compartment is disabled',
      (tester) async {
    final state = AppState(
      store: _ConfigurationStore([
        _package(33, zone: 'Porta-malas'),
      ]),
    );
    await state.init();
    final originalZones = [...state.activePhysicalZones];

    await tester.pumpWidget(MaterialApp(home: LoadScreen(state: state)));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Configurar compartimentos'));
    await tester.pumpAndSettle();

    for (final zone in AppState.carPhysicalZones) {
      await tester.tap(find.widgetWithText(CheckboxListTile, zone));
      await tester.pump();
    }

    final saveButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Salvar'),
    );
    expect(saveButton.onPressed, isNull);
    expect(state.activePhysicalZones, originalZones);
    expect(state.packages.single.physicalZone, 'Porta-malas');

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(state.activePhysicalZones, originalZones);
    expect(state.packages.single.physicalZone, 'Porta-malas');
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });


  testWidgets(
      'configuration cannot save when every motorcycle compartment is disabled',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'load_vehicle_type': 'motorcycle',
      'load_zones_motorcycle': ['Baú traseiro', 'Mochila de entrega'],
    });
    final state = AppState(
      store: _ConfigurationStore([
        _package(34, zone: 'Baú traseiro'),
      ]),
    );
    await state.init();
    final originalZones = [...state.activePhysicalZones];
    final preferences = await SharedPreferences.getInstance();

    expect(state.vehicleType, VehicleType.motorcycle);
    expect(originalZones, ['Baú traseiro', 'Mochila de entrega']);

    await tester.pumpWidget(MaterialApp(home: LoadScreen(state: state)));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Configurar compartimentos'));
    await tester.pumpAndSettle();

    for (final zone in originalZones) {
      await tester.tap(find.widgetWithText(CheckboxListTile, zone));
      await tester.pump();
    }

    final saveButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Salvar'),
    );
    expect(saveButton.onPressed, isNull);
    expect(state.activePhysicalZones, originalZones);
    expect(state.packages.single.physicalZone, 'Baú traseiro');
    expect(
      preferences.getStringList('load_zones_motorcycle'),
      originalZones,
    );

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(state.activePhysicalZones, originalZones);
    expect(state.packages.single.physicalZone, 'Baú traseiro');
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

}
