import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/services/package_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FailOnceZoneStore implements PackageStore {
  _FailOnceZoneStore(this.items);

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
      throw StateError('Falha simulada ao salvar os compartimentos.');
    }
    items = [...value];
  }
}

DeliveryPackage _package({
  required String id,
  required int scanNumber,
  required String zone,
}) =>
    DeliveryPackage(
      id: id,
      scanNumber: scanNumber,
      physicalZone: zone,
      status: DeliveryStatus.pending,
      address: AddressData(
        raw: 'Rua Teste, $scanNumber',
        street: 'Rua Teste',
        number: '$scanNumber',
        city: 'São Paulo',
        state: 'SP',
        confidence: 1,
        validation: ValidationStatus.confirmed,
      ),
      scannedAt: DateTime.utc(2026, 11, 25, 10, scanNumber),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'failed compartment removal rolls back preferences and package positions, then can be retried',
    () async {
      SharedPreferences.setMockInitialValues({
        'load_vehicle_type': 'car',
        'load_zones_car': ['Frente esquerda', 'Porta-malas'],
      });
      final store = _FailOnceZoneStore([
        _package(
          id: 'trunk-package',
          scanNumber: 1,
          zone: 'Porta-malas',
        ),
      ]);
      final state = AppState(store: store);

      await state.init();
      expect(state.activePhysicalZones, ['Frente esquerda', 'Porta-malas']);
      expect(state.packages.single.physicalZone, 'Porta-malas');

      store.failNextSave = true;
      await expectLater(
        state.setActivePhysicalZones(['Frente esquerda']),
        throwsA(isA<StateError>()),
      );

      final preferences = await SharedPreferences.getInstance();
      expect(state.vehicleType, VehicleType.car);
      expect(state.activePhysicalZones, ['Frente esquerda', 'Porta-malas']);
      expect(state.packages.single.physicalZone, 'Porta-malas');
      expect(store.items.single.physicalZone, 'Porta-malas');
      expect(
        preferences.getStringList('load_zones_car'),
        ['Frente esquerda', 'Porta-malas'],
      );

      // A failed destructive configuration must release the serialized queue.
      // Retrying should clear the package position and persist the new settings.
      await state.setActivePhysicalZones(['Frente esquerda']);

      expect(state.activePhysicalZones, ['Frente esquerda']);
      expect(state.packages.single.physicalZone, isNull);
      expect(store.items.single.physicalZone, isNull);
      expect(preferences.getStringList('load_zones_car'), ['Frente esquerda']);
      expect(store.saveCalls, 2);
      state.dispose();
    },
  );
}
