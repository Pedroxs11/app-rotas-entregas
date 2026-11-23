import '../domain/models.dart';
import 'package_store.dart';

/// Uses [primary] for all new data while importing an existing legacy store
/// once when the primary database is still empty.
///
/// Legacy data is deliberately kept after migration. That makes the first
/// rollout recoverable: an older app build can still read the previous data
/// until we explicitly retire the legacy store in a later version.
class MigratingPackageStore implements PackageStore {
  final PackageStore primary;
  final PackageStore legacy;
  bool _migrationChecked=false;

  MigratingPackageStore({required this.primary,required this.legacy});

  Future<void> _ensureMigrated() async {
    if(_migrationChecked)return;

    final current=await primary.load();
    if(current.isNotEmpty){
      _migrationChecked=true;
      return;
    }

    final old=await legacy.load();
    final optimized=await legacy.loadRouteOptimized();

    // Metadata also matters. A route can legitimately have no packages while
    // still carrying state that must survive an application upgrade.
    if(old.isEmpty&&!optimized){
      _migrationChecked=true;
      return;
    }

    await primary.save(old,routeOptimized:optimized);

    // Do not silently abandon the rollback copy if the primary store did not
    // persist exactly what was requested. A failed verification can be retried
    // on the next call because _migrationChecked remains false.
    final migrated=await primary.load();
    final migratedOptimized=await primary.loadRouteOptimized();
    final samePackages=migrated.length==old.length&&
        List.generate(old.length,(i)=>migrated[i].id==old[i].id).every((v)=>v);
    if(!samePackages||migratedOptimized!=optimized){
      throw StateError('Legacy package migration could not be verified.');
    }

    _migrationChecked=true;
  }

  @override
  Future<List<DeliveryPackage>> load() async {
    await _ensureMigrated();
    return primary.load();
  }

  @override
  Future<bool> loadRouteOptimized() async {
    await _ensureMigrated();
    return primary.loadRouteOptimized();
  }

  @override
  Future<void> save(List<DeliveryPackage> packages,{bool? routeOptimized}) async {
    await _ensureMigrated();
    await primary.save(packages,routeOptimized:routeOptimized);
  }

  @override
  Future<void> clear() async {
    // Clear must observe the same migrated snapshot that load() would expose.
    // Otherwise a failed legacy clear could restore data into an empty primary
    // store and have that stale route imported again on the next startup.
    await _ensureMigrated();
    // Clearing two independent stores is not a single atomic transaction.
    // Keep a snapshot of both before deleting either one: if the second clear
    // fails after the primary has already been emptied, the next startup must
    // not migrate the old route back from the legacy copy.
    final primaryPackages=await primary.load();
    final primaryOptimized=await primary.loadRouteOptimized();
    final legacyPackages=await legacy.load();
    final legacyOptimized=await legacy.loadRouteOptimized();

    try{
      await primary.clear();
      await legacy.clear();
      _migrationChecked=true;
    }catch(error,stackTrace){
      Object? primaryRollbackError;
      Object? legacyRollbackError;

      try{
        await primary.save(primaryPackages,routeOptimized:primaryOptimized);
      }catch(rollbackError){
        primaryRollbackError=rollbackError;
      }

      try{
        await legacy.save(legacyPackages,routeOptimized:legacyOptimized);
      }catch(rollbackError){
        legacyRollbackError=rollbackError;
      }

      // Re-check migration on the next read. If restoring the primary failed
      // but the legacy rollback succeeded, migration can still recover the data.
      _migrationChecked=false;

      if(primaryRollbackError!=null||legacyRollbackError!=null){
        final failures=<String>[
          if(primaryRollbackError!=null)
            'primary rollback failed: $primaryRollbackError',
          if(legacyRollbackError!=null)
            'legacy rollback failed: $legacyRollbackError',
        ];
        Error.throwWithStackTrace(
          StateError(
            'Package store clear failed: $error. '
            'Rollback was incomplete: ${failures.join('; ')}',
          ),
          stackTrace,
        );
      }

      Error.throwWithStackTrace(error,stackTrace);
    }
  }
}
