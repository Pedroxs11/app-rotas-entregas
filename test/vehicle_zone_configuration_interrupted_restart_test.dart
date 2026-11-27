import 'dart:io';

import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/services/sqlite_package_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

DeliveryPackage _package(
  String id,
  int number, {
  required String zone,
  DeliveryStatus status = DeliveryStatus.pending,
}) =>
    DeliveryPackage(
      id: id,
      scanNumber: number,
      physicalZone: zone,
      status: status,
      address: AddressData(
        raw: 'Rua da Carga, $number',
        street: 'Rua da Carga',
        number: '$number',
        city: 'São Paulo',
        state: 'SP',
        confidence: 1,
        validation: ValidationStatus.confirmed,
      ),
      scannedAt: DateTime.utc(2026, 11, 27, 8, number),
      completedAt: status == DeliveryStatus.delivered
          ? DateTime.utc(2026, 11, 27, 9, number)
          : null,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  for (final vehicle in VehicleType.values) {
    final isMotorcycle = vehicle == VehicleType.motorcycle;
    final retainedZone = isMotorcycle ? 'Baú traseiro' : 'Frente esquerda';
    final disabledZone = isMotorcycle
        ? 'Bolsa lateral esquerda'
        : 'Porta-malas';
    final preferenceKey = isMotorcycle
        ? 'load_zones_motorcycle'
        : 'load_zones_car';

    test(
      'startup recovers an interrupted compartment change for ${vehicle.name}',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'rotas-zone-interrupted-restart-${vehicle.name}-',
        );
        SqlitePackageStore? seedStore;
        SqlitePackageStore? store;
        AppState? state;
        AppState? reopenedState;

        try {
          await databaseFactory.setDatabasesPath(directory.path);

          // This is the durable state left if the process stops after saving
          // the new compartment preference but before updating package rows.
          SharedPreferences.setMockInitialValues({
            'load_vehicle_type': vehicle.name,
            preferenceKey: [retainedZone],
          });

          final original = [
            _package('active-disabled-zone', 1, zone: disabledZone),
            _package('active-retained-zone', 2, zone: retainedZone),
            _package('custom-label', 3, zone: 'Etiqueta: frágil'),
            _package(
              'delivered-history',
              4,
              zone: disabledZone,
              status: DeliveryStatus.delivered,
            ),
          ];

          seedStore = SqlitePackageStore();
          await seedStore.save(original, routeOptimized: true);
          await seedStore.close();
          seedStore = null;

          store = SqlitePackageStore();
          state = AppState(store: store);
          await state.init();

          expect(state.startupError, isNull);
          expect(state.vehicleType, vehicle);
          expect(state.activePhysicalZones, [retainedZone]);
          expect(state.routeOptimized, isTrue);
          expect(
            state.packages.map((package) => package.physicalZone).toList(),
            [null, retainedZone, 'Etiqueta: frágil', disabledZone],
            reason:
                'Startup must finish clearing active positions from disabled zones without changing custom labels or delivered history.',
          );

          final preferences = await SharedPreferences.getInstance();
          expect(preferences.getStringList(preferenceKey), [retainedZone]);
          expect(
            (await store.load())
                .map((package) => package.physicalZone)
                .toList(),
            [null, retainedZone, 'Etiqueta: frágil', disabledZone],
          );
          expect(await store.loadRouteOptimized(), isTrue);

          state.dispose();
          state = null;
          await store.close();
          store = null;

          // A second process-style restart must see the repaired mapping and
          // must not need another reconciliation pass.
          store = SqlitePackageStore();
          reopenedState = AppState(store: store);
          await reopenedState.init();

          expect(reopenedState.startupError, isNull);
          expect(reopenedState.vehicleType, vehicle);
          expect(reopenedState.activePhysicalZones, [retainedZone]);
          expect(reopenedState.routeOptimized, isTrue);
          expect(
            reopenedState.packages.map((package) => package.physicalZone).toList(),
            [null, retainedZone, 'Etiqueta: frágil', disabledZone],
          );
        } finally {
          state?.dispose();
          reopenedState?.dispose();
          await store?.close();
          await seedStore?.close();
          await directory.delete(recursive: true);
        }
      },
    );
  }
}
