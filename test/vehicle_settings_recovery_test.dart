import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/services/package_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _VehicleSettingsStore implements PackageStore {
  _VehicleSettingsStore(this.items);

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
  int number, {
  String? zone,
  DeliveryStatus status = DeliveryStatus.pending,
}) =>
    DeliveryPackage(
      id: id,
      scanNumber: number,
      physicalZone: zone,
      status: status,
      address: AddressData(
        raw: 'Rua Teste, $number',
        street: 'Rua Teste',
        number: '$number',
        city: 'São Paulo',
        state: 'SP',
        confidence: 1,
        validation: ValidationStatus.confirmed,
      ),
      scannedAt: DateTime.utc(2026, 11, 24, 10, number),
      completedAt: status == DeliveryStatus.delivered
          ? DateTime.utc(2026, 11, 24, 12, number)
          : null,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'repairs incorrectly typed vehicle and compartment preferences without changing package history',
    () async {
      SharedPreferences.setMockInitialValues({
        'load_vehicle_type': 42,
        'load_zones_car': 'not-a-compartment-list',
      });
      final store = _VehicleSettingsStore([
        _package('active', 1, zone: 'Frente esquerda'),
        _package(
          'delivered',
          2,
          zone: 'Porta-malas',
          status: DeliveryStatus.delivered,
        ),
      ]);
      final state = AppState(store: store);

      await state.init();

      expect(state.startupError, isNull);
      expect(state.vehicleType, VehicleType.car);
      expect(state.activePhysicalZones, AppState.carPhysicalZones);
      expect(state.packages, hasLength(2));
      expect(state.packages.first.physicalZone, 'Frente esquerda');
      expect(state.packages.last.status, DeliveryStatus.delivered);
      expect(state.packages.last.physicalZone, 'Porta-malas');
      expect(store.saves, 0);

      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('load_vehicle_type'), 'car');
      expect(
        preferences.getStringList('load_zones_car'),
        AppState.carPhysicalZones,
      );
    },
  );

  test(
    'normalizes saved motorcycle compartments into canonical order and removes stale entries',
    () async {
      SharedPreferences.setMockInitialValues({
        'load_vehicle_type': 'motorcycle',
        'load_zones_motorcycle': [
          ' Mochila de entrega ',
          'Bolsa lateral direita',
          'Baú traseiro',
          'Bolsa lateral direita',
          'Compartimento antigo',
          '',
        ],
      });
      final store = _VehicleSettingsStore([
        _package('rear', 1, zone: 'Baú traseiro'),
        _package('side', 2, zone: 'Bolsa lateral direita'),
        _package(
          'delivered',
          3,
          zone: 'Porta-malas',
          status: DeliveryStatus.delivered,
        ),
      ]);
      final state = AppState(store: store);

      await state.init();

      const expectedZones = [
        'Baú traseiro',
        'Bolsa lateral direita',
        'Mochila de entrega',
      ];
      expect(state.startupError, isNull);
      expect(state.vehicleType, VehicleType.motorcycle);
      expect(state.activePhysicalZones, expectedZones);
      expect(state.packages[0].physicalZone, 'Baú traseiro');
      expect(state.packages[1].physicalZone, 'Bolsa lateral direita');
      expect(state.packages[2].status, DeliveryStatus.delivered);
      expect(state.packages[2].physicalZone, 'Porta-malas');
      expect(store.saves, 0);

      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.getStringList('load_zones_motorcycle'),
        expectedZones,
      );
    },
  );
}
