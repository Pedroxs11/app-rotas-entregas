import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/screens/load_screen.dart';
import 'package:app_rotas_entregas/services/package_store.dart';

class _PaginationSemanticsStore implements PackageStore {
  _PaginationSemanticsStore(this.items);

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
      id: 'pagination-semantics-$number',
      scanNumber: number,
      address: AddressData(
        raw: 'Rua das Entregas, $number',
        street: 'Rua das Entregas',
        number: '$number',
        city: 'São Paulo',
        state: 'SP',
        confidence: 1,
        validation: ValidationStatus.confirmed,
      ),
      scannedAt: DateTime.utc(2026, 11, 27).add(Duration(minutes: number)),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'compartment pagination announces its vehicle-specific action to screen readers',
    (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      addTearDown(semantics.dispose);

      const scenarios = [
        (
          vehicle: VehicleType.car,
          zone: 'Porta-malas',
          label: 'PORTA-MALAS',
        ),
        (
          vehicle: VehicleType.motorcycle,
          zone: 'Baú traseiro',
          label: 'BAÚ TRASEIRO',
        ),
      ];

      for (final scenario in scenarios) {
        SharedPreferences.setMockInitialValues({
          'load_vehicle_type': scenario.vehicle.name,
        });
        final store = _PaginationSemanticsStore(
          List.generate(9, (index) => _package(index + 1)),
        );
        final state = AppState(store: store);
        await state.init();
        await state.setPhysicalZones(
          state.packages.map((package) => package.id).toSet(),
          scenario.zone,
        );

        await tester.pumpWidget(
          MaterialApp(home: LoadScreen(state: state)),
        );
        await tester.pumpAndSettle();

        final showMoreLabel =
            'Mostrar o próximo pacote em ${scenario.label}';
        final showMore = find.bySemanticsLabel(showMoreLabel);
        expect(showMore, findsOneWidget);
        expect(
          tester.getSemantics(showMore).hasAction(SemanticsAction.tap),
          isTrue,
          reason: 'The next-page action must be available to TalkBack.',
        );

        final visibleMoreButton = find.text('Ver mais 1');
        await Scrollable.ensureVisible(
          tester.element(visibleMoreButton),
          alignment: 0.5,
          duration: Duration.zero,
        );
        await tester.pumpAndSettle();
        await tester.tap(visibleMoreButton);
        await tester.pumpAndSettle();

        final showLessLabel = 'Mostrar menos pacotes em ${scenario.label}';
        final showLess = find.bySemanticsLabel(showLessLabel);
        expect(showLess, findsOneWidget);
        expect(
          tester.getSemantics(showLess).hasAction(SemanticsAction.tap),
          isTrue,
          reason: 'The collapse action must be available to TalkBack.',
        );

        final visibleLessButton = find.text('Mostrar menos');
        await Scrollable.ensureVisible(
          tester.element(visibleLessButton),
          alignment: 0.5,
          duration: Duration.zero,
        );
        await tester.pumpAndSettle();
        await tester.tap(visibleLessButton);
        await tester.pumpAndSettle();

        expect(find.bySemanticsLabel(showMoreLabel), findsOneWidget);
        expect(find.bySemanticsLabel(showLessLabel), findsNothing);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        state.dispose();
      }
    },
  );
}
