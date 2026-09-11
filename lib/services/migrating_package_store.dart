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
    if(current.isEmpty){
      final old=await legacy.load();
      if(old.isNotEmpty){
        final optimized=await legacy.loadRouteOptimized();
        await primary.save(old,routeOptimized:optimized);
      }
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
    await primary.clear();
    await legacy.clear();
    _migrationChecked=true;
  }
}
