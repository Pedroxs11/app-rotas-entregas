import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/screens/load_screen.dart';
import 'package:app_rotas_entregas/services/package_store.dart';

class _IndexedZoneStore implements PackageStore {
  _IndexedZoneStore(this.items);

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

class _VehicleZoneScenario {
  const _VehicleZoneScenario({
    required this.vehicle,
    required this.firstZone,
    required this.firstLabel,
    required this.secondZone,
    required this.secondLabel,
  });

  final VehicleType vehicle;
  final String firstZone;
  final String firstLabel;
  final String secondZone;
  final String secondLabel;
}

DeliveryPackage _package(int number, String street) => DeliveryPackage(
      id: 'indexed-zone-$number',
      scanNumber: number,
      address: AddressData(
        raw: '$street, $number',
        street: street,
        number: '$number',
        city: 'São Paulo',
        state: 'SP',
        confidence: 1,
        validation: ValidationStatus.confirmed,
      ),
      scannedAt: DateTime.utc(2026, 11, 24).add(Duration(minutes: number)),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'indexed compartment groups keep search counts isolated for car and motorcycle',
    (tester) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const scenarios = <_VehicleZoneScenario>[
        _VehicleZoneScenario(
          vehicle: VehicleType.car,
          firstZone: 'Porta-malas',
          firstLabel: 'PORTA-MALAS',
          secondZone: 'Frente esquerda',
          secondLabel: 'FRENTE E',
        ),
        _VehicleZoneScenario(
          vehicle: VehicleType.motorcycle,
          firstZone: 'Bolsa lateral esquerda',
          firstLabel: 'BOLSA ESQUERDA',
          secondZone: 'Bolsa lateral direita',
          secondLabel: 'BOLSA DIREITA',
        ),
      ];

      for (final scenario in scenarios) {
        SharedPreferences.setMockInitialValues({
          'load_vehicle_type': scenario.vehicle.name,
        });

        final packages = [
          for (var number = 1; number <= 6; number++)
            _package(number, 'Rua Alfa'),
          for (var number = 7; number <= 12; number++)
            _package(number, 'Rua Beta'),
        ];
        final state = AppState(store: _IndexedZoneStore(packages));
        await state.init();
        await state.setPhysicalZones(
          packages.take(6).map((package) => package.id).toSet(),
          scenario.firstZone,
        );
        await state.setPhysicalZones(
          packages.skip(6).map((package) => package.id).toSet(),
          scenario.secondZone,
        );

        await tester.pumpWidget(
          MaterialApp(home: LoadScreen(state: state)),
        );
        await tester.pumpAndSettle();

        Finder compartment(String label) => find
            .ancestor(
              of: find.text(label),
              matching: find.byType(InkWell),
            )
            .first;

        final firstCompartment = compartment(scenario.firstLabel);
        final secondCompartment = compartment(scenario.secondLabel);

        await tester.enterText(find.byType(TextField), 'alfa');
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: firstCompartment,
            matching: find.text('6/6'),
          ),
          findsOneWidget,
          reason: 'The first vehicle compartment must keep all six Alfa matches.',
        );
        expect(
          find.descendant(
            of: secondCompartment,
            matching: find.text('0/6'),
          ),
          findsOneWidget,
          reason: 'The second vehicle compartment must not inherit another zone\'s search matches.',
        );
        expect(
          find.descendant(
            of: secondCompartment,
            matching: find.text('Sem resultados'),
          ),
          findsOneWidget,
        );

        await tester.enterText(find.byType(TextField), 'beta');
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: firstCompartment,
            matching: find.text('0/6'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: secondCompartment,
            matching: find.text('6/6'),
          ),
          findsOneWidget,
          reason: 'The second vehicle compartment must show only its own Beta matches.',
        );
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        state.dispose();
      }
    },
  );
}
