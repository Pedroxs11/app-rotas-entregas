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
  test('startup repairs an incorrectly typed vehicle preference and preserves car compartments', () async {
    SharedPreferences.setMockInitialValues({
      'load_vehicle_type': 42,
      'load_zones_car': ['Porta-malas'],
    });
    final store = LoadStore([_p(1)]);
    final state = AppState(store: store);

    await state.init();

    final prefs = await SharedPreferences.getInstance();
    expect(state.vehicleType, VehicleType.car);
    expect(state.activePhysicalZones, ['Porta-malas']);
    expect(prefs.getString('load_vehicle_type'), 'car');
    expect(store.saves, 0);
  });

  test('startup repairs an unknown vehicle preference to the car default', () async {
    SharedPreferences.setMockInitialValues({
      'load_vehicle_type': 'truck',
    });
    final state = AppState(store: LoadStore([_p(1)]));

    await state.init();

    final prefs = await SharedPreferences.getInstance();
    expect(state.vehicleType, VehicleType.car);
    expect(prefs.getString('load_vehicle_type'), 'car');
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


  test('vehicle and compartment preferences survive app restart independently', () async {
    final store = LoadStore([_p(1)]);
    final firstSession = AppState(store: store);
    await firstSession.init();

    await firstSession.setActivePhysicalZones([
      'Frente esquerda',
      'Porta-malas',
    ]);
    await firstSession.setVehicleType(VehicleType.motorcycle);
    await firstSession.setActivePhysicalZones([
      'Baú traseiro',
      'Mochila de entrega',
    ]);

    final resumedSession = AppState(store: store);
    await resumedSession.init();

    expect(resumedSession.vehicleType, VehicleType.motorcycle);
    expect(
      resumedSession.activePhysicalZones,
      ['Baú traseiro', 'Mochila de entrega'],
    );

    await resumedSession.setVehicleType(VehicleType.car);
    expect(
      resumedSession.activePhysicalZones,
      ['Frente esquerda', 'Porta-malas'],
    );

    await resumedSession.setVehicleType(VehicleType.motorcycle);
    expect(
      resumedSession.activePhysicalZones,
      ['Baú traseiro', 'Mochila de entrega'],
    );
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

  test('bulk assignment organizes 600 active packages in one persistence operation', () async {
    final packages = [
      for (var i = 1; i <= 600; i++) _p(i),
      _p(601, status: DeliveryStatus.delivered, zone: 'Porta-malas'),
    ];
    final store = LoadStore(packages);
    final state = AppState(store: store);
    await state.init();

    final activeIds = state.packages
        .where((p) => p.status != DeliveryStatus.delivered)
        .map((p) => p.id)
        .toSet();
    expect(activeIds, hasLength(600));

    await state.setPhysicalZones(activeIds, 'Porta-malas');

    expect(state.packages, hasLength(601));
    expect(
      state.packages.take(600).every((p) => p.physicalZone == 'Porta-malas'),
      isTrue,
    );
    expect(state.packages.last.status, DeliveryStatus.delivered);
    expect(state.packages.last.physicalZone, 'Porta-malas');
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

  test('disabling a compartment clears large active loads in one pass and preserves delivered history', () async {
    final packages = [
      for (var i = 1; i <= 600; i++)
        _p(i, zone: 'Porta-malas'),
      _p(601, status: DeliveryStatus.delivered, zone: 'Porta-malas'),
    ];
    final store = LoadStore(packages);
    final state = AppState(store: store);
    await state.init();

    await state.setActivePhysicalZones(['Frente esquerda']);

    expect(state.packages.take(600).every((p) => p.physicalZone == null), isTrue);
    expect(state.packages.last.physicalZone, 'Porta-malas');
    expect(store.saves, 1);
  });

  test('saving unchanged compartments repairs stale active package positions but preserves delivered history', () async {
    SharedPreferences.setMockInitialValues({
      'load_vehicle_type': 'car',
      'load_zones_car': ['Frente esquerda'],
    });
    final store = LoadStore([
      _p(1, zone: 'Porta-malas'),
      _p(2, status: DeliveryStatus.delivered, zone: 'Porta-malas'),
      _p(3, zone: ' Frente esquerda '),
    ]);
    final state = AppState(store: store);
    await state.init();

    await state.setActivePhysicalZones(['Frente esquerda']);

    expect(state.activePhysicalZones, ['Frente esquerda']);
    expect(state.packages[0].physicalZone, isNull);
    expect(state.packages[1].physicalZone, 'Porta-malas');
    expect(state.packages[2].physicalZone, 'Frente esquerda');
    expect(store.saves, 1);
  });

  test('saving the unchanged compartment setup does not persist again', () async {
    final store = LoadStore([_p(1, zone: 'Porta-malas')]);
    final state = AppState(store: store);
    await state.init();

    await state.setActivePhysicalZones(AppState.carPhysicalZones);

    expect(state.packages.single.physicalZone, 'Porta-malas');
    expect(store.saves, 0);
  });


  test('switching to a vehicle restores saved compartments in canonical physical order', () async {
    SharedPreferences.setMockInitialValues({
      'load_vehicle_type': 'car',
      'load_zones_motorcycle': [
        'Bolsa lateral direita',
        'Baú traseiro',
        'Bolsa lateral esquerda',
        'Compartimento inválido',
        'Bolsa lateral direita',
      ],
    });
    final store = LoadStore([_p(1)]);
    final state = AppState(store: store);
    await state.init();

    await state.setVehicleType(VehicleType.motorcycle);

    expect(
      state.activePhysicalZones,
      [
        'Baú traseiro',
        'Bolsa lateral esquerda',
        'Bolsa lateral direita',
      ],
    );
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getStringList('load_zones_motorcycle'),
      [
        'Baú traseiro',
        'Bolsa lateral esquerda',
        'Bolsa lateral direita',
      ],
    );
  });

  test('startup trims saved compartment names and keeps only valid car areas', () async {
    SharedPreferences.setMockInitialValues({
      'load_vehicle_type': 'car',
      'load_zones_car': [
        ' Porta-malas ',
        '',
        'Compartimento inválido',
        'Porta-malas',
      ],
    });
    final state = AppState(store: LoadStore([_p(1)]));

    await state.init();

    final prefs = await SharedPreferences.getInstance();
    expect(state.activePhysicalZones, ['Porta-malas']);
    expect(prefs.getStringList('load_zones_car'), ['Porta-malas']);
  });

  test('switching to motorcycle normalizes saved areas and preserves car setup', () async {
    SharedPreferences.setMockInitialValues({
      'load_vehicle_type': 'car',
      'load_zones_car': ['Frente esquerda', 'Porta-malas'],
      'load_zones_motorcycle': [
        ' Mochila de entrega ',
        '',
        'Mochila de entrega',
        'Compartimento inválido',
      ],
    });
    final state = AppState(store: LoadStore([_p(1)]));

    await state.init();
    await state.setVehicleType(VehicleType.motorcycle);

    expect(state.activePhysicalZones, ['Mochila de entrega']);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getStringList('load_zones_motorcycle'),
      ['Mochila de entrega'],
    );

    await state.setVehicleType(VehicleType.car);
    expect(
      state.activePhysicalZones,
      ['Frente esquerda', 'Porta-malas'],
    );
    expect(
      prefs.getStringList('load_zones_car'),
      ['Frente esquerda', 'Porta-malas'],
    );
  });

  test('package updates normalize active compartment labels and preserve delivered history', () async {
    final store = LoadStore([
      _p(1, zone: 'Porta-malas'),
      _p(2, status: DeliveryStatus.delivered, zone: 'Porta-malas'),
    ]);
    final state = AppState(store: store);
    await state.init();

    await state.update(
      0,
      state.packages[0].copyWith(physicalZone: '  Porta-malas  '),
    );
    await state.update(
      1,
      state.packages[1].copyWith(physicalZone: '  Porta-malas  '),
    );
    await state.update(
      0,
      state.packages[0].copyWith(physicalZone: '   '),
    );

    expect(state.packages[0].physicalZone, isNull);
    expect(state.packages[1].physicalZone, '  Porta-malas  ');
    expect(store.saves, 3);
  });

  test('package updates cannot restore disabled compartments and preserve custom and delivered labels', () async {
    SharedPreferences.setMockInitialValues({
      'load_vehicle_type': 'car',
      'load_zones_car': ['Frente esquerda'],
    });
    final store = LoadStore([
      _p(1),
      _p(2, zone: 'A-01'),
      _p(3, status: DeliveryStatus.delivered, zone: 'Porta-malas'),
    ]);
    final state = AppState(store: store);
    await state.init();

    await state.update(
      0,
      state.packages[0].copyWith(physicalZone: ' Porta-malas '),
    );
    await state.update(
      1,
      state.packages[1].copyWith(physicalZone: ' A-01 '),
    );
    await state.update(
      2,
      state.packages[2].copyWith(physicalZone: ' Porta-malas '),
    );

    expect(state.packages[0].physicalZone, isNull);
    expect(state.packages[1].physicalZone, 'A-01');
    expect(state.packages[2].physicalZone, ' Porta-malas ');
  });

}
