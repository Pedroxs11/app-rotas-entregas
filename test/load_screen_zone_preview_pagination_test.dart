import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/screens/load_screen.dart';
import 'package:app_rotas_entregas/services/package_store.dart';

class _ZonePreviewStore implements PackageStore {
  _ZonePreviewStore(this.items);

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
      id: 'zone-preview-$number',
      scanNumber: number,
      address: AddressData(
        raw: 'Rua Teste, $number',
        street: 'Rua Teste',
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
    'large car and motorcycle compartments reveal assigned packages in bounded batches',
    (tester) async {
      tester.view.physicalSize = const Size(320, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final vehicle in VehicleType.values) {
        SharedPreferences.setMockInitialValues({
          'load_vehicle_type': vehicle.name,
        });
        final store = _ZonePreviewStore(
          List.generate(600, (index) => _package(index + 1)),
        );
        final state = AppState(store: store);
        await state.init();

        final targetZone = vehicle == VehicleType.car
            ? 'Porta-malas'
            : 'Baú traseiro';
        final targetLabel = vehicle == VehicleType.car
            ? 'PORTA-MALAS'
            : 'BAÚ TRASEIRO';
        await state.setPhysicalZones(
          state.packages.map((package) => package.id).toSet(),
          targetZone,
        );

        await tester.pumpWidget(
          MaterialApp(home: LoadScreen(state: state)),
        );
        await tester.pumpAndSettle();

        final targetCompartment = find.text(targetLabel);
        await tester.ensureVisible(targetCompartment);
        await tester.pumpAndSettle();

        // Only the first eight chips are built initially, even when one
        // compartment contains the entire 600-package load.
        expect(find.byType(InputChip), findsNWidgets(8));
        expect(find.text('P08'), findsOneWidget);
        expect(find.text('P09'), findsNothing);

        final firstBatch = find.text('Ver mais 24');
        await tester.ensureVisible(firstBatch);
        await tester.tap(firstBatch);
        await tester.pumpAndSettle();

        expect(find.byType(InputChip), findsNWidgets(32));
        expect(find.text('P32'), findsOneWidget);
        expect(find.text('P33'), findsNothing);

        final secondBatch = find.text('Ver mais 24');
        await tester.ensureVisible(secondBatch);
        await tester.tap(secondBatch);
        await tester.pumpAndSettle();

        expect(find.byType(InputChip), findsNWidgets(56));
        expect(find.text('P56'), findsOneWidget);
        expect(find.text('P57'), findsNothing);

        // Searching a package assigned beyond the visible batch must still
        // reveal it without requiring the driver to expand hundreds of chips.
        await tester.ensureVisible(find.byType(TextField));
        await tester.enterText(find.byType(TextField), '600');
        await tester.pumpAndSettle();

        expect(find.byType(InputChip), findsOneWidget);
        expect(find.text('P600'), findsOneWidget);
        expect(find.text('1/600'), findsOneWidget);

        await tester.tap(find.byTooltip('Limpar busca'));
        await tester.pumpAndSettle();

        // Clearing search restores the driver's previous expansion position.
        expect(find.byType(InputChip), findsNWidgets(56));
        expect(find.text('P56'), findsOneWidget);
        expect(find.text('P57'), findsNothing);

        final collapse = find.text('Mostrar menos');
        await tester.ensureVisible(collapse);
        await tester.tap(collapse);
        await tester.pumpAndSettle();

        expect(find.byType(InputChip), findsNWidgets(8));
        expect(find.text('P08'), findsOneWidget);
        expect(find.text('P09'), findsNothing);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        state.dispose();
      }
    },
  );
}
