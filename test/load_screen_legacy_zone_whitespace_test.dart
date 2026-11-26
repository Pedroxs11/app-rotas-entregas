import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/screens/load_screen.dart';
import 'package:app_rotas_entregas/services/package_store.dart';

class _LegacyZoneStore implements PackageStore {
  _LegacyZoneStore(this.items);

  List<DeliveryPackage> items;

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
  }
}

class _LegacyZoneScenario {
  const _LegacyZoneScenario({
    required this.vehicle,
    required this.preferenceKey,
    required this.zone,
    required this.label,
  });

  final VehicleType vehicle;
  final String preferenceKey;
  final String zone;
  final String label;
}

DeliveryPackage _package(String legacyZone) => DeliveryPackage(
      id: 'legacy-zone-package',
      scanNumber: 1,
      physicalZone: legacyZone,
      address: AddressData(
        raw: 'Rua da Compatibilidade, 1',
        street: 'Rua da Compatibilidade',
        number: '1',
        city: 'São Paulo',
        state: 'SP',
        confidence: 1,
        validation: ValidationStatus.confirmed,
      ),
      scannedAt: DateTime.utc(2026, 11, 24),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'legacy compartment labels are normalized and remain assigned in car and motorcycle organizers',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const scenarios = <_LegacyZoneScenario>[
        _LegacyZoneScenario(
          vehicle: VehicleType.car,
          preferenceKey: 'load_zones_car',
          zone: 'Porta-malas',
          label: 'PORTA-MALAS',
        ),
        _LegacyZoneScenario(
          vehicle: VehicleType.motorcycle,
          preferenceKey: 'load_zones_motorcycle',
          zone: 'Bolsa lateral esquerda',
          label: 'BOLSA ESQUERDA',
        ),
      ];

      for (final scenario in scenarios) {
        final legacyZone = '  ${scenario.zone}  ';
        SharedPreferences.setMockInitialValues({
          'load_vehicle_type': scenario.vehicle.name,
          scenario.preferenceKey: [scenario.zone],
        });

        final store = _LegacyZoneStore([_package(legacyZone)]);
        final state = AppState(store: store);
        await state.init();

        await tester.pumpWidget(
          MaterialApp(home: LoadScreen(state: state)),
        );
        await tester.pumpAndSettle();

        final zoneLabel = find.text(scenario.label);
        expect(zoneLabel, findsOneWidget);
        final compartment = find
            .ancestor(of: zoneLabel, matching: find.byType(AnimatedContainer))
            .first;
        final assignedChip = find.descendant(
          of: compartment,
          matching: find.widgetWithText(InputChip, 'P01'),
        );

        await tester.ensureVisible(assignedChip);
        await tester.pumpAndSettle();

        expect(
          assignedChip,
          findsOneWidget,
          reason: 'A legacy label for ${scenario.zone} must still render in its compartment.',
        );
        expect(
          find.text('Pacote 01'),
          findsNothing,
          reason: 'A package already assigned to an enabled compartment must not return to the unassigned list.',
        );
        expect(
          state.packages.single.physicalZone,
          scenario.zone,
          reason: 'Legacy compartment labels must be normalized in memory.',
        );
        expect(
          store.items.single.physicalZone,
          scenario.zone,
          reason: 'The repaired compartment label must be persisted for the next launch.',
        );
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        state.dispose();
      }
    },
  );
}
