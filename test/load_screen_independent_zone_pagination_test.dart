import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/screens/load_screen.dart';
import 'package:app_rotas_entregas/services/package_store.dart';

class _IndependentPaginationStore implements PackageStore {
  _IndependentPaginationStore(this.items);

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

DeliveryPackage _package(int number) => DeliveryPackage(
      id: 'independent-pagination-$number',
      scanNumber: number,
      address: AddressData(
        raw: 'Rua da Carga, $number',
        street: 'Rua da Carga',
        number: '$number',
        city: 'São Paulo',
        state: 'SP',
        confidence: 1,
        validation: ValidationStatus.confirmed,
      ),
      scannedAt: DateTime.utc(2026, 11, 27).add(Duration(minutes: number)),
    );

Future<void> _ensureVisible(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(
    tester.element(finder.first),
    alignment: 0.5,
    duration: Duration.zero,
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'expanding and collapsing one compartment never changes another compartment pagination for car and motorcycle',
    (tester) async {
      tester.view.physicalSize = const Size(400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const scenarios = [
        (
          vehicle: VehicleType.car,
          zones: ['Frente esquerda', 'Porta-malas'],
          labels: ['FRENTE E', 'PORTA-MALAS'],
        ),
        (
          vehicle: VehicleType.motorcycle,
          zones: ['Baú traseiro', 'Bolsa lateral esquerda'],
          labels: ['BAÚ TRASEIRO', 'BOLSA ESQUERDA'],
        ),
      ];

      for (final scenario in scenarios) {
        SharedPreferences.setMockInitialValues({
          'load_vehicle_type': scenario.vehicle.name,
        });

        final packages = List.generate(80, (index) => _package(index + 1));
        final store = _IndependentPaginationStore(packages);
        final state = AppState(store: store);
        await state.init();
        await state.setActivePhysicalZones(scenario.zones);

        await state.setPhysicalZones(
          packages.take(40).map((package) => package.id).toSet(),
          scenario.zones[0],
        );
        await state.setPhysicalZones(
          packages.skip(40).map((package) => package.id).toSet(),
          scenario.zones[1],
        );

        await tester.pumpWidget(
          MaterialApp(home: LoadScreen(state: state)),
        );
        await tester.pumpAndSettle();

        Finder compartment(String label) => find
            .ancestor(
              of: find.text(label),
              matching: find.byType(AnimatedContainer),
            )
            .first;

        Finder moreButton(String label) => find.descendant(
              of: compartment(label),
              matching: find.text('Ver mais 24'),
            );

        Finder lessButton(String label) => find.descendant(
              of: compartment(label),
              matching: find.text('Mostrar menos'),
            );

        Finder chips(String label) => find.descendant(
              of: compartment(label),
              matching: find.byType(InputChip),
            );

        void expectAccessibleTapTarget(Finder labelFinder) {
          final button = find.ancestor(
            of: labelFinder,
            matching: find.byType(TextButton),
          ).first;
          final size = tester.getSize(button);
          expect(size.width, greaterThanOrEqualTo(48));
          expect(size.height, greaterThanOrEqualTo(48));
        }

        // Each compartment starts with its own compact eight-package preview.
        expect(chips(scenario.labels[0]), findsNWidgets(8));
        expect(chips(scenario.labels[1]), findsNWidgets(8));

        // Expanding the first compartment must not expand the second one.
        final firstMore = moreButton(scenario.labels[0]);
        expectAccessibleTapTarget(firstMore);
        await _ensureVisible(tester, firstMore);
        await tester.tap(firstMore);
        await tester.pumpAndSettle();

        expect(chips(scenario.labels[0]), findsNWidgets(32));
        expect(chips(scenario.labels[1]), findsNWidgets(8));

        // The second compartment has an independent page counter.
        final secondMore = moreButton(scenario.labels[1]);
        expectAccessibleTapTarget(secondMore);
        await _ensureVisible(tester, secondMore);
        await tester.tap(secondMore);
        await tester.pumpAndSettle();

        expect(chips(scenario.labels[0]), findsNWidgets(32));
        expect(chips(scenario.labels[1]), findsNWidgets(32));

        // Collapsing the first compartment must leave the second expanded.
        final firstLess = lessButton(scenario.labels[0]);
        expectAccessibleTapTarget(firstLess);
        await _ensureVisible(tester, firstLess);
        await tester.tap(firstLess);
        await tester.pumpAndSettle();

        expect(chips(scenario.labels[0]), findsNWidgets(8));
        expect(chips(scenario.labels[1]), findsNWidgets(32));
        expect(state.packages, hasLength(80));
        expect(
          state.packages.where(
            (package) => package.physicalZone == scenario.zones[0],
          ),
          hasLength(40),
        );
        expect(
          state.packages.where(
            (package) => package.physicalZone == scenario.zones[1],
          ),
          hasLength(40),
        );
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        state.dispose();
      }
    },
  );
}
