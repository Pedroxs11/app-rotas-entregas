import 'dart:io';

import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/services/sqlite_package_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

DeliveryPackage _package(String id, int scanNumber, String zone) =>
    DeliveryPackage(
      id: id,
      scanNumber: scanNumber,
      physicalZone: zone,
      address: AddressData(
        raw: 'Rua Teste, $scanNumber',
        street: 'Rua Teste',
        number: '$scanNumber',
        city: 'São Paulo',
        state: 'SP',
        confidence: .8,
        validation: ValidationStatus.needsReview,
      ),
      scannedAt: DateTime.utc(2026, 11, 21, 10, scanNumber),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('failed SQLite batch save rolls back packages and route metadata', () async {
    final directory = await Directory.systemTemp.createTemp(
      'rotas-sqlite-atomicity-',
    );
    SqlitePackageStore? store;

    try {
      await databaseFactory.setDatabasesPath(directory.path);

      final original = [
        _package('package-1', 1, 'Frente esquerda'),
        _package('package-2', 2, 'Porta-malas'),
      ];

      store = SqlitePackageStore();
      await store.save(original, routeOptimized: true);
      await store.close();
      store = null;

      // Inject a deterministic SQLite constraint failure on the final row.
      // The production store must roll back earlier replacements and metadata
      // changes from the same transaction.
      final database = await databaseFactory.openDatabase(
        p.join(directory.path, 'delivery_routes.db'),
      );
      await database.execute('''
        CREATE TRIGGER abort_forced_package
        BEFORE INSERT ON packages
        WHEN NEW.id = 'forced-failure'
        BEGIN
          SELECT RAISE(ABORT, 'forced package write failure');
        END
      ''');
      await database.close();

      store = SqlitePackageStore();
      final attempted = [
        original[0].copyWith(physicalZone: 'Traseira direita'),
        original[1],
        _package('forced-failure', 3, 'Frente direita'),
      ];

      await expectLater(
        store.save(attempted, routeOptimized: false),
        throwsA(isA<Exception>()),
      );

      final recovered = await store.load();
      expect(recovered, hasLength(2));
      expect(
        recovered.map((package) => package.id).toList(),
        ['package-1', 'package-2'],
      );
      expect(
        recovered.singleWhere((package) => package.id == 'package-1').physicalZone,
        'Frente esquerda',
        reason: 'The earlier replacement must be rolled back with the failed batch.',
      );
      expect(
        recovered.singleWhere((package) => package.id == 'package-2').physicalZone,
        'Porta-malas',
      );
      expect(
        await store.loadRouteOptimized(),
        isTrue,
        reason: 'Route metadata must roll back with package rows.',
      );
    } finally {
      await store?.close();
      await directory.delete(recursive: true);
    }
  });
}
