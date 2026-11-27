import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/screens/load_screen.dart';
import 'package:app_rotas_entregas/services/package_store.dart';

class _ZoneSaveStore implements PackageStore {
  _ZoneSaveStore(this.items);

  List<DeliveryPackage> items;
  Completer<void>? saveGate;
  final Completer<void> saveStarted = Completer<void>();
  bool failNextSave = false;
  int saveAttempts = 0;
  int successfulSaves = 0;

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
    saveAttempts++;
    if (!saveStarted.isCompleted) saveStarted.complete();
    final gate = saveGate;
    saveGate = null;
    if (gate != null) await gate.future;
    if (failNextSave) {
      failNextSave = false;
      throw StateError('Falha simulada ao salvar compartimentos.');
    }
    items = [...value];
    successfulSaves++;
  }
}

class _VehicleScenario {
  const _VehicleScenario({
    required this.vehicle,
    required this.zone,
    required this.otherZone,
  });

  final VehicleType vehicle;
  final String zone;
  final String otherZone;

}

DeliveryPackage _package(String zone) => DeliveryPackage(
      id: 'zone-save-package',
      scanNumber: 1,
      physicalZone: zone,
      address: AddressData(
        raw: 'Rua dos Compartimentos, 1',
        street: 'Rua dos Compartimentos',
        number: '1',
        city: 'São Paulo',
        state: 'SP',
        confidence: 1,
        validation: ValidationStatus.confirmed,
      ),
      scannedAt: DateTime.utc(2026, 11, 27, 10),
    );

const _scenarios = [
  _VehicleScenario(
    vehicle: VehicleType.car,
    zone: 'Porta-malas',
    otherZone: 'Frente esquerda',
  ),
  _VehicleScenario(
    vehicle: VehicleType.motorcycle,
    zone: 'Baú traseiro',
    otherZone: 'Bolsa lateral esquerda',
  ),
];

void _setVehiclePreferences(_VehicleScenario scenario) {
  SharedPreferences.setMockInitialValues({
    'load_vehicle_type': scenario.vehicle.name,
    'load_zones_car': scenario.vehicle == VehicleType.car
        ? [scenario.otherZone, scenario.zone]
        : AppState.carPhysicalZones,
    'load_zones_motorcycle': scenario.vehicle == VehicleType.motorcycle
        ? [scenario.otherZone, scenario.zone]
        : AppState.motorcyclePhysicalZones,
  });
}

Future<void> _openAndDisableZone(
  WidgetTester tester,
  _VehicleScenario scenario,
) async {
  await tester.tap(find.byTooltip('Configurar compartimentos'));
  await tester.pumpAndSettle();

  final checkbox = find.widgetWithText(CheckboxListTile, scenario.zone);
  await tester.ensureVisible(checkbox);
  await tester.pumpAndSettle();
  expect(tester.widget<CheckboxListTile>(checkbox).value, isTrue);
  await tester.tap(checkbox);
  await tester.pumpAndSettle();

  await tester.tap(find.widgetWithText(FilledButton, 'Salvar'));
  // The parent dialog shows an indeterminate progress indicator while the
  // confirmation dialog is open, so advance the route transition explicitly.
  await tester.pump(const Duration(milliseconds: 300));
  expect(find.text('Desativar e continuar'), findsOneWidget);
  await tester.tap(find.text('Desativar e continuar'));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'saving compartment changes locks the dialog until persistence finishes for car and motorcycle',
    (tester) async {
      tester.view.physicalSize = const Size(400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final scenario in _scenarios) {
        _setVehiclePreferences(scenario);
        final store = _ZoneSaveStore([_package(scenario.zone)]);
        final gate = Completer<void>();
        store.saveGate = gate;
        final state = AppState(store: store);
        await state.init();

        await tester.pumpWidget(MaterialApp(home: LoadScreen(state: state)));
        await tester.pumpAndSettle();

        await _openAndDisableZone(tester, scenario);
        await store.saveStarted.future;
        await tester.pump();

        expect(find.text('Salvando...'), findsOneWidget);
        final saveButton = find.ancestor(
          of: find.text('Salvando...'),
          matching: find.byType(FilledButton),
        ).first;
        final cancelButton = find.widgetWithText(TextButton, 'Cancelar');
        final checkbox = find.widgetWithText(CheckboxListTile, scenario.zone);

        expect(tester.widget<FilledButton>(saveButton).onPressed, isNull);
        expect(tester.widget<TextButton>(cancelButton).onPressed, isNull);
        expect(tester.widget<CheckboxListTile>(checkbox).onChanged, isNull);

        // Even deliberate repeat taps cannot dismiss the dialog or queue
        // another save while the first compartment update is still pending.
        await tester.tap(cancelButton, warnIfMissed: false);
        await tester.tap(saveButton, warnIfMissed: false);
        await tester.pump();
        expect(store.saveAttempts, 1);
        expect(find.text('Salvando...'), findsOneWidget);
        expect(find.text(scenario.vehicle == VehicleType.car
            ? 'Compartimentos do carro'
            : 'Compartimentos da moto'), findsOneWidget);

        gate.complete();
        await tester.pumpAndSettle();

        expect(find.text('Salvando...'), findsNothing);
        expect(find.text(scenario.vehicle == VehicleType.car
            ? 'Compartimentos do carro'
            : 'Compartimentos da moto'), findsNothing);
        expect(state.activePhysicalZones, contains(scenario.otherZone));
        expect(state.activePhysicalZones, isNot(contains(scenario.zone)));
        expect(state.packages.single.physicalZone, isNull);
        expect(store.items.single.physicalZone, isNull);
        expect(store.saveAttempts, 1);
        expect(store.successfulSaves, 1);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        state.dispose();
      }
    },
  );

  testWidgets(
    'failed compartment persistence unlocks the dialog and allows retry',
    (tester) async {
      tester.view.physicalSize = const Size(400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final scenario = _scenarios.first;
      _setVehiclePreferences(scenario);
      final store = _ZoneSaveStore([_package(scenario.zone)])
        ..failNextSave = true;
      final state = AppState(store: store);
      await state.init();

      await tester.pumpWidget(MaterialApp(home: LoadScreen(state: state)));
      await tester.pumpAndSettle();

      await _openAndDisableZone(tester, scenario);
      await tester.pumpAndSettle();

      expect(store.saveAttempts, 1);
      expect(store.successfulSaves, 0);
      expect(state.activePhysicalZones, contains(scenario.zone));
      expect(state.packages.single.physicalZone, scenario.zone);
      expect(find.textContaining('Falha simulada ao salvar compartimentos'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Salvar'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Salvar'),
        ).onPressed,
        isNotNull,
      );

      // Retry the same selection. The warning must be requested again because
      // the failed transaction restored the original package position.
      await tester.tap(find.widgetWithText(FilledButton, 'Salvar'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Desativar e continuar'), findsOneWidget);
      await tester.tap(find.text('Desativar e continuar'));
      await tester.pumpAndSettle();

      expect(store.saveAttempts, 2);
      expect(store.successfulSaves, 1);
      expect(state.activePhysicalZones, isNot(contains(scenario.zone)));
      expect(state.packages.single.physicalZone, isNull);
      expect(store.items.single.physicalZone, isNull);
      expect(find.text('Compartimentos do carro'), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      state.dispose();
    },
  );
}
