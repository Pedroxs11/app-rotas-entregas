import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/screens/load_screen.dart';
import 'package:app_rotas_entregas/services/package_store.dart';

class _PersistentLoadStore implements PackageStore {
  _PersistentLoadStore(this.items);

  List<DeliveryPackage> items;
  int saves = 0;

  @override
  Future<void> clear() async {
    items = [];
  }

  @override
  Future<List<DeliveryPackage>> load() async => [...items];

  @override
  Future<bool> loadRouteOptimized() async => true;

  @override
  Future<void> save(
    List<DeliveryPackage> value, {
    bool? routeOptimized,
  }) async {
    items = [...value];
    saves++;
  }
}

DeliveryPackage _package(
  String id,
  int scanNumber, {
  String? zone,
  DeliveryStatus status = DeliveryStatus.pending,
}) =>
    DeliveryPackage(
      id: id,
      scanNumber: scanNumber,
      physicalZone: zone,
      status: status,
      address: AddressData(
        raw: 'Rua Teste, $scanNumber',
        street: 'Rua Teste',
        number: '$scanNumber',
        city: 'São Paulo',
        state: 'SP',
        confidence: 1,
        validation: ValidationStatus.confirmed,
      ),
      scannedAt: DateTime.utc(2026, 11, 20, 11, scanNumber),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'car and motorcycle layouts survive repeated UI switches and app restart',
    (tester) async {
      final store = _PersistentLoadStore([
        _package('active-1', 1, zone: 'Porta-malas'),
        _package('active-2', 2),
        _package(
          'delivered',
          3,
          zone: 'Porta-malas',
          status: DeliveryStatus.delivered,
        ),
      ]);
      final state = AppState(store: store);
      await state.init();

      await tester.pumpWidget(MaterialApp(home: LoadScreen(state: state)));
      await tester.pumpAndSettle();

      Future<void> configureOnly(
        List<String> zones,
        String retainedZone,
      ) async {
        await tester.tap(find.byTooltip('Configurar compartimentos'));
        await tester.pumpAndSettle();
        for (final zone in zones.where((zone) => zone != retainedZone)) {
          await tester.tap(find.widgetWithText(CheckboxListTile, zone));
          await tester.pump();
        }
        await tester.tap(find.text('Salvar'));
        await tester.pumpAndSettle();
        expect(state.activePhysicalZones, [retainedZone]);
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

      await configureOnly(AppState.carPhysicalZones, 'Porta-malas');
      await state.setPhysicalZone('active-2', 'Porta-malas');
      expect(
        state.packages.take(2).every((package) => package.physicalZone == 'Porta-malas'),
        isTrue,
      );

      await selectVehicle(VehicleType.motorcycle);
      expect(state.activePhysicalZones, AppState.motorcyclePhysicalZones);
      expect(
        state.packages.take(2).every((package) => package.physicalZone == null),
        isTrue,
      );
      expect(state.packages.last.physicalZone, 'Porta-malas');

      await configureOnly(
        AppState.motorcyclePhysicalZones,
        'Baú traseiro',
      );
      await state.setPhysicalZones(
        {'active-1', 'active-2'},
        'Baú traseiro',
      );
      expect(
        state.packages.take(2).every((package) => package.physicalZone == 'Baú traseiro'),
        isTrue,
      );

      await selectVehicle(VehicleType.car);
      expect(state.activePhysicalZones, ['Porta-malas']);
      expect(
        state.packages.take(2).every((package) => package.physicalZone == null),
        isTrue,
      );
      expect(state.packages.last.physicalZone, 'Porta-malas');

      await selectVehicle(VehicleType.motorcycle);
      expect(state.activePhysicalZones, ['Baú traseiro']);
      expect(state.packages.last.status, DeliveryStatus.delivered);
      expect(state.packages.last.physicalZone, 'Porta-malas');

      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.getStringList('load_zones_car'),
        ['Porta-malas'],
      );
      expect(
        preferences.getStringList('load_zones_motorcycle'),
        ['Baú traseiro'],
      );
      expect(preferences.getString('load_vehicle_type'), 'motorcycle');
      expect(tester.takeException(), isNull);

      final savesBeforeRestart = store.saves;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      final resumed = AppState(store: store);
      await resumed.init();

      expect(resumed.startupError, isNull);
      expect(resumed.vehicleType, VehicleType.motorcycle);
      expect(resumed.activePhysicalZones, ['Baú traseiro']);
      expect(resumed.packages, hasLength(3));
      expect(resumed.packages[0].physicalZone, isNull);
      expect(resumed.packages[1].physicalZone, isNull);
      expect(resumed.packages[2].status, DeliveryStatus.delivered);
      expect(resumed.packages[2].physicalZone, 'Porta-malas');
      expect(
        store.saves,
        savesBeforeRestart,
        reason: 'Restart must not rewrite an already reconciled load.',
      );

      await resumed.setVehicleType(VehicleType.car);
      expect(resumed.activePhysicalZones, ['Porta-malas']);
      await resumed.setVehicleType(VehicleType.motorcycle);
      expect(resumed.activePhysicalZones, ['Baú traseiro']);

      expect(
        preferences.getStringList('load_zones_car'),
        ['Porta-malas'],
      );
      expect(
        preferences.getStringList('load_zones_motorcycle'),
        ['Baú traseiro'],
      );
    },
  );
}
