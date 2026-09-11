import '../domain/models.dart';

/// Persistence boundary for route/package data.
///
/// Keeping AppState dependent on this contract lets us move from the current
/// lightweight storage to a database-backed implementation without changing
/// the delivery, scanner or route logic.
abstract class PackageStore {
  Future<List<DeliveryPackage>> load();
  Future<bool> loadRouteOptimized();
  Future<void> save(List<DeliveryPackage> packages,{bool? routeOptimized});
  Future<void> clear();
}
