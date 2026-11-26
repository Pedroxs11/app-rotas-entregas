import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/screens/load_screen.dart';
import 'package:app_rotas_entregas/services/package_store.dart';

class _RedistributionStore implements PackageStore {
  _RedistributionStore(this.items);

  List<DeliveryPackage> items;
  int saves = 0;

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
    saves++;
  }
}

DeliveryPackage _package(
  int number, {
  String? zone,
  DeliveryStatus status = DeliveryStatus.pending,
}) =>
    DeliveryPackage(
      id: 'redistribution-$number',
      scanNumber: number,
      physicalZone: zone,
      status: status,
      address: AddressData(
        raw: 'Rua Teste, $number',
        street: 'Rua Teste',
        number: '$number',
        city: 'São Paulo',
        state: 'SP',
        confidence: 1,
        validation: ValidationStatus.confirmed,
      ),
      scannedAt: DateTime.utc(2026, 11, 26, 10, number),
    );

Future<void> _selectAssignedChip(
  WidgetTester tester,
  String label,
) async {
  final chip = find.widgetWithText(InputChip, label);
  expect(chip, findsOneWidget);
  // Assigned chips live inside the vehicle diagram, below the fixed
  // summary card. Scroll the organizer until the chip is fully visible before
  // tapping; this avoids false misses when CI uses a shorter viewport.
  final scrollable = find.descendant(
    of: find.byType(CustomScrollView),
    matching: find.byType(Scrollable),
  ).first;
  await tester.scrollUntilVisible(chip, 120, scrollable: scrollable);
  await tester.pumpAndSettle();
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'selected packages can be redistributed and removed without moving other packages for car and motorcycle',
    (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final vehicle in VehicleType.values) {
        final isMotorcycle = vehicle == VehicleType.motorcycle;
        final firstZone = isMotorcycle
            ? 'Baú traseiro'
            : 'Frente esquerda';
        final secondZone = isMotorcycle
            ? 'Bolsa lateral esquerda'
            : 'Frente direita';
        final targetZone = isMotorcycle
            ? 'Bolsa lateral direita'
            : 'Porta-malas';
        final targetLabel = isMotorcycle ? 'BOLSA DIREITA' : 'PORTA-MALAS';

        SharedPreferences.setMockInitialValues({
          'load_vehicle_type': vehicle.name,
        });

        final store = _RedistributionStore([
          _package(1, zone: firstZone),
          _package(2, zone: secondZone),
          _package(3, zone: firstZone),
          _package(4, zone: secondZone),
          _package(5),
          _package(
            6,
            zone: firstZone,
            status: DeliveryStatus.delivered,
          ),
        ]);
        final state = AppState(store: store);
        await state.init();

        await tester.pumpWidget(
          MaterialApp(home: LoadScreen(state: state)),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('Selecionar vários'));
        await tester.pumpAndSettle();

        // Select packages from two different compartments, then move both
        // through the same compartment tap used by the driver.
        await _selectAssignedChip(tester, 'P01');
        await _selectAssignedChip(tester, 'P04');
        expect(find.text('2 pacote(s) selecionado(s)'), findsOneWidget);

        final targetCompartment = find.text(targetLabel);
        await tester.ensureVisible(targetCompartment);
        await tester.tap(targetCompartment);
        await tester.pumpAndSettle();

        expect(state.packages[0].physicalZone, targetZone);
        expect(state.packages[1].physicalZone, secondZone);
        expect(state.packages[2].physicalZone, firstZone);
        expect(state.packages[3].physicalZone, targetZone);
        expect(state.packages[4].physicalZone, isNull);
        expect(state.packages[5].physicalZone, firstZone);
        expect(store.items.map((package) => package.physicalZone).toList(), [
          targetZone,
          secondZone,
          firstZone,
          targetZone,
          null,
          firstZone,
        ]);
        expect(find.text('0 pacote(s) selecionado(s)'), findsOneWidget);

        // Remove one reassigned package from its compartment. This must clear
        // only its physical position, not delete it or affect the other load.
        await _selectAssignedChip(tester, 'P01');
        final removeButton = find.text('RETIRAR PACOTE SELECIONADO');
        await tester.ensureVisible(removeButton);
        await tester.tap(removeButton);
        await tester.pumpAndSettle();

        expect(state.packages, hasLength(6));
        expect(state.packages[0].physicalZone, isNull);
        expect(state.packages[1].physicalZone, secondZone);
        expect(state.packages[2].physicalZone, firstZone);
        expect(state.packages[3].physicalZone, targetZone);
        expect(state.packages[4].physicalZone, isNull);
        expect(state.packages[5].status, DeliveryStatus.delivered);
        expect(state.packages[5].physicalZone, firstZone);
        expect(store.items, hasLength(6));
        expect(find.text('0 pacote(s) selecionado(s)'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        state.dispose();

        // A new AppState simulates closing and reopening the app. All active
        // positions, the removed package, and delivered history must survive.
        final resumed = AppState(store: store);
        await resumed.init();

        expect(resumed.startupError, isNull);
        expect(resumed.vehicleType, vehicle);
        expect(resumed.packages, hasLength(6));
        expect(resumed.packages[0].physicalZone, isNull);
        expect(resumed.packages[1].physicalZone, secondZone);
        expect(resumed.packages[2].physicalZone, firstZone);
        expect(resumed.packages[3].physicalZone, targetZone);
        expect(resumed.packages[4].physicalZone, isNull);
        expect(resumed.packages[5].status, DeliveryStatus.delivered);
        expect(resumed.packages[5].physicalZone, firstZone);
        expect(store.saves, 2);

        resumed.dispose();
      }
    },
  );
}
