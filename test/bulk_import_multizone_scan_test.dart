import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/services/package_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MultiZoneStore implements PackageStore {
  _MultiZoneStore(this.items);

  bool optimized = true;

  List<DeliveryPackage> items;
  bool optimized;
  int saves = 0;

  @override
  Future<void> clear() async {
    items = [];
    optimized = false;
  }

  @override
  Future<List<DeliveryPackage>> load() async => [...items];

  @override
  Future<bool> loadRouteOptimized() async => optimized;

  @override
  Future<void> save(
    List<DeliveryPackage> value, {
    bool? routeOptimized,
  }) async {
    items = [...value];
    if (routeOptimized != null) optimized = routeOptimized;
    saves++;
  }
}

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

  test(
    'parallel scans preserve all 600 multi-zone assignments for car and motorcycle',
    () async {
      for (final vehicle in [VehicleType.car, VehicleType.motorcycle]) {
        final zones = vehicle == VehicleType.car
            ? AppState.carPhysicalZones
            : AppState.motorcyclePhysicalZones;
        final deliveredHistoryZone = vehicle == VehicleType.car
            ? 'Baú traseiro'
            : 'Porta-malas';

        SharedPreferences.setMockInitialValues({
          'load_vehicle_type': vehicle.name,
        });

        final organized = List.generate(
          600,
          (index) => _package(
            'organized-${vehicle.name}-$index',
            index + 1,
            zone: zones[index % zones.length],
          ),
        );
        final delivered = _package(
          'delivered-history-${vehicle.name}',
          601,
          zone: deliveredHistoryZone,
          status: DeliveryStatus.delivered,
        );
        final store = _MultiZoneStore([...organized, delivered]);
        final state = AppState(store: store);
        await state.init();

        expect(state.vehicleType, vehicle);
        expect(state.packages, hasLength(601));
        expect(state.routeOptimized, isTrue);

        final originalZones = {
          for (final package in organized) package.id: package.physicalZone,
        };
        final originalCounts = {
          for (final zone in zones)
            zone: organized.where((package) => package.physicalZone == zone).length,
        };

        final captured = await Future.wait([
          state.addFromText(
            'etiqueta sem endereco alpha',
            trackingCode: 'MULTI-${vehicle.name.toUpperCase()}-A',
          ),
          state.addFromText(
            'etiqueta sem endereco beta',
            trackingCode: 'MULTI-${vehicle.name.toUpperCase()}-B',
          ),
        ]);

        expect(state.packages, hasLength(603));
        expect(state.routeOptimized, isFalse);
        expect(store.optimized, isFalse);
        expect(store.saves, 2);

        for (final entry in originalZones.entries) {
          expect(
            state.packages.singleWhere((package) => package.id == entry.key).physicalZone,
            entry.value,
            reason: 'Scanning must not move ${entry.key} for $vehicle.',
          );
        }

        for (final entry in originalCounts.entries) {
          expect(
            state.packages.where((package) => package.physicalZone == entry.key).length,
            entry.value,
            reason: 'Scanning must preserve the package count in ${entry.key}.',
          );
        }

        expect(
          state.packages.singleWhere(
            (package) => package.id == delivered.id,
          ).physicalZone,
          deliveredHistoryZone,
        );
        expect(
          state.packages.singleWhere(
            (package) => package.id == delivered.id,
          ).status,
          DeliveryStatus.delivered,
        );

        expect(captured.map((package) => package.physicalZone), everyElement(isNull));
        expect(captured.map((package) => package.scanNumber).toSet(), {602, 603});
        expect(
          state.packages.map((package) => package.scanNumber).toSet(),
          hasLength(state.packages.length),
          reason: 'Concurrent scans must not reuse a scan number.',
        );
        expect(
          store.items.where((package) => package.id.startsWith('organized-')),
          hasLength(600),
        );

        // Re-open the state after the concurrent scans. All pre-existing
        // compartment assignments must survive, new scans stay unassigned,
        // and startup must not perform an unnecessary repair write.
        final savesBeforeRestart = store.saves;
        final resumed = AppState(store: store);
        await resumed.init();

        expect(resumed.vehicleType, vehicle);
        expect(resumed.packages, hasLength(603));
        expect(resumed.routeOptimized, isFalse);
        for (final entry in originalZones.entries) {
          expect(
            resumed.packages.singleWhere((package) => package.id == entry.key).physicalZone,
            entry.value,
            reason: 'Restart must preserve ${entry.key} for $vehicle.',
          );
        }
        expect(
          resumed.packages.where((package) => package.scanNumber == 602 || package.scanNumber == 603)
              .every((package) => package.physicalZone == null),
          isTrue,
        );
        final resumedHistory = resumed.packages.singleWhere(
          (package) => package.id == delivered.id,
        );
        expect(resumedHistory.status, DeliveryStatus.delivered);
        expect(resumedHistory.physicalZone, deliveredHistoryZone);
        expect(
          store.saves,
          savesBeforeRestart,
          reason: 'A clean multi-zone restart must not rewrite the stored load.',
        );
      }
    },
  );
}
