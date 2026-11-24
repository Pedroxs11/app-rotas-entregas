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

Future<void> _ensureLoadItemVisible(WidgetTester tester, Finder finder) async {
  final scrollable = find.descendant(
    of: find.byType(CustomScrollView),
    matching: find.byType(Scrollable),
  ).first;
  final position = tester.state<ScrollableState>(scrollable).position;
  final viewportFinder = find.byType(CustomScrollView);

  if (finder.evaluate().isEmpty && position.pixels > position.minScrollExtent) {
    position.jumpTo(position.minScrollExtent);
    await tester.pumpAndSettle();
  }

  for (var attempt = 0; attempt < 120; attempt++) {
    if (finder.evaluate().isNotEmpty) {
      final target = tester.getRect(finder.first);
      final viewport = tester.getRect(viewportFinder);
      if (target.top >= viewport.top && target.bottom <= viewport.bottom) {
        return;
      }
      final delta = target.top < viewport.top
          ? target.top - viewport.top
          : target.bottom - viewport.bottom;
      final next = (position.pixels + delta)
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      if ((next - position.pixels).abs() < 0.5) break;
      position.jumpTo(next);
    } else {
      final next = (position.pixels + 100)
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      if (next <= position.pixels) break;
      position.jumpTo(next);
    }
    await tester.pumpAndSettle();
  }

  expect(finder, findsWidgets);
  final target = tester.getRect(finder.first);
  final viewport = tester.getRect(viewportFinder);
  expect(target.top, greaterThanOrEqualTo(viewport.top));
  expect(target.bottom, lessThanOrEqualTo(viewport.bottom));
}

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
        await _ensureLoadItemVisible(tester, targetCompartment);
        await tester.pumpAndSettle();

        // Only the first eight chips are built initially, even when one
        // compartment contains the entire 600-package load.
        expect(find.byType(InputChip), findsNWidgets(8));
        expect(find.text('P08'), findsOneWidget);
        expect(find.text('P09'), findsNothing);

        final firstBatch = find.text('Ver mais 24');
        await _ensureLoadItemVisible(tester, firstBatch);
        await tester.tap(firstBatch);
        await tester.pumpAndSettle();

        expect(find.byType(InputChip), findsNWidgets(32));
        expect(find.text('P32'), findsOneWidget);
        expect(find.text('P33'), findsNothing);

        final secondBatch = find.text('Ver mais 24');
        await _ensureLoadItemVisible(tester, secondBatch);
        await tester.tap(secondBatch);
        await tester.pumpAndSettle();

        expect(find.byType(InputChip), findsNWidgets(56));
        expect(find.text('P56'), findsOneWidget);
        expect(find.text('P57'), findsNothing);

        // Searching a package assigned beyond the visible batch must still
        // reveal it without requiring the driver to expand hundreds of chips.
        await _ensureLoadItemVisible(tester, find.byType(TextField));
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
        final scrollable = find.descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        ).first;
        final position = tester.state<ScrollableState>(scrollable).position;
        final viewport = tester.getRect(find.byType(CustomScrollView));
        final target = tester.getRect(collapse);
        final scrollDelta = target.bottom - viewport.bottom + 8;
        position.jumpTo(
          (position.pixels + scrollDelta)
              .clamp(position.minScrollExtent, position.maxScrollExtent)
              .toDouble(),
        );
        await tester.pumpAndSettle();
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

  testWidgets(
    'clearing an empty compartment resets its next preview to the initial batch',
    (tester) async {
      tester.view.physicalSize = const Size(320, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({
        'load_vehicle_type': VehicleType.car.name,
      });

      final store = _ZonePreviewStore(
        List.generate(9, (index) => _package(index + 1)),
      );
      final state = AppState(store: store);
      await state.init();
      await state.setPhysicalZones(
        state.packages.map((package) => package.id).toSet(),
        'Porta-malas',
      );

      await tester.pumpWidget(MaterialApp(home: LoadScreen(state: state)));
      await tester.pumpAndSettle();

      final trunk = find.text('PORTA-MALAS');
      await _ensureLoadItemVisible(tester, trunk);
      final showOneMore = find.text('Ver mais 1');
      await _ensureLoadItemVisible(tester, showOneMore);
      await tester.tap(showOneMore);
      await tester.pumpAndSettle();
      expect(find.byType(InputChip), findsNWidgets(9));

      // Remove the complete load from the compartment.
      await tester.tap(find.byTooltip('Selecionar vários'));
      await tester.pumpAndSettle();
      for (var packageNumber = 1; packageNumber <= 9; packageNumber++) {
        final chip = find.widgetWithText(
          InputChip,
          'P${packageNumber.toString().padLeft(2, '0')}',
        );
        await _ensureLoadItemVisible(tester, chip);
        await tester.tap(chip);
        await tester.pump();
      }
      expect(find.text('9 pacote(s) selecionado(s)'), findsOneWidget);

      final removeAll = find.text('RETIRAR 9 PACOTES');
      await _ensureLoadItemVisible(tester, removeAll);
      await tester.tap(removeAll);
      await tester.pumpAndSettle();
      expect(
        state.packages.every((package) => package.physicalZone == null),
        isTrue,
      );

      // Put the same nine packages back. The empty compartment must not
      // remember the previous nine-chip expansion; it starts with eight.
      final selectAll = find.text('Selecionar lista');
      await _ensureLoadItemVisible(tester, selectAll);
      await tester.tap(selectAll);
      await tester.pumpAndSettle();
      expect(find.text('9 pacote(s) selecionado(s)'), findsOneWidget);

      await _ensureLoadItemVisible(tester, trunk);
      await tester.tap(trunk);
      await tester.pumpAndSettle();

      expect(
        state.packages.every((package) => package.physicalZone == 'Porta-malas'),
        isTrue,
      );
      expect(find.byType(InputChip), findsNWidgets(8));
      expect(find.text('P08'), findsOneWidget);
      expect(find.text('P09'), findsNothing);
      expect(find.text('Ver mais 1'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      state.dispose();
    },
  );

}
