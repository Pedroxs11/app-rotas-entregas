import 'dart:io';

import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/services/sqlite_package_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

DeliveryPackage _package(
  String id,
  int scanNumber, {
  required String zone,
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
        confidence: .8,
        validation: ValidationStatus.needsReview,
      ),
      scannedAt: DateTime.utc(2026, 11, 21, 10, scanNumber % 60),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
    'SQLite persists 600 multi-zone assignments and concurrent scans across restart for car and motorcycle',
    () async {
      for (final vehicle in [VehicleType.car, VehicleType.motorcycle]) {
        final directory = await Directory.systemTemp.createTemp(
          'rotas-sqlite-${vehicle.name}-',
        );
        SqlitePackageStore? seedStore;
        SqlitePackageStore? activeStore;
        SqlitePackageStore? resumedStore;

        try {
          await databaseFactory.setDatabasesPath(directory.path);
          SharedPreferences.setMockInitialValues({
            'load_vehicle_type': vehicle.name,
          });

          final zones = vehicle == VehicleType.car
              ? AppState.carPhysicalZones
              : AppState.motorcyclePhysicalZones;
          final deliveredHistoryZone = vehicle == VehicleType.car
              ? 'Baú traseiro'
              : 'Porta-malas';
          final organized = List.generate(
            600,
            (index) => _package(
              'sqlite-${vehicle.name}-${index + 1}',
              index + 1,
              zone: zones[index % zones.length],
            ),
          );
          final delivered = _package(
            'sqlite-delivered-${vehicle.name}',
            601,
            zone: deliveredHistoryZone,
            status: DeliveryStatus.delivered,
          );

          // Seed and close a real SQLite file before opening AppState, so the
          // first load exercises database creation and persisted JSON rows.
          seedStore = SqlitePackageStore();
          await seedStore.save(
            [...organized, delivered],
            routeOptimized: true,
          );
          await seedStore.close();
          seedStore = null;

          activeStore = SqlitePackageStore();
          final state = AppState(store: activeStore);
          await state.init();

          expect(state.startupError, isNull);
          expect(state.vehicleType, vehicle);
          expect(state.packages, hasLength(601));
          expect(state.routeOptimized, isTrue);

          final originalZones = {
            for (final package in organized)
              package.id: package.physicalZone,
          };
          final originalCounts = {
            for (final zone in zones)
              zone: organized
                  .where((package) => package.physicalZone == zone)
                  .length,
          };

          final captured = await Future.wait([
            state.addFromText(
              'etiqueta sem endereco alpha',
              trackingCode: 'SQLITE-${vehicle.name.toUpperCase()}-A',
            ),
            state.addFromText(
              'etiqueta sem endereco beta',
              trackingCode: 'SQLITE-${vehicle.name.toUpperCase()}-B',
            ),
          ]);

          expect(state.packages, hasLength(603));
          expect(state.routeOptimized, isFalse);
          for (final entry in originalZones.entries) {
            expect(
              state.packages.singleWhere((package) => package.id == entry.key).physicalZone,
              entry.value,
              reason: 'SQLite scan must preserve ${entry.key} for $vehicle.',
            );
          }
          for (final entry in originalCounts.entries) {
            expect(
              state.packages.where((package) => package.physicalZone == entry.key).length,
              entry.value,
              reason: 'SQLite scan must preserve the count in ${entry.key}.',
            );
          }
          expect(captured.map((package) => package.physicalZone), everyElement(isNull));
          expect(captured.map((package) => package.scanNumber).toSet(), {602, 603});
          expect(
            state.packages.map((package) => package.scanNumber).toSet(),
            hasLength(603),
          );
          expect(
            state.packages.singleWhere((package) => package.id == delivered.id).status,
            DeliveryStatus.delivered,
          );

          // Closing and constructing a new store forces a real database reopen,
          // unlike the in-memory PackageStore contract tests.
          await activeStore.close();
          activeStore = null;

          resumedStore = SqlitePackageStore();
          final resumed = AppState(store: resumedStore);
          await resumed.init();

          expect(resumed.startupError, isNull);
          expect(resumed.vehicleType, vehicle);
          expect(resumed.packages, hasLength(603));
          expect(resumed.routeOptimized, isFalse);
          for (final entry in originalZones.entries) {
            expect(
              resumed.packages.singleWhere((package) => package.id == entry.key).physicalZone,
              entry.value,
              reason: 'SQLite restart must preserve ${entry.key} for $vehicle.',
            );
          }
          expect(
            resumed.packages
                .where((package) => package.scanNumber == 602 || package.scanNumber == 603)
                .every((package) => package.physicalZone == null),
            isTrue,
          );
          final resumedHistory = resumed.packages.singleWhere(
            (package) => package.id == delivered.id,
          );
          expect(resumedHistory.status, DeliveryStatus.delivered);
          expect(resumedHistory.physicalZone, deliveredHistoryZone);
          expect(
            resumed.packages.map((package) => package.scanNumber).toSet(),
            hasLength(603),
          );
        } finally {
          await seedStore?.close();
          await activeStore?.close();
          await resumedStore?.close();
          await directory.delete(recursive: true);
        }
      }
    },
  );
}
