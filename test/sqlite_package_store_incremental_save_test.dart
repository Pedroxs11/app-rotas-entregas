import 'dart:io';

import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/services/sqlite_package_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
        raw: 'Rua Incremental, $scanNumber',
        street: 'Rua Incremental',
        number: '$scanNumber',
        city: 'São Paulo',
        state: 'SP',
        confidence: 1,
        validation: ValidationStatus.confirmed,
      ),
      scannedAt: DateTime.utc(2026, 11, 27, 10, scanNumber),
      completedAt: status == DeliveryStatus.delivered
          ? DateTime.utc(2026, 11, 27, 11, scanNumber)
          : null,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
    'SQLite skips unchanged package writes and preserves order and history',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'rotas-sqlite-incremental-save-',
      );
      SqlitePackageStore? store;

      try {
        await databaseFactory.setDatabasesPath(directory.path);
        store = SqlitePackageStore();

        final original = [
          _package('changed', 1, zone: 'Porta-malas'),
          _package('unchanged', 2, zone: 'Frente esquerda'),
          _package(
            'delivered',
            3,
            zone: 'HISTORICO',
            status: DeliveryStatus.delivered,
          ),
        ];
        await store.save(original, routeOptimized: true);

        // sqflite_common_ffi caches open handles by database path. Keep this
        // handle open for the lifetime of SqlitePackageStore; closing it here
        // would close the same connection held by the store and make the next
        // save fail with database_closed before the triggers can be exercised.
        final database = await store.databaseForTesting;
        // These triggers fail if a save attempts to replace or update an
        // unchanged row. A targeted save must leave both rows untouched.
        await database.execute('''
          CREATE TRIGGER reject_unchanged_package_insert
          BEFORE INSERT ON packages
          WHEN NEW.id = 'unchanged'
          BEGIN
            SELECT RAISE(ABORT, 'unchanged package was inserted again');
          END
        ''');
        await database.execute('''
          CREATE TRIGGER reject_unchanged_package_update
          BEFORE UPDATE ON packages
          WHEN NEW.id = 'unchanged'
          BEGIN
            SELECT RAISE(ABORT, 'unchanged package was updated');
          END
        ''');

        // A no-op save should not touch package rows or route metadata.
        await store.save(original, routeOptimized: true);

        final updated = original.first.copyWith(
          physicalZone: 'Frente direita',
        );
        await store.save(
          [updated, original[1], original[2]],
          routeOptimized: true,
        );

        var loaded = await store.load();
        expect(
          loaded.map((package) => package.id).toList(),
          ['changed', 'unchanged', 'delivered'],
        );
        expect(loaded[0].physicalZone, 'Frente direita');
        expect(loaded[1].physicalZone, 'Frente esquerda');
        expect(loaded[2].status, DeliveryStatus.delivered);
        expect(loaded[2].physicalZone, 'HISTORICO');
        expect(
          loaded[2].completedAt,
          DateTime.utc(2026, 11, 27, 11, 3),
        );
        expect(await store.loadRouteOptimized(), isTrue);

        // Reuse the same open handle so the store's cached connection stays
        // valid while the temporary triggers are removed.
        await database.execute(
          'DROP TRIGGER reject_unchanged_package_insert',
        );
        await database.execute(
          'DROP TRIGGER reject_unchanged_package_update',
        );

        // Reordering updates only the affected sort positions; removing a
        // package deletes the missing id without replacing the retained rows.
        await store.save([original[2], updated], routeOptimized: false);
        loaded = await store.load();

        expect(
          loaded.map((package) => package.id).toList(),
          ['delivered', 'changed'],
        );
        expect(loaded.first.status, DeliveryStatus.delivered);
        expect(loaded.first.physicalZone, 'HISTORICO');
        expect(loaded.last.physicalZone, 'Frente direita');
        expect(await store.loadRouteOptimized(), isFalse);
      } finally {
        await store?.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
