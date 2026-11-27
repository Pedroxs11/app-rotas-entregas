import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../domain/models.dart';
import 'package_store.dart';

/// SQLite-backed package persistence designed for growing routes and history.
/// Each package is stored independently instead of rewriting one giant JSON
/// preference on every delivery update.
class SqlitePackageStore implements PackageStore {
  static const _databaseName = 'delivery_routes.db';
  static const _databaseVersion = 1;
  static const _packagesTable = 'packages';
  static const _metaTable = 'route_meta';
  static const _optimizedKey = 'route_optimized';

  Database? _database;

  Future<Database> _db() async {
    final existing = _database;
    if (existing != null) return existing;

    final path = p.join(await getDatabasesPath(), _databaseName);
    return _database = await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: (db, _) async {
        await db.execute(
          'CREATE TABLE $_packagesTable '
          '(id TEXT PRIMARY KEY, sort_order INTEGER NOT NULL, payload TEXT NOT NULL)',
        );
        await db.execute(
          'CREATE INDEX idx_packages_sort_order ON $_packagesTable(sort_order)',
        );
        await db.execute(
          'CREATE TABLE $_metaTable (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
        );
      },
    );
  }

  @override
  Future<List<DeliveryPackage>> load() async {
    final db = await _db();
    final rows = await db.query(
      _packagesTable,
      columns: ['payload'],
      orderBy: 'sort_order ASC',
    );
    return rows
        .map(
          (row) => DeliveryPackage.fromJson(
            Map<String, dynamic>.from(
              jsonDecode(row['payload']! as String) as Map,
            ),
          ),
        )
        .toList();
  }

  @override
  Future<bool> loadRouteOptimized() async {
    final db = await _db();
    final rows = await db.query(
      _metaTable,
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [_optimizedKey],
      limit: 1,
    );
    return rows.isNotEmpty && rows.first['value'] == '1';
  }

  @override
  Future<void> save(
    List<DeliveryPackage> packages, {
    bool? routeOptimized,
  }) async {
    final db = await _db();
    await db.transaction((txn) async {
      // Compare the current rows before writing. A compartment assignment or
      // delivery update usually changes only a small part of a large route;
      // rewriting every package would create avoidable SQLite I/O.
      final existingRows = await txn.query(
        _packagesTable,
        columns: ['id', 'sort_order', 'payload'],
      );
      final existingById = <String, Map<String, Object?>>{
        for (final row in existingRows) row['id']! as String: row,
      };
      final ids = packages.map((package) => package.id).toSet();
      final batch = txn.batch();
      var hasWrites = false;

      for (var index = 0; index < packages.length; index++) {
        final package = packages[index];
        final payload = jsonEncode(package.toJson());
        final existing = existingById[package.id];

        if (existing == null) {
          batch.insert(_packagesTable, {
            'id': package.id,
            'sort_order': index,
            'payload': payload,
          });
          hasWrites = true;
          continue;
        }

        final orderChanged = existing['sort_order'] != index;
        final payloadChanged = existing['payload'] != payload;
        if (orderChanged || payloadChanged) {
          batch.update(
            _packagesTable,
            {'sort_order': index, 'payload': payload},
            where: 'id = ?',
            whereArgs: [package.id],
          );
          hasWrites = true;
        }
      }

      for (final row in existingRows) {
        final id = row['id']! as String;
        if (!ids.contains(id)) {
          batch.delete(
            _packagesTable,
            where: 'id = ?',
            whereArgs: [id],
          );
          hasWrites = true;
        }
      }

      if (routeOptimized != null) {
        final nextValue = routeOptimized ? '1' : '0';
        final metadataRows = await txn.query(
          _metaTable,
          columns: ['value'],
          where: 'key = ?',
          whereArgs: [_optimizedKey],
          limit: 1,
        );
        if (metadataRows.isEmpty || metadataRows.first['value'] != nextValue) {
          batch.insert(
            _metaTable,
            {'key': _optimizedKey, 'value': nextValue},
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          hasWrites = true;
        }
      }

      if (hasWrites) {
        await batch.commit(noResult: true);
      }
    });
  }

  @override
  Future<void> clear() async {
    final db = await _db();
    await db.transaction((txn) async {
      await txn.delete(_packagesTable);
      await txn.delete(_metaTable);
    });
  }

  Future<void> close() async {
    final db = _database;
    _database = null;
    await db?.close();
  }
}
