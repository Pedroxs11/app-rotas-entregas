import 'dart:io';

import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/services/sqlite_package_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

DeliveryPackage _largePackage(int number, {bool delivered = false}) =>
    DeliveryPackage(
      id: 'sqlite-load-$number',
      scanNumber: number,
      physicalZone: delivered ? 'HISTORICO' : null,
      address: AddressData(
        raw: 'Rua Teste, $number',
        street: 'Rua Teste',
        number: '$number',
        city: 'São Paulo',
        state: 'SP',
        confidence: 1,
        validation: ValidationStatus.confirmed,
      ),
      scannedAt: DateTime.utc(2026, 11, 23, 10).add(
        Duration(minutes: number),
      ),
      completedAt: delivered ? DateTime.utc(2026, 11, 23, 12) : null,
      status: delivered ? DeliveryStatus.delivered : DeliveryStatus.pending,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
    'SQLite keeps a 600-package organized load for car and motorcycle after restart',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'rotas-sqlite-large-load-',
      );

      try {
        for (final vehicle in VehicleType.values) {
          SharedPreferences.setMockInitialValues({
            'load_vehicle_type': vehicle.name,
          });

          final vehicleDirectory = Directory(
            p.join(root.path, vehicle.name),
          );
          await vehicleDirectory.create(recursive: true);
          await databaseFactory.setDatabasesPath(vehicleDirectory.path);

          SqlitePackageStore? store;
          SqlitePackageStore? reopenedStore;

          try {
            store = SqlitePackageStore();
            final original = List.generate(
              600,
              (index) => _largePackage(
                index + 1,
                delivered: index == 599,
              ),
            );
            final originalIds = original.map((package) => package.id).toSet();

            await store.save(original, routeOptimized: true);

            final state = AppState(store: store);
            await state.init();

            final zones = vehicle == VehicleType.car
                ? AppState.carPhysicalZones
                : AppState.motorcyclePhysicalZones;
            expect(state.vehicleType, vehicle);
            expect(state.routeOptimized, isTrue);
            expect(state.packages, hasLength(600));

            // Assign every active package through the same bulk mutation used
            // by the organizer, distributing the load across real vehicle
            // compartments without touching delivered history.
            for (var zoneIndex = 0; zoneIndex < zones.length; zoneIndex++) {
              final ids = state.packages
                  .where(
                    (package) =>
                        package.status != DeliveryStatus.delivered &&
                        (package.scanNumber - 1) % zones.length == zoneIndex,
                  )
                  .map((package) => package.id)
                  .toSet();
              await state.setPhysicalZones(ids, zones[zoneIndex]);
            }

            final firstZoneCount = state.packages
                .where((package) => package.physicalZone == zones.first)
                .length;
            final secondZoneCount = state.packages
                .where((package) => package.physicalZone == zones[1])
                .length;
            final movedIds = state.packages
                .where((package) => package.physicalZone == zones.first)
                .take(25)
                .map((package) => package.id)
                .toSet();

            await state.setPhysicalZones(movedIds, zones[1]);

            expect(state.packages, hasLength(600));
            expect(state.packages.map((package) => package.id).toSet(),
                originalIds);
            expect(
              state.packages.where(
                (package) => package.status != DeliveryStatus.delivered &&
                    package.physicalZone != null,
              ),
              hasLength(599),
            );
            expect(
              state.packages.where(
                (package) => package.physicalZone == zones.first,
              ),
              hasLength(firstZoneCount - movedIds.length),
            );
            expect(
              state.packages.where(
                (package) => package.physicalZone == zones[1],
              ),
              hasLength(secondZoneCount + movedIds.length),
            );

            final delivered = state.packages.singleWhere(
              (package) => package.status == DeliveryStatus.delivered,
            );
            expect(delivered.physicalZone, 'HISTORICO');
            expect(delivered.completedAt, DateTime.utc(2026, 11, 23, 12));

            await store.close();
            store = null;

            // Re-open the actual SQLite database, rather than reusing the
            // in-memory AppState, to verify that all 600 rows and their
            // physical compartments survive a process-style restart.
            reopenedStore = SqlitePackageStore();
            final reopened = AppState(store: reopenedStore);
            await reopened.init();

            expect(reopened.vehicleType, vehicle);
            expect(reopened.activePhysicalZones, zones);
            expect(reopened.routeOptimized, isTrue);
            expect(reopened.packages, hasLength(600));
            expect(reopened.packages.map((package) => package.id).toSet(),
                originalIds);
            expect(
              reopened.packages.where(
                (package) => package.status != DeliveryStatus.delivered &&
                    package.physicalZone != null,
              ),
              hasLength(599),
            );
            expect(
              reopened.packages.where(
                (package) => package.physicalZone == zones.first,
              ),
              hasLength(firstZoneCount - movedIds.length),
            );
            expect(
              reopened.packages.where(
                (package) => package.physicalZone == zones[1],
              ),
              hasLength(secondZoneCount + movedIds.length),
            );
            final restoredDelivered = reopened.packages.singleWhere(
              (package) => package.status == DeliveryStatus.delivered,
            );
            expect(restoredDelivered.physicalZone, 'HISTORICO');
            expect(
              restoredDelivered.completedAt,
              DateTime.utc(2026, 11, 23, 12),
            );
          } finally {
            await store?.close();
            await reopenedStore?.close();
          }
        }
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
}
