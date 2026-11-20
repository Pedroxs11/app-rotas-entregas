import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/services/package_store.dart';

class _SingleZoneStore implements PackageStore {
  _SingleZoneStore(this.items);

  List<DeliveryPackage> items;
  bool optimized = true;
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
  String? zone,
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
        confidence: 1,
        validation: ValidationStatus.confirmed,
      ),
      scannedAt: DateTime.utc(2026, 11, 20, 10, scanNumber),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'single active compartment persists for car and motorcycle without losing delivered history',
    () async {
      for (final vehicle in [VehicleType.car, VehicleType.motorcycle]) {
        final isMotorcycle = vehicle == VehicleType.motorcycle;
        final activeZone = isMotorcycle ? 'Baú traseiro' : 'Porta-malas';
        final disabledZone =
            isMotorcycle ? 'Bolsa lateral esquerda' : 'Frente esquerda';
        final deliveredHistoryZone =
            isMotorcycle ? 'Bolsa lateral direita' : 'Traseira direita';

        SharedPreferences.setMockInitialValues({
          'load_vehicle_type': vehicle.name,
        });

        final store = _SingleZoneStore([
          _package('active', 1, zone: activeZone),
          _package('disabled', 2, zone: disabledZone),
          _package('unassigned', 3),
          _package(
            'delivered',
            4,
            zone: deliveredHistoryZone,
            status: DeliveryStatus.delivered,
          ),
        ]);
        final state = AppState(store: store);
        await state.init();

        expect(state.vehicleType, vehicle);
        await state.setActivePhysicalZones([activeZone]);

        expect(state.activePhysicalZones, [activeZone]);
        expect(state.packages[0].physicalZone, activeZone);
        expect(state.packages[1].physicalZone, isNull);
        expect(state.packages[2].physicalZone, isNull);
        expect(state.packages[3].status, DeliveryStatus.delivered);
        expect(state.packages[3].physicalZone, deliveredHistoryZone);
        expect(store.saves, 1);

        final preferences = await SharedPreferences.getInstance();
        final preferenceKey =
            isMotorcycle ? 'load_zones_motorcycle' : 'load_zones_car';
        expect(preferences.getStringList(preferenceKey), [activeZone]);

        final savesBeforeRestart = store.saves;
        final resumed = AppState(store: store);
        await resumed.init();

        expect(resumed.vehicleType, vehicle);
        expect(resumed.activePhysicalZones, [activeZone]);
        expect(resumed.packages, hasLength(4));
        expect(resumed.packages[0].physicalZone, activeZone);
        expect(resumed.packages[1].physicalZone, isNull);
        expect(resumed.packages[2].physicalZone, isNull);
        expect(resumed.packages[3].status, DeliveryStatus.delivered);
        expect(resumed.packages[3].physicalZone, deliveredHistoryZone);
        expect(
          store.saves,
          savesBeforeRestart,
          reason: 'Restart must not rewrite an already reconciled $vehicle load.',
        );
      }
    },
  );
}
