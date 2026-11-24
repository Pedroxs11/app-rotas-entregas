import 'dart:io';

import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/services/sqlite_package_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

DeliveryPackage _legacyPackage(String zone) => DeliveryPackage(
      id: 'legacy-sqlite-zone',
      scanNumber: 1,
      physicalZone: zone,
      address: AddressData(
        raw: 'Rua da Compatibilidade, 1',
        street: 'Rua da Compatibilidade',
        number: '1',
        city: 'São Paulo',
        state: 'SP',
        confidence: 1,
        validation: ValidationStatus.confirmed,
      ),
      scannedAt: DateTime.utc(2026, 11, 24, 10),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
    'SQLite persists legacy compartment normalization for car and motorcycle after restart',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'rotas-sqlite-legacy-zone-',
      );

      try {
        for (final scenario in [
          (
            vehicle: VehicleType.car,
            preferenceKey: 'load_zones_car',
            zone: 'Porta-malas',
          ),
          (
            vehicle: VehicleType.motorcycle,
            preferenceKey: 'load_zones_motorcycle',
            zone: 'Bolsa lateral esquerda',
          ),
        ]) {
          final databaseDirectory = Directory(
            p.join(root.path, scenario.vehicle.name),
          );
          await databaseDirectory.create(recursive: true);
          await databaseFactory.setDatabasesPath(databaseDirectory.path);

          SharedPreferences.setMockInitialValues({
            'load_vehicle_type': scenario.vehicle.name,
            scenario.preferenceKey: [scenario.zone],
          });

          SqlitePackageStore? seedStore;
          SqlitePackageStore? migrationStore;
          SqlitePackageStore? verificationStore;
          AppState? state;

          try {
            seedStore = SqlitePackageStore();
            await seedStore.save(
              [_legacyPackage('  ${scenario.zone}  ')],
              routeOptimized: true,
            );
            await seedStore.close();
            seedStore = null;

            // A fresh store instance ensures AppState repairs the row read
            // from SQLite, rather than a package still held by the seeding
            // session.
            migrationStore = SqlitePackageStore();
            state = AppState(store: migrationStore);
            await state.init();

            expect(
              state.startupError,
              isNull,
              reason: '${scenario.vehicle} must load the legacy route cleanly.',
            );
            expect(state.vehicleType, scenario.vehicle);
            expect(state.routeOptimized, isTrue);
            expect(state.packages.single.physicalZone, scenario.zone);

            final preferences = await SharedPreferences.getInstance();
            expect(
              preferences.getStringList(scenario.preferenceKey),
              [scenario.zone],
            );

            await migrationStore.close();
            migrationStore = null;
            state.dispose();
            state = null;

            // Reopen SQLite again to prove the normalization was written to
            // disk and is not only an in-memory rendering adjustment.
            verificationStore = SqlitePackageStore();
            final persisted = await verificationStore.load();
            expect(persisted, hasLength(1));
            expect(persisted.single.physicalZone, scenario.zone);
            expect(await verificationStore.loadRouteOptimized(), isTrue);
          } finally {
            state?.dispose();
            await seedStore?.close();
            await migrationStore?.close();
            await verificationStore?.close();
          }
        }
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
}
