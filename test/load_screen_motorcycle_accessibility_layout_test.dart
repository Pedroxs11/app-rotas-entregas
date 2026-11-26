import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/screens/load_screen.dart';
import 'package:app_rotas_entregas/services/package_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _AccessibilityLayoutStore implements PackageStore {
  _AccessibilityLayoutStore(this.items);

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

DeliveryPackage _package() => DeliveryPackage(
      id: 'motorcycle-accessibility-package',
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
      scannedAt: DateTime.utc(2026, 11, 26),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'motorcycle side bag keeps its physical side with enlarged system text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const scenarios = [
        (
          zone: 'Bolsa lateral esquerda',
          label: 'BOLSA ESQUERDA',
          isRightSide: false,
        ),
        (
          zone: 'Bolsa lateral direita',
          label: 'BOLSA DIREITA',
          isRightSide: true,
        ),
      ];

      for (final scenario in scenarios) {
        SharedPreferences.setMockInitialValues({
          'load_vehicle_type': 'motorcycle',
          'load_zones_motorcycle': [scenario.zone],
        });
        final state = AppState(
          store: _AccessibilityLayoutStore([_package()]),
        );
        await state.init();

        final accessibleMedia = MediaQueryData.fromView(tester.view).copyWith(
          textScaler: TextScaler.linear(1.3),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: accessibleMedia,
              child: LoadScreen(state: state),
            ),
          ),
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
          reason: 'The side bag must remain a usable touch target.',
        );
        if (scenario.isRightSide) {
          expect(
            zoneRect.center.dx,
            greaterThan(organizerRect.center.dx),
            reason: 'The right bag must not move to the left at 130% text scale.',
          );
        } else {
          expect(
            zoneRect.center.dx,
            lessThan(organizerRect.center.dx),
            reason: 'The left bag must not move to the right at 130% text scale.',
          );
        }
        // Exercise the real assignment flow at the smallest supported width.
        // The selected package must land in the exact physical side that remains
        // enabled, even after the compact diagram stacks the motorcycle above it.
        final packageRow = find.text('Pacote 01');
        final scrollable = find.descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        ).first;
        await tester.scrollUntilVisible(
          packageRow,
          120,
          scrollable: scrollable,
        );
        await tester.pumpAndSettle();
        await tester.tap(packageRow);
        await tester.pump();
        await tester.ensureVisible(zone);
        await tester.pumpAndSettle();
        await tester.tap(zone);
        await tester.pumpAndSettle();

        expect(state.packages.single.physicalZone, scenario.zone);
        expect(
          find.descendant(of: zone, matching: find.text('P01')),
          findsOneWidget,
        );
        final assignedZoneRect = tester.getRect(zone);
        if (scenario.isRightSide) {
          expect(assignedZoneRect.center.dx, greaterThan(organizerRect.center.dx));
        } else {
          expect(assignedZoneRect.center.dx, lessThan(organizerRect.center.dx));
        }
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        state.dispose();
      }
    },
  );
}
