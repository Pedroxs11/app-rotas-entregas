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
  DeliveryStatus status = DeliveryStatus.pending,
  String? zone,
}) =>
    DeliveryPackage(
      id: id,
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
      scannedAt: DateTime.utc(2026, 11, 25, 8, number),
      completedAt: status == DeliveryStatus.delivered
          ? DateTime.utc(2026, 11, 25, 9, number)
          : null,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
    'independent car and motorcycle compartment configurations survive SQLite restart',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'rotas-zone-config-restart-',
      );
      SqlitePackageStore? store;
      SqlitePackageStore? reopenedStore;

      try {
        final databasePath = p.join(root.path, 'database');
        await Directory(databasePath).create(recursive: true);
        await databaseFactory.setDatabasesPath(databasePath);
        SharedPreferences.setMockInitialValues({
          'load_vehicle_type': 'car',
        });

        store = SqlitePackageStore();
        await store.save([
          _package('active-1', 1),
          _package('active-2', 2),
          _package(
            'delivered-history',
            3,
            status: DeliveryStatus.delivered,
            zone: 'Porta-malas',
          ),
        ], routeOptimized: true);

        final state = AppState(store: store);
        await state.init();

        const carZones = ['Frente esquerda', 'Porta-malas'];
        await state.setActivePhysicalZones(carZones);
        await state.setPhysicalZones({'active-1'}, 'Frente esquerda');
        await state.setPhysicalZones({'active-2'}, 'Porta-malas');

        await state.setVehicleType(VehicleType.motorcycle);
        const motorcycleZones = ['Baú traseiro', 'Bolsa lateral direita'];
        await state.setActivePhysicalZones(motorcycleZones);
        await state.setPhysicalZones({'active-1'}, 'Baú traseiro');
        await state.setPhysicalZones(
          {'active-2'},
          'Bolsa lateral direita',
        );

        await state.setVehicleType(VehicleType.car);
        expect(state.activePhysicalZones, carZones);
        expect(
          state.packages
              .where((package) => package.status != DeliveryStatus.delivered)
              .every((package) => package.physicalZone == null),
          isTrue,
        );

        await state.setVehicleType(VehicleType.motorcycle);
        expect(state.activePhysicalZones, motorcycleZones);
        await state.setPhysicalZones({'active-1'}, 'Baú traseiro');

        final preferences = await SharedPreferences.getInstance();
        expect(preferences.getString('load_vehicle_type'), 'motorcycle');
        expect(preferences.getStringList('load_zones_car'), carZones);
        expect(
          preferences.getStringList('load_zones_motorcycle'),
          motorcycleZones,
        );

        await store.close();
        store = null;
        state.dispose();

        reopenedStore = SqlitePackageStore();
        final reopened = AppState(store: reopenedStore);
        await reopened.init();

        expect(reopened.startupError, isNull);
        expect(reopened.vehicleType, VehicleType.motorcycle);
        expect(reopened.activePhysicalZones, motorcycleZones);
        expect(reopened.routeOptimized, isTrue);
        expect(reopened.packages, hasLength(3));
        expect(
          reopened.packages
              .singleWhere((package) => package.id == 'active-1')
              .physicalZone,
          'Baú traseiro',
        );
        expect(
          reopened.packages
              .singleWhere((package) => package.id == 'active-2')
              .physicalZone,
          isNull,
        );
        final delivered = reopened.packages
            .singleWhere((package) => package.id == 'delivered-history');
        expect(delivered.status, DeliveryStatus.delivered);
        expect(delivered.physicalZone, 'Porta-malas');
        expect(delivered.completedAt, DateTime.utc(2026, 11, 25, 9, 3));

        await reopened.setVehicleType(VehicleType.car);
        expect(reopened.activePhysicalZones, carZones);
        await reopened.setVehicleType(VehicleType.motorcycle);
        expect(reopened.activePhysicalZones, motorcycleZones);
      } finally {
        await store?.close();
        await reopenedStore?.close();
        await root.delete(recursive: true);
      }
    },
  );
}
