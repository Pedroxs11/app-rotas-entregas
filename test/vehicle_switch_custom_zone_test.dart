import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/services/package_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _VehicleSwitchStore implements PackageStore {
  _VehicleSwitchStore(this.items);

  List<DeliveryPackage> items;
  int saves = 0;

  @override
  Future<void> clear() async {
    items = [];
  }

  @override
  Future<List<DeliveryPackage>> load() async => [...items];

  @override
  Future<bool> loadRouteOptimized() async => true;

  @override
  Future<void> save(
    List<DeliveryPackage> value, {
    bool? routeOptimized,
  }) async {
    items = [...value];
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
      scannedAt: DateTime.utc(2026, 11, 24, 10, scanNumber),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'switching vehicles clears known positions but preserves custom and delivered labels',
    () async {
      SharedPreferences.setMockInitialValues({
        'load_vehicle_type': 'car',
      });
      final store = _VehicleSwitchStore([
        _package('car-position', 1, zone: 'Porta-malas'),
        _package('custom-label', 2, zone: 'A-01'),
        _package(
          'delivered-history',
          3,
          zone: 'Porta-malas',
          status: DeliveryStatus.delivered,
        ),
      ]);
      final state = AppState(store: store);

      await state.init();
      expect(store.saves, 0);

      await state.setVehicleType(VehicleType.motorcycle);

      expect(state.vehicleType, VehicleType.motorcycle);
      expect(state.packages[0].physicalZone, isNull);
      expect(state.packages[1].physicalZone, 'A-01');
      expect(state.packages[2].status, DeliveryStatus.delivered);
      expect(state.packages[2].physicalZone, 'Porta-malas');
      expect(store.items.map((package) => package.physicalZone), [
        null,
        'A-01',
        'Porta-malas',
      ]);
      expect(store.saves, 1);
    },
  );

  test(
    'switching vehicles does not rewrite storage when only custom labels remain',
    () async {
      SharedPreferences.setMockInitialValues({
        'load_vehicle_type': 'car',
      });
      final store = _VehicleSwitchStore([
        _package('custom-label', 1, zone: 'A-01'),
      ]);
      final state = AppState(store: store);

      await state.init();
      await state.setVehicleType(VehicleType.motorcycle);

      expect(state.packages.single.physicalZone, 'A-01');
      expect(store.items.single.physicalZone, 'A-01');
      expect(store.saves, 0);
    },
  );

  test(
    'switching vehicles trims custom labels without clearing them',
    () async {
      SharedPreferences.setMockInitialValues({
        'load_vehicle_type': 'car',
      });
      final store = _VehicleSwitchStore([
        _package('custom-label', 1, zone: '  A-01  '),
      ]);
      final state = AppState(store: store);

      await state.init();
      expect(state.packages.single.physicalZone, 'A-01');
      expect(store.saves, 1);

      await state.setVehicleType(VehicleType.motorcycle);

      expect(state.packages.single.physicalZone, 'A-01');
      expect(store.items.single.physicalZone, 'A-01');
      expect(store.saves, 1);
    },
  );
}
