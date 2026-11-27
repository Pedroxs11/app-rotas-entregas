import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/screens/load_screen.dart';
import 'package:app_rotas_entregas/services/package_store.dart';

class _ConfiguredLargeLoadStore implements PackageStore {
  _ConfiguredLargeLoadStore(this.items);

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

const _carZones = ['Frente esquerda', 'Porta-malas'];
const _carLabels = {
  'Frente esquerda': 'FRENTE E',
  'Porta-malas': 'PORTA-MALAS',
};

const _motorcycleZones = [
  'Baú traseiro',
  'Bolsa lateral direita',
  'Mochila de entrega',
];
const _motorcycleLabels = {
  'Baú traseiro': 'BAÚ TRASEIRO',
  'Bolsa lateral direita': 'BOLSA DIREITA',
  'Mochila de entrega': 'MOCHILA DE ENTREGA',
};

DeliveryPackage _largeConfiguredPackage(int number, String zone) =>
    DeliveryPackage(
      id: 'configured-large-load-$number',
      scanNumber: number,
      physicalZone: zone,
      recipient: 'Destinatário $number',
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

const _initialVisiblePackageCount = 8;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    '1000-package load keeps saved car and motorcycle compartment subsets usable on a compact phone',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final vehicle in VehicleType.values) {
        final zones = vehicle == VehicleType.car
            ? _carZones
            : _motorcycleZones;
        final labels = vehicle == VehicleType.car
            ? _carLabels
            : _motorcycleLabels;

        SharedPreferences.setMockInitialValues({
          'load_vehicle_type': vehicle.name,
          'load_zones_car': _carZones,
          'load_zones_motorcycle': _motorcycleZones,
        });

        final packages = List.generate(
          1000,
          (index) => _largeConfiguredPackage(
            index + 1,
            zones[index % zones.length],
          ),
        );
        final store = _ConfiguredLargeLoadStore(packages);
        final state = AppState(store: store);
        await state.init();

        expect(state.vehicleType, vehicle);
        expect(state.activePhysicalZones, zones);
        expect(state.packages, hasLength(1000));
        expect(
          state.packages.where((package) => package.physicalZone != null),
          hasLength(1000),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: const Size(320, 568),
                textScaler: TextScaler.linear(1.3),
              ),
              child: LoadScreen(state: state),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byType(InputChip),
          findsNWidgets(zones.length * 8),
          reason: 'Each configured compartment must render its first page.',
        );

        for (final entry in labels.entries) {
          final compartment = find.ancestor(
            of: find.text(entry.value),
            matching: find.byType(AnimatedContainer),
          ).first;
          expect(
            tester.getRect(compartment).width,
            greaterThan(90),
            reason: '${entry.value} must remain usable on a compact phone.',
          );
          expect(
            find.descendant(
              of: compartment,
              matching: find.byType(InputChip),
            ),
            findsNWidgets(8),
            reason: '${entry.value} must render the bounded first page.',
          );
        }

        // Pagination must be isolated per physical compartment. Expanding
        // one zone should reveal only its next 24 packages, leaving every
        // other configured zone on the compact first page.
        final firstZone = labels.entries.first;
        final firstCompartment = find
            .ancestor(
              of: find.text(firstZone.value),
              matching: find.byType(AnimatedContainer),
            )
            .first;
        final nextPageButton = find.descendant(
          of: firstCompartment,
          matching: find.widgetWithText(TextButton, 'Ver mais 24'),
        );
        await tester.ensureVisible(nextPageButton);
        await tester.pumpAndSettle();
        await tester.tap(nextPageButton);
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: firstCompartment,
            matching: find.byType(InputChip),
          ),
          findsNWidgets(32),
          reason: 'Only the expanded compartment should show its next page.',
        );
        for (final entry in labels.entries.skip(1)) {
          final compartment = find
              .ancestor(
                of: find.text(entry.value),
                matching: find.byType(AnimatedContainer),
              )
              .first;
          expect(
            find.descendant(
              of: compartment,
              matching: find.byType(InputChip),
            ),
            findsNWidgets(8),
            reason: '${entry.value} must remain on its own first page.',
          );
        }

        final collapseButton = find.descendant(
          of: firstCompartment,
          matching: find.widgetWithText(TextButton, 'Mostrar menos'),
        );
        await tester.ensureVisible(collapseButton);
        await tester.pumpAndSettle();
        await tester.tap(collapseButton);
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: firstCompartment,
            matching: find.byType(InputChip),
          ),
          findsNWidgets(8),
          reason: 'Collapsing a compartment must restore its compact preview.',
        );
        expect(
          find.byType(InputChip),
          findsNWidgets(zones.length * _initialVisiblePackageCount),
        );

        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        state.dispose();
      }
    },
  );
}
