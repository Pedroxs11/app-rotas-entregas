import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/screens/load_screen.dart';
import 'package:app_rotas_entregas/services/package_store.dart';

class _IndependentZoneStore implements PackageStore {
  _IndependentZoneStore(this.items);

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
      id: 'independent-zone-$number',
      scanNumber: number,
      address: AddressData(
        raw: 'Rua de teste, $number',
        street: 'Rua de teste',
        number: '$number',
        city: 'São Paulo',
        state: 'SP',
        confidence: 1,
        validation: ValidationStatus.confirmed,
      ),
      scannedAt: DateTime.utc(2026, 11, 24).add(Duration(minutes: number)),
    );

Future<void> _ensureVisible(WidgetTester tester, Finder finder) async {
  final scrollable = find.descendant(
    of: find.byType(CustomScrollView),
    matching: find.byType(Scrollable),
  ).first;
  final position = tester.state<ScrollableState>(scrollable).position;
  final viewport = find.byType(CustomScrollView);

  for (var attempt = 0; attempt < 120; attempt++) {
    if (finder.evaluate().isNotEmpty) {
      final targetRect = tester.getRect(finder.first);
      final viewportRect = tester.getRect(viewport);
      if (targetRect.top >= viewportRect.top &&
          targetRect.bottom <= viewportRect.bottom) {
        return;
      }
      final delta = targetRect.top < viewportRect.top
          ? targetRect.top - viewportRect.top
          : targetRect.bottom - viewportRect.bottom;
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
  final targetRect = tester.getRect(finder.first);
  final viewportRect = tester.getRect(viewport);
  expect(targetRect.top, greaterThanOrEqualTo(viewportRect.top));
  expect(targetRect.bottom, lessThanOrEqualTo(viewportRect.bottom));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'emptying one compartment resets only its preview and preserves another expanded load',
    (tester) async {
      tester.view.physicalSize = const Size(360, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({
        'load_vehicle_type': VehicleType.car.name,
      });

      final state = AppState(
        store: _IndependentZoneStore(
          List.generate(18, (index) => _package(index + 1)),
        ),
      );
      await state.init();

      await state.setPhysicalZones(
        state.packages.take(9).map((package) => package.id).toSet(),
        'Porta-malas',
      );
      await state.setPhysicalZones(
        state.packages.skip(9).map((package) => package.id).toSet(),
        'Frente esquerda',
      );

      await tester.pumpWidget(MaterialApp(home: LoadScreen(state: state)));
      await tester.pumpAndSettle();

      Finder compartment(String label) => find
          .ancestor(
            of: find.text(label),
            matching: find.byType(InkWell),
          )
          .first;

      Finder showOneMore(String label) => find.descendant(
            of: compartment(label),
            matching: find.text('Ver mais 1'),
          );

      // Expand both compartments to nine packages.
      for (final label in ['PORTA-MALAS', 'FRENTE E']) {
        final more = showOneMore(label);
        await _ensureVisible(tester, more);
        await tester.tap(more);
        await tester.pumpAndSettle();
      }
      expect(find.byType(InputChip), findsNWidgets(18));
      expect(
        find.descendant(
          of: compartment('FRENTE E'),
          matching: find.text('P18'),
        ),
        findsOneWidget,
      );

      // Remove all packages from the trunk only.
      await tester.tap(find.byTooltip('Selecionar vários'));
      await tester.pumpAndSettle();
      for (var number = 1; number <= 9; number++) {
        final chip = find.widgetWithText(
          InputChip,
          'P${number.toString().padLeft(2, '0')}',
        );
        await _ensureVisible(tester, chip);
        await tester.tap(chip);
        await tester.pump();
      }
      expect(find.text('9 pacote(s) selecionado(s)'), findsOneWidget);

      final removeAll = find.text('RETIRAR 9 PACOTES');
      await _ensureVisible(tester, removeAll);
      await tester.tap(removeAll);
      await tester.pumpAndSettle();

      // The still-occupied front compartment keeps its expanded preview.
      expect(
        find.descendant(
          of: compartment('FRENTE E'),
          matching: find.byType(InputChip),
        ),
        findsNWidgets(9),
      );
      expect(
        find.descendant(
          of: compartment('FRENTE E'),
          matching: find.text('P18'),
        ),
        findsOneWidget,
      );

      // Reassign the nine unpositioned packages to the now-empty trunk.
      final selectAll = find.text('Selecionar lista');
      await _ensureVisible(tester, selectAll);
      await tester.tap(selectAll);
      await tester.pumpAndSettle();
      final trunk = compartment('PORTA-MALAS');
      await _ensureVisible(tester, trunk);
      await tester.tap(trunk);
      await tester.pumpAndSettle();

      // Only the trunk returns to its initial eight-chip preview.
      expect(
        find.descendant(
          of: compartment('PORTA-MALAS'),
          matching: find.byType(InputChip),
        ),
        findsNWidgets(8),
      );
      expect(
        find.descendant(
          of: compartment('PORTA-MALAS'),
          matching: find.text('P08'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: compartment('PORTA-MALAS'),
          matching: find.text('P09'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: compartment('FRENTE E'),
          matching: find.byType(InputChip),
        ),
        findsNWidgets(9),
      );
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      state.dispose();
    },
  );
}
