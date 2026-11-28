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
    'drag selection auto-scrolls through a 1000-package route for car and motorcycle',
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
          List.generate(1000, (index) => _package(index + 1)),
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
        final scrollPosition =
            tester.state<ScrollableState>(scrollable).position;
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
        // Auto-scroll hit-testing runs after layout; pump once more so the
        // selected-count label reflects that final post-frame selection.
        await tester.pump();

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
        // The diagram is the first SliverToBoxAdapter and may be unmounted
        // after auto-scroll moves the lazy viewport far down the package list.
        // Scroll back until the target zone is built again before tapping it.
        // The vehicle diagram is at the beginning of the same scroll view.
        // Jump to its known boundary instead of asking scrollUntilVisible to
        // locate a possibly unmounted sliver child.
        scrollPosition.jumpTo(scrollPosition.minScrollExtent);
        await tester.pumpAndSettle();
        expect(targetCompartment, findsOneWidget);
        // The vehicle diagram can begin just below the root viewport on a
        // compact test device even at minScrollExtent. Bring the actual
        // destination tile into the hit-testable area before tapping it.
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


  testWidgets(
    'drag selection auto-scrolls upward through a 1000-package route for car and motorcycle',
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
          List.generate(1000, (index) => _package(index + 1)),
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
        final lastPackage = find.text('Pacote 1000');
        final scrollPosition =
            tester.state<ScrollableState>(scrollable).position;
        // scrollUntilVisible cannot discover a lazy child that has not been
        // built yet. Move to the end of this viewport first, then assert that
        // the final package is mounted and visible before starting the drag.
        scrollPosition.jumpTo(scrollPosition.maxScrollExtent);
        await tester.pumpAndSettle();
        expect(lastPackage, findsOneWidget);

        final viewport = tester.getRect(find.byType(CustomScrollView));
        final lastRect = tester.getRect(lastPackage);
        expect(lastRect.top, greaterThanOrEqualTo(viewport.top));
        expect(lastRect.bottom, lessThanOrEqualTo(viewport.bottom));

        final gesture = await tester.startGesture(
          tester.getCenter(lastPackage),
        );
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.text('1 pacote(s) selecionado(s)'), findsOneWidget);

        // Holding near the upper edge must scroll toward the start of the
        // lazy list and select every row that passes under the pointer.
        await gesture.moveTo(
          Offset(viewport.center.dx, viewport.top + 20),
          timeStamp: const Duration(milliseconds: 700),
        );
        for (var frame = 0; frame < 60; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        // Auto-scroll hit-testing runs after layout; pump once more so the
        // selected-count label reflects that final post-frame selection.
        await tester.pump();

        final selectionLabel = find.textContaining(
          'pacote(s) selecionado(s)',
        );
        expect(selectionLabel, findsOneWidget);
        final selectedText = tester.widget<Text>(selectionLabel).data!;
        final selectedCount = int.parse(selectedText.split(' ').first);
        expect(
          selectedCount,
          greaterThan(1),
          reason: 'Holding a drag at the upper edge must select rows while scrolling in $vehicle mode.',
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
        // Return to the known start boundary so the diagram sliver is
        // mounted before tapping the destination compartment.
        scrollPosition.jumpTo(scrollPosition.minScrollExtent);
        await tester.pumpAndSettle();
        expect(targetCompartment, findsOneWidget);
        // The vehicle diagram can begin just below the root viewport on a
        // compact test device even at minScrollExtent. Bring the actual
        // destination tile into the hit-testable area before tapping it.
        await tester.ensureVisible(targetCompartment);
        await tester.pumpAndSettle();
        await tester.tap(targetCompartment);
        await tester.pumpAndSettle();

        final assigned = state.packages
            .where((package) => package.physicalZone == targetZone)
            .toList(growable: false);
        expect(assigned.length, selectedCount);
        expect(
          assigned.map((package) => package.scanNumber).toSet(),
          containsAll(
            List.generate(selectedCount, (index) => 1000 - index),
          ),
        );
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        state.dispose();
      }
    },
  );

  testWidgets(
    'short viewport keeps the center drag band neutral for car and motorcycle',
    (tester) async {
      tester.view.physicalSize = const Size(360, 240);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final vehicle in [VehicleType.car, VehicleType.motorcycle]) {
        SharedPreferences.setMockInitialValues({
          'load_vehicle_type': vehicle.name,
        });
        final store = _AutoScrollStore(
          List.generate(1000, (index) => _package(index + 1)),
        );
        final state = AppState(store: store);
        await state.init();

        await tester.pumpWidget(
          MaterialApp(home: LoadScreen(state: state)),
        );
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'The organizer header must not overflow a 240 px viewport in $vehicle mode.',
        );
        await tester.tap(find.byTooltip('Selecionar vários'));
        await tester.pumpAndSettle();

        final scrollable = find.descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        ).first;
        final scrollPosition =
            tester.state<ScrollableState>(scrollable).position;
        final package = find.text('Pacote 100');
        await tester.scrollUntilVisible(
          package,
          80,
          scrollable: scrollable,
        );
        await tester.ensureVisible(package);
        await tester.pumpAndSettle();

        final viewport = tester.getRect(find.byType(CustomScrollView));
        final packageRect = tester.getRect(package);
        expect(packageRect.top, greaterThanOrEqualTo(viewport.top));
        expect(packageRect.bottom, lessThanOrEqualTo(viewport.bottom));
        expect(
          viewport.height,
          lessThan(128),
          reason: 'This regression test must exercise overlapping 64 px edge bands.',
        );

        final gesture = await tester.startGesture(tester.getCenter(package));
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.text('1 pacote(s) selecionado(s)'), findsOneWidget);
        final offsetBeforeCenterHold = scrollPosition.pixels;

        // A short viewport has a neutral center band. With two fixed 64 px
        // edge bands, the center would incorrectly be classified as the
        // upper edge and the list would scroll upward while the finger rests.
        await gesture.moveTo(
          viewport.center,
          timeStamp: const Duration(milliseconds: 700),
        );
        for (var frame = 0; frame < 60; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
        }

        expect(
          scrollPosition.pixels,
          closeTo(offsetBeforeCenterHold, 0.5),
          reason: 'Holding in the center must not trigger edge auto-scroll in $vehicle mode.',
        );

        // The lower third must remain an active edge zone after shrinking
        // the bands; a compact viewport must not lose downward auto-scroll.
        final offsetBeforeLowerEdgeHold = scrollPosition.pixels;
        await gesture.moveTo(
          Offset(viewport.center.dx, viewport.bottom - 4),
          timeStamp: const Duration(milliseconds: 1700),
        );
        for (var frame = 0; frame < 30; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(
          scrollPosition.pixels,
          greaterThan(offsetBeforeLowerEdgeHold),
          reason: 'The lower edge must still auto-scroll in $vehicle mode.',
        );

        await gesture.up();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        state.dispose();
      }
    },
  );

}
