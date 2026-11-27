import 'dart:io';

import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/services/sqlite_package_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
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
    final configuredZones = isMotorcycle
        ? <String>['Baú traseiro', 'Bolsa lateral esquerda']
        : <String>['Frente esquerda', 'Porta-malas'];

    test(
      'SQLite compartment rollback and retry stay atomic for ${vehicle.name}',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'rotas-zone-atomicity-${vehicle.name}-',
        );
        SqlitePackageStore? store;
        AppState? state;

        try {
          await databaseFactory.setDatabasesPath(directory.path);
          SharedPreferences.setMockInitialValues({
            'load_vehicle_type': vehicle.name,
            preferenceKey: configuredZones,
          });

          final original = [
            _package('active-to-clear-first', 1, zone: disabledZone),
            _package('forced-failure', 2, zone: disabledZone),
            _package('active-retained', 3, zone: retainedZone),
            _package(
              'delivered-history',
              4,
              zone: disabledZone,
              status: DeliveryStatus.delivered,
            ),
          ];

          final seedStore = SqlitePackageStore();
          await seedStore.save(original, routeOptimized: true);
          await seedStore.close();

          // Fail on the second changed package. The first update has already
          // entered the batch, so this exercises the real SQLite transaction
          // and proves that the earlier row is rolled back as well.
          final database = await databaseFactory.openDatabase(
            p.join(directory.path, 'delivery_routes.db'),
          );
          await database.execute('''
            CREATE TRIGGER abort_compartment_update
            BEFORE UPDATE ON packages
            WHEN NEW.id = 'forced-failure'
            BEGIN
              SELECT RAISE(ABORT, 'forced compartment persistence failure');
            END
          ''');
          await database.close();

          store = SqlitePackageStore();
          state = AppState(store: store);
          await state.init();

          expect(state.vehicleType, vehicle);
          expect(state.activePhysicalZones, configuredZones);
          expect(state.routeOptimized, isTrue);

          await expectLater(
            state.setActivePhysicalZones([retainedZone]),
            throwsA(isA<Exception>()),
          );

          final preferences = await SharedPreferences.getInstance();
          const originalZones = [
            'active-to-clear-first',
            'forced-failure',
            'active-retained',
            'delivered-history',
          ];
          expect(state.activePhysicalZones, configuredZones);
          expect(
            state.packages.map((package) => package.id).toList(),
            originalZones,
          );
          expect(
            state.packages.map((package) => package.physicalZone).toList(),
            [disabledZone, disabledZone, retainedZone, disabledZone],
          );
          expect(
            (await store.load())
                .map((package) => package.physicalZone)
                .toList(),
            [disabledZone, disabledZone, retainedZone, disabledZone],
            reason: 'The earlier package update must roll back with the failed row.',
          );
          expect(await store.loadRouteOptimized(), isTrue);
          expect(preferences.getStringList(preferenceKey), configuredZones);

          state.dispose();
          state = null;
          await store.close();
          store = null;

          // Remove the injected failure and reopen both the app state and
          // SQLite store, proving the failed attempt did not leave stale data.
          final repairDatabase = await databaseFactory.openDatabase(
            p.join(directory.path, 'delivery_routes.db'),
          );
          await repairDatabase.execute(
            'DROP TRIGGER abort_compartment_update',
          );
          await repairDatabase.close();

          store = SqlitePackageStore();
          state = AppState(store: store);
          await state.init();

          expect(state.vehicleType, vehicle);
          expect(state.activePhysicalZones, configuredZones);
          expect(
            state.packages.map((package) => package.physicalZone).toList(),
            [disabledZone, disabledZone, retainedZone, disabledZone],
          );

          await state.setActivePhysicalZones([retainedZone]);

          expect(state.activePhysicalZones, [retainedZone]);
          expect(
            state.packages.map((package) => package.physicalZone).toList(),
            [null, null, retainedZone, disabledZone],
            reason: 'Only active packages lose the disabled compartment; delivered history stays intact.',
          );
          expect(
            (await store.load())
                .map((package) => package.physicalZone)
                .toList(),
            [null, null, retainedZone, disabledZone],
          );
          expect(await store.loadRouteOptimized(), isTrue);
          expect(preferences.getStringList(preferenceKey), [retainedZone]);
        } finally {
          state?.dispose();
          await store?.close();
          await directory.delete(recursive: true);
        }
      },
    );
  }
}
