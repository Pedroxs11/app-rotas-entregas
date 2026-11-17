import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/services/package_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoadStore implements PackageStore {
  LoadStore(this.packages);
  List<DeliveryPackage> packages;
  bool optimized = true;
  int saves = 0;

  @override
  Future<List<DeliveryPackage>> load() async => [...packages];

  @override
  Future<bool> loadRouteOptimized() async => optimized;

  @override
  Future<void> save(List<DeliveryPackage> value, {bool? routeOptimized}) async {
    packages = [...value];
    if (routeOptimized != null) optimized = routeOptimized;
    saves++;
  }

  @override
  Future<void> clear() async {
    packages = [];
    optimized = false;
  }
}

DeliveryPackage _p(
  int n, {
  DeliveryStatus status = DeliveryStatus.pending,
  String? zone,
}) =>
    DeliveryPackage(
      id: 'p$n',
      scanNumber: n,
      status: status,
      physicalZone: zone,
      address: AddressData(
        raw: 'Rua $n',
        street: 'Rua',
        number: '$n',
        city: 'São Paulo',
        state: 'SP',
        confidence: 1,
        validation: ValidationStatus.confirmed,
      ),
      scannedAt: DateTime.utc(2026, 9, 13, 22, n % 60),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('manual organization uses the five vehicle areas without auto distribution', () async {
    final store = LoadStore(List.generate(5, (i) => _p(i + 1)));
    final state = AppState(store: store);
    await state.init();

    expect(state.packages.every((p) => p.physicalZone == null), isTrue);

    await state.setPhysicalZone('p1', 'Frente esquerda');
    await state.setPhysicalZone('p2', 'Frente direita');
    await state.setPhysicalZone('p3', 'Traseira esquerda');
    await state.setPhysicalZone('p4', 'Traseira direita');
    await state.setPhysicalZone('p5', 'Porta-malas');

    expect(
      state.packages.map((p) => p.physicalZone).toList(),
      [
        'Frente esquerda',
        'Frente direita',
        'Traseira esquerda',
        'Traseira direita',
        'Porta-malas',
      ],
    );
    expect(store.saves, 5);
  });

  test('manual organization allows multiple packages in the same vehicle area', () async {
    final store = LoadStore(List.generate(8, (i) => _p(i + 1)));
    final state = AppState(store: store);
    await state.init();

    for (final p in state.packages.take(4)) {
      await state.setPhysicalZone(p.id, 'Porta-malas');
    }

    expect(
      state.packages.take(4).every((p) => p.physicalZone == 'Porta-malas'),
      isTrue,
    );
  });

  test('clears several package compartments in one persistence operation', () async {
    final store = LoadStore([
      _p(1, zone: 'Porta-malas'),
      _p(2, zone: 'Porta-malas'),
      _p(3, zone: 'Frente esquerda'),
    ]);
    final state = AppState(store: store);
    await state.init();

    await state.clearPhysicalZones({'p1', 'p2'});

    expect(
      state.packages.map((p) => p.physicalZone).toList(),
      [null, null, 'Frente esquerda'],
    );
    expect(store.saves, 1);
  });
  test('vehicle changes restore each vehicle compartment setup and clear pending positions', () async {
    final store = LoadStore([_p(1, zone: 'Frente esquerda')]);
    final state = AppState(store: store);
    await state.init();

    await state.setActivePhysicalZones(['Frente esquerda', 'Porta-malas']);
    await state.setVehicleType(VehicleType.motorcycle);
    expect(state.activePhysicalZones, AppState.motorcyclePhysicalZones);
    expect(state.packages.single.physicalZone, isNull);

    await state.setActivePhysicalZones(['Baú traseiro']);
    await state.setVehicleType(VehicleType.car);
    expect(state.activePhysicalZones, ['Frente esquerda', 'Porta-malas']);
    expect(state.packages.single.physicalZone, isNull);

    await state.setVehicleType(VehicleType.motorcycle);
    expect(state.activePhysicalZones, ['Baú traseiro']);
  });


  test('switching vehicle clears active positions but preserves delivered load history', () async {
    final store = LoadStore([
      _p(1, zone: 'Porta-malas'),
      _p(2, status: DeliveryStatus.delivered, zone: 'Porta-malas'),
    ]);
    final state = AppState(store: store);
    await state.init();

    await state.setVehicleType(VehicleType.motorcycle);

    expect(state.activePhysicalZones, AppState.motorcyclePhysicalZones);
    expect(state.packages[0].physicalZone, isNull);
    expect(state.packages[1].physicalZone, 'Porta-malas');
  });

  test('disabling a compartment clears active packages but preserves delivered history', () async {
    final store = LoadStore([
      _p(1, zone: 'Porta-malas'),
      _p(2, status: DeliveryStatus.delivered, zone: 'Porta-malas'),
    ]);
    final state = AppState(store: store);
    await state.init();

    await state.setActivePhysicalZones(['Frente esquerda']);

    expect(state.packages[0].physicalZone, isNull);
    expect(state.packages[1].physicalZone, 'Porta-malas');
  });

  test('assigns several selected packages in one persistence operation', () async {
    final store = LoadStore(List.generate(4, (i) => _p(i + 1)));
    final state = AppState(store: store);
    await state.init();

    await state.setPhysicalZones({'p1', 'p2', 'p3'}, 'Porta-malas');

    expect(
      state.packages.map((p) => p.physicalZone).toList(),
      ['Porta-malas', 'Porta-malas', 'Porta-malas', null],
    );
    expect(store.saves, 1);
  });

  test('bulk assignment rejects unknown package ids without partial changes', () async {
    final store = LoadStore(List.generate(2, (i) => _p(i + 1)));
    final state = AppState(store: store);
    await state.init();

    await expectLater(
      state.setPhysicalZones({'p1', 'missing'}, 'Porta-malas'),
      throwsA(isA<StateError>()),
    );

    expect(state.packages.every((p) => p.physicalZone == null), isTrue);
    expect(store.saves, 0);
  });

  test('bulk assignment rejects delivered packages atomically', () async {
    final store = LoadStore([
      _p(1),
      _p(2, status: DeliveryStatus.delivered, zone: 'Porta-malas'),
    ]);
    final state = AppState(store: store);
    await state.init();

    await expectLater(
      state.setPhysicalZones({'p1', 'p2'}, 'Frente esquerda'),
      throwsA(isA<StateError>()),
    );

    expect(state.packages.first.physicalZone, isNull);
    expect(state.packages.last.physicalZone, 'Porta-malas');
    expect(store.saves, 0);
  });

}
