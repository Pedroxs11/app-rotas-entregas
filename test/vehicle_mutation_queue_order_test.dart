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

}
