import 'dart:io';

import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/services/package_store.dart';
import 'package:app_rotas_entregas/services/sqlite_package_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FailOnceSqlitePackageStore implements PackageStore {
  _FailOnceSqlitePackageStore(this.delegate);

  final SqlitePackageStore delegate;
  bool failNextSave = false;
  int saveCalls = 0;

  @override
  Future<void> clear() => delegate.clear();

  @override
  Future<List<DeliveryPackage>> load() => delegate.load();

  @override
  Future<bool> loadRouteOptimized() => delegate.loadRouteOptimized();

  @override
  Future<void> save(
    List<DeliveryPackage> packages, {
    bool? routeOptimized,
  }) async {
    saveCalls++;
    if (failNextSave) {
      failNextSave = false;
      throw StateError('Falha simulada antes da gravação SQLite.');
    }
    await delegate.save(packages, routeOptimized: routeOptimized);
  }
}

DeliveryPackage _package(
  int number, {
  required String zone,
  DeliveryStatus status = DeliveryStatus.pending,
}) =>
    DeliveryPackage(
      id: 'sqlite-switch-$number',
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
      scannedAt: DateTime.utc(2026, 11, 24, 12).add(
        Duration(minutes: number),
      ),
      completedAt: status == DeliveryStatus.delivered
          ? DateTime.utc(2026, 11, 24, 18)
          : null,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
    'SQLite vehicle switch rollback keeps 600 packages intact and retry survives restart',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'rotas-sqlite-vehicle-switch-',
      );
      SqlitePackageStore? seedStore;
      SqlitePackageStore? reopenedStore;

      try {
        await databaseFactory.setDatabasesPath(p.join(root.path, 'database'));
        await Directory(p.join(root.path, 'database')).create(recursive: true);
        SharedPreferences.setMockInitialValues({
          'load_vehicle_type': 'car',
          'load_zones_motorcycle': ['Bolsa lateral esquerda'],
        });

        final carZones = AppState.carPhysicalZones;
        final original = List.generate(600, (index) {
          final number = index + 1;
          if (number == 600) {
            return _package(
              number,
              zone: 'HISTORICO',
              status: DeliveryStatus.delivered,
            );
          }
          if (number == 1) {
            return _package(number, zone: 'A-01');
          }
          return _package(
            number,
            zone: carZones[(number - 2) % carZones.length],
          );
        });

        seedStore = SqlitePackageStore();
        await seedStore.save(original, routeOptimized: true);

        final store = _FailOnceSqlitePackageStore(seedStore);
        final state = AppState(store: store);
        await state.init();

        expect(state.startupError, isNull);
        expect(state.vehicleType, VehicleType.car);
        expect(state.routeOptimized, isTrue);
        expect(state.packages, hasLength(600));

        store.failNextSave = true;
        await expectLater(
          state.setVehicleType(VehicleType.motorcycle),
          throwsA(isA<StateError>()),
        );

        final preferences = await SharedPreferences.getInstance();
        expect(state.vehicleType, VehicleType.car);
        expect(state.activePhysicalZones, carZones);
        expect(state.packages, hasLength(600));
        expect(
          state.packages.firstWhere(
            (package) => package.id == 'sqlite-switch-1',
          ).physicalZone,
          'A-01',
        );
        expect(
          state.packages.firstWhere(
            (package) => package.id == 'sqlite-switch-2',
          ).physicalZone,
          carZones.first,
        );
        expect(
          preferences.getString('load_vehicle_type'),
          'car',
        );
        expect(
          preferences.getStringList('load_zones_motorcycle'),
          ['Bolsa lateral esquerda'],
        );

        // The failed attempt must leave the real database untouched.
        final afterFailure = await seedStore.load();
        expect(afterFailure, hasLength(600));
        expect(
          afterFailure.firstWhere(
            (package) => package.id == 'sqlite-switch-2',
          ).physicalZone,
          carZones.first,
        );

        await state.setVehicleType(VehicleType.motorcycle);

        expect(state.vehicleType, VehicleType.motorcycle);
        expect(
          state.activePhysicalZones,
          ['Bolsa lateral esquerda'],
        );
        expect(state.packages, hasLength(600));
        expect(
          state.packages.where(
            (package) =>
                package.status != DeliveryStatus.delivered &&
                package.physicalZone != null &&
                package.physicalZone != 'A-01',
          ),
          isEmpty,
        );
        expect(
          state.packages.firstWhere(
            (package) => package.id == 'sqlite-switch-1',
          ).physicalZone,
          'A-01',
        );
        expect(
          state.packages.last.status,
          DeliveryStatus.delivered,
        );
        expect(state.packages.last.physicalZone, 'HISTORICO');
        expect(store.saveCalls, 2);

        await seedStore.close();
        seedStore = null;

        // Reopen a fresh SQLite connection and AppState, simulating a process
        // restart after the successful retry.
        reopenedStore = SqlitePackageStore();
        final reopened = AppState(store: reopenedStore);
        await reopened.init();

        expect(reopened.startupError, isNull);
        expect(reopened.vehicleType, VehicleType.motorcycle);
        expect(
          reopened.activePhysicalZones,
          ['Bolsa lateral esquerda'],
        );
        expect(reopened.routeOptimized, isTrue);
        expect(reopened.packages, hasLength(600));
        expect(
          reopened.packages.firstWhere(
            (package) => package.id == 'sqlite-switch-1',
          ).physicalZone,
          'A-01',
        );
        expect(
          reopened.packages.where(
            (package) =>
                package.status != DeliveryStatus.delivered &&
                package.physicalZone != null &&
                package.physicalZone != 'A-01',
          ),
          isEmpty,
        );
        expect(reopened.packages.last.status, DeliveryStatus.delivered);
        expect(reopened.packages.last.physicalZone, 'HISTORICO');
      } finally {
        await seedStore?.close();
        await reopenedStore?.close();
        await root.delete(recursive: true);
      }
    },
  );
}
