import 'dart:async';

import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/services/package_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _QueuedMutationStore implements PackageStore {
  _QueuedMutationStore(this.items);

  List<DeliveryPackage> items;
  Completer<void>? nextSaveGate;
  Completer<void>? saveStarted;
  int saveCalls = 0;
  bool failNextSave = false;

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
    final gate = nextSaveGate;
    if (gate != null) {
      nextSaveGate = null;
      final started = saveStarted;
      if (started != null && !started.isCompleted) started.complete();
      await gate.future;
    }
    if (failNextSave) {
      failNextSave = false;
      throw StateError('Falha simulada ao salvar uma alteração da carga.');
    }
    items = [...value];
  }
}

DeliveryPackage _package({String? zone}) => DeliveryPackage(
      id: 'queued-package',
      scanNumber: 1,
      physicalZone: zone,
      status: DeliveryStatus.pending,
      address: AddressData(
        raw: 'Rua da Fila, 1',
        street: 'Rua da Fila',
        number: '1',
        city: 'São Paulo',
        state: 'SP',
        confidence: 1,
        validation: ValidationStatus.confirmed,
      ),
      scannedAt: DateTime.utc(2026, 11, 25, 10),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'assignment queued during vehicle switch uses the newly selected motorcycle',
    () async {
      SharedPreferences.setMockInitialValues({'load_vehicle_type': 'car'});
      final store = _QueuedMutationStore([
        _package(zone: 'Porta-malas'),
      ]);
      final state = AppState(store: store);
      await state.init();

      final saveGate = Completer<void>();
      final saveStarted = Completer<void>();
      store.nextSaveGate = saveGate;
      store.saveStarted = saveStarted;

      try {
        final switching = state.setVehicleType(VehicleType.motorcycle);
        await saveStarted.future;

        // This call must wait behind the in-flight switch. It is valid only
        // after the motorcycle compartments become active.
        final assigning = state.setPhysicalZones(
          {'queued-package'},
          'Baú traseiro',
        );

        expect(state.vehicleType, VehicleType.car);
        expect(state.packages.single.physicalZone, 'Porta-malas');

        saveGate.complete();
        await switching;
        await assigning;

        expect(state.vehicleType, VehicleType.motorcycle);
        expect(state.activePhysicalZones, AppState.motorcyclePhysicalZones);
        expect(state.packages.single.physicalZone, 'Baú traseiro');
        expect(store.items.single.physicalZone, 'Baú traseiro');
        expect(store.saveCalls, 2);
      } finally {
        if (!saveGate.isCompleted) saveGate.complete();
        state.dispose();
      }
    },
  );

  test(
    'vehicle switch queued during assignment clears the completed car position',
    () async {
      SharedPreferences.setMockInitialValues({'load_vehicle_type': 'car'});
      final store = _QueuedMutationStore([_package()]);
      final state = AppState(store: store);
      await state.init();

      final saveGate = Completer<void>();
      final saveStarted = Completer<void>();
      store.nextSaveGate = saveGate;
      store.saveStarted = saveStarted;

      try {
        final assigning = state.setPhysicalZones(
          {'queued-package'},
          'Porta-malas',
        );
        await saveStarted.future;

        // The switch must observe the committed assignment, then remove the
        // car-only physical position before exposing the motorcycle layout.
        final switching = state.setVehicleType(VehicleType.motorcycle);

        saveGate.complete();
        await assigning;
        await switching;

        expect(state.vehicleType, VehicleType.motorcycle);
        expect(state.activePhysicalZones, AppState.motorcyclePhysicalZones);
        expect(state.packages.single.physicalZone, isNull);
        expect(store.items.single.physicalZone, isNull);
        expect(store.saveCalls, 2);
      } finally {
        if (!saveGate.isCompleted) saveGate.complete();
        state.dispose();
      }
    },
  );

  test(
    'a failed queued assignment releases the next compartment mutation',
    () async {
      SharedPreferences.setMockInitialValues({'load_vehicle_type': 'car'});
      final store = _QueuedMutationStore([_package()]);
      final state = AppState(store: store);
      await state.init();

      final saveGate = Completer<void>();
      final saveStarted = Completer<void>();
      store.nextSaveGate = saveGate;
      store.saveStarted = saveStarted;
      store.failNextSave = true;

      try {
        final failingAssignment = state.setPhysicalZones(
          {'queued-package'},
          'Porta-malas',
        );
        await saveStarted.future;

        // Queue a valid retry before the first persistence operation fails.
        // The failure must roll back only its own mutation and release the
        // queue so the following operation can commit against fresh state.
        final succeedingAssignment = state.setPhysicalZones(
          {'queued-package'},
          'Frente esquerda',
        );

        saveGate.complete();
        await expectLater(
          failingAssignment,
          throwsA(isA<StateError>()),
        );
        await succeedingAssignment;

        expect(state.vehicleType, VehicleType.car);
        expect(state.packages.single.physicalZone, 'Frente esquerda');
        expect(store.items.single.physicalZone, 'Frente esquerda');
        expect(store.saveCalls, 2);
      } finally {
        if (!saveGate.isCompleted) saveGate.complete();
        state.dispose();
      }
    },
  );


  test(
    'compartment configuration queued during vehicle switch is saved for the new vehicle only',
    () async {
      SharedPreferences.setMockInitialValues({
        'load_vehicle_type': 'car',
        'load_zones_car': ['Frente esquerda', 'Porta-malas'],
      });
      final store = _QueuedMutationStore([
        _package(zone: 'Porta-malas'),
      ]);
      final state = AppState(store: store);
      await state.init();

      final saveGate = Completer<void>();
      final saveStarted = Completer<void>();
      store.nextSaveGate = saveGate;
      store.saveStarted = saveStarted;

      try {
        final switching = state.setVehicleType(VehicleType.motorcycle);
        await saveStarted.future;

        // The configuration request arrives while the car-to-moto switch is
        // persisting. It must run after the switch and target the motorcycle,
        // rather than accidentally replacing the car's saved compartments.
        final configuring = state.setActivePhysicalZones([
          'Baú traseiro',
          'Bolsa lateral esquerda',
        ]);

        expect(state.vehicleType, VehicleType.car);
        expect(state.activePhysicalZones, ['Frente esquerda', 'Porta-malas']);

        saveGate.complete();
        await switching;
        await configuring;

        expect(state.vehicleType, VehicleType.motorcycle);
        expect(
          state.activePhysicalZones,
          ['Baú traseiro', 'Bolsa lateral esquerda'],
        );
        expect(state.packages.single.physicalZone, isNull);

        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getStringList('load_zones_car'),
          ['Frente esquerda', 'Porta-malas'],
        );
        expect(
          prefs.getStringList('load_zones_motorcycle'),
          ['Baú traseiro', 'Bolsa lateral esquerda'],
        );

        await state.setVehicleType(VehicleType.car);
        expect(
          state.activePhysicalZones,
          ['Frente esquerda', 'Porta-malas'],
        );
        await state.setVehicleType(VehicleType.motorcycle);
        expect(
          state.activePhysicalZones,
          ['Baú traseiro', 'Bolsa lateral esquerda'],
        );
      } finally {
        if (!saveGate.isCompleted) saveGate.complete();
        state.dispose();
      }
    },
  );


  test(
    'a failed compartment configuration restores preferences and releases the next mutation',
    () async {
      SharedPreferences.setMockInitialValues({
        'load_vehicle_type': 'car',
        'load_zones_car': ['Frente esquerda', 'Porta-malas'],
      });
      final store = _QueuedMutationStore([
        _package(zone: 'Porta-malas'),
      ]);
      final state = AppState(store: store);
      await state.init();

      store.failNextSave = true;

      try {
        // Disabling the trunk requires clearing its package assignment. If
        // that SQLite/store write fails, the old configuration and package
        // position must both be restored before the next queued mutation.
        final failingConfiguration = state.setActivePhysicalZones([
          'Frente esquerda',
        ]);
        final succeedingAssignment = state.setPhysicalZones(
          {'queued-package'},
          'Frente esquerda',
        );

        await expectLater(
          failingConfiguration,
          throwsA(isA<StateError>()),
        );
        await succeedingAssignment;

        expect(state.vehicleType, VehicleType.car);
        expect(
          state.activePhysicalZones,
          ['Frente esquerda', 'Porta-malas'],
        );
        expect(state.packages.single.physicalZone, 'Frente esquerda');
        expect(store.items.single.physicalZone, 'Frente esquerda');
        expect(store.saveCalls, 2);

        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getStringList('load_zones_car'),
          ['Frente esquerda', 'Porta-malas'],
        );
      } finally {
        state.dispose();
      }
    },
  );


  test(
    'a failed vehicle switch releases the queue and applies the next mutation to the restored vehicle',
    () async {
      SharedPreferences.setMockInitialValues({
        'load_vehicle_type': 'car',
        'load_zones_car': ['Frente esquerda', 'Porta-malas'],
        'load_zones_motorcycle': ['Bolsa lateral esquerda'],
      });
      final store = _QueuedMutationStore([
        _package(zone: 'Porta-malas'),
      ]);
      final state = AppState(store: store);
      await state.init();

      final saveGate = Completer<void>();
      final saveStarted = Completer<void>();
      store.nextSaveGate = saveGate;
      store.saveStarted = saveStarted;
      store.failNextSave = true;

      try {
        final switching = state.setVehicleType(VehicleType.motorcycle);
        await saveStarted.future;

        // This car-only assignment is queued while the switch is saving.
        // If the switch fails, the queue must continue using the restored
        // car configuration instead of leaving a stale motorcycle state.
        final assigning = state.setPhysicalZones(
          {'queued-package'},
          'Frente esquerda',
        );

        expect(state.vehicleType, VehicleType.car);
        expect(state.activePhysicalZones, ['Frente esquerda', 'Porta-malas']);

        saveGate.complete();
        await expectLater(
          switching,
          throwsA(isA<StateError>()),
        );
        await assigning;

        expect(state.vehicleType, VehicleType.car);
        expect(state.activePhysicalZones, ['Frente esquerda', 'Porta-malas']);
        expect(state.packages.single.physicalZone, 'Frente esquerda');
        expect(store.items.single.physicalZone, 'Frente esquerda');
        expect(store.saveCalls, 2);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('load_vehicle_type'), 'car');
        expect(
          prefs.getStringList('load_zones_car'),
          ['Frente esquerda', 'Porta-malas'],
        );
        expect(
          prefs.getStringList('load_zones_motorcycle'),
          ['Bolsa lateral esquerda'],
        );
      } finally {
        if (!saveGate.isCompleted) saveGate.complete();
        state.dispose();
      }
    },
  );


  test(
    'a compartment configuration queued during a failed vehicle switch applies to the restored car',
    () async {
      SharedPreferences.setMockInitialValues({
        'load_vehicle_type': 'car',
        'load_zones_car': ['Frente esquerda', 'Porta-malas'],
        'load_zones_motorcycle': ['Baú traseiro', 'Bolsa lateral direita'],
      });
      final store = _QueuedMutationStore([
        _package(zone: 'Porta-malas'),
      ]);
      final state = AppState(store: store);
      await state.init();

      final saveGate = Completer<void>();
      final saveStarted = Completer<void>();
      store.nextSaveGate = saveGate;
      store.saveStarted = saveStarted;
      store.failNextSave = true;

      try {
        final switching = state.setVehicleType(VehicleType.motorcycle);
        await saveStarted.future;

        // A configuration change queued behind a failed switch must use the
        // restored car, not the motorcycle whose persistence was rejected.
        final configuring = state.setActivePhysicalZones([
          'Frente esquerda',
        ]);

        expect(state.vehicleType, VehicleType.car);
        expect(
          state.activePhysicalZones,
          ['Frente esquerda', 'Porta-malas'],
        );

        saveGate.complete();
        await expectLater(
          switching,
          throwsA(isA<StateError>()),
        );
        await configuring;

        expect(state.vehicleType, VehicleType.car);
        expect(state.activePhysicalZones, ['Frente esquerda']);
        expect(state.packages.single.physicalZone, isNull);
        expect(store.items.single.physicalZone, isNull);
        expect(store.saveCalls, 2);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('load_vehicle_type'), 'car');
        expect(
          prefs.getStringList('load_zones_car'),
          ['Frente esquerda'],
        );
        expect(
          prefs.getStringList('load_zones_motorcycle'),
          ['Baú traseiro', 'Bolsa lateral direita'],
        );
      } finally {
        if (!saveGate.isCompleted) saveGate.complete();
        state.dispose();
      }
    },
  );


  test(
    'vehicle switch queued behind a failed compartment configuration uses restored car settings',
    () async {
      SharedPreferences.setMockInitialValues({
        'load_vehicle_type': 'car',
        'load_zones_car': ['Frente esquerda', 'Porta-malas'],
        'load_zones_motorcycle': ['Baú traseiro', 'Bolsa lateral direita'],
      });
      final store = _QueuedMutationStore([
        _package(zone: 'Porta-malas'),
      ]);
      final state = AppState(store: store);
      await state.init();
      store.failNextSave = true;

      try {
        // Disabling an occupied car compartment fails first. The queued
        // vehicle switch must observe the rolled-back car configuration and
        // clear its physical assignment only as part of the successful switch.
        final configuring = state.setActivePhysicalZones([
          'Frente esquerda',
        ]);
        final switching = state.setVehicleType(VehicleType.motorcycle);

        await expectLater(
          configuring,
          throwsA(isA<StateError>()),
        );
        await switching;

        expect(state.vehicleType, VehicleType.motorcycle);
expect(
            state.activePhysicalZones,
            ['Baú traseiro', 'Bolsa lateral direita'],
          );
        expect(state.packages.single.physicalZone, isNull);
        expect(store.items.single.physicalZone, isNull);
        expect(store.saveCalls, 2);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('load_vehicle_type'), 'motorcycle');
        expect(
          prefs.getStringList('load_zones_car'),
          ['Frente esquerda', 'Porta-malas'],
        );
        expect(
          prefs.getStringList('load_zones_motorcycle'),
          ['Baú traseiro', 'Bolsa lateral direita'],
        );
      } finally {
        state.dispose();
      }
    },
  );

}
