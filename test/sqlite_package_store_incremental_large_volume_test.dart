import 'dart:io';

import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/services/sqlite_package_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

DeliveryPackage _package(int number) => DeliveryPackage(
      id: 'bulk-${number.toString().padLeft(3, '0')}',
      scanNumber: number,
      address: AddressData(
        raw: 'Rua da Carga, $number',
        street: 'Rua da Carga',
        number: '$number',
        city: 'São Paulo',
        state: 'SP',
        confidence: 1,
        validation: ValidationStatus.confirmed,
      ),
      scannedAt: DateTime.utc(2026, 11, 27, 10).add(
        Duration(minutes: number),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
    'incremental SQLite save writes only the 25 changed rows in a 600-package load',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'rotas-sqlite-incremental-large-',
      );
      SqlitePackageStore? store;

      try {
        await databaseFactory.setDatabasesPath(directory.path);
        store = SqlitePackageStore();

        final original = List.generate(600, (index) => _package(index + 1));
        await store.save(original, routeOptimized: true);

        // sqflite_common_ffi reuses open handles for a database path. Keep this
        // handle alive while the store performs its writes and close the store
        // before deleting the temporary database directory.
        final database = await databaseFactory.openDatabase(
          p.join(directory.path, 'delivery_routes.db'),
        );
        await database.execute(
          'CREATE TABLE package_write_audit (package_id TEXT NOT NULL)',
        );
        await database.execute(
          'CREATE TABLE metadata_write_audit (key TEXT NOT NULL)',
        );
        await database.execute('''
          CREATE TRIGGER audit_package_update
          AFTER UPDATE ON packages
          BEGIN
            INSERT INTO package_write_audit(package_id) VALUES (NEW.id);
          END
        ''');
        await database.execute('''
          CREATE TRIGGER reject_package_insert
          BEFORE INSERT ON packages
          BEGIN
            SELECT RAISE(ABORT, 'incremental save inserted an existing load row');
          END
        ''');
        await database.execute('''
          CREATE TRIGGER reject_package_delete
          BEFORE DELETE ON packages
          BEGIN
            SELECT RAISE(ABORT, 'incremental save deleted an unchanged load row');
          END
        ''');
        await database.execute('''
          CREATE TRIGGER audit_metadata_insert
          AFTER INSERT ON route_meta
          BEGIN
            INSERT INTO metadata_write_audit(key) VALUES (NEW.key);
          END
        ''');
        await database.execute('''
          CREATE TRIGGER audit_metadata_update
          AFTER UPDATE ON route_meta
          BEGIN
            INSERT INTO metadata_write_audit(key) VALUES (NEW.key);
          END
        ''');

        // A no-op save must not rewrite any of the 600 packages or route
        // metadata, even when the same route optimization flag is supplied.
        await store.save(original, routeOptimized: true);
        expect(await database.query('package_write_audit'), isEmpty);
        expect(await database.query('metadata_write_audit'), isEmpty);

        // Move only 25 packages. The triggers reject inserts/deletes, while
        // the audit table records every package row actually updated.
        final changed = original
            .take(25)
            .map((package) => package.copyWith(physicalZone: 'Baú traseiro'))
            .toList();
        final next = [...changed, ...original.skip(25)];
        await store.save(next, routeOptimized: true);

        final writes = await database.query(
          'package_write_audit',
          columns: ['package_id'],
          orderBy: 'package_id ASC',
        );
        final writtenIds = writes
            .map((row) => row['package_id']! as String)
            .toList();
        final expectedIds = original
            .take(25)
            .map((package) => package.id)
            .toList()
          ..sort();

        expect(writtenIds, expectedIds);
        expect(writtenIds, hasLength(25));
        expect(await database.query('metadata_write_audit'), isEmpty);

        final loaded = await store.load();
        expect(loaded, hasLength(600));
        expect(
          loaded.take(25).every(
                (package) => package.physicalZone == 'Baú traseiro',
              ),
          isTrue,
        );
        expect(
          loaded.skip(25).every((package) => package.physicalZone == null),
          isTrue,
        );
        expect(await store.loadRouteOptimized(), isTrue);

        await store.close();
        store = null;

        // Reopen from disk to ensure the incremental write did not merely
        // update an in-memory representation.
        final reopenedStore = SqlitePackageStore();
        try {
          final reopened = await reopenedStore.load();
          expect(reopened, hasLength(600));
          expect(
            reopened.map((package) => package.id).toList(),
            original.map((package) => package.id).toList(),
          );
          expect(
            reopened.take(25).every(
                  (package) => package.physicalZone == 'Baú traseiro',
                ),
            isTrue,
          );
          expect(await reopenedStore.loadRouteOptimized(), isTrue);
        } finally {
          await reopenedStore.close();
        }
      } finally {
        await store?.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
