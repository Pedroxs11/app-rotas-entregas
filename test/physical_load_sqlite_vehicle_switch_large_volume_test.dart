import 'dart:io';

import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/services/sqlite_package_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

DeliveryPackage _switchPackage(int number, {bool delivered = false}) =>
    DeliveryPackage(
      id: 'vehicle-switch-load-$number',
      scanNumber: number,
      physicalZone: delivered ? 'HISTORICO' : null,
      address: AddressData(
        raw: 'Rua da Carga, $number',
        street: 'Rua da Carga',
        number: '$number',
        city: 'São Paulo',
        state: 'SP',
        confidence: 1,
        validation: ValidationStatus.confirmed,
      ),
      scannedAt: DateTime.utc(2026, 11, 26, 10).add(
        Duration(minutes: number),
      ),
      completedAt: delivered ? DateTime.utc(2026, 11, 26, 12) : null,
      status: delivered ? DeliveryStatus.delivered : DeliveryStatus.pending,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
    'SQLite preserves a 600-package load while switching car and motorcycle and restarting',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'rotas-sqlite-vehicle-switch-',
      );

      try {
        SharedPreferences.setMockInitialValues({
          'load_vehicle_type': VehicleType.car.name,
          'load_zones_car': ['Frente esquerda', 'Porta-malas'],
          'load_zones_motorcycle': AppState.motorcyclePhysicalZones,
        });

        await databaseFactory.setDatabasesPath(
          p.join(root.path, 'database'),
        );

        SqlitePackageStore? store;
        SqlitePackageStore? reopenedStore;
        AppState? state;
        AppState? resumed;

        try {
          store = SqlitePackageStore();
          await store.save(
            List.generate(
              600,
              (index) => _switchPackage(
                index + 1,
                delivered: index == 599,
              ),
            ),
            routeOptimized: true,
          );

          state = AppState(store: store);
          await state.init();

          expect(state.vehicleType, VehicleType.car);
          expect(
            state.activePhysicalZones,
            ['Frente esquerda', 'Porta-malas'],
          );
          expect(state.packages, hasLength(600));

          final carZones = [...state.activePhysicalZones];
          for (var zoneIndex = 0; zoneIndex < carZones.length; zoneIndex++) {
            final ids = state.packages
                .where(
                  (package) =>
                      package.status != DeliveryStatus.delivered &&
                      (package.scanNumber - 1) % carZones.length == zoneIndex,
                )
                .map((package) => package.id)
                .toSet();
            await state.setPhysicalZones(ids, carZones[zoneIndex]);
          }

          expect(
            state.packages.where(
              (package) =>
                  package.status != DeliveryStatus.delivered &&
                  package.physicalZone != null,
            ),
            hasLength(599),
          );

          await state.setVehicleType(VehicleType.motorcycle);

          expect(state.vehicleType, VehicleType.motorcycle);
          expect(
            state.activePhysicalZones,
            AppState.motorcyclePhysicalZones,
          );
          expect(
            state.packages.where(
              (package) =>
                  package.status != DeliveryStatus.delivered &&
                  package.physicalZone != null,
            ),
            isEmpty,
            reason: 'Car-only positions must not leak into the motorcycle.',
          );

          final delivered = state.packages.singleWhere(
            (package) => package.status == DeliveryStatus.delivered,
          );
          expect(delivered.physicalZone, 'HISTORICO');
          expect(
            delivered.completedAt,
            DateTime.utc(2026, 11, 26, 12),
          );

          final motorcycleZones = [...state.activePhysicalZones];
          for (var zoneIndex = 0;
              zoneIndex < motorcycleZones.length;
              zoneIndex++) {
            final ids = state.packages
                .where(
                  (package) =>
                      package.status != DeliveryStatus.delivered &&
                      (package.scanNumber - 1) % motorcycleZones.length ==
                          zoneIndex,
                )
                .map((package) => package.id)
                .toSet();
            await state.setPhysicalZones(ids, motorcycleZones[zoneIndex]);
          }

          final expectedZonesByPackage = <String, String?>{
            for (final package in state.packages)
              package.id: package.physicalZone,
          };
          expect(
            state.packages.where(
              (package) =>
                  package.status != DeliveryStatus.delivered &&
                  package.physicalZone != null,
            ),
            hasLength(599),
          );

          state.dispose();
          state = null;
          await store.close();
          store = null;

          reopenedStore = SqlitePackageStore();
          resumed = AppState(store: reopenedStore);
          await resumed.init();

          expect(resumed.startupError, isNull);
          expect(resumed.vehicleType, VehicleType.motorcycle);
          expect(
            resumed.activePhysicalZones,
            AppState.motorcyclePhysicalZones,
          );
          expect(resumed.packages, hasLength(600));
          expect(
            <String, String?>{
              for (final package in resumed.packages)
                package.id: package.physicalZone,
            },
            expectedZonesByPackage,
            reason:
                'Every package must recover its exact motorcycle compartment.',
          );

          final restoredDelivered = resumed.packages.singleWhere(
            (package) => package.status == DeliveryStatus.delivered,
          );
          expect(restoredDelivered.physicalZone, 'HISTORICO');
          expect(
            restoredDelivered.completedAt,
            DateTime.utc(2026, 11, 26, 12),
          );

          await resumed.setVehicleType(VehicleType.car);
          expect(resumed.vehicleType, VehicleType.car);
          expect(
            resumed.activePhysicalZones,
            ['Frente esquerda', 'Porta-malas'],
          );
          expect(
            resumed.packages.where(
              (package) =>
                  package.status != DeliveryStatus.delivered &&
                  package.physicalZone != null,
            ),
            isEmpty,
            reason:
                'Switching back must clear motorcycle-only positions as well.',
          );
          expect(
            resumed.packages
                .singleWhere(
                  (package) => package.status == DeliveryStatus.delivered,
                )
                .physicalZone,
            'HISTORICO',
          );

          final preferences = await SharedPreferences.getInstance();
          expect(
            preferences.getStringList('load_zones_car'),
            ['Frente esquerda', 'Porta-malas'],
          );
          expect(
            preferences.getStringList('load_zones_motorcycle'),
            AppState.motorcyclePhysicalZones,
          );
        } finally {
          state?.dispose();
          resumed?.dispose();
          await store?.close();
          await reopenedStore?.close();
        }
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
}
