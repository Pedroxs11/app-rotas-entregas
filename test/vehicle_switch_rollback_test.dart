import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/services/package_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _VehicleSwitchStore implements PackageStore {
  _VehicleSwitchStore(this.items);

  List<DeliveryPackage> items;
  bool failNextSave = false;
  int saveCalls = 0;

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
    saveCalls++;
    if (failNextSave) {
      failNextSave = false;
      throw StateError('Falha simulada ao persistir a troca de veículo.');
    }
    items = [...value];
  }
}

DeliveryPackage _package() => DeliveryPackage(
      id: 'package-1',
      scanNumber: 1,
      physicalZone: 'Porta-malas',
      status: DeliveryStatus.pending,
      address: AddressData(
        raw: 'Rua Teste, 1',
        street: 'Rua Teste',
        number: '1',
        city: 'São Paulo',
        state: 'SP',
        confidence: 1,
        validation: ValidationStatus.confirmed,
      ),
      scannedAt: DateTime.utc(2026, 11, 24, 10),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'failed vehicle switch restores preferences and can be retried safely',
    () async {
      SharedPreferences.setMockInitialValues({
        'load_vehicle_type': 'car',
        'load_zones_car': ['Frente direita', 'Porta-malas'],
        'load_zones_motorcycle': ['Bolsa lateral esquerda'],
      });
      final store = _VehicleSwitchStore([_package()]);
      final state = AppState(store: store);

      await state.init();
      expect(state.vehicleType, VehicleType.car);
      expect(state.activePhysicalZones, ['Frente direita', 'Porta-malas']);

      store.failNextSave = true;
      await expectLater(
        state.setVehicleType(VehicleType.motorcycle),
        throwsA(isA<StateError>()),
      );

      final prefs = await SharedPreferences.getInstance();
      expect(state.vehicleType, VehicleType.car);
      expect(state.activePhysicalZones, ['Frente direita', 'Porta-malas']);
      expect(state.packages.single.physicalZone, 'Porta-malas');
      expect(store.items.single.physicalZone, 'Porta-malas');
      expect(prefs.getString('load_vehicle_type'), 'car');
      expect(
        prefs.getStringList('load_zones_car'),
        ['Frente direita', 'Porta-malas'],
      );
      expect(
        prefs.getStringList('load_zones_motorcycle'),
        ['Bolsa lateral esquerda'],
      );

      // The failed operation must release the serialized mutation queue.
      // Retrying should then commit the new vehicle and clear only the old
      // physical position, without losing the package itself.
      await state.setVehicleType(VehicleType.motorcycle);

      expect(state.vehicleType, VehicleType.motorcycle);
      expect(state.activePhysicalZones, ['Bolsa lateral esquerda']);
      expect(state.packages, hasLength(1));
      expect(state.packages.single.physicalZone, isNull);
      expect(store.items.single.physicalZone, isNull);
      expect(prefs.getString('load_vehicle_type'), 'motorcycle');
      expect(
        prefs.getStringList('load_zones_motorcycle'),
        ['Bolsa lateral esquerda'],
      );
      expect(store.saveCalls, 2);
    },
  );
}
