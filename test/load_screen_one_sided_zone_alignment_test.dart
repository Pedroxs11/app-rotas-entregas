import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/screens/load_screen.dart';
import 'package:app_rotas_entregas/services/package_store.dart';

class _OneSidedZoneStore implements PackageStore {
  _OneSidedZoneStore(this.items);

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

class _ZoneScenario {
  const _ZoneScenario(
    this.vehicle,
    this.zones,
    this.label, {
    required this.isRightSide,
  });

  final VehicleType vehicle;
  final List<String> zones;
  final String label;
  final bool isRightSide;
}

DeliveryPackage _package() => DeliveryPackage(
      id: 'one-sided-zone-package',
      scanNumber: 1,
      address: AddressData(
        raw: 'Rua de teste, 1',
        street: 'Rua de teste',
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
    'single enabled vehicle compartments keep their physical left or right side',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const scenarios = <_ZoneScenario>[
        _ZoneScenario(
          VehicleType.car,
          ['Frente esquerda'],
          'FRENTE E',
          isRightSide: false,
        ),
        _ZoneScenario(
          VehicleType.car,
          ['Frente direita'],
          'FRENTE D',
          isRightSide: true,
        ),
        _ZoneScenario(
          VehicleType.motorcycle,
          ['Bolsa lateral esquerda'],
          'BOLSA ESQUERDA',
          isRightSide: false,
        ),
        _ZoneScenario(
          VehicleType.motorcycle,
          ['Bolsa lateral direita'],
          'BOLSA DIREITA',
          isRightSide: true,
        ),
      ];

      // Exercise both the narrow stacked motorcycle layout and the wider
      // three-column layout. The active compartment must never drift across
      // the vehicle centerline just because its opposite side is disabled.
      const viewports = <Size>[
        Size(320, 568),
        Size(480, 800),
      ];

      for (final viewportSize in viewports) {
        tester.view.physicalSize = viewportSize;

        for (final scenario in scenarios) {
          final zonesKey = scenario.vehicle == VehicleType.car
              ? 'load_zones_car'
              : 'load_zones_motorcycle';
          SharedPreferences.setMockInitialValues({
            'load_vehicle_type': scenario.vehicle.name,
            zonesKey: scenario.zones,
          });

          final state = AppState(
            store: _OneSidedZoneStore([_package()]),
          );
          await state.init();

          await tester.pumpWidget(
            MaterialApp(home: LoadScreen(state: state)),
          );
          await tester.pumpAndSettle();

          final label = find.text(scenario.label);
          expect(label, findsOneWidget);

          final zone = find
              .ancestor(of: label, matching: find.byType(InkWell))
              .first;
          final zoneRect = tester.getRect(zone);
          final organizerRect = tester.getRect(find.byType(CustomScrollView));

          expect(
            zoneRect.width,
            greaterThan(80),
            reason: 'The active compartment must remain a usable touch target.',
          );
          if (scenario.isRightSide) {
            expect(
              zoneRect.center.dx,
              greaterThan(organizerRect.center.dx),
              reason: '${scenario.label} must stay on the physical right side '
                  'at viewport ${viewportSize.width} px.',
            );
          } else {
            expect(
              zoneRect.center.dx,
              lessThan(organizerRect.center.dx),
              reason: '${scenario.label} must stay on the physical left side '
                  'at viewport ${viewportSize.width} px.',
            );
          }
          // Verify the physical-side invariant through the real assignment
          // flow, not only through diagram geometry. This covers one-sided
          // car seats and motorcycle bags on both compact and wider layouts.
          final packageRow = find.text('Pacote 01');
          await tester.ensureVisible(packageRow);
          await tester.pumpAndSettle();
          await tester.tap(packageRow);
          await tester.pump();

          await tester.ensureVisible(zone);
          await tester.pumpAndSettle();
          await tester.tap(zone);
          await tester.pumpAndSettle();

          expect(state.packages.single.physicalZone, scenario.zones.single);
          expect(
            find.descendant(of: zone, matching: find.text('P01')),
            findsOneWidget,
            reason: 'The package must be stored in the selected physical side.',
          );
          final assignedRect = tester.getRect(zone);
          if (scenario.isRightSide) {
            expect(assignedRect.center.dx, greaterThan(organizerRect.center.dx));
          } else {
            expect(assignedRect.center.dx, lessThan(organizerRect.center.dx));
          }
          expect(tester.takeException(), isNull);

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          state.dispose();
        }
      }
    },
  );
}
