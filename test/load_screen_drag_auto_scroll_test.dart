import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/screens/load_screen.dart';
import 'package:app_rotas_entregas/services/package_store.dart';

class _AutoScrollStore implements PackageStore {
  _AutoScrollStore(this.items);

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
      id: 'auto-scroll-$number',
      scanNumber: number,
      address: AddressData(
        raw: 'Rua Auto Scroll, $number',
        street: 'Rua Auto Scroll',
        number: '$number',
        city: 'São Paulo',
        state: 'SP',
        confidence: 1,
        validation: ValidationStatus.confirmed,
      ),
      scannedAt: DateTime.utc(2026, 11, 25).add(Duration(minutes: number)),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'drag selection auto-scrolls through long package lists for car and motorcycle',
    (tester) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final vehicle in [VehicleType.car, VehicleType.motorcycle]) {
        SharedPreferences.setMockInitialValues({
          'load_vehicle_type': vehicle.name,
        });
        final store = _AutoScrollStore(
          List.generate(80, (index) => _package(index + 1)),
        );
        final state = AppState(store: store);
        await state.init();

        await tester.pumpWidget(
          MaterialApp(home: LoadScreen(state: state)),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('Selecionar vários'));
        await tester.pumpAndSettle();

        final scrollable = find.descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        ).first;
        final firstPackage = find.text('Pacote 01');
        await tester.scrollUntilVisible(
          firstPackage,
          80,
          scrollable: scrollable,
        );
        await tester.pumpAndSettle();

        final viewport = tester.getRect(find.byType(CustomScrollView));
        final firstRect = tester.getRect(firstPackage);
        expect(firstRect.top, greaterThanOrEqualTo(viewport.top));
        expect(firstRect.bottom, lessThanOrEqualTo(viewport.bottom));

        final gesture = await tester.startGesture(
          tester.getCenter(firstPackage),
        );
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.text('1 pacote(s) selecionado(s)'), findsOneWidget);

        // Keep the pointer near the viewport's lower edge. The organizer must
        // scroll the lazy list and select each row that passes under the
        // pointer, rather than stopping at the initially mounted packages.
        await gesture.moveTo(
          Offset(viewport.center.dx, viewport.bottom - 20),
          timeStamp: const Duration(milliseconds: 700),
        );
        for (var frame = 0; frame < 60; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
        }

        final selectionLabel = find.textContaining(
          'pacote(s) selecionado(s)',
        );
        expect(selectionLabel, findsOneWidget);
        final selectedText = tester.widget<Text>(selectionLabel).data!;
        final selectedCount = int.parse(selectedText.split(' ').first);
        expect(
          selectedCount,
          greaterThan(1),
          reason: 'Holding a drag at the lower edge must select rows as the list scrolls in $vehicle mode.',
        );

        await gesture.up();
        await tester.pumpAndSettle();

        final targetZone = vehicle == VehicleType.car
            ? 'Frente esquerda'
            : 'Baú traseiro';
        final targetLabel = vehicle == VehicleType.car
            ? 'FRENTE E'
            : 'BAÚ TRASEIRO';
        final targetCompartment = find.text(targetLabel);
        await tester.ensureVisible(targetCompartment);
        await tester.pumpAndSettle();
        await tester.tap(targetCompartment);
        await tester.pumpAndSettle();

        final assigned = state.packages
            .where((package) => package.physicalZone == targetZone)
            .toList(growable: false);
        expect(
          assigned.length,
          selectedCount,
          reason: 'The compartment must receive every package selected by auto-scroll.',
        );
        expect(
          assigned.map((package) => package.scanNumber).toSet(),
          containsAll(List.generate(selectedCount, (index) => index + 1)),
        );
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        state.dispose();
      }
    },
  );
}
